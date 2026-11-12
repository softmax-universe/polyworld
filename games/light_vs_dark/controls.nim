## Human overlord commands for Light vs Dark.
##
## Graphics queues intents. The decide tick applies them through the Game
## `apply*` wrappers that also record the tape.

import
  sim, content, replays

type
  PlayerCommandKind = enum
    CommandMove
    CommandAttackMove
    CommandAttack
    CommandHarvest
    CommandBuild
    CommandTrain
    CommandResearch
    CommandRally
    CommandCancel

  PlayerCommand = object
    kind: PlayerCommandKind
    player: int32
    entityId: int32
    first: int32
    second: int32
    third: int32
    append: bool

  ProductionReservation = object
    world: World
    command: PlayerCommand

var
  pending: seq[PlayerCommand]
  inFlight: seq[ProductionReservation]
  rotationWorld: World
  lastProducer = NoEntity
  pendingBuild*: int32 = -1
    ## Building kind ordinal waiting for a map click, or -1.
  attackMoveArmed*: bool
    ## Next ground click is an attack-move.

proc clearPlayerCommands*() =
  ## Prevent menu transitions from carrying stale orders into another world.
  pending.setLen(0)
  inFlight.setLen(0)
  rotationWorld = nil
  lastProducer = NoEntity
  pendingBuild = -1
  attackMoveArmed = false

proc queueMove*(player, unitId, x, y: int32, append = false) =
  ## Queues a move for one owned unit.
  pending.add PlayerCommand(
    kind: CommandMove,
    append: append,
    player: player,
    entityId: unitId,
    first: x,
    second: y
  )

proc queueAttackMove*(player, unitId, x, y: int32, append = false) =
  ## Queues an attack-move for one owned unit.
  pending.add PlayerCommand(
    kind: CommandAttackMove,
    append: append,
    player: player,
    entityId: unitId,
    first: x,
    second: y
  )

proc queueAttack*(player, unitId, targetId: int32, append = false) =
  ## Queues an attack on one enemy.
  pending.add PlayerCommand(
    kind: CommandAttack,
    append: append,
    player: player,
    entityId: unitId,
    first: targetId
  )

proc queueHarvest*(player, unitId, target, isTree: int32, append = false) =
  ## Queues a harvest on a mine or tree.
  pending.add PlayerCommand(
    kind: CommandHarvest,
    append: append,
    player: player,
    entityId: unitId,
    first: target,
    second: isTree
  )

proc queueBuild*(player, peonId, kindValue, x, y: int32) =
  ## Queues a building placement.
  pending.add PlayerCommand(
    kind: CommandBuild,
    player: player,
    entityId: peonId,
    first: kindValue,
    second: x,
    third: y
  )

proc queueTrain*(player, buildingId, kindValue: int32) =
  ## Queues one unit from a building.
  pending.add PlayerCommand(
    kind: CommandTrain,
    player: player,
    entityId: buildingId,
    first: kindValue
  )

proc selectedProducer*(world: World, player: int32, selected: openArray[int32],
    kind: UnitKind): int32 =
  ## Read-only UI routing. Queue slot zero already includes active production.
  result = NoEntity
  if world == nil or player < 0 or player >= world.players.len: return
  var reservedGold, reservedWood, reservedFood: int32
  var commands: seq[PlayerCommand]
  for reservation in inFlight:
    if reservation.world == world: commands.add reservation.command
  commands.add pending
  for command in commands:
    if command.player != player: continue
    case command.kind
    of CommandTrain:
      let stats = unitOf(player, UnitKind(command.first))
      reservedGold += stats.gold
      reservedWood += stats.wood
      reservedFood += stats.food
    of CommandBuild:
      let stats = BuildingTable[BuildingKind(command.first)]
      reservedGold += stats.gold
      reservedWood += stats.wood
    of CommandResearch:
      let kind = ResearchKind(command.first)
      let stats = researchStats(kind, world.researchLevel(player, kind) + 1)
      reservedGold += stats.gold
      reservedWood += stats.wood
    else: discard
  let stats = unitOf(player, kind)
  let side = world.players[player]
  if side.gold - reservedGold < stats.gold or side.wood - reservedWood < stats.wood or
      side.foodUsed + reservedFood + stats.food > side.foodCap: return
  var start = 0
  if rotationWorld == world:
    for i, id in selected:
      if id == lastProducer: start = i + 1
  var bestLoad = int.high
  for offset in 0 ..< selected.len:
    let id = selected[(start + offset) mod selected.len]
    let index = world.buildingIndex(id)
    if index < 0: continue
    let structure = world.buildings[index]
    if structure.owner != player or structure.hp <= 0 or not world.canTrain(id, kind): continue
    var load = structure.queueLength.int
    for command in commands:
      if command.kind == CommandTrain and command.player == player and command.entityId == id:
        inc load
    if load < QueueSlots and load < bestLoad:
      result = id
      bestLoad = load

proc selectedTrainingCount*(world: World, player: int32,
    selected: openArray[int32], kind: UnitKind): int =
  ## Badges count accepted and pending work across the selected producer union.
  for i, id in selected:
    if id in selected.toOpenArray(0, i - 1): continue
    let index = world.buildingIndex(id)
    if index < 0: continue
    let b = world.buildings[index]
    if b.owner != player or b.hp <= 0 or b.state != BuildingComplete: continue
    for slot in 0 ..< b.queueLength.int:
      if b.queue[slot] == uint8(kind.ord + 1): inc result
    for command in pending:
      if command.kind == CommandTrain and command.player == player and
          command.entityId == id and command.first == kind.ord.int32: inc result
    for reservation in inFlight:
      let command = reservation.command
      if reservation.world == world and command.kind == CommandTrain and
          command.player == player and command.entityId == id and
          command.first == kind.ord.int32: inc result

proc queueSelectedTrain*(world: World, player: int32, selected: openArray[int32],
    kind: UnitKind): bool =
  let id = world.selectedProducer(player, selected, kind)
  if id == NoEntity: return false
  queueTrain(player, id, kind.ord.int32)
  rotationWorld = world
  lastProducer = id
  true

proc queueResearch*(player, buildingId: int32, kind: ResearchKind) =
  ## Enqueue only; multiplayer waits for its authoritative packet.
  pending.add PlayerCommand(kind: CommandResearch, player: player,
    entityId: buildingId, first: kind.ord.int32)

proc queueSetRally*(player, buildingId, x, y: int32) =
  ## Queues a rally point.
  pending.add PlayerCommand(
    kind: CommandRally,
    player: player,
    entityId: buildingId,
    first: x,
    second: y
  )

proc queueCancel*(player, entityId: int32) =
  ## Queues a cancel on one owned entity.
  pending.add PlayerCommand(
    kind: CommandCancel,
    player: player,
    entityId: entityId
  )

proc applyCommand(game: Game, command: PlayerCommand): bool =
  ## Applies one queued command through the recording wrappers.
  case command.kind
  of CommandMove:
    game.applyMove(
      command.player, command.entityId, command.first, command.second,
      append = command.append
    )
  of CommandAttackMove:
    game.applyAttackMove(
      command.player, command.entityId, command.first, command.second,
      append = command.append
    )
  of CommandAttack:
    game.applyAttack(command.player, command.entityId, command.first, command.append)
  of CommandHarvest:
    game.applyHarvest(
      command.player,
      command.entityId,
      command.first,
      command.second, command.append
    )
  of CommandBuild:
    game.applyBuild(
      command.player,
      command.entityId,
      command.first,
      command.second,
      command.third
    )
  of CommandTrain:
    game.applyTrain(command.player, command.entityId, command.first)
  of CommandResearch:
    game.applyResearch(command.player, command.entityId, command.first)
  of CommandRally:
    game.applySetRally(
      command.player, command.entityId, command.first, command.second
    )
  of CommandCancel:
    game.applyCancel(command.player, command.entityId)

proc flushPlayerCommands*(game: Game) =
  ## Drains the human queue on a decision tick.
  if pending.len == 0:
    return
  let commands = pending
  pending.setLen(0)
  for command in commands:
    if game.applyCommand(command) and game.networked and
        command.kind in {CommandTrain, CommandBuild, CommandResearch}:
      inFlight.add ProductionReservation(world: game.world, command: command)

proc retireProductionReservation*(world: World, action: ReplayAction) =
  ## Release only when authority applies (or rejects) this exact command, not
  ## when transport sends it or acknowledges a future decision-tick packet.
  let kind = case action.kind
    of ActionTrain: CommandTrain
    of ActionBuild: CommandBuild
    of ActionResearch: CommandResearch
    else: return
  for i, reservation in inFlight:
    let command = reservation.command
    if reservation.world == world and command.kind == kind and
        command.player == action.playerId and command.entityId == action.entityId and
        command.first == action.first and command.second == action.second and
        command.third == action.third:
      inFlight.delete(i)
      return
