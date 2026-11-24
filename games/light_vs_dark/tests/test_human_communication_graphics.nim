## Native production graphics callbacks, not source-string route assertions.
## Uses hidden native GL; focus is supplied to the callback harness explicitly.
import std/[macros, importutils, os, strutils, tables]
import windy/internal
import polyworld/mailboxes
import ../presets
include ../graphics
privateAccess(Window)

proc renameDirector(node: NimNode): NimNode {.compileTime.} =
  ## Routes local camera and focus inputs into extracted production callbacks.
  if node.kind == nnkIdent and node.strVal == "actionCam": return ident("director")
  if node.kind == nnkDotExpr and node.repr == "window.focused":
    return ident("fixtureFocused")
  result = copyNimNode(node)
  for item in node: result.add renameDirector(item)

macro productionCallback(name: static[string]): untyped =
  ## Uses the final gameplay callback after resource-loading setup.
  result = newStmtList()
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkAsgn and child[0].repr == "window." & name and
            child[1].kind == nnkLambda:
          result = renameDirector(child)

macro productionRoutine(name: static[string]): untyped =
  for node in parseStmt(staticRead("../graphics.nim")):
    if node.kind == nnkProcDef and node[0].repr == "runGraphics*":
      for child in node[^1]:
        if child.kind == nnkProcDef and child[0].repr == name: return renameDirector(child)
  error("Missing production routine: " & name)

macro finishProductionUi(): untyped =
  proc search(node: NimNode): NimNode =
    if node.kind == nnkIfStmt and node.repr.contains(
        "window.runeInputEnabled = humanCommunicationTyping() and window.focused") and
        node[0][0].repr == "matchMenu == HiddenMatchMenu": return node
    for child in node:
      let found = search(child)
      if found != nil: return found
  result = renameDirector(search(parseStmt(staticRead("../graphics.nim"))))
  if result == nil: error("Missing production post-Silky rune restoration")

window = newWindow("LvD communication callback regression", ivec2(1920, 1080), visible = false)
window.makeContextCurrent()
loadExtensions()
glClearColor(0, 0, 0, 1)
let atlas = buildUiAtlas(factionOrder(DefaultSeed.int64))
for icon in ["battle", "diplomacy", "alliance", "confirm", "cancel",
    "arrow_left", "hostile", unitSymbolKey(PeonUnit)]:
  doAssert atlas.atlas.entries.hasKey(icon), "Missing diplomacy icon: " & icon
sk = newSilky(window, atlas.atlasImage, atlas.atlas)
var
  fixtureFocused = true
  framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, window.size.x, window.size.y,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
  GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
pollEvents()
doAssert not window.visible
var config = defaultConfig(2)
config.diplomacySettings.enabled = true
config.maxTicks = 100
config.mapSettings = MapSettings(layout: RandomLayout, size: 90, expansions: 0)
run = newLocalMatch(config, ["", ""])
options.playerSlot = 1
for unit in run.world.units:
  if unit.owner == 0:
    selectedIds = @[unit.id]
    primaryId = unit.id
    break
var matchMenu = HiddenMatchMenu
var preferences = readLvdPreferences()
var director = initActionCam(subjectMode = true)
let network: NetworkMatch = nil
let hooks = GraphicsHooks()
var scene: CharacterScene
productionRoutine("playerMode")
productionRoutine("selectionTarget")
productionRoutine("selectedCount")
productionRoutine("clearSelection")
productionRoutine("selectAllUnits")
productionRoutine("pruneSelection")
productionRoutine("selectedCenter")
productionRoutine("selectedRadius")
productionRoutine("updateCamera")
productionCallback("onButtonPress")
productionCallback("onButtonRelease")
productionCallback("onRune")
productionCallback("onFocusChange")
resetHumanCommunication()

proc press(button: Button) =
  window.state.buttonDown.incl button
  window.onButtonPress(button)
proc release(button: Button) =
  window.state.buttonDown.excl button
  window.onButtonRelease(button)

press(KeyEnter)
doAssert humanCommunicationBlocksGameplay(), "Enter must open chat through graphics callback"
doAssert window.onRune != nil, "Graphics must register rune callback"
doAssert window.runeInputEnabled, "Enter must request native rune input immediately"
release(KeyEnter)
sk.beginUi(window, window.size)
sk.endUi()
doAssert not window.runeInputEnabled, "Fixture must exercise Silky ending unused text capture"
finishProductionUi()
doAssert window.runeInputEnabled, "Graphics must restore capture after Silky"
for rune in "Hi 雪🙂".runes: window.onRune(rune)
let selectedBefore = selectedIds
let cameraBefore = cameraTarget
window.state.buttonDown = {KeyLeftControl, KeyA, KeyRight, MouseMiddle}
window.state.perFrame = PerFrame(buttonPressed: {KeyA, MouseMiddle})
updateCamera(1)
doAssert selectedIds == selectedBefore, "Polled Ctrl+A must not select while typing"
doAssert cameraTarget == cameraBefore and not panning, "Polled camera must not move while typing"
window.state.buttonDown = {}
window.state.perFrame = PerFrame()
let tilesBefore = showTiles
let playingBefore = transport.playing
for key in [KeyS, KeyB, KeyE, KeySpace, KeyA]:
  press(key)
  release(key)
doAssert showTiles == tilesBefore, "Typed E toggled terrain"
doAssert transport.playing == playingBefore, "Typed Space paused transport"
doAssert pendingBuild == -1 and not attackMoveArmed
run.networked = true
run.flushPlayerCommands()
doAssert run.submissions.len == 0, "Typed Stop/build must not queue gameplay commands"
run.networked = false
press(KeyEnter)
doAssert run.inboxes[1].count == 1, "Enter must send exactly one authoritative local chat"
press(KeyEnter) # OS auto-repeat cannot reopen chat or double-send.
doAssert run.inboxes[1].count == 1
release(KeyEnter)
doAssert run.inboxes[1].messages[run.inboxes[1].first] == "Hi 雪🙂"
doAssert run.inboxes[1].pop() == -2
doAssert humanCommunicationBlocksGameplay(), "Closing event must block this frame"
window.state.buttonDown = {KeyRight}
updateCamera(1)
doAssert cameraTarget == cameraBefore, "Sending must not release polling in the closing frame"
window.state.buttonDown = {}
finishHumanCommunicationFrame()
doAssert not humanCommunicationBlocksGameplay()
press(KeyEnter)
release(KeyEnter)
window.onRune(Rune('x'))
press(KeyEscape)
doAssert matchMenu == HiddenMatchMenu, "Escape cancels chat rather than opening pause"
release(KeyEscape)
finishHumanCommunicationFrame()
doAssert run.inboxes[1].count == 0
block diplomacyPanel:
  for size in [vec2(800, 600), vec2(1200, 800), vec2(1920, 1080)]:
    let
      layout = initGameUiLayout(size)
      minimap = layout.panel(GameUiRegion.TopRight, PanelMinimap)
      button = layout.diplomacyButtonPanel()
    doAssert button.origin.y >= minimap.origin.y + minimap.size.y
    doAssert button.origin.x >= 0 and button.origin.y >= 0
    doAssert button.origin.x + button.size.x <= size.x
    doAssert button.origin.y + button.size.y <= size.y
  var colors = @[rgbx(230, 100, 100, 255), rgbx(100, 100, 230, 255)]
  proc drawHud(at: Vec2, pressed: set[Button] = {}) =
    ## Draws the actual HUD into the hidden capture target with mouse input.
    sk.uiScale = gameUiScale(window)
    window.state.mousePos = ivec2((at.x * sk.uiScale).int32, (at.y * sk.uiScale).int32)
    window.state.perFrame = PerFrame(buttonPressed: pressed)
    glClear(GL_COLOR_BUFFER_BIT)
    sk.beginUi(window, window.size)
    drawUi(sk, window, transport, cameraTarget, cameraDistance, viewMode,
      primaryId, selectedIds, followSelection, director, colors)
    sk.endUi()
    finishProductionUi()
    finishHumanCommunicationFrame()
    window.state.perFrame = PerFrame()
  let
    diplomacyButton = currentLayout(window).diplomacyButtonPanel()
    diplomacyCenter = diplomacyButton.origin + diplomacyButton.size / 2
  doAssert window.mouseOverUi(diplomacyCenter),
    "Diplomacy button must block commands to the world behind it"
  drawHud(diplomacyCenter)
  let screenshotPath = getEnv("LVD_DIPLOMACY_FIXTURE")
  if screenshotPath.len > 0:
    let
      minimap = currentLayout(window).panel(GameUiRegion.TopRight, PanelMinimap)
      left = max(0'i32, int32((minimap.origin.x - 8) * sk.uiScale))
      top = max(0'i32, int32((minimap.origin.y - 8) * sk.uiScale))
      right = min(window.size.x,
        int32((minimap.origin.x + minimap.size.x + 8) * sk.uiScale))
      bottom = min(window.size.y,
        int32((diplomacyButton.origin.y + diplomacyButton.size.y + 8) * sk.uiScale))
      screenshot = newImage(right - left, bottom - top)
    glReadPixels(left, window.size.y - bottom, right - left, bottom - top,
      GL_RGBA, GL_UNSIGNED_BYTE,
      screenshot.data[0].addr)
    screenshot.flipVertical()
    screenshot.writeFile(screenshotPath)
  # Typing the default keyboard-select alias while hovering Diplomacy cannot
  # turn a text character into a panel toggle.
  customBindingsEnabled = true
  inputBindings[SelectInput] = [MouseLeft, KeyZ]
  press(KeyEnter)
  release(KeyEnter)
  press(KeyZ)
  press(KeyTab)
  drawHud(diplomacyCenter, {KeyZ})
  doAssert humanCommunicationTyping(), "Typed select alias clicked Diplomacy"
  doAssert not director.manualPanel, "Typed Tab must not engage the stats director"
  release(KeyTab)
  release(KeyZ)
  press(KeyEscape)
  release(KeyEscape)
  finishHumanCommunicationFrame()
  drawHud(diplomacyCenter, {MouseLeft})
  doAssert humanCommunicationBlocksGameplay(), "Diplomacy button must open panel"
  drawHud(diplomacyCenter, {MouseLeft})
  doAssert not humanCommunicationBlocksGameplay(),
    "Diplomacy button must also close its panel"
  drawHud(diplomacyCenter, {MouseLeft})
  doAssert humanCommunicationBlocksGameplay(), "Diplomacy button must reopen panel"
  let layout = currentLayout(window)
  let width = min(660'f32, layout.size.x - 24)
  let rows = max(1, min(6, int((layout.size.y - 148) / 92)))
  let height = 100'f32 + float32(rows * 92)
  let origin = vec2((layout.size.x-width)/2, max(12'f32, (layout.size.y-height)/2))
  let firstAction = origin + vec2(104, 104)
  let secondAction = firstAction + vec2(164, 0)
  drawHud(firstAction, {MouseLeft})
  doAssert run.world.diplomacy.relation(0, 1).offer == PeaceOffer
  options.playerSlot = 2
  drawHud(secondAction, {MouseLeft})
  doAssert run.world.diplomacy.relation(0, 1).offer == NoOffer, "Recipient Decline button"
  # Opposite side can immediately offer; original sender retains cooldown.
  drawHud(firstAction, {MouseLeft})
  doAssert run.world.diplomacy.relation(0, 1).offer == PeaceOffer
  options.playerSlot = 1
  drawHud(firstAction, {MouseLeft})
  doAssert run.world.diplomacy.relation(0, 1).state == Neutral, "Recipient Accept button"
  press(KeyEscape)
  release(KeyEscape)
  finishHumanCommunicationFrame()
  run.world.diplomacy.settings.enabled = false
  drawHud(diplomacyCenter, {MouseLeft})
  doAssert not humanCommunicationBlocksGameplay(),
    "Fixed team icon must not open negotiation controls"
  block playerBadges:
    let
      previousRun = run
      previousSelection = selectedIds
      previousPrimary = primaryId
    var rosterConfig = defaultConfig(8)
    rosterConfig.diplomacySettings.enabled = true
    rosterConfig.diplomacySettings.neutralStart = true
    rosterConfig.maxTicks = 100
    rosterConfig.mapSettings = config.mapSettings
    const Names = ["Aster", "Briar", "Cinder", "Dawn",
      "Ember", "Flint", "Gale", "Haven"]
    for player in 0 ..< rosterConfig.players.len:
      rosterConfig.players[player].name = Names[player]
    run = newLocalMatch(rosterConfig, ["", "", "", "", "", "", "", ""])
    selectedIds = @[]
    primaryId = NoEntity
    colors = @[]
    for faction in playerFactions(run.mapSeed,
        run.world.diplomacy.settings, run.world.players.len):
      colors.add FactionColors[faction]
    resetHumanCommunication()
    # Show all eight actions across six rows without advancing the simulation.
    for other in 1'i32 .. 6:
      let index = run.world.diplomacy.pairIndex(0, other)
      run.world.diplomacy.pairs[index] = case other
        of 2: Relation(state: AtWar)
        of 3: Relation(state: Neutral, offer: AllianceOffer, sender: 3,
          offerId: 1, offerDeadline: TickRate * 60)
        of 4: Relation(state: Allied)
        of 5: Relation(state: Neutral, offer: AllianceOffer, sender: 0,
          offerId: 2, offerDeadline: TickRate * 60)
        of 6: Relation(state: WarPending, initiator: 0,
          deadline: TickRate * 10)
        else: Relation(state: Neutral)
    run.world.players[7].defeated = true
    drawHud(diplomacyCenter, {MouseLeft})
    drawHud(vec2(0))
    let screenshot = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
      GL_UNSIGNED_BYTE, screenshot.data[0].addr)
    screenshot.flipVertical()
    proc pixelAt(image: Image, at: Vec2): ColorRGBX =
      ## Samples the rendered image in the HUD's logical coordinates.
      image[int(at.x * sk.uiScale), int(at.y * sk.uiScale)]
    proc brightPixels(image: Image, at, size: Vec2, threshold = 100): int =
      ## Counts visible glyph pixels independently of the button background.
      for y in 0 ..< int(size.y):
        for x in 0 ..< int(size.x):
          let pixel = image.pixelAt(at + vec2(x.float32, y.float32))
          if pixel.r.int > threshold or pixel.g.int > threshold or
            pixel.b.int > threshold:
              inc result
    doAssert rows == 6, "Fixture must show the complete first diplomacy page"
    for row in 0 ..< rows:
      let badge = origin + vec2(12, 44 + row.float32 * 92)
      doAssert screenshot.pixelAt(badge + vec2(10, 66)) == colors[row + 1],
        "Player badge must use the exact unit/minimap color"
      doAssert screenshot.brightPixels(badge + vec2(4, 6), vec2(48), 35) > 30,
        "Player badge must contain a visible tinted player icon"
      let firstIcon = badge + vec2(64 + 6, 46 + 6)
      doAssert screenshot.brightPixels(firstIcon, vec2(16)) > 4,
        "Every visible first action must display its icon"
      if row in [0, 2, 5]:
        doAssert screenshot.brightPixels(firstIcon + vec2(164, 0),
          vec2(16)) > 4, "Second actions must display their icons"
    let panelPath = getEnv("LVD_DIPLOMACY_PANEL_FIXTURE")
    if panelPath.len > 0:
      let
        left = int((origin.x - 4) * sk.uiScale)
        top = int((origin.y - 4) * sk.uiScale)
        panelWidth = int((width + 8) * sk.uiScale)
        panelHeight = int((height + 8) * sk.uiScale)
      createDir(panelPath.parentDir)
      screenshot.subImage(left, top, panelWidth, panelHeight).writeFile(panelPath)
    let next = origin + vec2(120, height - 26)
    drawHud(next, {MouseLeft})
    drawHud(vec2(0))
    let nextPage = newImage(window.size.x, window.size.y)
    glReadPixels(0, 0, window.size.x, window.size.y, GL_RGBA,
      GL_UNSIGNED_BYTE, nextPage.data[0].addr)
    nextPage.flipVertical()
    doAssert nextPage.pixelAt(origin + vec2(22, 110)) == colors[7],
      "Next page must show the next opponent's color"
    let defeatedRelation = run.world.diplomacy.relation(0, 7)
    drawHud(firstAction, {MouseLeft})
    drawHud(secondAction, {MouseLeft})
    doAssert run.world.diplomacy.relation(0, 7) == defeatedRelation,
      "Defeated players must retain disabled diplomacy actions"
    drawHud(origin + vec2(50, height - 26), {MouseLeft})
    drawHud(firstAction, {MouseLeft})
    doAssert run.world.diplomacy.relation(0, 1).offer == AllianceOffer,
      "Previous page must restore the first opponent's action targets"
    resetHumanCommunication()
    run = previousRun
    selectedIds = previousSelection
    primaryId = previousPrimary
press(KeyEnter)
release(KeyEnter)
press(KeyS) # Deliberately lose its release while unfocused.
fixtureFocused = false
window.onFocusChange()
doAssert not humanCommunicationTyping()
doAssert not window.runeInputEnabled
finishHumanCommunicationFrame()
doAssert not humanCommunicationBlocksGameplay(), "Focus loss clears held-key quarantine"
press(KeyEscape)
doAssert matchMenu == PauseMenu, "Escape outside communication still opens pause"
release(KeyEscape)
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
window = nil
run = nil
echo "PASS production graphics Enter/rune/send/repeat/Escape, Silky capture restoration, focus loss, hotkeys and camera/Ctrl+A polling suppression; HUD alias/Tab isolation, diplomacy actions, colored player badges, action icons, paging and defeated guards"
