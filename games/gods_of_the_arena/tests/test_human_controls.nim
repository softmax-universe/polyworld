## Execute production graphics procedures with real Windy state and command queue.
## Geometry is deterministic here; no renderer, browser or OS focus is required.
import std/[macros, os, importutils]
import windy, windy/internal, vmath
import polyworld/[inputs, rtscameras]
from polyworld/actioncam import initActionCam, takeManual, toggle
import polyworld/player
import ../[chats, chatinput]
import ../[content, game, sim, cameras, minimaporders]
include ../controls
privateAccess(Window)

macro production(names: varargs[untyped]): untyped =
  let tree = parseStmt(readFile(currentSourcePath().parentDir.parentDir / "graphics.nim"))
  result = newStmtList()
  for name in names:
    proc find(node: NimNode): NimNode =
      if node.kind == nnkProcDef and node[0].eqIdent(name.strVal): return node
      for child in node:
        result = find(child)
        if result != nil: return
    let found = find(tree)
    doAssert found != nil, name.strVal
    result.add found

macro buttonCallback(): untyped =
  let tree = parseStmt(readFile(currentSourcePath().parentDir.parentDir / "graphics.nim"))
  proc find(node: NimNode): NimNode =
    if node.kind == nnkAsgn and node[0].repr == "window.onButtonPress" and
        node[1].kind == nnkLambda: return node
    for child in node:
      result = find(child)
      if result != nil: return
  result = find(tree)
  doAssert result != nil

proc main() =
  let window = newWindow("GotA human controls", ivec2(800, 600), visible = false)
  var
    primaryId = 0'i32
    selectedIds: seq[int32]
    followSelection = false
    groupCameraScale = 1'f32
    actionCam = initActionCam()
    selectionStarted = false
    selectionAdditive = false
    selectionPressPosition = vec2(0)
    attackMoveArmed = false
    pickedId = 0'i32
    overUi = false
    sk = (mousePos: vec2(0),)

  type SelectionTarget = object
    found: bool
    position: Vec3
    focusHeight: float32
  proc selectionTarget(id: int32): SelectionTarget = SelectionTarget(found: id != 0)
  proc isSelected(id: int32): bool = id in selectedIds
  proc selectedTargetCount(): int = selectedIds.len
  proc playerMode(): bool = options.playerSlot > 0 and not run.replayMode
  proc playerHeroId(): int32 = run.world.heroes[options.playerSlot - 1].id
  proc objectTeam(id: int32): int32 = (if id == playerHeroId(): 1 else: 2)
  proc mouseOverUi(window: Window, mouse: Vec2, id: int32): bool = overUi
  proc pickEntity(vp: Mat4): int32 = pickedId
  proc pickActionTarget(vp: Mat4, healing = false): int32 = pickedId
  proc issueGroundOrder(vp: Mat4, attackMove: bool) =
    if attackMove: queueAttackMove(playerHeroId(), 4, 5)
    else: queueWalkTo(playerHeroId(), 4, 5)
  production(selectEntity, clearSelection, holdingAttackMove, updateWorldSelection)

  run = Game(world: World(phase: Playing))
  run.world.heroes.add Hero(id: 101, hp: 100)
  options.playerSlot = 1
  customBindingsEnabled = true
  inputBindings = DefaultBindings

  # Ordinary left click inspects enemies without touching the authoritative queue.
  pickedId = 202
  selectionStarted = true
  window.state.perFrame = PerFrame(buttonReleased: {MouseLeft})
  updateWorldSelection(mat4())
  doAssert primaryId == 202, "left click should inspect the enemy"
  doAssert pending.len == 0, "ordinary left enemy inspection must not queue an attack"
  doAssert not followSelection, "human inspection must not follow the inspected enemy"
  echo "PASS human left-click inspection uses production selection and empty command queue"
  attackMoveArmed = true
  selectionStarted = true
  updateWorldSelection(mat4())
  doAssert pending.len == 1 and pending[0].kind == CommandAttack
  doAssert pending[0].heroId == 101 and pending[0].first == 202
  doAssert primaryId == 202
  pending.setLen(0)
  pickedId = 0
  attackMoveArmed = true
  selectionStarted = true
  updateWorldSelection(mat4())
  doAssert pending.len == 1 and pending[0].kind == CommandAttackMove
  doAssert primaryId == 202, "armed ground orders must preserve inspection"
  pending.setLen(0)
  pickedId = 202

  # Production right-click dispatch must retain inspection and use own hero.
  block rightOrder:
    var matchMenu = 0
    const HiddenMatchMenu = 0
    var aimError = NoActionError
    var minimapHit = false
    proc minimapAim(window: Window, mouse: Vec2, point: var Vec2): bool =
      point = vec2(12, 14)
      minimapHit
    type Markers = object
      count: int
    var clickMarks, attackMarks: Markers
    proc emitClickMark(marks: var Markers, point: Vec3) = inc marks.count
    proc surfaceHeight(x, z: float32): float32 = 0
    proc mouseRay(mouse, size: Vec2, vp: Mat4): (Vec3, Vec3) = (vec3(0), vec3(0))
    type Pick = object
      hit: bool
      layer, x, z: int
    let layers = [(originX: 0, originZ: 0)]
    proc pickTile(origin, direction: Vec3): Pick = Pick(hit: false)
    proc pickWalkableTile(origin, direction: Vec3): Pick = Pick(hit: false)
    proc mapOrigin(): int = 0
    var chat = (blocksGameplay: false,)
    production(updatePlayerOrder)
    window.state.perFrame = PerFrame(buttonPressed: {MouseRight})
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandAttack
    doAssert pending[0].heroId == 101 and pending[0].first == 202
    doAssert primaryId == 202, "issuing an order must retain enemy inspection"
    pending.setLen(0)
    # Polling routes must enforce modal ownership, not depend on their caller.
    chat.blocksGameplay = true
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 0, "chat must suppress contextual orders"
    chat.blocksGameplay = false
    matchMenu = 1
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 0, "menu must suppress contextual orders"
    matchMenu = HiddenMatchMenu
    attackMoveArmed = true
    minimapHit = true
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandAttackMove
    doAssert attackMarks.count == 1 and clickMarks.count == 0
    doAssert primaryId == 202
    pending.setLen(0)
    attackMoveArmed = false
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandWalk
    doAssert attackMarks.count == 1 and clickMarks.count == 1
    pending.setLen(0)
    echo "PASS production right-click ownhero, retained inspection, A-move red / move green minimap routes"
  block cameraHold:
    var
      cameraTarget = vec3(40, 0, 40)
      cameraDistance = 50'f32
      cameraEase: CameraEase
      focusPlayerHero = false
      minimapPanning, panning: bool
      matchMenu = 0
      chat = (blocksGameplay: false,)
      preferences = (edgeScrolling: NoEdgeScroll,)
    const HiddenMatchMenu = 0
    proc pruneSelection() = discard
    proc syncViewMode() = discard
    proc playerHeroFrame(): Vec3 = vec3(3, 1, 7)
    proc updateMinimapCamera(window: Window, mouse: Vec2, target: var Vec3,
        minimap, follow: var bool) = discard
    proc selectAllHeroes() = discard
    proc selectedCenter(): Vec3 = vec3(0)
    proc selectedRadius(center: Vec3): float32 = 1
    proc mapHalfSize(): float32 = 100
    const DefaultCameraDistance = 80'f32
    proc scaleModifier(window: Window): bool = false
    proc damping(rate, dt: float32): float32 = 1
    production(updateCamera)
    window.state.buttonDown = {KeySpace}
    window.state.perFrame = PerFrame()
    updateCamera(0.1, true)
    doAssert cameraTarget == playerHeroFrame(), "held Space must center on own hero"
    window.state.buttonDown = {}
    cameraTarget = vec3(20, 0, 20)
    updateCamera(0.1, true)
    doAssert cameraTarget == vec3(20, 0, 20), "release must restore free camera"
    window.state.buttonDown = {KeySpace}
    for gate in 0 .. 4:
      cameraTarget = vec3(20, 0, 20)
      chat.blocksGameplay = gate == 0
      matchMenu = (if gate == 1: 1 else: HiddenMatchMenu)
      shopOpen = gate == 2
      run.world.phase = (if gate == 3: Drafting else: Playing)
      updateCamera(0.1, gate != 4)
      doAssert cameraTarget == vec3(20, 0, 20), "camera must respect chat/menu/shop/draft/focus"
    chat.blocksGameplay = false
    matchMenu = HiddenMatchMenu
    shopOpen = false
    run.world.phase = Playing
    window.state.buttonDown = {}
    focusPlayerHero = true
    updateCamera(0.55, true)
    doAssert cameraTarget == playerHeroFrame(), "self portrait remains a one-shot recenter"
    cameraTarget = vec3(20, 0, 20)
    updateCamera(0.1, true)
    doAssert cameraTarget == vec3(20, 0, 20), "portrait recenter must not latch follow"
    echo "PASS production hold/release camera, modal/focus gates, portrait one-shot"
  block callback:
    type TestNetwork = ref object
      isSpectator: bool
    var
      network: TestNetwork
      matchMenu = 0
      quitToMenu = false
      chat: ChatEditor
      minimapPanning, panning: bool
      transport = initPlayer(live = true, durationTicks = 1000, playing = true)
      preferences: int
      showOccludedCharacters = false
      scene = 0
    const
      HiddenMatchMenu = 0
      PauseMenu = 1
      MatchSettings = 2
    proc canHumanChat(network: TestNetwork): bool = true
    proc scaleKey(window: Window, button: Button, preferences: var int,
        scale: float32, name: string): bool = false
    proc syncChatInput(window: Window, chat: ChatEditor) = discard
    proc clearHudTooltip() = discard
    proc handleChromeKey(button: Button): bool = false
    proc setFullscreen(window: Window, value: bool) = discard
    proc isFullscreen(window: Window): bool = false
    proc toggleShading(scene: int) = discard
    proc epochTime(): float64 = 0
    var sk = (uiScale: 1'f32,)
    var shopResets = 0
    proc resetShopUi() = inc shopResets
    buttonCallback()
    shopOpen = true
    armedAbility = 1
    window.onButtonPress(KeyEscape)
    doAssert not shopOpen and matchMenu == HiddenMatchMenu,
      "Escape must close the shop before opening the match menu"
    doAssert shopResets == 1 and armedAbility == -1,
      "shop close must retire shop interaction and targeting"
    window.onButtonPress(KeyEscape)
    doAssert matchMenu == PauseMenu, "a second Escape may open the match menu"
    matchMenu = HiddenMatchMenu
    window.onButtonPress(KeySpace)
    doAssert transport.playing, "human Space must not pause local playback"
    run.replayMode = true
    window.onButtonPress(KeySpace)
    doAssert not transport.playing, "replay Space must retain playback pause"
    run.replayMode = false
    window.onButtonPress(KeyA)
    doAssert attackMoveArmed, "A must arm attack-move, not become a mouse click"
    doAssert not window.mousePressed(MouseLeft)
    doAssert not window.mouseDown(MouseMiddle), "S must not be a camera-drag alias"
    attackMoveArmed = false
    discard chat.handleChatButton(KeyEnter, true)
    window.onButtonPress(KeyA)
    doAssert not attackMoveArmed, "chat must own gameplay shortcut callbacks"
    discard chat.handleChatButton(KeyEscape, true)
    matchMenu = PauseMenu
    window.onButtonPress(KeyA)
    doAssert not attackMoveArmed
    matchMenu = HiddenMatchMenu
    run.world.phase = Drafting
    window.onButtonPress(KeySpace)
    doAssert not transport.playing, "Space must not pause/resume drafts"
    run.world.phase = Playing
    echo "PASS production callbacks: human Space camera-only, replay pause, A-move, chat/menu/draft"
  block abilityReadiness:
    var matchMenu = 0
    const HiddenMatchMenu = 0
    production(updatePlayerSpells)
    let hero = run.world.heroes[0]
    hero.mana = 10000
    for heroClass in HeroClass:
      hero.class = heroClass
      for slot in HeroAbilitySlot:
        hero.abilityLevels[slot] = 1
        hero.charges[slot] = 1
        hero.cooldowns[slot] = 20
        armedAbility = 2
        armedItem = 1
        doAssert not activatePlayerAbility(run.world, hero.id, slot.ord.int32)
        doAssert armedAbility == -1 and armedItem == -1 and pending.len == 0,
          "cooldown ability must neither arm nor queue, and must retire stale aim"
        # The actual polled keyboard route shares the HUD activation helper.
        let key = [KeyQ, KeyW, KeyE, KeyR][slot.ord]
        window.state.perFrame = PerFrame(buttonPressed: {key})
        updatePlayerSpells()
        doAssert armedAbility == -1 and pending.len == 0
        hero.cooldowns[slot] = 0
        discard activatePlayerAbility(run.world, hero.id, slot.ord.int32)
        if heroAbility(hero.class, slot).abilitySpec.casting == SelfCast:
          doAssert pending.len == 1 and pending[0].kind == CommandCastTarget
          doAssert pending[0].heroId == hero.id and pending[0].first == hero.id
        else:
          doAssert armedAbility == slot.ord.int32 and pending.len == 0,
            "ready aimed abilities must still arm normally"
        pending.setLen(0)
        armedAbility = -1
    echo "PASS every class/slot cooldown blocks HUD helper and production spell keys; ready casts preserved"
  window.close()

main()
