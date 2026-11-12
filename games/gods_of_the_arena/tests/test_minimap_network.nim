## Real sparse humans: minimap pixel -> human queue -> binary relay -> applied path.
import std/math
import jsony, vmath
import polyworld/[rooms, roomclients, relays, rtscameras, pathing]
import ../[controls, game, maps, minimaporders, multiplayer, replays, sim]

proc scenario() =
  clearPlayerCommands()
  var relay = Relay()
  var now = 0.0
  let clients = [RoomClient(identity: gotaIdentity(), name: "Red human"),
    RoomClient(identity: gotaIdentity(), name: "Southwest human")]
  proc exchange() =
    for attempt in 0 ..< 20:
      var sent = false
      for i, client in clients:
        let outgoing = client.outgoing
        client.outgoing = @[]
        for bytes in outgoing:
          relay.process(i + 1, bytes, now)
          sent = true
      var outgoing: seq[Outgoing]
      swap(outgoing, relay.outgoing)
      for output in outgoing:
        if output.bytes.len > 0:
          clients[output.connection - 1].accept(output.bytes)
          sent = true
      for client in clients: doAssert client.error.len == 0, client.error
      if not sent: return
    doAssert false, "exchange did not settle"
  for client in clients: client.opened()
  exchange()
  clients[0].send(RoomMessage(kind: CreateRoom, name: "Minimap coordinates", number: 10,
    tickRate: 24, payload: parseConfig("{\"maxTicks\":240}").toJson()))
  exchange()
  clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
  exchange()
  clients[0].claimHumanSeat(0)
  exchange()
  clients[1].claimHumanSeat(5)
  exchange()
  let host = clients[0].requestStart([])
  exchange()
  let sessions = [host, prepareNetworkMatch(clients[1], [])]
  for i, session in sessions:
    doAssert session.humanHeroIndex() == i
    doAssert session.game.world.heroes.len == 2
    session.start(clients[i].events[0])
    clients[i].events.setLen(0)
  exchange()
  template step() =
    block:
      exchange()
      now += 1.0 / 24
      relay.advance(now)
      exchange()
      for i, session in sessions:
        while clients[i].packets.len > 0:
          let packet = clients[i].packets[0]
          clients[i].packets.delete(0)
          session.applyPacket(packet)
      exchange()
      doAssert sessions[0].game.stateHash() == sessions[1].game.stateHash()
  for attempt in 0 ..< 20:
    for session in sessions:
      let id = session.game.world.draftHeroId()
      if id != 0 and session.game.world.heroIndex(id) == session.humanHeroIndex():
        queueDraft(id, session.humanHeroIndex().int32)
        session.flushSubmissions()
    step()
    if sessions[0].game.world.phase != Drafting: break
  doAssert sessions[0].game.world.phase == Playing
  for i, session in sessions:
    let hero = session.game.world.heroes[i]
    doAssert hero.id == FirstHeroId + (if i == 0: 0 else: 5)
    echo "SPAWN seat=", (if i == 0: 0 else: 5), " team=", hero.team,
      " position=", hero.position, " mapOrigin=", mapOrigin(), " tiles=", mapTiles()

  # Asymmetric targets on real walkable ground, in all signed quadrants.
  # Select actual terrain cells, never fabricate a flat map or teleport a hero.
  let half = mapTiles() div 2
  for signs in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
    var tile: tuple[x, y: int32]
    var found = false
    for z in 3 .. 12:
      for x in 3 .. 17:
        if x == z: continue
        let tx = half + signs[0] * x
        let tz = half + signs[1] * z
        if isWalkable(GroundLayer, tx, tz):
          tile = (tx.int32, tz.int32)
          found = true
          break
      if found: break
    doAssert found
    let point = vec2(tile.x.float32 - half.float32 + 0.25'f,
      tile.y.float32 - half.float32 + 0.75'f)
    let origin = vec2(19, 37)
    let size = vec2(231, 173)
    let pixel = origin + ((point + vec2(mapHalfSize())) / (2 * mapHalfSize())) * size
    let minimapPoint = minimapWorldPoint(pixel, origin, size, mapHalfSize())
    for i, session in sessions:
      let hero = session.game.world.heroes[i]
      # Real ground picking: engine layer index minus centered engine origin.
      let groundX = (layers[GroundLayer].originX + tile.x.int - mapOrigin()).int32
      let groundY = (layers[GroundLayer].originZ + tile.y.int - mapOrigin()).int32
      queueWalkTo(hero.id, groundX, groundY)
      session.flushSubmissions()
      for delivery in 0 ..< 4: step()
      doAssert hero.moveTileX == tile.x and hero.moveTileY == tile.y
      doAssert hero.movePath.len > 0
      let groundDestination = hero.movePath[^1]
      doAssert mapCoordinate(groundDestination.x) == tile.x and
        mapCoordinate(groundDestination.z) == tile.y, "fixture requires reachable ground cell"
      let before = session.game.stateHash()
      let destination = minimapDestination(minimapPoint)
      queueWalkTo(hero.id, destination.x, destination.y)
      session.flushSubmissions()
      doAssert session.game.stateHash() == before, "submission must not move local world"
      for delivery in 0 ..< 4: step()
      echo "ORDER team=", hero.team, " point=", point, " queued=", destination,
        " groundWorld=", groundDestination, " minimapWorld=", hero.movePath[^1]
      doAssert hero.moveTileX == tile.x and hero.moveTileY == tile.y,
        "minimap and ground must reach the same absolute map cell on both axes"
      doAssert hero.movePath[^1] == groundDestination,
        "authoritative world destination must equal the clicked ground destination"
      let marker = minimapMarker(destination, 3.5'f)
      doAssert marker.x == floor(point.x) + 0.5'f and
        marker.z == floor(point.y) + 0.5'f, "feedback must remain in centered world space"
      queueAttackMove(hero.id, destination.x, destination.y)
      session.flushSubmissions()
      step()
      doAssert hero.attackMoving
      doAssert hero.moveTileX == tile.x and hero.moveTileY == tile.y
      doAssert hero.movePath[^1] == groundDestination
  echo "PASS sparse seats 0/5: both teams, four asymmetric quadrants, ground/minimap/A-move destinations, peer hashes"

scenario()
