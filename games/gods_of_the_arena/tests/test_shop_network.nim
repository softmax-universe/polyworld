## Shop commands through two binary clients and the real opaque relay.
import jsony
import polyworld/[rooms, roomclients, relays, tapes]
import ../[content, controls, maps, multiplayer, replays, sim]

block authoritativeShop:
  let relay = Relay()
  let clients = [RoomClient(identity: gotaIdentity(), name: "Shop host"),
    RoomClient(identity: gotaIdentity(), name: "Shop guest")]
  var now = 0.0
  proc exchange() =
    for attempt in 0 ..< 30:
      var sent = false
      for i, client in clients:
        let outgoing = client.outgoing
        client.outgoing = @[]
        for bytes in outgoing:
          relay.process(i + 1, bytes, now)
          sent = true
      let outgoing = relay.outgoing
      relay.outgoing = @[]
      for output in outgoing:
        if output.bytes.len > 0:
          clients[output.connection - 1].accept(output.bytes)
          doAssert clients[output.connection - 1].error.len == 0
          sent = true
      if not sent: return
    doAssert false, "shop exchange did not settle"
  for client in clients: client.opened()
  exchange()
  clients[0].send(RoomMessage(kind: CreateRoom, name: "Shop QA", number: 10,
    tickRate: 24, payload: parseConfig("{\"maxTicks\":48}").toJson()))
  exchange()
  clients[1].send(RoomMessage(kind: JoinRoom, room: clients[0].snapshot.room))
  exchange()
  clients[0].claimHumanSeat(1)
  clients[1].claimHumanSeat(8)
  exchange()
  let sessions = [prepareNetworkMatch(clients[0], []), prepareNetworkMatch(clients[1], [])]
  clients[0].send(RoomMessage(kind: StartMatch, revision: sessions[0].revision,
    hash: sessions[0].game.networkHash()))
  exchange()
  for i, session in sessions:
    session.start(clients[i].events[0])
    clients[i].events.setLen(0)
    # Explicit deterministic shop fixture, identical on both clients.
    let world = session.game.world
    world.phase = sim.Playing
    world.spawnTimerTicks = 100_000
    world.heroTurnTicks = 100_000
    for hero in world.heroes:
      hero.state = Dying
      hero.hp = 0
      hero.mana = 0
      hero.gold = 1000
      hero.deathTicks = 40
      hero.potionCooldownEnds[ManaRecovery] = 110
      hero.portalCooldownEnds = 220
    let config = session.game.recorder.data.config
    session.game.recorder = initReplayRecorder(session.game.currentSetup(48), session.game.map.preset)
    session.game.recorder.data.config = config
  exchange()
  let initial = sessions[0].game.world.clone()
  proc step() =
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
  let hero = sessions[0].game.world.heroes[0]
  let guest = sessions[1].game.world.heroes[1]
  clearPlayerCommands()
  for i in 0 ..< 3: queueBuyItem(hero.id, ManaPotion.ord.int32)
  queueBuyItem(hero.id, PortalScroll.ord.int32)
  sessions[0].flushSubmissions()
  queueBuyItem(guest.id, KnightArmor.ord.int32)
  sessions[1].flushSubmissions()
  doAssert hero.inventory[0] == NoItem and hero.gold == 1000
  doAssert guest.inventory[0] == NoItem and guest.gold == 1000
  exchange()
  for i in 0 ..< 3: step()
  doAssert hero.inventory[0] == ManaPotion and hero.itemCounts[0] == 3
  doAssert hero.inventory[1] == PortalScroll and hero.itemCounts[1] == 1
  doAssert guest.inventory[0] == KnightArmor
  let gold = hero.gold
  queueSwapItems(hero.id, 0, 1)
  queueSwapItems(hero.id, 1, 5)
  queueSwapItems(hero.id, -1, 0)
  sessions[0].flushSubmissions()
  doAssert hero.inventory[0] == ManaPotion
  exchange()
  for i in 0 ..< 3: step()
  doAssert hero.inventory[0] == PortalScroll and hero.itemCounts[0] == 1
  doAssert hero.inventory[1] == NoItem and hero.itemCounts[1] == 0
  doAssert hero.inventory[5] == ManaPotion and hero.itemCounts[5] == 3
  doAssert hero.itemCooldown(5, sessions[0].game.world.tick) == 110 - sessions[0].game.world.tick
  doAssert hero.gold == gold
  queueSellItem(hero.id, 5)
  queueSellItem(hero.id, 5) # Repeated sale cannot mint money.
  queueSellItem(hero.id, InventorySlots)
  queueBuyItem(hero.id, KnightArmor.ord.int32)
  queueBuyItem(hero.id, KnightArmor.ord.int32) # No duplicate equipment.
  sessions[0].flushSubmissions()
  queueSellItem(guest.id, 0)
  sessions[1].flushSubmissions()
  doAssert hero.itemCounts[5] == 3
  exchange()
  for i in 0 ..< 3: step()
  doAssert hero.inventory[5] == NoItem and hero.itemCounts[5] == 0
  doAssert hero.gold == gold + ManaPotion.itemSpec.cost * 3 div 2 - KnightArmor.itemSpec.cost
  doAssert hero.gold >= 0 and guest.gold == 1000 - KnightArmor.itemSpec.cost div 2
  doAssert hero.hp == 0 and hero.mana == 0 and hero.state == Dying
  let data = decodeReplay(encodeReplay(sessions[0].game.recorder.data))
  doAssert data.actions == sessions[1].game.recorder.data.actions
  doAssert data.hashes == sessions[1].game.recorder.data.hashes
  doAssert data.actions.len == 14
  let playback = newGame(generateMap(data.config.seed, data.config.mapPreset),
    data.config.spawnIntervalTicks, 0, true, data)
  playback.historyPlayback = true
  playback.replayPlayer = initReplayPlayer(data)
  for pass in 0 .. 1:
    playback.world.restore(initial)
    playback.replayPlayer.syncCursor(0)
    for tick in 0 ..< data.hashes.len: playback.tickWorld(nil)
    doAssert playback.hashCheck.mismatches == 0, playback.hashCheck.error
    doAssert playback.stateHash() == sessions[0].game.stateHash()
  # New action kinds survive signed bounds unchanged; invalid kinds never enter.
  for kind in [ActionSellItem, ActionSwapItems]:
    for slot in [-1'i32, 0, InventorySlots.int32, int32.high]:
      let action = ReplayAction(kind: kind, heroId: hero.id, slot: slot, first: int32.high)
      let decoded = decodeSubmission(GameSubmission(action: action).encodeSubmission())
      doAssert decoded.action == action
  var rejected = false
  try:
    discard decodeSubmission(GameSubmission(action: ReplayAction(kind: ActionSwapItems + 1)).encodeSubmission())
  except RoomsError: rejected = true
  doAssert rejected
  echo "Shop relay/replay parity passed: 2 clients, 14 actions, signed bounds, repeated seek"
