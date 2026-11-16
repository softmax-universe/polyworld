## Light vs Dark executable entry point.

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
      outcome: "winner_" & $run.world.winner
    ))
else:
  import windy, polyworld/[menus, sounds], game, graphics, frontend, lobbies,
    assets
  initializeOptions()
  try:
    var preferences = readLvdPreferences()
    configureSounds(
      preferences.soundMuted, preferences.mainVolume,
      preferences.fxVolume, preferences.uiVolume, preferences.musicVolume
    )
    initSounds(MusicPath)
    if playerNameOverride.len > 0:
      preferences.name = playerNameOverride
      preferences.savePreferences("Polyworld LvD")
    if options.botGroups.len > 0 or options.replayPath.len > 0 or
        options.playerSlot > 0 or defined(takeScreenshot):
      initializeMatch()
      runGraphics()
    if window == nil or not window.closeRequested:
      runFrontend()
  finally:
    closeSounds()
