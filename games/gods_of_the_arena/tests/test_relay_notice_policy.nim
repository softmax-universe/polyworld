import polyworld/rooms
import ../relaynotice

let current = GameIdentity(game: "gods_of_the_arena", gameplay: 79, protocol: 4)
let seats = @[Seat(owner: 1)]
for identity in [GameIdentity(game: "galcon", gameplay: 79, protocol: 4),
    GameIdentity(game: "gods_of_the_arena", gameplay: 78, protocol: 4),
    GameIdentity(game: "gods_of_the_arena", gameplay: 79, protocol: 3)]:
  var state = initRelayNotice(identity, "not JSON", 1, seats)
  doAssert not identity.supportsRelayNotice()
  doAssert not state.advanceNotice(10000, [])
for payload in ["not JSON", "{\"maxTicks\":0}",
    "{\"maxTicks\":2147483647}", "{\"draftMode\":\"forged\"}"]:
  var rejected = false
  try:
    var fullSeats = newSeq[Seat](10)
    fullSeats[0].owner = 1
    discard initRelayNotice(current, payload, 24, fullSeats)
  except RoomsError: rejected = true
  doAssert rejected, "Invalid schedule must reject before match starts"
doAssert noticePayload().len == 8
for command in [Command(participant: 0, seat: 0, sequence: 1, payload: noticePayload()),
    Command(participant: 1, seat: ServerNoticeSeat, sequence: 1, payload: noticePayload())]:
  doAssert not command.validNotice()
echo "PASS policy exact gameplay79/protocol4 opt-in, legacy/other adapters untouched, invalid startup schedule rejected"
