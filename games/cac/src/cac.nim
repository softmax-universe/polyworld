## Cards and Casters — Polyworld native and browser client.
## Reads the command line and starts a game mode.
import std/os
import core/[sim, cardlist]
export sim

when not defined(headless):
  import std/[options, strutils]
  import windy
  import polyworld/[connections, menus, sounds]
  import core/[sessions, replays, bots], app, replayer, scene/post,
    modes/duel, modes/multiplayer, frontend

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
    echo "Cards and Casters\n" &
      "Options (--key value or --key=value):\n" &
      "  --menu           Open the main menu (default without match flags)\n" &
      "  --direct         Launch a match without the menus\n" &
      "  --server URL     Open multiplayer using a Polyworld relay\n" &
      "  --room CODE      Join a room on the selected relay\n" &
      "  --players N      Player count (2). 2 plays a duel; 3 to 7 play a\n" &
      "                   multiplayer match: the last player alive wins.\n" &
      "  --seed INTEGER   Set the battle seed\n" &
      "  --bot PATH       Bot program (.bas), repeatable up to " & $PlayerCount &
        " times.\n" &
      "                   Duel: one bot plays both seats; with --human it\n" &
      "                   plays the opponent. Multiplayer: the bots take\n" &
      "                   every seat but yours, in turn.\n" &
      "                   Defaults to the reference bots in players/.\n" &
      "  --human [PATH]   Play seat 0 yourself instead of watching bots.\n" &
      "                   With a bot program (.bas), play the class and deck\n" &
      "                   it lists; otherwise choose a class on screen and\n" &
      "                   play its precon.\n" &
      "  --replay PATH    Watch a recorded match (see --record in the\n" &
      "                   headless build)\n" &
      "  --mute           Mute this launch; otherwise use saved settings\n" &
      "  --unmute         Enable sound for this launch (--mute=false)\n" &
      "  --cards          List every card and exit\n" &
      "  --cards:CLASS    List one class's cards (archer, warrior or mage)\n" &
      "                   and exit\n" &
      "  --card:NAME      Show one card and exit; case, spaces and hyphens\n" &
      "                   don't matter (--card:hail-of-arrows)\n" &
      "  -h, --help       Show this help and exit"

  proc readHumanSeat(path: string, seats: int, seed: int64): Seat =
    ## The class and deck a bot script lists, for the human to play. Only
    ## its setup runs. An illegal deck is reported and seats them with none.
    try:
      resetInboxes(seats)
      let vm = loadBot(readFile(path), 0)
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
    var soundExplicit = false
    for argument in commandLineParams():
      if argument == "--unmute" or argument.startsWith("--mute"):
        soundExplicit = true
    configureSoundLaunch(options.soundMuted, soundExplicit)
    when defined(takeScreenshot):
      options.menu = "--menu" in commandLineParams()
    when defined(replayViewer):
      options.menu = false
    # Before initApp, which moves to the Polyworld folder.
    for path in options.botPaths.mitems:
      path = absolutePath(path)
    var humanSeat: Option[Seat]
    if options.humanDeckPath.len > 0:
      humanSeat = some(readHumanSeat(options.humanDeckPath,
        max(options.playerCount, PlayerCount), options.seed))
    var replay: Replayer
    if options.replayPath.len > 0:
      # Before initApp, which moves to the Polyworld folder.
      replay = newReplayer(loadReplay(options.replayPath))
      options.playerCount = replay.classes.len
      options.human = false
    let app = initApp(options)
    initSounds()
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
          if app.options.playerCount > PlayerCount:
            app.runMultiplayer()
          else:
            app.runDuel()
        else:
          app.replay = nil
          app.humanSeat = none(Seat)
          let selected = app.runFrontend(connection, returnToLobby)
          if selected.kind == ExitFrontend:
            break
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
