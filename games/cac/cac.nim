## Cards and Casters — Polyworld native and browser client.
## Reads the command line and starts a game mode.
import std/os
import core/[sim, cardlist]
export sim

when not defined(headless):
  import std/options
  import windy
  import polyworld/[cli, connections, menus, screenshots, sounds]
  import core/[sessions, replays, bots], app, replayer, scene/post,
    modes/duel, modes/multiplayer, frontend, paths

  static:
    # Lists the compile-time (-d:) flags while this build compiles.
    proc onOff(on: bool): string = (if on: "ON" else: "OFF")
    const Rule = "-------------------------"
    echo Rule
    echo "Flags"
    echo Rule
    echo " cacPostPanel = ", onOff(PostPanelControls)
    echo " cacPostLayers = ", onOff(PostLayerControls)
    echo " cacLayoutTuning = ", onOff(defined(cacLayoutTuning))
    echo " takeScreenshot = ", onOff(defined(takeScreenshot))
    echo Rule

  proc printHelp() =
    ## Lists shared launch arguments and CaC-specific setup choices.
    echo "Cards and Casters"
    echo commonUsageFor(SessionFlags)
    echo "  --menu           Open the main menu (default without match flags)"
    echo "  --direct         Launch a match without the menus"
    echo "  --players N      Set 2 to 7 seats (defaults to supplied roster or 2)"
    echo "  --deck PATH      Read the human class/deck from a bot setup script"
    echo "                   Requires --player; only the setup program runs"
    echo "  --cards          List every card and exit"
    echo "  --cards:CLASS    List archer, warrior, or mage cards and exit"
    echo "  --card:NAME      Show one card and exit"
    echo "  -h, --help       Show this help and exit"
    echo "Supply one bot per nonhuman seat; absent bots use bundled defaults."

  proc readHumanSeat(path: string, seats: int, seed: int64, player: int32): Seat =
    ## The class and deck a bot script lists, for the human to play. Only
    ## its setup runs. An illegal deck is reported and seats them with none.
    try:
      resetInboxes(seats)
      let vm = loadBot(readFile(path), player)
      result = vm.setupSeat(seats, seed)
      for problem in vm.deckProblems:
        stderr.writeLine "Your deck in ", path, " is illegal: ", problem
    except IOError, BasicError:
      quit "Cannot read a deck from " & path & ": " & getCurrentExceptionMsg()

  proc runCac*() =
    ## Runs the shared menus and matches without replacing the window.
    if "--help" in commandLineParams() or "-h" in commandLineParams():
      printHelp()
      return
    # The card reference needs no window.
    if printCardReference(commandLineParams()):
      return
    var options = parseSessionOptions(commandLineParams())
    options.resolveSessionPaths()
    configureCapture(options.capture, "cac.png")
    configureSoundLaunch(options.soundMuted or captureActive(),
      options.common.soundOverride or captureActive())
    when defined(takeScreenshot):
      options.menu = "--menu" in commandLineParams()
    when defined(replayViewer):
      options.menu = false
    var humanSeat: Option[Seat]
    if options.humanDeckPath.len > 0:
      humanSeat = some(readHumanSeat(options.humanDeckPath,
        max(options.playerCount, PlayerCount), options.seed,
        options.common.playerSlot - 1))
    var replay: Replayer
    if options.replayPath.len > 0:
      # Before initApp, which moves to the Polyworld folder.
      replay = newReplayer(loadReplay(options.replayPath))
      options.playerCount = replay.classes.len
      options.human = false
    let app = initApp(options)
    initSounds(CacMusicPath)
    app.replay = replay
    app.humanSeat = humanSeat
    var
      directLaunch = not options.menu
      connection: Connection
      returnToLobby = false
    try:
      while not app.window.closeRequested:
        app.returnToMenu = false
        if directLaunch:
          directLaunch = false
          if app.options.playerCount > PlayerCount or
              app.options.common.playerSlot > 1:
            app.runMultiplayer()
          else:
            app.runDuel()
        else:
          app.replay = nil
          app.humanSeat = none(Seat)
          let selected = app.runFrontend(connection, returnToLobby)
          if selected.kind == ExitFrontend:
            break
          when not defined(emscripten):
            if selected.kind == ReplayFrontend:
              let previousOptions = app.options
              try:
                app.network = nil
                app.connection = nil
                app.configuredSeats = @[]
                app.configuredBotSources = @[]
                app.configuredHumanSeat = -1
                app.playerNames = @[]
                app.replay = newReplayer(loadReplay(selected.replayPath))
                app.options.replayPath = selected.replayPath
                app.options.botPaths = @[]
                app.options.humanDeckPath = ""
                app.options.human = false
                app.options.playerCount = app.replay.classes.len
                if app.options.playerCount > PlayerCount:
                  app.runMultiplayer()
                else:
                  app.runDuel()
              except CatchableError as problem:
                app.preferenceError = problem.msg
                app.window.closeRequested = false
              finally:
                app.window.onFrame = nil
                app.window.onButtonPress = nil
                app.options = previousOptions
                app.replay = nil
              returnToLobby = false
              continue
          app.connection = connection
          app.network = selected.network
          app.configuredSeats = selected.seats
          app.configuredBotSources = selected.botSources
          app.configuredHumanSeat = selected.humanSeat
          app.playerNames = selected.playerNames
          app.options.seed = selected.seed
          app.options.seedGiven = true
          app.options.human = selected.humanSeat >= 0
          app.options.playerCount =
            if selected.kind == NetworkFrontend:
              selected.network.game.playerCount
            else:
              selected.seats.len
          app.runMultiplayer()
        returnToLobby = app.network != nil and connection != nil and
          connection.client.snapshot.room.len > 0
        app.network = nil
    finally:
      app.window.onFrame = nil
      app.window.onButtonPress = nil
      connection.close()
      app.closeCapture()
      closeSounds()

  when isMainModule:
    runCac()

when defined(headless):
  import modes/headless
  when isMainModule:
    when defined(coworld):
      runCoworld()
    else:
      if not printCardReference(commandLineParams()):
        runHeadless()
