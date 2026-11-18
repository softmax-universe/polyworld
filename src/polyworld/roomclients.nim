import rooms

const
  MaxClientCommands* = 4096
  MaxBufferedTicks* = 128

type
  PendingCommand = object
    message: RoomMessage
    sent: bool
  RoomClient* = ref object
    identity*: GameIdentity
    name*, token*, error*, status*: string
    participant*, match*, applied*, serverTick*: uint32
    connected*, welcomed*, catchupPending*, began*: bool
    snapshot*, initialSnapshot*: RoomMessage
    appliedSeats*: seq[Seat]
    takenTick: uint32
    takenSeats: seq[Seat]
    listings*: seq[RoomListing]
    packets*: seq[RoomMessage]
    outgoing*: seq[string]
    events*: seq[RoomMessage]
    pending: seq[PendingCommand]
    rejected: seq[RoomMessage]
    sequence: uint64
    received: uint64
    timing*: PacketTiming
    receiptPending*: bool
    rejectedCommands*: uint64
    lastHash, finalHash: RoomMessage
    awaitingRoomState: bool
    recoveryReplyPending: bool
    recoveryTarget: uint32

proc setupSnapshot*(client: RoomClient): RoomMessage =
  ## Keeps match initialization separate from live administration changes.
  if client.began: client.initialSnapshot else: client.snapshot

proc catchingUp*(client: RoomClient): bool =
  ## Distinguishes missing match history from a routine live-edge probe.
  client.recoveryReplyPending or client.applied < client.recoveryTarget

proc send*(client: RoomClient, message: RoomMessage) =
  ## Adds a bounded control operation to the transport outbox.
  if message.kind == ReportHash:
    client.lastHash = message
  elif message.kind == FinishMatch:
    client.finalHash = message
  if client.outgoing.len >= 1024:
    reject("Client outgoing queue exhausted")
  var packet = message
  packet.timing.echo = client.timing.server
  packet.timing.received = client.received
  client.outgoing.add packet.encode()
  client.receiptPending = false

proc opened*(client: RoomClient) =
  ## Identifies this connection without persisting the private reconnect token.
  client.connected = true
  client.welcomed = false
  client.awaitingRoomState = false
  client.received = 0
  client.timing = PacketTiming()
  client.receiptPending = false
  client.outgoing.setLen(0)
  client.send(RoomMessage(
    kind: Hello, identity: client.identity, name: client.name, token: client.token
  ))

proc lost*(client: RoomClient) =
  ## Retains simulation, local VMs and unacknowledged submissions in memory.
  client.connected = false
  client.welcomed = false
  client.awaitingRoomState = false
  client.catchupPending = false
  client.recoveryReplyPending = client.began
  client.status = "Disconnected. Reconnecting with the same seats."
  client.outgoing.setLen(0)
  for pending in client.pending.mitems:
    pending.sent = false

proc requestHistory*(client: RoomClient, recovery = true) =
  ## Requests recovery or probes the live edge without blocking gameplay.
  if not client.welcomed or not client.began:
    return
  if recovery:
    client.recoveryReplyPending = true
  if client.catchupPending:
    return
  client.send(RoomMessage(
    kind: Catchup, match: client.match, tick: client.applied
  ))
  client.catchupPending = true

proc flushCommands*(client: RoomClient) =
  ## Retransmits commands using their original participant sequence numbers.
  if not client.welcomed:
    return
  for pending in client.pending.mitems:
    if not pending.sent:
      client.send(pending.message)
      pending.sent = true

proc hasPendingCommand*(client: RoomClient, seat: uint32): bool =
  ## Reports a seat's submissions still awaiting the authoritative tick.
  for pending in client.pending:
    if pending.message.seat == seat:
      return true

proc submit*(client: RoomClient, seat: uint32, payload: string): bool =
  ## Reports queue acceptance only, never gameplay success.
  if not client.began or payload.len > MaxCommandBytes or
    client.pending.len >= MaxClientCommands or
    seat >= uint32(client.snapshot.seats.len) or
    client.snapshot.seats[seat].owner != client.participant or
    client.snapshot.phase in {Ended, Desynced}:
      return false
  inc client.sequence
  client.pending.add PendingCommand(message: RoomMessage(
    kind: SubmitCommand, match: client.match,
    seat: seat, seatKind: client.snapshot.seats[seat].kind,
    sequence: client.sequence, payload: payload
  ))
  client.flushCommands()
  true

proc clearMatch(client: RoomClient) =
  ## Discards playback and submissions when their match cannot continue.
  client.began = false
  client.match = 0
  client.applied = 0
  client.serverTick = 0
  client.sequence = 0
  client.pending.setLen(0)
  client.rejected.setLen(0)
  client.packets.setLen(0)
  client.events.setLen(0)
  client.catchupPending = false
  client.recoveryReplyPending = false
  client.recoveryTarget = 0
  client.lastHash = RoomMessage()
  client.finalHash = RoomMessage()
  client.initialSnapshot = RoomMessage()
  client.appliedSeats.setLen(0)
  client.takenTick = 0
  client.takenSeats.setLen(0)

proc accept*(client: RoomClient, bytes: string) =
  ## Validates relay messages and preserves packets until their exact tick runs.
  let message = decode(bytes)
  if message.delivery > 0:
    if message.delivery != client.received + 1:
      reject("Relay delivery sequence is not consecutive")
    client.received = message.delivery
    client.receiptPending = true
  client.timing = message.timing
  case message.kind
  of Welcome:
    if client.participant != 0 and client.participant != message.participant:
      reject("Reconnect changed participant identity")
    client.participant = message.participant
    client.token = message.token
    client.awaitingRoomState = client.snapshot.room.len > 0
    client.welcomed = not client.awaitingRoomState
    if client.welcomed:
      client.status = "Connected"
    else:
      client.status = "Checking room membership."
    client.send(RoomMessage(kind: ListRooms))
  of RoomList:
    client.listings = message.rooms
    if client.awaitingRoomState:
      # Hello sends a membership snapshot before replying to ListRooms.
      client.awaitingRoomState = false
      client.welcomed = true
      client.snapshot = RoomMessage(kind: RoomState)
      client.clearMatch()
      client.status = "The previous room is no longer available."
  of RoomState:
    let resume = client.awaitingRoomState and client.began and
      message.room == client.snapshot.room and message.match == client.match and
      message.phase != Lobby
    client.snapshot = message
    if message.phase == Lobby or message.room.len == 0 or
        (client.awaitingRoomState and not resume):
      client.clearMatch()
    if client.awaitingRoomState:
      client.awaitingRoomState = false
      client.welcomed = true
      client.status = "Connected"
    if resume:
      client.flushCommands()
      if client.lastHash.kind == ReportHash:
        client.send(client.lastHash)
      if client.finalHash.kind == FinishMatch:
        client.send(client.finalHash)
  of BeginMatch:
    if message.hash != message.setupHash():
      reject("Initial setup hash does not match the received configuration")
    var initial = message
    initial.delivery = 0
    initial.timing = PacketTiming()
    if client.began and client.match == message.match:
      if initial != client.initialSnapshot:
        reject("Immutable match initialization changed")
      client.requestHistory()
    else:
      client.initialSnapshot = initial
      client.appliedSeats = initial.seats
      client.takenTick = 0
      client.takenSeats.setLen(0)
      client.match = message.match
      client.began = true
      client.applied = 0
      client.serverTick = 0
      client.sequence = 0
      client.packets.setLen(0)
      client.pending.setLen(0)
      client.rejected.setLen(0)
      client.lastHash = RoomMessage()
      client.finalHash = RoomMessage()
      client.catchupPending = false
      client.recoveryReplyPending = false
      client.recoveryTarget = 0
      client.events.add message
      client.requestHistory()
  of TickPacket:
    if message.match != client.match or message.tick == 0:
      reject("Tick packet belongs to an unexpected match")
    client.serverTick = max(client.serverTick, message.tick)
    for command in message.commands:
      if command.participant == client.participant:
        for i in countdown(client.pending.high, 0):
          if client.pending[i].message.sequence == command.sequence:
            client.pending.delete(i)
    if message.tick <= client.applied:
      return
    for packet in client.packets:
      if packet.tick == message.tick:
        var original = packet
        var repeated = message
        original.delivery = 0
        repeated.delivery = 0
        original.timing = PacketTiming()
        repeated.timing = PacketTiming()
        if original != repeated:
          reject("Immutable tick packet changed")
        return
    if client.packets.len >= MaxBufferedTicks:
      reject("Client tick buffer exhausted")
    client.packets.add message
  of CommandAck:
    if message.match != client.match or message.sequence > client.sequence:
      reject("Unknown command acknowledgement")
    for i in 0 ..< client.pending.len:
      if client.pending[i].message.sequence == message.sequence:
        if message.flag:
          if client.rejected.len >= MaxClientCommands:
            reject("Rejected submission queue exhausted")
          inc client.rejectedCommands
          client.rejected.add client.pending[i].message
        if message.flag or message.tick <= client.applied:
          client.pending.delete(i)
        else:
          # A reconnect receipt can arrive before the reserved tick is sealed.
          # Leave the submission sent until the authoritative echo arrives.
          client.pending[i].sent = true
        break
  of CaughtUp:
    if message.match != client.match:
      reject("Catch-up belongs to another match")
    let recovering = client.catchingUp or message.tick < message.number
    client.catchupPending = false
    client.recoveryReplyPending = false
    client.serverTick = max(client.serverTick, message.number)
    if recovering:
      client.recoveryTarget = max(client.recoveryTarget, message.number)
    if client.applied == message.number:
      client.send(RoomMessage(
        kind: AppliedTick, match: client.match, tick: client.applied
      ))
  of MatchStatus:
    if message.match != client.match:
      reject("Status belongs to another match")
    client.snapshot.phase = message.phase
    client.snapshot.flag = message.flag
    client.serverTick = max(client.serverTick, message.tick)
    client.status = message.detail
    if message.phase == Desynced:
      client.error = message.detail
  of Failure:
    client.error = message.detail
  of Keepalive:
    discard
  else:
    reject("Unexpected server message")

proc takeRejected*(client: RoomClient, submission: var RoomMessage): bool =
  ## Returns canceled local submissions so games can release UI reservations.
  if client.rejected.len == 0:
    return false
  submission = client.rejected[0]
  client.rejected.delete(0)
  true

proc takeTick*(client: RoomClient, packet: var RoomMessage): bool =
  ## Returns only the next authoritative tick, without advancing the cursor.
  if client.snapshot.phase == Desynced:
    return false
  for i in 0 ..< client.packets.len:
    if client.packets[i].tick == client.applied + 1:
      packet = client.packets[i]
      client.takenTick = packet.tick
      client.takenSeats = packet.seats
      client.packets.delete(i)
      return true
  if client.serverTick > client.applied:
    client.requestHistory()

proc appliedTick*(client: RoomClient, tick: uint32) =
  ## Acknowledges a tick only after the game simulation executed it.
  if tick != client.applied + 1:
    reject("Simulation tick did not advance exactly once")
  client.applied = tick
  if client.takenTick == tick:
    client.appliedSeats = client.takenSeats
    client.takenTick = 0
    client.takenSeats.setLen(0)
  if client.welcomed:
    client.send(RoomMessage(kind: AppliedTick, match: client.match, tick: tick))
  # A consumed push window is not proof that the relay is at this tick: asset
  # loading or a slow client may have let it advance beyond the bounded push.
  # Probe once on progress, not on empty takeTick calls or CaughtUp replies.
  if client.packets.len == 0 and
      (client.snapshot.phase in {Playing, Waiting} or
        (client.snapshot.phase == Ended and client.serverTick > client.applied)):
    client.requestHistory(recovery = false)
