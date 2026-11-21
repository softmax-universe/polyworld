import
  std/[os, parseopt, strutils],
  polyworld/cli,
  common, brains

type Options* = object
  seed*, width*, height*: int
  offline*, noVoice*, soundMuted*, conversation*: bool
  saveDir*, prompt*, model*, selection*: string
  capture*: ScreenshotOptions

proc parseOptions*(parameters = commandLineParams()): Options =
  ## Reads Monster settings and the shared native screenshot arguments.
  var customSave = false
  result = Options(
    seed: 42, width: 1440, height: 900,
    model: DefaultMonsterModel,
    saveDir: getDataDir() / "polyworld" / "monster"
  )
  try:
    var
      arguments: seq[string]
      index = 0
      width = result.width.int32
      height = result.height.int32
    while index < parameters.len:
      let argument = parameters[index]
      if result.capture.takeCaptureFlag(parameters, index, argument):
        discard
      elif takeWindowSizeFlag(width, height, parameters, index, argument):
        result.width = width.int
        result.height = height.int
      elif result.soundMuted.takeSoundFlag(argument):
        result.conversation = not result.soundMuted
      else:
        arguments.add argument
      inc index
    if arguments.len > 0:
      for kind, key, value in getopt(arguments):
        case kind
        of cmdLongOption, cmdShortOption:
          case key
          of "seed":
            result.seed = parseInt(value)
          of "width":
            result.width = parseInt(value)
          of "height":
            result.height = parseInt(value)
          of "save-dir":
            result.saveDir = absolutePath(value)
            customSave = true
          of "select":
            result.selection = value
          of "prompt":
            result.prompt = value
          of "model":
            result.model = value
          of "offline":
            result.offline = true
          of "no-voice":
            result.noVoice = true
          of "help", "h":
            echo "Monster / Polyworld"
            echo "Run from the repository: nim r games/monster/monster.nim"
            echo "Options: --model:ID --seed:N --save-dir:PATH --offline"
            echo "Modes: Text, or Conversation with an OpenAI key."
            echo "Conversation listens continuously and supports interruption."
            echo "Audio: --no-voice disables Conversation; --unmute starts it."
            echo "Capture: --screenshot PATH --frames N --windowSize WxH"
            echo "Capture defaults to 30 frames and does not save game progress."
            echo "Add --prompt:TEXT to wait for an explicit model instruction."
            echo "Inspect a profile with --select:moss or a person/place ID."
            echo "Or use -d:takeScreenshot (default: output/monster.png)."
            echo "Camera: right-drag to pan, wheel to zoom, F to find Moss."
            echo "Click or drag the minimap to look around; click Moss to follow."
            echo "Left-click a villager, house, or stash to inspect it."
            echo "Conversation: Enter to speak, Escape to release focus."
            quit(0)
          else:
            raise newException(MonsterError, "Unknown option: " & key)
        of cmdArgument:
          raise newException(MonsterError, "Unexpected argument: " & key)
        of cmdEnd:
          discard
    result.capture.validateCapture()
  except ValueError, ScreenshotError:
    raise newException(MonsterError,
      "Invalid Monster option: " & getCurrentExceptionMsg())
  if result.width < 640 or result.height < 480:
    raise newException(MonsterError, "Use at least a 640x480 window.")
  if not customSave:
    result.saveDir = result.saveDir / $result.seed
