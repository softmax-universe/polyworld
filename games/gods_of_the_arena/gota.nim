## Gods of the Arena executable entry point.

when defined(headless):
  import game
  initializeOptions()
  initializeMatch()
  runHeadless()
  when defined(coworld):
    import polyworld/coworld
    import sim
    finishCoworld(CoworldResults(
      scores: run.world.scores(),
      ticks: run.world.tick,
      seed: options.seed,
      outcome: run.world.outcome()
    ), run.world.totalXp())
else:
  import
    windy, polyworld/[menus, sounds, viewers],
    assets, game, graphics, frontend, pointers, settings
  initializeOptions()
  configureCapture(options.capture, "games/gods_of_the_arena/gota_shot.png")
  configureSoundLaunch(captureActive() or options.soundMuted,
    captureActive() or options.soundOverride)
  try:
    var preferences = readGotaPreferences()
    configureSounds(
      false, preferences.mainVolume,
      preferences.fxVolume, preferences.uiVolume, preferences.musicVolume
    )
    if not captureActive():
      initSounds(GotaMusicPath)
    if playerNameOverride.len > 0:
      preferences.name = playerNameOverride
      preferences.savePreferences("Polyworld GotA")
    localPlayerName = preferences.name
    if options.botGroups.len > 0 or options.replayPath.len > 0 or
      options.playerSlot > 0:
        initializeMatch()
        runGraphics()
    if window == nil or not window.closeRequested:
      runFrontend()
  finally:
    releaseCursorConfinement()
    releaseGotaCapture()
    closeSounds()
