# Polyworld gameserver

The gameserver is a WebSocket relay for game clients. It owns rooms,
participants, slot assignments, command ordering, retained packets and hash
comparison. It treats game identity fields as compatibility labels and game
configuration JSON and command payloads as opaque bytes. It has no game
imports, gameplay rules, team rules, draft logic or match-duration clock.

The shared room protocol is version 5. Rebuild the relay and every client
using it together. Earlier wire versions are rejected; there are no legacy
game adapters in the server. See [the packet reference](gameserver-packets.md)
for the complete wire layout.

## Run locally

Install the repository's locked Nim dependencies, then run from the checkout:

```sh
nim r tools/gameserver.nim --port 9911 --address 127.0.0.1
```

Connect a native or browser game client to `ws://localhost:9911/ws`. Each
game owns its launch options and menus. An HTTPS game page needs a `wss://`
relay. `GET /healthz` provides a health check.

The executable defaults to port 8090 on `127.0.0.1`. `PORT` and `BIND`
override those defaults; `--port` and `--address` override the environment.
Use `--address 0.0.0.0` to listen on all IPv4 interfaces, including Tailscale.
The server uses Mummy's socket workers and one room event loop. Workers pass
bounded transport events to that loop; only the loop mutates room state.

## Rooms and identities

Clients supply a game name, gameplay version and game payload protocol
version. The relay compares all three fields for exact equality when listing
rooms, joining and reconnecting. Their values never select different server
behavior. The outer room protocol version is checked independently.

The creator owns the room, chooses public or unlisted visibility and manages
its configuration and participants. New invitation codes contain six
uppercase letters or digits. They identify rooms; they are not reconnect
credentials. Reconnect tokens are private, randomly generated secrets and
are never included in room snapshots or invitations.

A participant may own human or bot slots, or watch without owning a slot.
Each slot has an explicit controller kind, owner participant and display
name. A display name never grants permissions or identifies a bot. Teams,
factions and other game groupings belong to the game's configuration.

The same ownership rules apply to every game and in every match phase:

- The host may assign or reassign any slot to a room participant, remove any
  human or bot slot assignment, and remove other participants.
- Other participants may claim empty slots for themselves or their bots,
  update their own assignments, and release only assignments they own.
- Removing a participant releases that participant's assignments.
- Resizing may add empty slots or remove trailing slots. During a match it
  cannot change the game's initial configuration bytes or tick rate.

Bots run in their owners' clients. The relay receives their ordinary
commands and routing metadata, never bot source, weights or VM memory.
Assigning a bot slot does not transfer a bot implementation between clients.
Each game's client decides how a newly controlled slot maps to its gameplay.

A room exists while at least one participant remains connected, including
seatless spectators and bot owners. The last departure, disconnect or
15-second inactivity timeout deletes the room and its history. A reconnect
token can restore a participant identity, but cannot restore a deleted room.
Replacing an existing connection with its authenticated reconnect token
counts as continuous presence.

## Initialization and readiness

The initial setup consists of the ordered slot responsibilities and opaque
game configuration, together with the chosen tick rate and initial owner
display names. `setupHash` in `rooms.nim` hashes this shared representation
identically for every game. It hashes the exact configuration bytes; it does
not parse, normalize or compare JSON fields.

The host starts by sending the current room revision and `setupHash` of that
snapshot. The relay validates those two values and starts immediately. There
is no manual readiness gate, preparation handshake or wait for connected
controllers. `ReadyStatus` changes only the visible ready flag so that the
host can see participants' intentions.

`BeginMatch` contains the immutable initial setup and its hash. Every client
checks that hash, then lets its game parse the JSON and build the initial
simulation. Invalid game settings are handled by the game client, not by
server-specific rules. Clients report the resulting simulation hash at tick
zero. That simulation hash is separate from the shared setup hash: the first
report establishes the checkpoint and later reports must match it.

Initial setup stays immutable throughout the match. Later `RoomState`
snapshots describe current room membership and assignments; they must not be
used to reconstruct the starting world. `RoomClient.initialSnapshot` and
`setupSnapshot(client)` provide the initial setup after a match begins.

## Commands and live ownership changes

The server admits commands only for slots currently owned by their sender,
assigns them to the next tick and preserves receipt order. Each retained
command records its submitting participant, slot and controller kind at
admission. Game clients validate gameplay payloads and game-specific actor
ownership; they do not recheck historical commands against the latest room
snapshot.

Each `TickPacket` contains the full routing roster at the end of that tick.
Apply the commands using their retained provenance, then adopt that roster
for subsequent control decisions. `RoomClient.appliedSeats` advances with
`appliedTick`. This separates the current administrative snapshot from the
roster at a client's actual simulation position. Reassigning or releasing a
slot does not rewrite commands already accepted for it. Input that arrives
after its sender loses the slot is acknowledged as discarded, so the client
can retire it without breaking its command sequence.

Every client executes each consecutive tick exactly once, including empty
ticks. Clients do not advance live simulation without an authoritative
packet. They report a simulation hash every simulated second. The relay
compares each report to that tick's historical checkpoint; missing or late
reports never hold up tick production. A mismatch stops the match visibly.
There is no state repair or gameplay validation in the relay.

Games decide when they have finished and report the final tick and hash.
The relay compares completion reports and stops producing ticks. It never
calculates a winner, enforces a game duration, or emits gameplay warnings.
Countdowns and notices such as remaining-time popups belong to each game's
client and replay presentation.

## Joining, reconnecting and catch-up

A new connection identifies itself with an empty reconnect token. A returning
connection uses its existing token to resume the same participant identity.
A participant joining a running room initially owns no slots, but may claim
an empty slot or receive an assignment under the ordinary ownership rules.
The game determines what that assignment means for its existing world.

The relay sends the immutable `BeginMatch` setup separately from the current
`RoomState`. A late client can reconstruct from that setup and replay retained
tick packets. A reconnecting live client keeps its simulation and private bot
VMs and requests packets after its applied tick. Unacknowledged commands and
hash reports are retried without duplicating accepted commands.

Slow or disconnected controllers do not pause the room while another
participant remains connected. Slow clients pull bounded history batches
instead of accumulating unbounded live packets. Spectators use the same
history and hash checks without executing other participants' bots.

Room state is in memory. Restarting the relay loses its rooms. Recovering a
private bot VM after a browser refresh or client process restart is not
provided by the relay. Clients remain trusted to submit their own commands
and simulation hashes; hash agreement is consistency checking, not
server-authoritative anti-cheat.

## Pause, departure and limits

The host or a controller can pause or resume tick production. Already issued ticks remain
immutable, queued commands stay queued, and acknowledgements and hash checks
continue. Resume resets the scheduling deadline without producing a burst of
missed wall-clock ticks. Leaving or being removed releases assignments; the
remaining participants can continue. An explicit `AbortMatch` reports a fatal
client-side failure and stops the match.

There is no fixed match-duration or history-tick ceiling. Resource limits
still bound memory and traffic: 64 rooms, 512 guests, 256 live sockets, and
64 slots and participants per room. Packets are at most 256 KiB, setup payloads
64 KiB and individual commands 4 KiB. Pending commands and retained history
are bounded by encoded size. Exhaustion stops a match visibly instead of
dropping accepted commands.

History has a 128 MiB accounting budget per room and 512 MiB across rooms.
Outgoing transport credit is 512 KiB per participant, released by receipt
acknowledgements. Incoming traffic is limited to 256 KiB per second per
identified participant. Catch-up transfers at most 16 ticks per batch.
These are service resource bounds, not gameplay duration rules.

## Hosting

A container example is in `tools/gameserver/Dockerfile`. From the checkout:

```sh
docker compose -f tools/gameserver/compose.yaml up --build -d
```

The compose file publishes loopback port 8090. Put the supplied
`tools/gameserver/nginx.conf` locations inside a TLS-enabled nginx server
block and expose `/ws` as `wss://your-domain/ws`. The container runs as a
non-root user. Configure host resource limits for the expected room count.
The server build requires shared server/protocol modules, not game sources.

## Integrating a game

Games import `rooms`, `roomclients` and `connections`. The dependency points
from games to the shared relay protocol; the relay imports no game adapter.
A game supplies its exact compatibility identity, JSON setup, command codec,
local simulation, replay representation and simulation hash function.

Use explicit human/bot slot kinds and the common ownership operations.
Send `ReadyStatus` only for display. Start with the current revision and
`setupHash`; reconstruct with `setupSnapshot(client)`. During play, process
opaque game commands from each tick, apply the tick's ending roster and
report simulation hashes. Keep teams, drafting, duration, rules and notices
inside the game. No server change is needed to introduce another game.

The server logs lifecycle events, rejected requests, timeouts and exhausted
traffic limits. Logs omit reconnect tokens, invitation codes, game payloads
and routine tick/hash traffic. Transport RTT uses echoed server timestamps,
so client clock synchronization is unnecessary. Replayed history receives
fresh transport timestamps; those timestamps never enter gameplay state.
