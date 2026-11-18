## Completed live matches retain their final state until results are dismissed.
import
  std/[macros, os, strutils],
  windy,
  polyworld/[actioncam, inputs, player],
  ../[chats, content, game, sim]
include ../controls

type ResultWindow = object
  runeInputEnabled: bool
  buttonDown, buttonPressed: array[Button, bool]

macro production(name: untyped): untyped =
  ## Extracts the actual match transition without constructing a renderer.
  let tree = parseStmt(readFile(
    currentSourcePath().parentDir.parentDir / "graphics.nim"
  ))
  proc find(node: NimNode): NimNode =
    ## Finds the named procedure in its graphics closure.
    if node.kind == nnkProcDef and node[0].eqIdent(name.strVal):
      return node
    for child in node:
      result = find(child)
      if result != nil:
        return
  result = find(tree)
  doAssert result != nil

macro resultInput(): untyped =
  ## Extracts the production return-button and fresh-click guards together.
  let tree = parseStmt(readFile(
    currentSourcePath().parentDir.parentDir / "graphics.nim"
  ))
  proc find(node: NimNode): NimNode =
    ## Finds the adjacent result action and readiness branches.
    if node.kind == nnkStmtList:
      for i in 0 ..< node.len - 1:
        let child = node[i]
        if child.kind == nnkIfStmt and
          "drawMatchResults" in child[0][0].repr:
            doAssert "resultsInputReady" in node[i + 1].repr
            return newStmtList(child, node[i + 1])
    for child in node:
      result = find(child)
      if result != nil:
        return
  result = find(tree)
  doAssert result != nil

proc main() =
  ## Covers timeout, victory, draw, stale seeks, and replay exclusion.
  const
    HiddenMatchMenu = 0
    MatchResults = 3
  var
    transport: Player
    matchMenu = HiddenMatchMenu
    resultsInputReady: bool
    heldRightMove, attackMoveArmed, selectionStarted: bool
    minimapPanning, panning: bool
    chat: ChatEditor
    window: ResultWindow
    actionCam = initActionCam()
    shopResets, tooltipResets: int
  proc resetShopUi() =
    ## Records cleanup of an open shop gesture.
    inc shopResets
  proc clearHudTooltip() =
    ## Records cleanup of an overlapping tooltip.
    inc tooltipResets
  production(updateMatchResults)

  proc prepare() =
    ## Seeds active input and an old automatic rewind before completion.
    clearPlayerCommands()
    run = Game(world: World(phase: Playing))
    run.replayData.config.maxTicks = 3 * TickRate
    transport = initPlayer(
      live = true,
      durationTicks = run.config.maxTicks,
      playing = true,
      repeating = true
    )
    transport.restoreTick = 0
    transport.targetTick = 0
    transport.accumulator = 0.2
    matchMenu = HiddenMatchMenu
    resultsInputReady = true
    heldRightMove = true
    attackMoveArmed = true
    selectionStarted = true
    minimapPanning = true
    panning = true
    bindingCapture = true
    chat = ChatEditor(typing: true, text: "unfinished message")
    window.runeInputEnabled = true
    actionCam = initActionCam()
    shopOpen = true
    armedAbility = 1
    armedItem = 2
    queueWalkTo(101, 4, 5)
    shopResets = 0
    tooltipResets = 0

  for outcome in 0 .. 3:
    prepare()
    case outcome
    of 0:
      run.world.tick = run.config.maxTicks
      doAssert run.finished() and not run.world.gameOver and not run.world.draw,
        "A time-limit draw must not depend on the gameOver flag"
    of 1, 2:
      run.world.gameOver = true
      run.world.winner = if outcome == 1: RedTeam else: BlueTeam
    else:
      run.world.gameOver = true
      run.world.draw = true
    let finalTick = run.world.tick
    updateMatchResults()
    doAssert matchMenu == MatchResults
    doAssert not resultsInputReady,
      "Entering results must reject a click carried over from gameplay"
    doAssert not transport.playing and not transport.repeating
    doAssert transport.targetTick == -1 and transport.restoreTick == -1
    doAssert transport.accumulator == 0
    doAssert pending.len == 0 and not shopOpen
    doAssert armedAbility == -1 and armedItem == -1
    doAssert not heldRightMove and not attackMoveArmed and not selectionStarted
    doAssert not minimapPanning and not panning and not bindingCapture
    doAssert not chat.blocksGameplay and chat.text.len == 0
    doAssert not window.runeInputEnabled and not actionCam.enabled
    doAssert shopResets == 1 and tooltipResets == 1
    resultsInputReady = true
    for frame in 0 ..< 120:
      transport.sync(run.world.tick, run.world.tick, run.finished())
      updateMatchResults()
      doAssert transport.takeRestore() == -1
      transport.startFrame(1.0'f / 60, TickRate)
      doAssert not transport.shouldTick(0)
      doAssert run.world.tick == finalTick and matchMenu == MatchResults
      doAssert resultsInputReady,
        "Later result frames must preserve readiness for a fresh click"
    doAssert shopResets == 1 and tooltipResets == 1,
      "Results must remain latched without repeatedly resetting UI state"
  echo "PASS live timeout, both winners, draw, input cleanup and stable results"

  block freshResultClick:
    var
      leaveMatch = false
      quitToMenu = true
      resultClicked: bool
      network: pointer
    let
      sk = 0
      heroId = 0'i32
      ready = true
    proc drawMatchResults(sk: int, window: ResultWindow, game: Game,
        heroId: int32, online, ready: bool): bool =
      ## Supplies a button hit while the actual production guard owns exit.
      resultClicked
    proc frame(down, pressed, clicked: bool) =
      ## Runs the final result action against native-style button states.
      window.buttonDown[MouseLeft] = down
      window.buttonPressed[MouseLeft] = pressed
      resultClicked = clicked
      resultInput()
    prepare()
    run.world.tick = run.config.maxTicks
    updateMatchResults()
    frame(true, true, true)
    doAssert not leaveMatch and not resultsInputReady
    frame(false, true, true)
    doAssert not leaveMatch and not resultsInputReady,
      "Even a press and release within one frame must not skip results"
    frame(true, false, false)
    doAssert not leaveMatch and not resultsInputReady
    frame(false, false, false)
    doAssert not leaveMatch and resultsInputReady
    updateMatchResults()
    frame(true, true, true)
    doAssert leaveMatch and not quitToMenu,
      "A new click after release may return to the existing menu or lobby"
    echo "PASS final gameplay clicks cannot dismiss newly opened results"

  for replay in [false, true]:
    prepare()
    run.replayMode = replay
    run.world.gameOver = replay
    updateMatchResults()
    doAssert matchMenu == HiddenMatchMenu
    doAssert transport.playing and transport.repeating
    doAssert transport.restoreTick == 0 and transport.targetTick == 0
    doAssert pending.len == 1 and shopResets == 0 and tooltipResets == 0
  clearPlayerCommands()
  bindingCapture = false
  run = nil
  echo "PASS unfinished live games and replay playback retain their controls"

main()
