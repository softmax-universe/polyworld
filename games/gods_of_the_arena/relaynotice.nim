## Game-owned relay policy: a bounded draft clock, NOT a game simulation.
## Opt in only to the exact gameplay/network contract below. No world/maps/VMs.
import polyworld/[rooms, rngs]
import content, presets

const
  NoticeGameplay* = 79'u32
  NoticeProtocol* = 4'u32
  ServerNoticeSeat* = high(uint32)
  ThreeMinuteNotice* = "3 minutes remain"
  NoticeCategory* = 3'u32
  ThreeMinuteEvent* = 1'u32

type RelayNotice* = object
  enabled: bool
  maximum: int32
  mode: DraftMode
  order: seq[int]
  classes: seq[int32]
  turn, turnTicks: int
  rng: Rng
  due: uint32

proc supportsRelayNotice*(identity: GameIdentity): bool =
  identity.game == "gods_of_the_arena" and
    identity.gameplay == NoticeGameplay and identity.protocol == NoticeProtocol

proc noticePayload*(): string =
  result.put32(NoticeCategory)
  result.put32(ThreeMinuteEvent)

proc reservedNoticePayload*(payload: string): bool =
  if payload.len < 4: return false
  var reader = PacketReader(data: payload)
  reader.get32() == NoticeCategory

proc initRelayNotice*(identity: GameIdentity, payload: string,
    tickRate: uint32, seats: openArray[Seat]): RelayNotice =
  if not identity.supportsRelayNotice(): return
  if tickRate != TickRate.uint32 or seats.len != 10:
    reject("GotA notice policy requires ten seats and 24 ticks per second")
  var config: GotaConfig
  try: config = parseConfig(payload)
  except CatchableError:
    reject("Invalid GotA notice schedule config: " & getCurrentExceptionMsg())
  if config.maxTicks > high(int32) - PreparationTicks - 10 * DraftPickTicks:
    reject("GotA notice schedule duration overflows")
  result.maximum = config.maxTicks
  result.enabled = config.maxTicks > 180 * TickRate
  result.mode = config.draftMode
  result.classes = newSeq[int32](10)
  for value in result.classes.mitems: value = -1
  var occupied: seq[int]
  for seat, value in seats:
    if value.owner != 0: occupied.add seat
  if occupied.len == 0: reject("GotA notice schedule requires occupied seats")
  result.rng = initRng(config.seed)
  # newGame's only pre-draft order-stream draw (camps use a separate RNG).
  discard result.rng.below(occupied.len.int32)
  var team = result.rng.below(2).int
  var next: array[2, int]
  while result.order.len < occupied.len:
    while next[team] < occupied.len:
      let seat = occupied[next[team]]
      inc next[team]
      if (if seat < 5: 0 else: 1) == team:
        result.order.add seat
        break
    team = 1 - team

proc available(state: RelayNotice, class: int32): bool =
  if class < 0 or class >= 10: return false
  for seat, picked in state.classes:
    if picked != class: continue
    case state.mode
    of UniqueDraft: return false
    of TeamDraft:
      if (seat < 5) == (state.order[state.turn] < 5): return false
    of OpenDraft: discard
  true

proc pick(state: var RelayNotice, class: int32) =
  state.classes[state.order[state.turn]] = class
  inc state.turn
  state.turnTicks = 0

proc advanceNotice*(state: var RelayNotice, tick: uint32,
    commands: openArray[Command]): bool =
  if not state.enabled: return false
  if state.turn < state.order.len:
    inc state.turnTicks
    # Mirror only valid draft picks in the authoritative command order.
    for command in commands:
      if state.turn == state.order.len: break
      if command.payload.len != 32: continue
      var reader = PacketReader(data: command.payload)
      if reader.get32() != 0: continue
      let hero = cast[int32](reader.get32())
      if reader.get32() != 18: continue # ActionDraft
      discard reader.get32() # slot
      let class = cast[int32](reader.get32())
      if command.seat.int != state.order[state.turn] or
          hero != 100 + state.order[state.turn].int32 or not state.available(class):
        continue
      state.pick(class)
    if state.turn < state.order.len and state.turnTicks == DraftPickTicks:
      var choices: seq[int32]
      for class in 0'i32 .. 9'i32:
        if state.available(class): choices.add class
      state.pick(choices[state.rng.below(choices.len.int32)])
    if state.turn == state.order.len:
      state.due = tick + uint32(PreparationTicks + state.maximum - 180 * TickRate)
  if state.due != 0 and tick == state.due:
    state.enabled = false
    return true

proc validNotice*(command: Command): bool =
  command.participant == 0 and command.seat == ServerNoticeSeat and
    command.sequence == 1 and command.payload == noticePayload()
