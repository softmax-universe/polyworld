## Bounded script formation gestures use the same planner as human line moves.
import
  bassy,
  content, linemoves, sim

const MaxScriptLinePoints = 2048

proc bindLineCommands*(host: var Host, playerId: int32,
    active: proc(): Game {.closure.}) =
  ## Gives one player's host a private, one-shot line formation builder.
  var
    world: World
    units: seq[int32]
    points: seq[LinePoint]

  proc clearLine() =
    ## Discards unfinished staging without touching any unit orders.
    world = nil
    units = @[]
    points = @[]

  let startProc: HostProc = proc(arguments: openArray[int32]): int32 =
    ## Starts a fresh group and stroke in the active match.
    clearLine()
    let game = active()
    if game == nil or game.world == nil or playerId < 0 or
        playerId >= game.world.players.len:
      return 0
    world = game.world
    1
  discard host.addFunction("lineStart", 0, startProc, 8)

  let addUnitProc: HostProc = proc(arguments: openArray[int32]): int32 =
    ## Adds a unique living owned unit, respecting the ordinary line filter.
    let game = active()
    if game == nil or world == nil or game.world != world:
      clearLine()
      return 0
    let id = arguments[0]
    if units.len >= UnitsPerPlayer or id in units or
        world.eligibleLineUnits(playerId, [id]).len == 0:
      return 0
    units.add id
    1
  discard host.addFunction("lineAddUnit", 1, addUnitProc, 20)

  let addPointProc: NumericHostProc = proc(arguments: openArray[Value]): Value =
    ## Converts the same tile-center coordinates accepted by moveUnit.
    let game = active()
    if game == nil or world == nil or game.world != world:
      clearLine()
      return 0'i32
    let
      x = int32(arguments[0].asFixed).float64 / 65536.0 + 0.5
      y = int32(arguments[1].asFixed).float64 / 65536.0 + 0.5
    if points.len >= MaxScriptLinePoints or x < 0 or y < 0 or
        x >= world.map.side.float64 or y >= world.map.side.float64:
      clearLine()
      return 0'i32
    points.add linePoint(x, y)
    1'i32
  discard host.addFunction("lineAddPoint", 2, addPointProc, 8)

  let moveProc: ContextHostProc = proc(runtime: Runtime,
      arguments: openArray[Value]): Value =
    ## Consumes one gesture and records accepted ordinary or attack moves.
    let
      game = active()
      selected = move(units)
      stroke = move(points)
      staged = world
      attack = arguments[0].asInt
      append = arguments[1].asInt
    clearLine()
    if game == nil or staged == nil or game.world != staged or
        selected.len == 0 or stroke.len == 0 or
        attack notin 0'i32 .. 1'i32 or append notin 0'i32 .. 1'i32:
      return 0'i32
    runtime.chargeWork(selected.len.int64 * 400 +
      staged.map.side.int64 * staged.map.side.int64)
    let
      eligible = staged.eligibleLineUnits(playerId, selected)
      targets = staged.planLineMove(playerId, eligible, stroke)
    if targets.len != eligible.len:
      return 0'i32
    var accepted = 0'i32
    for target in targets:
      let unit = staged.units[staged.unitIndex(target.unitId)]
      let applied =
        if attack != 0 and unit.kind != PeonUnit:
          game.applyAttackMove(playerId, target.unitId,
            target.tile.x.int32, target.tile.y.int32, target.offset,
            append = append != 0)
        else:
          game.applyMove(playerId, target.unitId,
            target.tile.x.int32, target.tile.y.int32, target.offset,
            append = append != 0)
      if applied: inc accepted
    accepted
  discard host.addFunction("lineMove", 2, moveProc, 100000)
