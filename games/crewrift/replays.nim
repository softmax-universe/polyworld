## Ordered action replays with a fingerprint for every original rule tick.

import
  std/[os, strutils],
  jsony,
  sim

const ReplayVersion* = 2

type
  ReplayActionKind* = enum
    InputAction, VoteAction, ChatAction
  ReplayAction* = object
    kind*: ReplayActionKind
    slot*: int
    mask*: uint8
    choice*: int
    text*: string
  ReplayFrame* = object
    actions*: seq[ReplayAction]
    hash*: string
  ReplayData* = object
    version*: int
    config*: GameConfig
    players*: int
    playerNames*: seq[string]
    frames*: seq[ReplayFrame]

proc inputMask*(input: InputState): uint8 =
  ## Packs seven explicit buttons into one portable replay byte.
  for i, pressed in [input.up, input.down, input.left, input.right,
      input.select, input.attack, input.b]:
      if pressed:
        result = result or (1'u8 shl i)

proc readInput*(mask: uint8): InputState =
  ## Expands a portable replay byte into the original input buttons.
  result.up = (mask and 1) != 0
  result.down = (mask and 2) != 0
  result.left = (mask and 4) != 0
  result.right = (mask and 8) != 0
  result.select = (mask and 16) != 0
  result.attack = (mask and 32) != 0
  result.b = (mask and 64) != 0

proc loadReplay*(path: string): ReplayData =
  ## Loads and validates a recording before it can drive the simulation.
  try:
    result = readFile(path).fromJson(ReplayData)
  except IOError, ValueError:
    raise newException(
      CrewriftError,
      "Cannot load replay: " & getCurrentExceptionMsg()
    )
  if result.version != ReplayVersion or result.players < MinPlayers or
    result.players > MaxPlayers or result.frames.len > 1_000_000:
      raise newException(CrewriftError, "Invalid Crewrift replay header.")
  if result.playerNames.len notin [0, result.players]:
    raise newException(CrewriftError, "Invalid replay player identity count.")
  for name in result.playerNames:
    if name.len == 0 or name.len > 128 or name != cleanChatMessage(name):
      raise newException(CrewriftError, "Invalid replay player identity.")
  for frame in result.frames:
    var inputs: array[MaxPlayers, bool]
    for action in frame.actions:
      if action.slot < 0 or action.slot >= result.players:
        raise newException(CrewriftError, "Invalid replay action slot.")
      case action.kind
      of InputAction:
        if action.mask > 127:
          raise newException(CrewriftError, "Invalid replay button mask.")
        if inputs[action.slot]:
          raise newException(CrewriftError, "Duplicate replay input slot.")
        inputs[action.slot] = true
      of VoteAction:
        if action.choice < 0 or action.choice > result.players:
          raise newException(CrewriftError, "Invalid replay vote target.")
      of ChatAction:
        if action.text.len == 0 or
          action.text != cleanChatMessage(action.text):
            raise newException(CrewriftError, "Invalid replay chat text.")
    for slot in 0 ..< result.players:
      if not inputs[slot]:
        raise newException(CrewriftError, "Missing replay input slot.")

proc saveReplay*(path: string, data: ReplayData) =
  ## Saves one finished or interrupted local input recording.
  if path.len == 0:
    return
  try:
    let directory = path.parentDir
    if directory.len > 0:
      createDir(directory)
    writeFile(path, data.toJson())
  except IOError, OSError:
    raise newException(
      CrewriftError,
      "Cannot save replay: " & getCurrentExceptionMsg()
    )

proc verifyFrame*(sim: SimServer, frame: ReplayFrame) =
  ## Rejects the first simulation tick that differs from the recording.
  if sim.gameHash().toHex(16) != frame.hash:
    raise newException(
      CrewriftError,
      "Replay diverged at tick " & $sim.tickCount & "."
    )
