## Execute production graphics procedures with real Windy state and command queue.
## Geometry is deterministic here; no renderer, browser or OS focus is required.
import std/[macros, os, importutils]
import windy, windy/internal, vmath
import polyworld/[inputs, rtscameras, soundassets]
from polyworld/actioncam import initActionCam, takeManual, toggle
import polyworld/player
import ../[chats, chatinput]
import ../[content, game, sim, cameras, minimaporders, pointers]
include ../controls
privateAccess(Window)

var playedSounds: seq[SoundCue]

proc playSound(cue: SoundCue) =
  ## Records feedback without opening an audio device.
  playedSounds.add cue

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
    heldRightMove = false
    nextRightMoveTick = 0'i32
    pickedId = 0'i32
    overUi = false
    groundHit = true
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
  proc objectTeam(id: int32): int32 =
    ## Keeps one allied creep distinct from the fixture's enemy mesh hits.
    if id in [playerHeroId(), 303'i32]: 1 else: 2
  proc mouseOverUi(window: Window, mouse: Vec2, id: int32): bool = overUi
  proc pickEntity(vp: Mat4): int32 = pickedId
  proc pickActionTarget(vp: Mat4, healing = false,
      denying = false): int32 = pickedId
  type Pick = object
    hit: bool
    layer, x, z: int
  let layers = [(originX: 7, originZ: 11)]
  proc mouseRay(mouse, size: Vec2, vp: Mat4): (Vec3, Vec3) =
    ## Gives each screen point a deterministic ground ray for order tests.
    (vec3(mouse.x, 0, mouse.y), vec3(0, -1, 0))
  proc pickWalkableTile(origin, direction: Vec3): Pick =
    ## Maps screen coordinates to distinct tiles without a renderer.
    Pick(hit: groundHit, x: int(origin.x) div 10, z: int(origin.z) div 10)
  proc mapOrigin(): int = 3
  production(issueGroundOrder, selectEntity, clearSelection,
    holdingAttackMove, updateWorldSelection)

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
  window.state.buttonDown = {KeyLeftShift}
  attackMoveArmed = true
  selectionStarted = true
  updateWorldSelection(mat4())
  doAssert pending.len == 1 and pending[0].kind == CommandQueueAttackMove,
    "Shift A-click must append an attack-move"
  pending.setLen(0)
  pickedId = 202
  attackMoveArmed = true
  selectionStarted = true
  updateWorldSelection(mat4())
  doAssert pending.len == 1 and pending[0].kind == CommandQueueAttack,
    "Shift A-click on an enemy must append an attack"
  pending.setLen(0)
  window.state.buttonDown = {}
  pickedId = 202

  # Denies require an explicit attack gesture and never change inspection.
  block denyClicks:
    run.world.footmen = @[Footman(id: 303, team: run.world.heroes[0].team)]
    run.world.footmen[0].hp = run.world.footmen[0].unitMaxHp div 2 - 1
    pickedId = 303
    attackMoveArmed = true
    selectionStarted = true
    updateWorldSelection(mat4())
    doAssert pending.len == 1 and pending[0].kind == CommandAttack
    doAssert pending[0].heroId == 101 and pending[0].first == 303
    doAssert primaryId == 202, "A-deny must preserve the inspected unit"
    pending.setLen(0)
    attackMoveArmed = false
    selectionStarted = true
    updateWorldSelection(mat4())
    doAssert pending.len == 0 and primaryId == 303,
      "Ordinary allied left-click must remain inspection"
    primaryId = 202
    run.world.footmen[0].hp = run.world.footmen[0].unitMaxHp div 2
    attackMoveArmed = true
    selectionStarted = true
    updateWorldSelection(mat4())
    doAssert pending.len == 1 and pending[0].kind == CommandAttackMove,
      "Exactly half health must not queue a friendly attack"
    pending.setLen(0)
    dec run.world.footmen[0].hp
    attackMoveArmed = false
    pickedId = 202
    echo "PASS A-targeting denies below-half creeps without changing inspection"

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
    proc pickTile(origin, direction: Vec3): Pick = Pick(hit: false)
    var chat = (blocksGameplay: false,)
    production(updatePlayerOrder, updateHeldMovement)
    window.state.perFrame = PerFrame(buttonPressed: {MouseRight})
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandAttack
    doAssert pending[0].heroId == 101 and pending[0].first == 202
    doAssert primaryId == 202, "issuing an order must retain enemy inspection"
    doAssert not heldRightMove, "Enemy attacks must not start held movement"
    pending.setLen(0)
    pickedId = 303
    attackMoveArmed = true
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandAttack and
      pending[0].first == 303,
      "A plus right-click may explicitly deny an allied creep"
    doAssert not heldRightMove
    pending.setLen(0)
    attackMoveArmed = false
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandWalk,
      "Ordinary right-click must not accidentally deny an allied creep"
    pending.setLen(0)
    heldRightMove = false
    pickedId = 202
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
    doAssert not heldRightMove
    pending.setLen(0)
    attackMoveArmed = false
    updatePlayerOrder(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandWalk
    doAssert attackMarks.count == 1 and clickMarks.count == 1
    doAssert not heldRightMove, "Minimap orders must remain single clicks"
    pending.setLen(0)
    echo "PASS production right-click ownhero, retained inspection, A-move red / move green minimap routes"

    for shift in [KeyLeftShift, KeyRightShift]:
      window.state.buttonDown = {MouseRight, shift}
      for minimap in [false, true]:
        minimapHit = minimap
        pickedId = 0
        attackMoveArmed = false
        updatePlayerOrder(mat4(), true)
        doAssert pending.len == 1 and pending[0].kind == CommandQueueWalk,
          "Either Shift key must append world and minimap walks"
        doAssert not heldRightMove,
          "Shift-click must add one waypoint without starting held steering"
        pending.setLen(0)
        window.state.perFrame = PerFrame()
        run.world.tick += TickRate
        updateHeldMovement(mat4(), true)
        doAssert pending.len == 0, "Holding Shift-click must not add repeats"
        window.state.perFrame = PerFrame(buttonPressed: {MouseRight})
        attackMoveArmed = true
        updatePlayerOrder(mat4(), true)
        doAssert pending.len == 1 and
          pending[0].kind == CommandQueueAttackMove
        pending.setLen(0)
      minimapHit = false
      pickedId = 202
      attackMoveArmed = false
      updatePlayerOrder(mat4(), true)
      doAssert pending.len == 1 and pending[0].kind == CommandQueueAttack
      pending.setLen(0)
    window.state.buttonDown = {}
    echo "PASS Shift appends world, minimap and attack orders without repeats"

    minimapHit = false
    pickedId = 0
    window.state.mousePos = ivec2(40, 50)
    window.state.buttonDown = {MouseRight}
    playedSounds.setLen(0)
    updatePlayerOrder(mat4(), true)
    doAssert heldRightMove and nextRightMoveTick > run.world.tick
    doAssert pending.len == 1 and pending[0].kind == CommandWalk
    doAssert pending[0].first == 8 and pending[0].second == 13,
      "Ground orders must retain the layer and map origin conversion"
    doAssert playedSounds == @[MoveOrderSound]
    pending.setLen(0)
    window.state.perFrame = PerFrame()
    window.state.mousePos = ivec2(90, 30)
    run.world.tick = nextRightMoveTick - 1
    updateHeldMovement(mat4(), true)
    doAssert pending.len == 0, "Held movement must wait for its repeat tick"
    inc run.world.tick
    updateHeldMovement(mat4(), true)
    doAssert pending.len == 1 and pending[0].kind == CommandWalk
    doAssert pending[0].first == 13 and pending[0].second == 11,
      "A held order must use the current pointer destination"
    doAssert playedSounds == @[MoveOrderSound],
      "Held movement must not repeat the order sound"
    pending.setLen(0)
    updateHeldMovement(mat4(), true)
    doAssert pending.len == 0, "Render frames must not flood the command queue"
    let hero = run.world.heroes[0]
    hero.hasMoveTarget = true
    hero.moveTileX = 13
    hero.moveTileY = 11
    run.world.tick = nextRightMoveTick
    updateHeldMovement(mat4(), true)
    doAssert pending.len == 0, "An unchanged active destination needs no order"
    hero.hasMoveTarget = false
    window.state.buttonDown = {}
    updateHeldMovement(mat4(), true)
    doAssert not heldRightMove and pending.len == 0
    window.state.buttonDown = {MouseRight}
    run.world.tick += TickRate
    updateHeldMovement(mat4(), true)
    doAssert pending.len == 0,
      "A held button cannot restart movement without a fresh world press"

    for gate in 0 .. 14:
      window.state.buttonDown = {MouseRight}
      window.state.perFrame = PerFrame(buttonPressed: {MouseRight})
      updatePlayerOrder(mat4(), true)
      doAssert heldRightMove and pending.len == 1
      pending.setLen(0)
      window.state.perFrame = PerFrame(
        buttonPressed: if gate == 13: {MouseLeft} else: {})
      run.world.tick = nextRightMoveTick
      if gate == 14:
        window.state.buttonDown.incl KeyLeftShift
      chat.blocksGameplay = gate == 0
      matchMenu = if gate == 1: 1 else: HiddenMatchMenu
      shopOpen = gate == 2
      run.world.phase = if gate == 3: Drafting else: Playing
      run.world.gameOver = gate == 4
      bindingCapture = gate == 5
      armedAbility = if gate == 6: 0 else: -1
      armedItem = if gate == 7: 0 else: -1
      attackMoveArmed = gate == 8
      hero.hp = if gate == 9: 0 else: 100
      hero.state = if gate == 10: Dying else: Marching
      options.playerSlot = if gate == 11: 0 else: 1
      updateHeldMovement(mat4(), gate != 12)
      doAssert not heldRightMove and pending.len == 0,
        "A modal, focus loss or unavailable hero must cancel held movement"
      chat.blocksGameplay = false
      matchMenu = HiddenMatchMenu
      shopOpen = false
      run.world.phase = Playing
      run.world.gameOver = false
      bindingCapture = false
      armedAbility = -1
      armedItem = -1
      attackMoveArmed = false
      hero.hp = 100
      hero.state = Marching
      options.playerSlot = 1
      window.state.buttonDown = {MouseRight}
      window.state.perFrame = PerFrame()
      updateHeldMovement(mat4(), true)
      doAssert pending.len == 0,
        "Removing the cancellation gate must still require a fresh press"

    for source in 0 .. 3:
      window.state.perFrame = PerFrame(buttonPressed: {MouseRight})
      overUi = source == 0
      groundHit = source != 1
      pickedId = if source == 2: 202 else: 0
      minimapHit = source == 3
      updatePlayerOrder(mat4(), true)
      doAssert not heldRightMove,
        "UI, missed ground, enemy and minimap presses must not start a hold"
      pending.setLen(0)
      overUi = false
      groundHit = true
      pickedId = 0
      minimapHit = false
      window.state.perFrame = PerFrame()
      run.world.tick += TickRate
      updateHeldMovement(mat4(), true)
      doAssert pending.len == 0,
        "Dragging into the world must not start a hold from another input owner"
    window.state.buttonDown = {}
    echo "PASS held ground steering, throttling, quiet repeats and cancellation gates"
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
    proc rtsPanDir(
        window: Window,
        mode: EdgeScrollMode,
        margin = RtsEdgePanMargin,
        pointerConfined = false
    ): Vec2 =
      ## Uses real pan math while updateCamera supplies simulated OS focus.
      let edge =
        if rtsEdgePanAllowed(
          true,
          window.mouseInside or pointerConfined,
          window.mouseCaptured,
          mode
        ):
          rtsEdgePanDir(window.mousePos.vec2, window.size.vec2, margin)
        else:
          vec2(0)
      rtsPanDir(rtsKeyPanDir(window), edge)
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

    preferences.edgeScrolling = AlwaysEdgeScroll
    window.state.mouseInside = true
    window.state.perFrame = PerFrame()
    let size = window.size
    for human in [true, false]:
      options.playerSlot = if human: 1 else: 0
      for offset in [30'i32, 60]:
        for (pointer, direction) in [
          (ivec2(offset, size.y div 2), vec2(-1, 0)),
          (ivec2(size.x - offset, size.y div 2), vec2(1, 0)),
          (ivec2(size.x div 2, offset), vec2(0, -1)),
          (ivec2(size.x div 2, size.y - offset), vec2(0, 1))
        ]:
          cameraTarget = vec3(0)
          followSelection = not human
          actionCam = initActionCam()
          window.state.mousePos = pointer
          # HUD overlap must not create gaps in the edge scrolling band.
          overUi = true
          for frame in 0 ..< 10:
            let before = cameraTarget
            updateCamera(1.0'f / 60, true)
            let movement = cameraTarget - before
            doAssert dot(vec2(movement.x, movement.z), direction) > 0,
              "A stationary pointer inside the 60-pixel band must keep panning"
          doAssert not followSelection
          if not human:
            doAssert not actionCam.enabled,
              "Edge scrolling must release spectator camera following"
          window.state.mousePos = ivec2(size.x div 2, size.y div 2)
          let stopped = cameraTarget
          updateCamera(1.0'f / 60, true)
          doAssert cameraTarget == stopped,
            "Moving away from the edge must stop scrolling immediately"

      for pointer in [
        ivec2(61, size.y div 2),
        ivec2(size.x - 61, size.y div 2),
        ivec2(size.x div 2, 61),
        ivec2(size.x div 2, size.y - 61)
      ]:
        cameraTarget = vec3(0)
        window.state.mousePos = pointer
        updateCamera(1.0'f / 60, true)
        doAssert cameraTarget == vec3(0),
          "The 60-pixel band must not scroll from 61 pixels inside the window"

      window.state.mousePos = ivec2(30, size.y div 2)
      for gate in 0 .. 4:
        cameraTarget = vec3(0)
        chat.blocksGameplay = gate == 0
        matchMenu = if gate == 1: 1 else: HiddenMatchMenu
        shopOpen = gate == 2
        run.world.phase = if gate == 3: Drafting else: Playing
        updateCamera(1.0'f / 60, gate != 4)
        doAssert cameraTarget == vec3(0),
          "Edge scrolling must respect chat/menu/shop/draft/focus"
      chat.blocksGameplay = false
      matchMenu = HiddenMatchMenu
      shopOpen = false
      run.world.phase = Playing
      updateCamera(1.0'f / 60, true)
      doAssert cameraTarget.x < 0,
        "Edge scrolling must resume when a modal closes or focus returns"
    options.playerSlot = 1
    overUi = false
    echo "PASS continuous 60-pixel edge band, release, both camera modes and modal/focus gates"
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
      debugToggles = 0
      chromeCalls = 0
    const
      HiddenMatchMenu = 0
      PauseMenu = 1
      MatchSettings = 2
      MatchResults = 3
    proc canHumanChat(network: TestNetwork): bool = true
    proc scaleKey(window: Window, button: Button, preferences: var int,
        scale: float32, name: string): bool = false
    proc syncChatInput(window: Window, chat: ChatEditor) = discard
    proc clearHudTooltip() = discard
    proc handleChromeKey(button: Button): bool =
      ## Records debug toggles through the production callback's modal gates.
      inc chromeCalls
      if button == KeyF2:
        inc debugToggles
        return true
    proc setFullscreen(window: Window, value: bool) = discard
    proc isFullscreen(window: Window): bool = false
    proc toggleShading(scene: int) = discard
    proc epochTime(): float64 = 0
    var sk = (uiScale: 1'f32,)
    var shopResets = 0
    proc resetShopUi() = inc shopResets
    var confinementButtons: seq[Button]
    proc captureCursorConfinement(window: Window, button: Button) =
      ## Records clicks routed through the production callback before UI gates.
      confinementButtons.add button
    buttonCallback()
    bindingCapture = true
    window.onButtonPress(MouseLeft)
    bindingCapture = false
    doAssert confinementButtons == @[MouseLeft],
      "A click must reach confinement even when a UI capture consumes input"
    matchMenu = PauseMenu
    window.onButtonPress(MouseRight)
    doAssert confinementButtons == @[MouseLeft, MouseRight],
      "A click over the match menu must still reach confinement"
    matchMenu = HiddenMatchMenu
    shopOpen = true
    window.onButtonPress(KeyF2)
    doAssert debugToggles == 1 and shopOpen,
      "F2 must open debugging while the shop remains open"
    armedAbility = 1
    heldRightMove = true
    window.onButtonPress(KeyEscape)
    doAssert not shopOpen and matchMenu == HiddenMatchMenu,
      "Escape must close the shop before opening the match menu"
    doAssert not heldRightMove, "Closing the shop must retire held movement"
    doAssert shopResets == 1 and armedAbility == -1,
      "shop close must retire shop interaction and targeting"
    heldRightMove = true
    window.onButtonPress(KeyEscape)
    doAssert matchMenu == PauseMenu, "a second Escape may open the match menu"
    doAssert not heldRightMove, "Opening the menu must retire held movement"
    matchMenu = HiddenMatchMenu
    let callsBeforeSpace = chromeCalls
    window.onButtonPress(KeySpace)
    doAssert transport.playing, "human Space must not pause local playback"
    doAssert chromeCalls == callsBeforeSpace,
      "Human Space must remain reserved before configurable debug shortcuts"
    run.replayMode = true
    window.onButtonPress(KeySpace)
    doAssert not transport.playing, "replay Space must retain playback pause"
    run.replayMode = false
    heldRightMove = true
    window.onButtonPress(KeyA)
    doAssert attackMoveArmed, "A must arm attack-move, not become a mouse click"
    doAssert not heldRightMove, "Attack-move must retire ordinary held movement"
    doAssert not window.mousePressed(MouseLeft)
    doAssert not window.mouseDown(MouseMiddle), "S must not be a camera-drag alias"
    attackMoveArmed = false
    heldRightMove = true
    window.onButtonPress(KeyS)
    doAssert not heldRightMove and pending.len == 1
    doAssert pending[0].kind == CommandStop,
      "Stop must cancel held movement and queue exactly one stop"
    pending.setLen(0)
    heldRightMove = true
    window.onButtonPress(KeyEnter)
    doAssert not heldRightMove, "Opening chat must retire held movement"
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
    echo "PASS production callbacks: confinement click, human Space, replay pause, A-move, chat/menu/draft"
    matchMenu = MatchResults
    chat = ChatEditor()
    clearPlayerCommands()
    playedSounds.setLen(0)
    for button in [KeyEscape, KeyEnter, KeyQ, KeyW, KeyE, KeyR,
        KeyA, KeyS, KeyB, KeyF, KeyG, KeySpace, MouseLeft, MouseRight]:
      window.onButtonPress(button)
      doAssert matchMenu == MatchResults and not chat.typing
      doAssert pending.len == 0 and not shopOpen and not attackMoveArmed
      doAssert armedAbility == -1 and armedItem == -1
      doAssert not transport.playing,
        "Result-screen keys must not resume playback or dismiss the result"
    doAssert playedSounds.len == 0
    echo "PASS results own Escape, chat, gameplay shortcuts and mouse callbacks"
  block abilityReadiness:
    var matchMenu = 0
    const HiddenMatchMenu = 0
    production(updatePlayerSpells)
    let hero = run.world.heroes[0]
    hero.mana = 10000
    hero.level = HeroMaxLevel
    hero.abilityLevels = [1'i32, 1, 1, 1]
    overUi = true
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
        heldRightMove = true
        updatePlayerSpells()
        doAssert armedAbility == -1 and pending.len == 0 and not heldRightMove
        hero.cooldowns[slot] = 0
        doAssert hero.abilityLevelError(slot) == NoActionError,
          "The learning overlay must be available during this input test"
        let points = hero.abilityPoints
        doAssert activatePlayerAbility(run.world, hero.id, slot.ord.int32),
          "A ready ability must report successful activation"
        pending.setLen(0)
        armedAbility = -1
        playedSounds.setLen(0)
        updatePlayerSpells()
        doAssert playedSounds == @[SelectSound],
          "Ability keys must succeed while upgrade overlays are available"
        if heroAbility(hero.class, slot).abilitySpec.casting == SelfCast:
          doAssert pending.len == 1 and pending[0].kind == CommandCastTarget
          doAssert pending[0].heroId == hero.id and pending[0].first == hero.id
        else:
          doAssert armedAbility == slot.ord.int32 and pending.len == 0,
            "ready aimed abilities must still arm normally"
        pending.setLen(0)
        armedAbility = -1
        doAssert hero.abilityPoints == points and hero.abilityLevels[slot] == 1,
          "Plain ability keys must not spend upgrade points"
        window.state.buttonDown = {KeyLeftShift}
        updatePlayerSpells()
        doAssert pending.len == 1 and pending[0].kind == CommandLevelAbility
        doAssert pending[0].heroId == hero.id and pending[0].slot == slot.ord
        doAssert armedAbility == -1,
          "Shift plus an ability key must still request an upgrade"
        pending.setLen(0)
        window.state.buttonDown = {}
    overUi = false
    echo "PASS every class/slot cooldown, upgrade-overlay activation and explicit learning keys"
  window.close()

main()
