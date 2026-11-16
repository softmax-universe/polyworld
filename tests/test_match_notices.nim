import std/[unittest, strutils]
import polyworld/[rooms, relays, roomclients]

suite "duration preparation and typed notice codec":
  test "legacy preparation encodings remain byte identical":
    for item in [(Ready, 10), (StartMatch, 11), (Prepared, 31)]:
      var fixture = "PWRM"
      fixture.put32(4)
      fixture.put32(uint32(item[1]))
      fixture.add repeat('\0', 52)
      fixture.put32(7)
      fixture.put64(42)
      check RoomMessage(kind: item[0], revision: 7, hash: 42).encode == fixture
      check decode(fixture).kind == item[0]
  test "duration and typed notice round trip without extending old packets":
    when declared(PreparedDuration) and declared(ServerNotice):
      let preparation = RoomMessage(kind: PreparedDuration, revision: 7,
        hash: 42, durationTicks: 5000)
      check decode(preparation.encode) == preparation
      let notice = RoomMessage(kind: ServerNotice, match: 3, noticeId: 1,
        tick: 680, noticeCode: ThreeMinutesRemain)
      check decode(notice.encode) == notice
      var invalid = notice.encode
      invalid[^1] = '\xff'
      expect RoomsError: discard decode(invalid)
      expect RoomsError: discard decode(notice.encode & "x")
    else:
      check false # New append-only wire operations are missing.

proc send(r: Relay, c: int, m: RoomMessage, now = 0.0) =
  r.receive(c, decode(m.encode), now)

proc lobby(protocol = 4'u32): Relay =
  result = Relay()
  for c in 1 .. 3:
    result.send(c, RoomMessage(kind: Hello, name: "Human " & $c,
      identity: GameIdentity(game: "light_vs_dark", gameplay: 1, protocol: protocol)))
  result.send(1, RoomMessage(kind: CreateRoom, name: "Clock", number: 2, tickRate: 1))
  for c in 2 .. 3:
    result.send(c, RoomMessage(kind: JoinRoom, room: result.rooms[0].id))
  for c in 1 .. 2:
    result.send(c, RoomMessage(kind: ClaimSeat, seat: uint32(c-1), name: "Human"))

proc prepare(r: Relay, c: int, duration = 184'u32, hash = 42'u64) =
  r.send(c, RoomMessage(kind: PreparedDuration, revision: r.rooms[0].revision,
    hash: hash, durationTicks: duration))

proc start(r: Relay, duration = 184'u32) =
  for c in 1 .. 2: r.prepare(c, duration)
  r.send(1, RoomMessage(kind: StartMatch))
  r.outgoing.setLen(0)

proc notices(r: Relay): seq[RoomMessage] =
  for output in r.outgoing:
    if output.bytes.len > 0:
      let message = decode(output.bytes)
      if message.kind == ServerNotice: result.add message

suite "real relay duration and applied-time notices":
  test "protocol four requires bounded duration proof from every occupied owner":
    let r = lobby()
    expect RoomsError: r.prepare(1, 0)
    expect RoomsError: r.prepare(1, uint32(MaxHistoryTicks) + 1)
    expect RoomsError:
      r.send(1, RoomMessage(kind: Prepared, revision: r.rooms[0].revision, hash: 42))
    r.send(1, RoomMessage(kind: StartMatch))
    r.prepare(1)
    check r.rooms[0].phase == Lobby
    r.prepare(2)
    check r.rooms[0].phase == Playing
  test "same hash with disagreeing duration cannot begin":
    let r = lobby()
    r.prepare(1, 184)
    r.prepare(2, 185)
    r.send(1, RoomMessage(kind: StartMatch))
    check r.rooms[0].phase == Desynced
  test "issued ticks and elapsed time alone never announce; applied edge broadcasts once":
    let r = lobby()
    r.start()
    for tick in 1 .. 6: r.advance(float64(tick))
    check r.notices.len == 0
    r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 3), 6)
    r.advance(6)
    check r.notices.len == 0
    # A slow controller and spectator must receive the same trigger, not hold it up.
    r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 5), 6)
    check r.notices.len == 0 # Only advance decides, after completion reports.
    r.advance(6)
    check r.notices.len == 3
    for notice in r.notices:
      check notice.match == 1 and notice.noticeId == 1
      check notice.tick == 4 and notice.noticeCode == ThreeMinutesRemain
    r.advance(7)
    check r.notices.len == 3
  test "a spectator acknowledgement cannot trigger a server notice":
    let r = lobby()
    r.start()
    for tick in 1 .. 5: r.advance(float64(tick))
    r.send(3, RoomMessage(kind: AppliedTick, match: 1, tick: 5), 5)
    r.advance(5)
    check r.notices.len == 0
  test "completion known in same scheduler batch suppresses notice":
    let r = lobby()
    r.start()
    for tick in 1 .. 5: r.advance(float64(tick))
    r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 5), 5)
    r.send(2, RoomMessage(kind: FinishMatch, match: 1, tick: 4, hash: 99), 5)
    r.advance(5)
    check r.rooms[0].phase == Ended
    check r.notices.len == 0
  test "paused clock and matches no longer than three minutes never announce":
    for duration in [180'u32, 184'u32]:
      let r = lobby()
      r.start(duration)
      r.advance(1)
      r.send(1, RoomMessage(kind: PauseMatch, match: 1, flag: true), 1)
      for tick in 2 .. 10: r.advance(float64(tick))
      check r.rooms[0].tick == 1
      check r.notices.len == 0
      r.send(1, RoomMessage(kind: PauseMatch, match: 1, flag: false), 10)
      for tick in 11 .. 15: r.advance(float64(tick))
      r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: r.rooms[0].tick), 15)
      r.advance(15)
      check r.notices.len == (if duration == 180: 0 else: 3)
  test "server notice cannot be submitted as an authenticated player operation":
    let r = lobby()
    r.start()
    expect RoomsError:
      r.send(1, RoomMessage(kind: ServerNotice, match: 1, noticeId: 1,
        tick: 4, noticeCode: ThreeMinutesRemain))
    check r.notices.len == 0
  test "reconnect and late spectator recover the one retained notice":
    let r = lobby()
    r.start()
    for tick in 1 .. 4: r.advance(float64(tick))
    r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 4), 4)
    r.advance(4)
    let token = r.guest(2).token
    r.disconnect(2)
    r.outgoing.setLen(0)
    r.send(4, RoomMessage(kind: Hello, name: "Human 2", token: token,
      identity: r.guest(1).identity), 4)
    check r.notices.len == 1
    r.outgoing.setLen(0)
    r.send(5, RoomMessage(kind: Hello, name: "Late spectator",
      identity: r.guest(1).identity), 4)
    r.send(5, RoomMessage(kind: JoinRoom, room: r.rooms[0].id), 4)
    check r.notices.len == 1
  test "revision invalidates duration and rematch resets notice identity":
    let r = lobby()
    r.prepare(1)
    r.send(1, RoomMessage(kind: ReleaseSeat, seat: 0))
    r.send(1, RoomMessage(kind: ClaimSeat, seat: 0, name: "Human"))
    r.send(1, RoomMessage(kind: StartMatch))
    r.prepare(2)
    check r.rooms[0].phase == Lobby
    r.prepare(1)
    for tick in 1 .. 4: r.advance(float64(tick))
    r.send(1, RoomMessage(kind: AppliedTick, match: 1, tick: 4), 4)
    r.advance(4)
    check r.notices.len == 3
    r.send(1, RoomMessage(kind: FinishMatch, match: 1, tick: 4, hash: 99), 4)
    r.advance(4)
    r.send(1, RoomMessage(kind: ReturnLobby), 4)
    r.start()
    check r.rooms[0].match == 2
    for tick in 1 .. 4: r.advance(float64(tick))
    r.send(1, RoomMessage(kind: AppliedTick, match: 2, tick: 4), 4)
    r.advance(4)
    check r.notices.len == 3
    for notice in r.notices: check notice.match == 2 and notice.noticeId == 1

suite "client applied notice presentation cursor":
  test "queue until applied, dedupe reconnect, retire on new match":
    when declared(takeNotice):
      let c = RoomClient(connected: true, welcomed: true)
      c.accept(RoomMessage(kind: BeginMatch, match: 1).encode)
      let notice = RoomMessage(kind: ServerNotice, match: 1, noticeId: 1,
        tick: 4, noticeCode: ThreeMinutesRemain)
      c.accept(notice.encode)
      var shown: RoomMessage
      check not c.takeNotice(shown)
      for tick in 1'u32 .. 3: c.appliedTick(tick)
      check not c.takeNotice(shown)
      c.lost()
      c.opened()
      c.accept(RoomMessage(kind: BeginMatch, match: 1).encode)
      c.accept(notice.encode)
      c.appliedTick(4)
      check c.takeNotice(shown)
      check shown == notice
      c.accept(notice.encode)
      check not c.takeNotice(shown)
      var corrupt = notice
      corrupt.tick = 5
      expect RoomsError: c.accept(corrupt.encode)
      corrupt = notice
      corrupt.noticeId = 2
      expect RoomsError: c.accept(corrupt.encode) # One notice type, bounded retention.
      c.accept(RoomMessage(kind: RoomState, room: "same", phase: Lobby).encode)
      c.accept(RoomMessage(kind: BeginMatch, match: 2).encode)
      expect RoomsError: c.accept(notice.encode)
      var next = notice
      next.match = 2
      c.accept(next.encode)
      for tick in 1'u32 .. 4: c.appliedTick(tick)
      check c.takeNotice(shown)
      check shown.match == 2
    else:
      check false # Missing applied notice queue.
