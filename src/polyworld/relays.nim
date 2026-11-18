import
  std/[strutils, sysrand, times],
  rooms

const
  MaxRooms* = 64
  MaxGuests* = 512
  MaxHistoryBytes* = 128 * 1024 * 1024
  MaxTotalHistoryBytes* = 512 * 1024 * 1024
  MaxUnacknowledgedBytes* = 512 * 1024
  MaxInputBytesPerSecond* = 256 * 1024
  CatchupBatch* = 16

type
  Delivery = object
    id, stamp: uint64
    bytes: int
  Checkpoint = object
    present: bool
    hash: uint64
    participant: uint32
  Receipt = object
    tick: uint32
    seat: uint32
    seatKind: SeatKind
    payload: string
    discarded: bool
  Guest* = ref object
    id*: uint32
    connection*: int
    identity*: GameIdentity
    name*, token*: string
    room*: string
    ready*, recovering*: bool
    applied*, hashTick*, finishTick: uint32
    hash, finishHash: uint64
    receipts: seq[Receipt]
    deliveries: seq[Delivery]
    delivered, received: uint64
    unacknowledged, inputBytes: int
    lastSeen, inputEpoch: float64
    timing: PacketTiming
  RelayRoom* = ref object
    id*, name*: string
    identity*: GameIdentity
    owner*: uint32
    public*, paused*: bool
    phase*: RoomPhase
    revision*, match*, tickRate*, tick*: uint32
    payload*: string
    seats*: seq[Seat]
    participants*: seq[uint32]
    pending*: seq[Command]
    history*: seq[string]
    historyBytes, pendingBytes: int
    initial*: RoomMessage
    checkpoints: seq[Checkpoint]
    finalTick: uint32
    finalHash: uint64
    deadline*: float64
    detail*, pausedBy: string
  Outgoing* = object
    connection*: int
    bytes*: string
    close*: bool
  Relay* = ref object
    logEvents*: bool
    guests*: seq[Guest]
    rooms*: seq[RelayRoom]
    outgoing*: seq[Outgoing]
    nextId: uint32
    now: float64

proc secret(): string =
  ## Creates an unguessable reconnect token from operating-system entropy.
  var bytes: array[24, byte]
  if not urandom(bytes):
    reject("Cannot obtain reconnect token entropy")
  for value in bytes:
    result.add toHex(value, 2).toLowerAscii

proc guest*(relay: Relay, id: uint32): Guest =
  ## Looks up a stable participant identity.
  for candidate in relay.guests:
    if candidate.id == id:
      return candidate

proc connectionGuest(relay: Relay, connection: int): Guest =
  ## Finds the participant bound to one live connection.
  for candidate in relay.guests:
    if candidate.connection == connection:
      return candidate

proc room*(relay: Relay, id: string): RelayRoom =
  ## Finds a room without interpreting its game identity.
  for candidate in relay.rooms:
    if candidate.id == id:
      return candidate

proc newRoomId*(relay: Relay,
    entropy: proc(bytes: var openArray[byte]): bool = urandom): string =
  ## Short invite codes are discovery IDs, not authentication secrets.
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  var bytes: array[6, byte]
  # Bound both collision retries and rejection sampling entropy requests.
  for attempt in 0 ..< 32:
    if not entropy(bytes):
      reject("Cannot obtain room code entropy")
    for value in bytes:
      # Reject the incomplete alphabet bucket instead of biasing modulo 36.
      if int(value) < 256 - (256 mod alphabet.len):
        result.add alphabet[int(value) mod alphabet.len]
        if result.len == 6:
          break
    if result.len == 6:
      if relay.room(result) == nil:
        return
      result.setLen(0)
  reject("Cannot allocate a unique room code")

proc controls(room: RelayRoom, id: uint32): bool =
  ## Reports whether a participant owns any seats in this room.
  for seat in room.seats:
    if seat.owner == id:
      return true

proc controlledAt(room: RelayRoom, id, tick: uint32): bool =
  ## Recognizes controllers at either side of an immutable completed tick.
  if tick == 0 or tick > uint32(room.history.len):
    return false
  let before = if tick == 1: room.initial.seats
    else: decode(room.history[int(tick) - 2]).seats
  for seat in before:
    if seat.owner == id:
      return true
  let packet = decode(room.history[int(tick) - 1])
  for seat in packet.seats:
    if seat.owner == id:
      return true
  for command in packet.commands:
    if command.participant == id:
      return true

proc logEvent*(
    relay: Relay, event: string, connection = 0,
    room: RelayRoom = nil, detail = ""
) =
  ## Echoes lifecycle events without tokens, invite codes or game payloads.
  if not relay.logEvents:
    return
  var
    line = getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'") & " " & event
    activeRoom = room
  if connection > 0:
    line.add " connection=" & $connection
    let guest = relay.connectionGuest(connection)
    if guest != nil:
      line.add " player=" & $guest.id & " name=" & guest.name.escape &
        " game=" & guest.identity.game.escape &
        " gameplay=" & $guest.identity.gameplay &
        " protocol=" & $guest.identity.protocol
      if activeRoom == nil:
        activeRoom = relay.room(guest.room)
  if activeRoom != nil:
    line.add " room=" & activeRoom.name.escape &
      " owner=" & $activeRoom.owner & " match=" & $activeRoom.match &
      " tick=" & $activeRoom.tick
  if detail.len > 0:
    line.add " detail=" & detail.escape
  echo line

proc send(relay: Relay, guest: Guest, message: RoomMessage) =
  ## Bounds transport credit until the peer acknowledges receiving bytes.
  if guest == nil or guest.connection == 0:
    return
  var packet = message
  inc guest.delivered
  packet.delivery = guest.delivered
  packet.timing = guest.timing
  packet.timing.server = uint64(max(0.0, relay.now) * 1_000_000)
  let bytes = packet.encode()
  if guest.unacknowledged + bytes.len > MaxUnacknowledgedBytes:
    relay.logEvent("connection.backpressure", guest.connection,
      detail = "Unacknowledged outgoing byte limit exceeded")
    relay.outgoing.add Outgoing(connection: guest.connection, close: true)
    guest.connection = 0
    return
  guest.deliveries.add Delivery(id: packet.delivery, stamp: packet.timing.server,
    bytes: bytes.len)
  guest.unacknowledged += bytes.len
  relay.outgoing.add Outgoing(connection: guest.connection, bytes: bytes)

proc broadcast(relay: Relay, room: RelayRoom, message: RoomMessage) =
  ## Sends control state to connected room participants.
  for id in room.participants:
    relay.send(relay.guest(id), message)

proc state*(relay: Relay, room: RelayRoom): RoomMessage =
  ## Produces a lobby snapshot without exposing reconnect secrets.
  result = RoomMessage(
    kind: RoomState, room: room.id, name: room.name,
    participant: room.owner, revision: room.revision, phase: room.phase,
    match: room.match, tickRate: room.tickRate, payload: room.payload,
    # Lobby snapshots expose visibility; match snapshots expose pause state.
    flag: (if room.phase == Lobby: room.public else: room.paused),
    seats: room.seats
  )
  for id in room.participants:
    let guest = relay.guest(id)
    result.participants.add Participant(
      id: id, name: guest.name, connected: guest.connection != 0,
      ready: guest.ready
    )

proc publish(relay: Relay, room: RelayRoom) =
  ## Publishes the current room snapshot.
  relay.broadcast(room, relay.state(room))

proc playbackTick(room: RelayRoom): uint32 =
  ## Keeps issued history immutable while exposing the actual completed edge.
  if room.phase == Ended: room.finalTick else: room.tick

proc status(relay: Relay, room: RelayRoom) =
  ## Publishes the exact frozen or running server tick.
  relay.broadcast(room, RoomMessage(
    kind: MatchStatus, match: room.match, phase: room.phase,
    tick: room.playbackTick(), detail: room.detail, flag: room.paused
  ))

proc stop(relay: Relay, room: RelayRoom, detail: string) =
  ## Stops a match visibly without attempting desync repair.
  if room.phase == Desynced:
    return
  room.phase = Desynced
  room.detail = detail
  relay.logEvent("match.stopped", room = room, detail = detail)
  relay.status(room)

proc retainedBytes(relay: Relay): int =
  ## Counts bounded history and pending storage across all rooms.
  for room in relay.rooms:
    result += room.historyBytes + room.pendingBytes +
      room.checkpoints.len * sizeof(Checkpoint)

proc changed(relay: Relay, room: RelayRoom) =
  ## Revises routing and setup without changing cosmetic readiness.
  inc room.revision
  relay.publish(room)

proc clearMembership(guest: Guest) =
  ## Preparation, receipts and playback cursors belong to the old room only.
  guest.room = ""
  guest.ready = false
  guest.recovering = false
  guest.applied = 0
  guest.hashTick = 0
  guest.finishTick = 0
  guest.hash = 0
  guest.finishHash = 0
  guest.receipts.setLen(0)

proc closeIfUnwatched(relay: Relay, room: RelayRoom): bool =
  ## Seats and private bots have no residency independent of connected people.
  for id in room.participants:
    let guest = relay.guest(id)
    if guest != nil and guest.room == room.id and guest.connection != 0:
      return false
  relay.logEvent("room.closed", room = room)
  for guest in relay.guests:
    if guest.room == room.id:
      guest.clearMembership()
  room.paused = false
  room.deadline = 0
  room.owner = 0
  room.participants.setLen(0)
  room.seats.setLen(0)
  room.pending.setLen(0)
  room.pendingBytes = 0
  room.history.setLen(0)
  room.historyBytes = 0
  room.checkpoints.setLen(0)
  room.payload = ""
  room.initial = RoomMessage()
  room.detail = ""
  room.pausedBy = ""
  for i in 0 ..< relay.rooms.len:
    if relay.rooms[i] == room:
      relay.rooms.delete(i)
      break
  true

proc disconnectConnection(relay: Relay, connection: int, preserveRoom = false) =
  ## Releases one connection without holding up the shared timeline.
  let guest = relay.connectionGuest(connection)
  if guest == nil:
    return
  relay.logEvent("player.disconnected", connection)
  guest.connection = 0
  guest.deliveries.setLen(0)
  guest.unacknowledged = 0
  let room = relay.room(guest.room)
  if room == nil or (not preserveRoom and relay.closeIfUnwatched(room)):
    return
  guest.ready = false
  relay.publish(room)

proc disconnect*(relay: Relay, connection: int) =
  ## Ordinary socket closure retires a room when its final watcher leaves.
  relay.disconnectConnection(connection)

proc hello(relay: Relay, connection: int, message: RoomMessage, now: float64) =
  ## Binds a new connection or restores an existing participant securely.
  if not message.name.validName or message.identity.game.len == 0:
    reject("A game identity and display name are required")
  if relay.connectionGuest(connection) != nil:
    reject("Connection already identified")
  var guest: Guest
  if message.token.len > 0:
    for candidate in relay.guests:
      if candidate.token == message.token:
        guest = candidate
        break
    if guest == nil or guest.identity != message.identity:
      reject("Reconnect token is unknown or belongs to another game version")
    if guest.connection != 0:
      let oldConnection = guest.connection
      relay.outgoing.add Outgoing(connection: oldConnection, close: true)
      # A token-authenticated takeover is continuous presence, not abandonment.
      relay.disconnectConnection(oldConnection, preserveRoom = true)
  else:
    if relay.guests.len >= MaxGuests:
      reject("Server participant limit reached")
    inc relay.nextId
    guest = Guest(
      id: relay.nextId, token: secret(), name: message.name,
      identity: message.identity
    )
    relay.guests.add guest
  let
    room = relay.room(guest.room)
    renamed = guest.name != message.name
  if room == nil or room.phase == Lobby:
    guest.name = message.name
  guest.connection = connection
  relay.logEvent(
    if message.token.len > 0: "player.reconnected" else: "player.identified",
    connection
  )
  guest.lastSeen = now
  guest.inputEpoch = now
  guest.inputBytes = 0
  guest.timing = PacketTiming()
  guest.delivered = 0
  guest.received = 0
  guest.deliveries.setLen(0)
  guest.unacknowledged = 0
  relay.send(guest, RoomMessage(
    kind: Welcome, participant: guest.id, token: guest.token
  ))
  if room != nil:
    if room.phase == Lobby and renamed and room.controls(guest.id):
      relay.changed(room)
    else:
      relay.publish(room)
    if room.phase != Lobby:
      guest.recovering = room.controls(guest.id)
      relay.send(guest, room.initial)
      relay.send(guest, RoomMessage(
        kind: MatchStatus, match: room.match, phase: room.phase,
        tick: room.playbackTick(), detail: room.detail, flag: room.paused
      ))

proc acknowledge(guest: Guest, sequence: uint64) =
  ## Releases transport credit only for actually issued deliveries.
  if sequence < guest.received or sequence > guest.delivered:
    reject("Invalid delivery acknowledgement")
  guest.received = sequence
  var consumed = 0
  for delivery in guest.deliveries:
    if delivery.id > sequence:
      break
    guest.unacknowledged -= delivery.bytes
    inc consumed
  if consumed > 0:
    for i in consumed ..< guest.deliveries.len:
      guest.deliveries[i - consumed] = guest.deliveries[i]
    guest.deliveries.setLen(guest.deliveries.len - consumed)

proc catchup(relay: Relay, guest: Guest, room: RelayRoom, tick: uint32) =
  ## Streams bounded chunks of the immutable history to one client.
  if tick > room.tick:
    reject("Catch-up tick is ahead of the server")
  let edge = room.playbackTick()
  let last = min(edge, tick + CatchupBatch)
  for index in int(tick) ..< int(last):
    relay.send(guest, decode(room.history[index]))
  relay.send(guest, RoomMessage(
    kind: CaughtUp, match: room.match, tick: last, number: edge
  ))

proc removeGuest(relay: Relay, room: RelayRoom, guest: Guest) =
  ## Removes membership and releases owned slots in every room phase.
  relay.logEvent("room.left", guest.connection, room,
    "player=" & $guest.id)
  guest.clearMembership()
  var seatsChanged = false
  for seat in room.seats.mitems:
    if seat.owner == guest.id:
      seat = Seat()
      seatsChanged = true
  for i in 0 ..< room.participants.len:
    if room.participants[i] == guest.id:
      room.participants.delete(i)
      break
  if room.owner == guest.id:
    if room.participants.len > 0:
      room.owner = room.participants[0]
  relay.send(guest, RoomMessage(kind: RoomState))
  if relay.closeIfUnwatched(room):
    return
  if seatsChanged:
    relay.changed(room)
  else:
    relay.publish(room)

proc receive*(
    relay: Relay, connection: int, message: RoomMessage, now: float64
) =
  ## Handles one event in the sole owner thread of the relay state.
  relay.now = now
  if message.delivery != 0:
    reject("Clients cannot assign delivery identifiers")
  if message.kind == Hello:
    relay.hello(connection, message, now)
    return
  let guest = relay.connectionGuest(connection)
  if guest == nil:
    reject("Identify before sending room messages")
  guest.lastSeen = now
  if now - guest.inputEpoch >= 1:
    guest.inputEpoch = now
    guest.inputBytes = 0
  guest.inputBytes += message.encode.len
  if guest.inputBytes > MaxInputBytesPerSecond:
    reject("Incoming traffic limit exceeded")
  if message.timing.received > guest.received:
    var found = false
    for delivery in guest.deliveries:
      if delivery.id == message.timing.received:
        if delivery.stamp != message.timing.echo:
          reject("Timestamp echo does not match its delivery")
        let
          stamp = uint64(max(0.0, now) * 1_000_000)
          elapsed = stamp - min(stamp, delivery.stamp)
          rtt = uint32(min(elapsed, uint64(uint32.high)))
        guest.timing.jitter =
          if guest.timing.measuredAt == 0: 0'u32
          else: uint32(abs(int64(rtt) - int64(guest.timing.rtt)))
        guest.timing.rtt = rtt
        guest.timing.measuredAt = stamp
        found = true
        break
    if not found:
      reject("Unknown timestamp delivery")
    guest.acknowledge(message.timing.received)
  if message.kind == Received:
    if message.sequence > 0:
      guest.acknowledge(message.sequence)
    return
  if message.kind == Keepalive:
    relay.send(guest, RoomMessage(kind: Keepalive))
    return
  if message.kind == ListRooms:
    var reply = RoomMessage(kind: RoomList)
    for room in relay.rooms:
      if not room.public or room.identity != guest.identity:
        continue
      var occupied = 0'u32
      for seat in room.seats:
        if seat.owner != 0:
          inc occupied
      reply.rooms.add RoomListing(
        id: room.id, name: room.name, phase: room.phase,
        occupied: occupied, seats: uint32(room.seats.len)
      )
    relay.send(guest, reply)
    return
  if message.kind == CreateRoom:
    if guest.room.len > 0 or relay.rooms.len >= MaxRooms:
      reject("Leave the current room or free server room capacity first")
    if message.number notin 1'u32 .. uint32(MaxSeats) or
      message.tickRate notin 1'u32 .. 120'u32 or not message.name.validName:
        reject("Invalid room settings")
    let room = RelayRoom(
      id: relay.newRoomId(), name: message.name, identity: guest.identity,
      owner: guest.id, public: message.flag, phase: Lobby, revision: 1,
      tickRate: message.tickRate, payload: message.payload,
      seats: newSeq[Seat](int(message.number)), participants: @[guest.id]
    )
    guest.room = room.id
    relay.rooms.add room
    relay.logEvent("room.created", connection, room,
      "seats=" & $message.number & " tickRate=" & $message.tickRate &
      " public=" & $message.flag)
    relay.changed(room)
    return
  if message.kind == JoinRoom:
    if guest.room.len > 0:
      reject("Leave the current room first")
    # Preserve exact legacy IDs; only six-character alphanumeric invites fold case.
    var room = relay.room(message.room)
    if room == nil and message.room.len == 6 and
        message.room.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9'}):
      room = relay.room(message.room.toUpperAscii)
    if room == nil or room.identity != guest.identity:
      reject("Room not found or incompatible exact game/protocol version")
    if room.participants.len >= MaxParticipants:
      reject("Room participant limit reached")
    guest.room = room.id
    guest.ready = false
    room.participants.add guest.id
    relay.logEvent("room.joined", connection, room)
    if room.phase == Lobby:
      # Joining does not claim a seat or alter the prepared game setup.
      relay.publish(room)
    else:
      guest.applied = 0
      guest.hashTick = 0
      guest.hash = 0
      relay.publish(room)
      relay.send(guest, room.initial)
      relay.send(guest, RoomMessage(
        kind: MatchStatus, match: room.match, phase: room.phase,
        tick: room.playbackTick(), detail: room.detail, flag: room.paused
      ))
    return
  let room = relay.room(guest.room)
  if room == nil:
    reject("Join a room first")
  if message.kind in {SubmitCommand, AppliedTick, Catchup, ReportHash,
      FinishMatch, AbortMatch, PauseMatch} and message.match != room.match:
    reject("Stale match identifier")
  case message.kind
  of ConfigureRoom, ResizeRoom:
    if guest.id != room.owner:
      reject("Only the owner can change room settings")
    if message.number notin 1'u32 .. uint32(MaxSeats) or
        message.tickRate notin 1'u32 .. 120'u32 or
        not message.name.validName or message.payload.len > MaxPayloadBytes:
      reject("Invalid room settings")
    if room.phase != Lobby and
        (message.kind != ResizeRoom or message.payload != room.payload or
          message.tickRate != room.tickRate):
      reject("Running game setup is immutable")
    room.seats.setLen(int(message.number))
    room.name = message.name
    room.payload = message.payload
    room.public = message.flag
    room.tickRate = message.tickRate
    relay.logEvent("room.configured", connection, room)
    relay.changed(room)
  of ClaimSeat, ReleaseSeat:
    if message.seat >= uint32(room.seats.len):
      reject("Seat is outside this room")
    let
      owner = room.seats[message.seat].owner
      host = guest.id == room.owner
      target = if message.participant == 0: guest.id else: message.participant
    if not host and owner notin [0'u32, guest.id]:
      reject("Seat belongs to another participant")
    if message.kind == ClaimSeat:
      if not host and target != guest.id:
        reject("Only the owner can assign another participant")
      if target notin room.participants:
        reject("Assigned participant is not in this room")
      if not message.name.validName:
        reject("A seat display name is required")
      room.seats[message.seat] = Seat(owner: target, name: message.name,
        kind: message.seatKind)
    else:
      room.seats[message.seat] = Seat()
    relay.changed(room)
  of ReadyStatus:
    guest.ready = message.flag
    relay.publish(room)
  of StartMatch:
    if room.phase != Lobby or room.owner != guest.id:
      reject("Only the owner can start a lobby")
    if message.revision != room.revision:
      reject("Start refers to outdated room settings")
    let snapshot = relay.state(room)
    if message.hash != snapshot.setupHash():
      reject("Start setup hash differs from the room configuration")
    room.initial = snapshot
    room.initial.kind = BeginMatch
    room.initial.hash = message.hash
    room.checkpoints = @[Checkpoint()]
    room.finalTick = 0
    room.finalHash = 0
    room.history.setLen(0)
    room.pending.setLen(0)
    room.historyBytes = 0
    room.pendingBytes = 0
    room.tick = 0
    inc room.match
    room.initial.match = room.match
    room.initial.phase = Playing
    room.initial.flag = false
    for id in room.participants:
      let controller = relay.guest(id)
      controller.receipts.setLen(0)
      controller.applied = 0
      controller.hashTick = 0
      controller.hash = 0
      controller.finishTick = 0
    room.phase = Playing
    room.paused = false
    room.detail = ""
    room.deadline = now + 1.0 / float64(room.tickRate)
    relay.broadcast(room, room.initial)
    relay.status(room)
    relay.logEvent("match.started", connection, room,
      "seats=" & $room.seats.len & " setupHash=" & $message.hash)
  of SubmitCommand:
    if message.sequence == 0 or
      message.sequence > uint64(guest.receipts.len) + 1:
        reject("Command sequence must be consecutive")
    if message.sequence <= uint64(guest.receipts.len):
      let receipt = guest.receipts[int(message.sequence - 1)]
      if receipt.seat != message.seat or receipt.payload != message.payload or
          receipt.seatKind != message.seatKind:
        reject("Retransmitted sequence has different contents")
      relay.send(guest, RoomMessage(
        kind: CommandAck, match: room.match,
        sequence: message.sequence, tick: receipt.tick,
        flag: receipt.discarded
      ))
      return
    if room.phase notin {Playing, Waiting}:
      reject("New commands require an active match")
    if message.seat >= uint32(room.seats.len) or
        room.seats[message.seat].owner != guest.id or
        room.seats[message.seat].kind != message.seatKind:
      # Account for a canceled in-flight command without breaking its stream.
      let storage = message.payload.len + 64
      if room.historyBytes + room.pendingBytes + storage > MaxHistoryBytes or
          relay.retainedBytes() + storage > MaxTotalHistoryBytes:
        relay.stop(room, "Command receipt history limit exhausted")
        return
      guest.receipts.add Receipt(seat: message.seat,
        seatKind: message.seatKind, payload: message.payload, discarded: true)
      room.historyBytes += storage
      relay.send(guest, RoomMessage(kind: CommandAck,
        sequence: message.sequence, match: room.match, flag: true))
      return
    if room.pending.len >= MaxCommandsPerTick or
      room.pendingBytes + message.payload.len + 32 > MaxWireBytes div 2:
        relay.stop(room, "Pending command limit exhausted")
        return
    if room.historyBytes + room.pendingBytes + message.payload.len * 2 +
      64 > MaxHistoryBytes:
        relay.stop(room, "Match history limit exhausted")
        return
    if relay.retainedBytes() + message.payload.len * 2 + 64 >
      MaxTotalHistoryBytes:
        relay.stop(room, "Server history limit exhausted")
        return
    let tick = room.tick + 1
    guest.receipts.add Receipt(
      tick: tick, seat: message.seat, seatKind: message.seatKind,
      payload: message.payload
    )
    room.pending.add Command(
      participant: guest.id, seat: message.seat,
      seatKind: room.seats[message.seat].kind,
      sequence: message.sequence, payload: message.payload
    )
    room.pendingBytes += message.payload.len * 2 + 64
    # The next authoritative tick acknowledges new commands in its payload.
  of AppliedTick:
    if message.tick < guest.applied or message.tick > room.tick:
      reject("Invalid simulated tick acknowledgement")
    guest.applied = message.tick
    if message.tick == room.tick:
      guest.recovering = false
  of Catchup:
    relay.catchup(guest, room, message.tick)
  of ReportHash, FinishMatch:
    if room.phase == Lobby:
      reject("State hashes require an active or completed match")
    if message.tick > room.tick:
      reject("Invalid state hash tick")
    if message.kind == FinishMatch and room.finalTick == 0 and
        not room.controlledAt(guest.id, message.tick):
      reject("Only a controller of the completed tick can finish a match")
    if message.kind == ReportHash and message.tick mod room.tickRate != 0:
      reject("State hash must refer to a second boundary")
    if message.tick mod room.tickRate == 0:
      let index = int(message.tick div room.tickRate)
      if room.checkpoints.len <= index:
        room.checkpoints.setLen(index + 1)
      let checkpoint = room.checkpoints[index]
      if checkpoint.present and checkpoint.hash != message.hash:
        relay.stop(room, "Desync at tick " & $message.tick & ": " &
          $checkpoint.hash & " versus " & $message.hash &
          " from " & guest.name & " (participant " & $guest.id & ")")
        return
      if not checkpoint.present:
        room.checkpoints[index] = Checkpoint(
          present: true, hash: message.hash, participant: guest.id
        )
      if message.tick >= guest.hashTick:
        guest.hashTick = message.tick
        guest.hash = message.hash
    if message.kind == FinishMatch:
      if message.tick == 0:
        reject("A finished match must contain at least one tick")
      if room.finalTick != 0 and
        (room.finalTick != message.tick or room.finalHash != message.hash):
          relay.stop(room, "Final desync at tick " & $message.tick & ": " &
            $room.finalHash & " at tick " & $room.finalTick & " versus " &
            $message.hash & " from " & guest.name)
          return
      room.finalTick = message.tick
      room.finalHash = message.hash
      guest.finishTick = message.tick
      guest.finishHash = message.hash
  of LeaveRoom:
    relay.removeGuest(room, guest)
  of KickParticipant:
    if guest.id != room.owner or message.participant == guest.id:
      reject("Only the owner can remove other participants")
    let removed = relay.guest(message.participant)
    if removed == nil or removed.room != room.id:
      reject("Participant is not in this room")
    relay.removeGuest(room, removed)
  of PauseMatch:
    if room.phase notin {Playing, Waiting} or
        (guest.id != room.owner and not room.controls(guest.id)):
      reject("Only a controlling participant can pause an active match")
    if room.paused != message.flag:
      relay.logEvent(
        if message.flag: "match.paused" else: "match.resume-requested",
        connection, room
      )
    room.paused = message.flag
    room.pausedBy = guest.name
    room.phase = Waiting
    room.detail =
      if room.paused:
        "Match paused by " & guest.name & " at tick " & $room.tick
      else:
        "Resuming match"
    room.deadline = now + 1.0 / float64(room.tickRate)
    relay.status(room)
  of AbortMatch:
    if (guest.id == room.owner or room.controls(guest.id)) and
        room.phase in {Playing, Waiting}:
      relay.stop(room, guest.name & ": " & message.detail)
  of ReturnLobby:
    if guest.id != room.owner or room.phase notin {Ended, Desynced}:
      reject("Only the owner can reopen a completed room")
    room.phase = Lobby
    room.initial = RoomMessage()
    relay.logEvent("room.reopened", connection, room)
    room.paused = false
    room.pausedBy = ""
    for seat in room.seats.mitems:
      if seat.owner notin room.participants:
        seat = Seat()
    room.pending.setLen(0)
    room.history.setLen(0)
    room.historyBytes = 0
    room.pendingBytes = 0
    room.checkpoints.setLen(0)
    for id in room.participants:
      relay.guest(id).receipts.setLen(0)
    relay.changed(room)
  else:
    reject("Message is not a client room operation")

proc advance*(relay: Relay, now: float64) =
  ## Emits ticks independently of client progress; hashes are checked on receipt.
  relay.now = now
  for guest in relay.guests:
    if guest.connection != 0 and now - guest.lastSeen > 15:
      let connection = guest.connection
      relay.logEvent("connection.timeout", connection)
      relay.outgoing.add Outgoing(connection: connection, close: true)
      relay.disconnect(connection)
  for room in relay.rooms:
    if room.phase notin {Playing, Waiting}:
      continue
    var reason: string
    if room.finalTick != 0:
      room.phase = Ended
      room.detail = "Match completed at tick " & $room.finalTick
      relay.logEvent("match.ended", room = room,
        detail = "finalTick=" & $room.finalTick & " finalHash=" & $room.finalHash)
      relay.status(room)
      continue
    if reason.len == 0 and room.paused:
      reason = "Match paused by " & room.pausedBy & " at tick " & $room.tick
    if reason.len > 0:
      if room.phase != Waiting or room.detail != reason:
        room.phase = Waiting
        room.detail = reason
        relay.status(room)
      room.deadline = now + 1.0 / float64(room.tickRate)
      continue
    if room.phase == Waiting:
      room.phase = Playing
      room.detail = ""
      room.deadline = now + 1.0 / float64(room.tickRate)
      relay.status(room)
    if now < room.deadline:
      continue
    if room.tick == high(uint32) or
      room.historyBytes + room.pendingBytes + 64 > MaxHistoryBytes or
      relay.retainedBytes() + 64 > MaxTotalHistoryBytes:
        relay.stop(room, "Match history limit exhausted")
        continue
    let packet = RoomMessage(
      kind: TickPacket, match: room.match, tick: room.tick + 1,
      commands: room.pending, seats: room.seats
    )
    let bytes = packet.encode()
    if room.historyBytes + room.pendingBytes + bytes.len > MaxHistoryBytes or
        relay.retainedBytes() + bytes.len > MaxTotalHistoryBytes:
      relay.stop(room, "Match history limit exhausted")
      continue
    room.tick = packet.tick
    room.history.add bytes
    room.historyBytes += bytes.len + room.pendingBytes
    room.pending.setLen(0)
    room.pendingBytes = 0
    for id in room.participants:
      let guest = relay.guest(id)
      # Slow controllers, like spectators, pull bounded history batches.
      if guest.applied + CatchupBatch >= room.tick:
        relay.send(guest, packet)
    room.deadline = now + 1.0 / float64(room.tickRate)
  for i in countdown(relay.rooms.high, 0):
    # send() may retire a backpressured connection during this scheduler pass.
    discard relay.closeIfUnwatched(relay.rooms[i])
  for i in countdown(relay.guests.high, 0):
    let guest = relay.guests[i]
    if guest.room.len == 0 and guest.connection == 0 and
      now - guest.lastSeen > 60:
        relay.guests.delete(i)

proc process*(relay: Relay, connection: int, bytes: string, now: float64) =
  ## Reports invalid input to its sender while preserving the server loop.
  try:
    relay.receive(connection, decode(bytes), now)
  except RoomsError as error:
    relay.logEvent("request.rejected", connection, detail = error.msg)
    let guest = relay.connectionGuest(connection)
    if guest != nil:
      relay.send(guest, RoomMessage(kind: Failure, detail: error.msg))
    else:
      relay.outgoing.add Outgoing(
        connection: connection,
        bytes: RoomMessage(kind: Failure, detail: error.msg).encode(),
        close: true
      )
