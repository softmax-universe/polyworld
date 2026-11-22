import std/[json, strutils]
import polyworld/rooms

# Cross-language fixtures use the real encoder so browser evidence fails loudly
# when the relay wire layout changes. All credentials below are dummy values.
var fixtures = newJArray()
for kind in MessageKind:
  var message = RoomMessage(kind: kind, match: 73, delivery: 123,
    identity: GameIdentity(game: repeat("g", 80), gameplay: 23, protocol: 0),
    room: "R42", name: "Arbitrary room", token: "fixture-only-credential",
    participant: 13, seat: 1, seatKind: BotSeat, revision: 7, tick: 94,
    number: 2, tickRate: 30, sequence: 9007199254740995'u64,
    hash: 18446744073709551610'u64, flag: true, phase: Waiting,
    payload: "{\"arbitrary\":[1,true,\"opaque\"]}", detail: "detail",
    timing: PacketTiming(server: 11, echo: 12, received: 13, measuredAt: 14,
      rtt: 15, jitter: 16),
    participants: @[Participant(id: 13, name: "Alpha", connected: true),
      Participant(id: 29, name: "Beta", ready: true)],
    seats: @[Seat(owner: 13, kind: HumanSeat, name: "any-human"),
      Seat(owner: 29, kind: BotSeat, name: "any-bot")],
    rooms: @[RoomListing(id: "R42", name: "Arbitrary room", phase: Playing,
      occupied: 1, seats: 2)],
    commands: @[Command(participant: 29, seat: 1, seatKind: BotSeat,
      sequence: 9007199254740995'u64, payload: "\x00\xff\x01")])
  let bytes = message.encode()
  discard bytes.decode()
  fixtures.add %*{"kind": $kind, "hex": bytes.toHex()}
echo fixtures
