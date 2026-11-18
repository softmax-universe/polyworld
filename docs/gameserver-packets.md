# Gameserver packets

Outer protocol **5**. See [hosting and integration](gameserver.md).

One binary WebSocket message carries one packet at `/ws`. Fields below are
in wire order, little endian, without padding. A `string` is a `uint32` byte
length followed by its bytes; a `seq[T]` is a `uint32` count followed by its
records. Boolean flags are `uint32` values restricted to 0 or 1.

Version 5 is an exact wire contract. Earlier versions are rejected. There
are no game-name policies or compatibility branches, and no manual-ready,
preparation-duration or server-announcement messages.

## Common header

Every packet starts with this 64-byte header. Message descriptions below
list only the body.

| Field | Wire type | Meaning |
| --- | --- | --- |
| `magic` | 4 bytes | ASCII `PWRM`. |
| `version` | `uint32` | Exactly 5. |
| `kind` | `uint32` | Message ID below. |
| `delivery` | `uint64` | Server delivery counter, starting at 1 per connection; clients send 0. |
| `match` | `uint32` | Match generation within the room; increments on each start. |
| `server` | `uint64` | Server monotonic send time, microseconds. |
| `echo` | `uint64` | Client echo of its latest received server timestamp. |
| `received` | `uint64` | Cumulative server-delivery acknowledgement paired with `echo`. |
| `measuredAt` | `uint64` | Server time of latest RTT measurement; 0 if unavailable. |
| `rtt` | `uint32` | Server-measured round trip, microseconds. |
| `jitter` | `uint32` | Absolute difference between consecutive RTT samples, microseconds. |

The relay checks timestamp echoes against its delivery records. Client
clocks are not used. RTT includes client processing and acknowledgement
turnaround. Catch-up packets receive fresh transport timestamps; timestamps
are not part of simulation state.

Receipts normally ride on outgoing packet headers, with a 100 ms idle
fallback. Clients send application keepalives after three seconds without
outgoing traffic. WebSocket control ping/pong frames are not room packets.

## Shared records

Fields in each row are ordered exactly as encoded.

| Record | Ordered fields |
| --- | --- |
| `GameIdentity` | `game: string`, `gameplay: uint32`, `protocol: uint32` |
| `Participant` | `id: uint32`, `name: string`, `connected: uint32`, `ready: uint32` |
| `Seat` | `owner: uint32`, `kind: uint32`, `name: string` |
| `Command` | `participant: uint32`, `seat: uint32`, `seatKind: uint32`, `sequence: uint64`, `payload: string` |
| `RoomListing` | `id: string`, `name: string`, `phase: uint32`, `occupied: uint32`, `seats: uint32` |

`GameIdentity` is an opaque compatibility tuple. All three fields must match
for discovery, joining and reconnecting. `game` is nonempty and at most
96 bytes; `protocol` is nonzero. Their values do not select server behavior.

A participant ID is nonzero. Participant names are at most 64 bytes.
`ready` is cosmetic information for the host; it never gates startup.
`connected` describes the participant's current transport state.

A seat's array index is its stable slot identifier. Owner 0 means empty.
`kind` and `seatKind` use `HumanSeat = 0` and `BotSeat = 1`; names are at
most 96 bytes and have no permission or type semantics. Teams are not part
of this record. A command's participant and kind are stamped by the relay
when it admits the submission, before any later reassignment.

Room IDs are at most 64 bytes and room names at most 96 bytes. Phase values
are `Lobby = 0`, `Playing = 1`, `Waiting = 2`, `Ended = 3`, `Desynced = 4`.
`Desynced` also represents fatal aborts and exhausted service limits.

## Room settings and snapshot bodies

`CreateRoom`, `ConfigureRoom` and `ResizeRoom` share this ordered body:

| Field | Wire type | Meaning |
| --- | --- | --- |
| `name` | `string` | Room name, at most 96 bytes. |
| `flag` | `uint32` | Public = 1; unlisted = 0. |
| `tickRate` | `uint32` | 1 through 120 ticks per second. |
| `number` | `uint32` | 1 through 64 slots. |
| `payload` | `string` | Opaque game configuration, at most 65,536 bytes. |

`RoomState` and `BeginMatch` share this ordered snapshot body. `BeginMatch`
appends a `uint64` setup hash after the snapshot:

| Field | Wire type | Meaning |
| --- | --- | --- |
| `room` | `string` | Room ID; an empty RoomState clears membership. |
| `name` | `string` | Room name. |
| `participant` | `uint32` | Host participant ID. |
| `revision` | `uint32` | Configuration/roster revision. |
| `phase` | `uint32` | Room phase. |
| `tickRate` | `uint32` | Simulation ticks per second. |
| `flag` | `uint32` | In Lobby, public visibility; in match phases, pause state. |
| `payload` | `string` | Opaque game configuration. |
| `participants` | `seq[Participant]` | At most 64 participants. |
| `seats` | `seq[Seat]` | At most 64 ordered slots. |
| `hash` | `uint64` | BeginMatch only: immutable initial setup hash. |

`RoomState` describes the current administrative state. `BeginMatch` carries
the preserved starting setup, including original slot responsibilities and
owner names. Later membership and ownership edits do not rewrite it. A late
joiner must reconstruct from `BeginMatch`, then replay the tick history.

## Initialization hash

Use `rooms.setupHash(snapshot)` for every game's `StartMatch`. It is 64-bit
FNV-1a over the following byte sequence, using offset basis
`14695981039346656037` and prime `1099511628211`, with multiplication modulo
2^64:

1. Raw ASCII `Polyworld room setup v5`, without a length prefix.
2. `tickRate` as `uint32`.
3. `seats` as `seq[Seat]`, in slot order.
4. For every slot, its owning participant's name as a `string`; empty for an
   unowned slot or an owner absent from the snapshot's participant list.
5. The exact game configuration `payload` as a `string`.

Participant array ordering does not affect name lookup. Ready and connected
flags, room name/visibility, host identity, revision and transport timing are
not hashed. The revision is validated separately. JSON key order and
whitespace are part of the exact setup bytes; the relay does not normalize
JSON. This digest checks setup agreement, not cryptographic authenticity.

After checking the setup hash, clients construct their own simulation and
send `ReportHash` at tick zero. The first simulation report establishes that
checkpoint; it is not compared with the setup hash.

## Messages

All fields listed in a body cell are in wire order. "Header only" means a
64-byte packet with no body. See the preceding tables for settings and
snapshot bodies.

| ID | Message | Direction | Body |
| --- | --- | --- | --- |
| 0 | `Hello` | Client to server | `identity: GameIdentity`, `name: string`, `token: string` |
| 1 | `Welcome` | Server to client | `participant: uint32`, `token: string` |
| 2 | `ListRooms` | Client to server | Header only |
| 3 | `RoomList` | Server to client | `rooms: seq[RoomListing]` |
| 4 | `CreateRoom` | Client to server | Settings body |
| 5 | `JoinRoom` | Client to server | `room: string` |
| 6 | `RoomState` | Server to client | Snapshot body without hash |
| 7 | `ConfigureRoom` | Client to server | Settings body |
| 8 | `ClaimSeat` | Client to server | `seat: uint32`, `participant: uint32`, `seatKind: uint32`, `name: string` |
| 9 | `ReleaseSeat` | Client to server | `seat: uint32` |
| 10 | `StartMatch` | Client to server | `revision: uint32`, `hash: uint64` |
| 11 | `BeginMatch` | Server to client | Snapshot body followed by `hash: uint64` |
| 12 | `SubmitCommand` | Client to server | `seat: uint32`, `sequence: uint64`, `payload: string` |
| 13 | `CommandAck` | Server to client | `sequence: uint64`, `tick: uint32`, `flag: uint32` |
| 14 | `TickPacket` | Server to client | `tick: uint32`, `commands: seq[Command]`, `seats: seq[Seat]` |
| 15 | `AppliedTick` | Client to server | `tick: uint32` |
| 16 | `Catchup` | Client to server | `tick: uint32` |
| 17 | `CaughtUp` | Server to client | `tick: uint32`, `number: uint32` |
| 18 | `ReportHash` | Client to server | `tick: uint32`, `hash: uint64` |
| 19 | `MatchStatus` | Server to client | `flag: uint32`, `phase: uint32`, `tick: uint32`, `detail: string` |
| 20 | `LeaveRoom` | Client to server | Header only |
| 21 | `KickParticipant` | Client to server | `participant: uint32` |
| 22 | `ReturnLobby` | Client to server | Header only |
| 23 | `FinishMatch` | Client to server | `tick: uint32`, `hash: uint64` |
| 24 | `Received` | Client to server | `sequence: uint64` |
| 25 | `Keepalive` | Both directions | Header only |
| 26 | `Failure` | Server to client | `detail: string` |
| 27 | `AbortMatch` | Client to server | `detail: string` |
| 28 | `PauseMatch` | Client to server | `flag: uint32` |
| 29 | `ResizeRoom` | Client to server | Settings body |
| 30 | `ReadyStatus` | Client to server | `flag: uint32` |

### Connection and membership

`Hello` with an empty token creates a participant. A nonempty token restores
that participant after an identity comparison; a replacement connection
closes the old connection. `Welcome` returns the private token, at most
64 bytes. Tokens are never broadcast. A restored live client retains its
private VM and simulation state; reconnecting does not start a new match.

`ListRooms` returns at most 64 compatible public rooms. `CreateRoom` creates
a room and gives its creator ownership. `JoinRoom` joins a compatible room
by invitation code, including an unlisted room. Lookup tries the exact ID
then uppercases a six-character alphanumeric invitation. Joining a running
match sends both current room state and the immutable starting setup.

`LeaveRoom` releases the sender's assignments and removes membership, even
during play. `KickParticipant` lets the host remove another participant in
any phase. The host leaves through `LeaveRoom`, rather than kicking itself.
A room with no connected participants is deleted. If the host leaves while
others remain, ownership passes to a remaining participant.

### Configuration and slots

`ConfigureRoom` is host-only and lobby-only. It changes the opaque setup,
slot count and administrative settings, then increments the revision.
`ResizeRoom` is host-only and also works during a match, when `payload` and
`tickRate` must stay unchanged. The server never parses game JSON to classify
a change. Shrinking releases removed trailing slots, including assignments
to other participants when requested by the host.

`ClaimSeat.participant = 0` selects the sender. A nonzero target must belong
to the room. Hosts may assign empty or occupied slots to any participant;
guests may claim empty slots for themselves or update their own slots.
`seatKind` explicitly selects human or bot control. The name must be nonempty
and printable; it never determines the kind. `ReleaseSeat` accepts an
already-empty slot. Hosts may release any assignment; others may release
only their own. These operations apply in every room phase.

`ReadyStatus` updates any room participant's own visible ready flag in any
phase. Settings and roster edits preserve that cosmetic flag. It is never
consulted by `StartMatch`. There is no prepared-state handshake.

### Starting and advancing

`StartMatch` is host-only in the lobby. Its revision must equal the current
room revision and its hash must equal `setupHash` of that snapshot. A valid
request starts immediately without waiting for ready flags, preparation
reports or controller connectivity. An empty occupied roster is also valid
for the relay; the game decides whether its setup is playable. `BeginMatch`
gives every client the same initial configuration and slot responsibilities.

`SubmitCommand` is accepted only for a slot owned by its sender in an active
match. The relay supplies the command's participant and controller kind;
clients cannot choose that provenance. Sequences are consecutive from 1 per
participant across all their slots and survive reconnect. An exact
retransmission receives its original `CommandAck`; changed retransmissions
or gaps fail. Admission does not promise that gameplay will accept the
command.

If the sender no longer owns the slot when a new submission arrives, the
relay consumes its sequence and returns `CommandAck` with `tick = 0` and
`flag = 1`. The discarded command never enters game history. This retires
in-flight input after a removal or resize without breaking later command
sequences. `flag = 0` acknowledges an admitted command at its assigned tick.
Retransmissions retain the original admitted/discarded result even if slot
ownership has since changed.

`TickPacket` executes once at its consecutive tick. Its commands retain
admission-time provenance, even if a slot was reassigned before delivery.
Its `seats` is the complete end-of-tick routing roster. Apply game commands
first, then update applied ownership. Do not validate historical commands
against the latest `RoomState`. The shared client's `appliedTick` updates
`appliedSeats` after the taken packet is executed.

`AppliedTick` acknowledges executed simulation progress. `Catchup` requests
ticks after that position, up to 16 at a time. `CaughtUp.tick` is the last
tick in the batch, and `number` is the current playback edge, or final tick
for a completed match. It does not authorize skipping intermediate ticks.

### Hashes, completion and pause

`ReportHash` is valid at tick zero and simulation-second boundaries, never
ahead of the relay. The first report for each historical checkpoint sets its
hash; later reports compare against that checkpoint. Missing reports do not
pause the timeline. Disagreeing reports, including spectator reports, stop
the match. Setup agreement and simulation agreement are separate checks.

`FinishMatch` reports a game-decided final tick and hash. The first report
must come from a participant that controlled a slot at the beginning or end
of that tick, or submitted an admitted command in that tick. This preserves
completion authority across later reassignment. The relay retains the
completed edge even if that controller subsequently leaves, and compares
subsequent completion reports. The final tick must be positive. The relay
has no configured gameplay duration and does not calculate the outcome.

`PauseMatch` lets the host or a controller pause or resume new ticks. Pending commands
remain queued and already emitted packets stay immutable. `MatchStatus`
reports the phase, pause flag, playback edge and diagnostic. `AbortMatch`
lets the host or a controller stop the match after a fatal client error. `ReturnLobby`
lets the host reopen an ended or failed room and clear its match history.

### Transport and errors

`Received.sequence` is an optional cumulative delivery acknowledgement;
zero uses the acknowledgement in the header. Acknowledgements release
outgoing transport credit. Idle clients send `Keepalive`; the server closes
connections with no application traffic for 15 seconds.

`Failure.detail` describes a rejected operation or packet and does not
necessarily end the match. Status and failure text are limited to 4,096
bytes. Malformed lengths, invalid enum/flag values, trailing packet bytes,
stale match IDs and unauthorized room mutations are rejected.

## Limits and lifetime

| Resource | Bound |
| --- | --- |
| Entire outer packet | 256 KiB |
| Setup / command payload | 64 KiB / 4 KiB |
| Rooms / guests / live sockets | 64 / 512 / 256 |
| Slots / participants per room | 64 / 64 |
| Commands per decoded tick | 1,024; byte accounting may stop admission earlier |
| Retained room history | 128 MiB accounting budget |
| Aggregate retained history | 512 MiB accounting budget |
| Unacknowledged outgoing bytes | 512 KiB per guest |
| Identified incoming traffic | 256 KiB per one-second accounting window |
| Client pending commands / buffered ticks | 4,096 / 128 |

There is no fixed match-duration or retained-tick-count limit. Memory and
wire limits remain enforced. The relay stops a match visibly if retaining
accepted history would exceed its resource budget. History is kept until
returning to the lobby or deleting the room; a server restart loses it.
History contains commands and routing snapshots, never bot programs or
private VM state. Game timers, drafting, teams, countdowns and announcements
are entirely client-owned.

## Source

| File | Owns |
| --- | --- |
| [rooms.nim](../src/polyworld/rooms.nim) | Wire codec, types and setup hash. |
| [relays.nim](../src/polyworld/relays.nim) | Rooms, routing, timeline, limits and hash comparison. |
| [roomclients.nim](../src/polyworld/roomclients.nim) | Initial/applied snapshots, acknowledgements and catch-up. |
| [connections.nim](../src/polyworld/connections.nim) | Windy transport. |
| [gameserver.nim](../tools/gameserver.nim) | Mummy event loop. |
