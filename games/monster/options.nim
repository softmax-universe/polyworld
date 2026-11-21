import
  std/os,
  polyworld/cli,
  common, brains

type Options* = object
  game*: GameOptions
  offline*, noVoice*, conversation*: bool
  saveDir*, prompt*, model*, selection*: string

proc help() =
  ## Describes supported common settings and Monster's conversation options.
  echo "Monster / Polyworld"
  echo "Run from the repository: nim r games/monster/monster.nim"
  echo "Common: --seed N --windowSize WxH --vsync BOOL"
  echo "        --play BOOL --speed N --mute --unmute --verbose"
  echo "Capture: --screenshot PATH --frames N (default 30)"
  echo "Options: --model ID --save-dir PATH --offline --select ID"
  echo "         --prompt TEXT --conversation --no-voice"
  echo "Valued options accept separate, equals, or colon values."
  echo "Conversation starts the microphone; --unmute only enables sound."
  echo "Capture does not save progress or start voice or inference."
  echo "Add --prompt TEXT to wait for an explicit model instruction."
  echo "Monster has no BASIC bot roster or action replay playback."
  echo "Camera: right-drag to pan, wheel to zoom, F to find Moss."
  echo "Space pauses or resumes while the text editor is unfocused."
  echo "Click or drag the minimap to look around; click Moss to follow."
  echo "Left-click a villager, house, or stash to inspect it."
  echo "Conversation: Enter to speak, Escape to release focus."

proc parseOptions*(parameters = commandLineParams()): Options =
  ## Reads common launch arguments and Monster's own conversation settings.
  var customSave = false
  result = Options(
    game: GameOptions(seed: 42, windowWidth: 1440, windowHeight: 900,
      speed: 1),
    model: DefaultMonsterModel,
    saveDir: getDataDir() / "polyworld" / "monster"
  )
  try:
    var index = 0
    while index < parameters.len:
      let
        argument = parameters[index]
        name = splitFlag(argument).name
      if result.game.takeCommonFlag(parameters, index, argument):
        discard
      else:
        case name
        of "--save-dir":
          result.saveDir = absolutePath(
            parameters.flagValue(index, argument)
          )
          customSave = true
        of "--select":
          result.selection = parameters.flagValue(index, argument)
        of "--prompt":
          result.prompt = parameters.flagValue(index, argument)
        of "--model":
          result.model = parameters.flagValue(index, argument)
        of "--offline", "--no-voice", "--conversation":
          if argument != name:
            raise newException(MonsterError, name & " does not take a value")
          case name
          of "--offline": result.offline = true
          of "--no-voice": result.noVoice = true
          else: result.conversation = true
        of "--help", "-h":
          help()
          quit(0)
        of "--width", "--height":
          raise newException(MonsterError, "Use --windowSize WIDTHxHEIGHT")
        else:
          raise newException(MonsterError, "Unknown option: " & argument)
      inc index
    result.game.rejectUnsupportedFlags({SeedFlag, WindowSizeFlag, VsyncFlag,
      PlayFlag, SpeedFlag, SoundFlag, VerboseFlag, ScreenshotFlag, FramesFlag})
    result.game.validateGameOptions(0, "")
  except ValueError, ScreenshotError:
    raise newException(MonsterError,
      "Invalid Monster option: " & getCurrentExceptionMsg())
  if result.game.windowWidth < 640 or result.game.windowHeight < 480:
    raise newException(MonsterError, "Use at least a 640x480 window.")
  if not customSave:
    result.saveDir = result.saveDir / $result.game.seed
