## Run: nim r games/light_vs_dark/tests/manual_pathing.nim
## Uses the standard LvD renderer, units, terrain, HUD, and replay transport.
## Keys: 1-5 scenes, Space pause, R replay, S speed, P paths, F frame, Esc menu.
## Capture: --scenario=5 --ticks=240 --capture=output/lvd-pathing.png

import
  std/[os, strutils],
  polyworld/[cli, menus],
  ../[game, graphics],
  pathinggraphics, pathingscenarios

type
  PathingOptions = object
    scenario: PathingScenario
    capture: string
    ticks: int32
    pause, help: bool
    soundMuted, soundOverride: bool

proc readOptions(): PathingOptions =
  ## Reads scene and capture options without invoking the match CLI parser.
  result.ticks = 240
  for argument in commandLineParams():
    if result.soundMuted.takeSoundFlag(argument):
      result.soundOverride = true
    elif argument in ["--help", "-h"]:
      result.help = true
    elif argument == "--pause":
      result.pause = true
    elif argument.startsWith("--scenario="):
      let index = parseInt(argument.split('=', 1)[1])
      if index notin 1 .. 5:
        raise newException(ValueError, "Scenario must be 1 through 5")
      result.scenario = PathingScenario(index - 1)
    elif argument.startsWith("--ticks="):
      let ticks = parseInt(argument.split('=', 1)[1])
      if ticks notin 0 .. PathingDurationTicks:
        raise newException(ValueError, "Capture ticks must be 0 through 1800")
      result.ticks = ticks.int32
    elif argument.startsWith("--capture="):
      result.capture = argument.split('=', 1)[1]
      if result.capture.len == 0:
        raise newException(ValueError, "Capture needs an output PNG path")
    else:
      raise newException(ValueError, "Unknown manual pathing option: " & argument)

proc main() =
  ## Loads the standard renderer once and switches fixtures in place.
  let settings = readOptions()
  if settings.help:
    echo """Light vs Dark manual pathing test (standard game renderer).
Run: nim r games/light_vs_dark/tests/manual_pathing.nim
1-5: scenario / Space: pause / R: replay / S: speed / P: paths
F: frame scenario / Scroll: zoom / Middle drag or arrows: pan
F12: screenshot / Escape: game menu
Options: --scenario=1..5 --pause --ticks=240 --capture=output/lvd-pathing.png
Audio: saved volumes by default; --mute[=BOOL], --unmute"""
    return
  options.soundMuted = settings.soundMuted
  options.soundOverride = settings.soundOverride
  configureSoundLaunch(settings.soundMuted, settings.soundOverride)
  options.windowWidth = 1600
  options.windowHeight = 1000
  options.playerSlot = 0
  options.viewMode = 0
  options.maximumTicks = PathingDurationTicks
  options.recordPath = ""
  options.pauseOnStart = settings.pause or settings.capture.len > 0
  if settings.capture.len > 0:
    options.vsync = false
  runGraphics(
    hooks = pathingHooks(settings.scenario, settings.capture, settings.ticks),
    hidden = settings.capture.len > 0
  )

main()
