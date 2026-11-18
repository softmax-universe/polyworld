## Verify the unit loop uses authoritative inputs, without replacing tooltips.
import std/[os, strutils, unittest]

suite "LvD training command integration":
  test "faction and queue count come from the current player and selected producer union":
    let source = readFile(currentSourcePath().parentDir / "../ui.nim")
    let start = source.find("    elif action <= TrainSummonShortcut:")
    let finish = source.find("  else:", start)
    let units = source[start ..< finish]
    check units.contains("sk.drawTrainPortrait(")
    check units.contains("teamColors[player]")
    check units.contains("run.world.selectedTrainingCount(player, selectedIds, kind)")
    check source.contains("run.world.performShortcut(options.playerSlot - 1, selectedIds, action)")
    check units.contains("unitTooltipTarget(kind, player)")
    check units.contains("sk.drawTrainCosts(")
