## Heartleaf launch options without creating a world or loading bots.

import
  polyworld/cli,
  content, seeking

when not defined(headless) and not defined(emscripten):
  import std/os

type LaunchOptions* = object
  common*: GameOptions
  dayCount*: int32
  startupTarget*: SeekTarget
  durationLimited*: bool
  showHelp*: bool

const HeartleafCommonFlags* =
  when defined(headless):
    AllCommonFlags - {NameFlag, ServerFlag, RoomFlag, LlmModeFlag}
  else:
    AllCommonFlags - {
      NameFlag, ServerFlag, RoomFlag, LlmModeFlag, HeadlessTickRateFlag
    }

proc parseLaunchOptions*(arguments: seq[string]): LaunchOptions =
  ## Parses the shared launch contract and Heartleaf's calendar and seek flags.
  result.common = GameOptions(seed: DefaultSeed, speed: 1)
  result.dayCount = DefaultDayCount
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if result.common.takeCommonFlag(arguments, index, argument):
      discard
    elif argument in ["--help", "-h"]:
      result.showHelp = true
      return
    else:
      let flag = splitFlag(argument).name
      if flag notin ["--days", "--seek-tick", "--seek-event"]:
        raise newException(CliError, "unknown argument: " & argument)
      let value = arguments.flagValue(index, argument)
      if flag == "--days":
        result.dayCount = parsePositiveInt32(value, flag)
        if result.dayCount > MaxDayCount:
          raise newException(CliError,
            "--days must be at most " & $MaxDayCount)
      else:
        if result.startupTarget.kind != NoSeek:
          raise newException(CliError,
            "only one startup seek target is allowed")
        result.startupTarget = parseSeekTarget(flag, value)
    inc index
  result.common.rejectUnsupportedFlags(HeartleafCommonFlags)
  result.durationLimited = (result.common.specifiedFlags * DurationFlags) != {}
  if not result.durationLimited:
    result.common.setMaximumTicks(gameLengthTicks(result.dayCount))
  else:
    result.common.setMaximumTicks(min(
      result.common.maximumTicks, gameLengthTicks(result.dayCount)
    ))
  when defined(emscripten):
    if result.common.botGroups.len == 0 and
      result.common.replayPath.len == 0:
        result.common.botGroups.add BotGroup(
          path: "/players/base.bas",
          count: VillagerCount - ord(result.common.playerSlot > 0)
        )
  elif not defined(headless):
    if result.common.capture.path.len > 0 and
      result.common.botGroups.len == 0 and
      result.common.replayPath.len == 0 and result.common.playerSlot == 0:
        result.common.botGroups.add BotGroup(
          path: currentSourcePath().parentDir / "players" / "base.bas",
          count: VillagerCount
        )
  result.common.validateGameOptions(
    VillagerCount,
    "a live game requires exactly nine bots"
  )
  if result.startupTarget.kind != NoSeek and result.common.playerSlot > 0:
    raise newException(CliError,
      "startup seeking requires a replay or nine scripted bots")
  result.common.resolveGamePaths()

proc executionTicks*(options: LaunchOptions, available: int32): int32 =
  ## Applies an explicit duration without changing the recorded calendar setup.
  if options.durationLimited:
    min(options.common.maximumTicks, available)
  else:
    available
