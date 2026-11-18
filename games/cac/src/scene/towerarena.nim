## Tower Arena's compact two-player table, shared by local and online games.
import
  std/math,
  vmath,
  placement, table, ../play

export placement

type
  TowerArenaView* = object
    camera*, nearHand*, farHand*, spell*: Placement
    handRoll*: float32

const
  BoardWidth = 18.0'f
  BoardDepth = 11.0'f
  DefaultTowerArenaView* = TowerArenaView(
    camera: Placement(height: 12.05, distance: 13.08, pitch: 0.7659),
    nearHand: Placement(height: 1.25, distance: 5.86),
    farHand: Placement(height: 1.52, distance: 3.60),
    spell: Placement(height: 1.60, distance: 0.35),
    handRoll: -0.0684)

proc towerSide*(seat: int): float32 =
  ## The side of the courtyard occupied by this seat.
  if seat == 0: 1.0'f else: -1.0'f

proc ownerYaw(seat: int): float32 =
  ## A card on a player's side reads the right way up from their seat.
  if seat == 0: 0.0'f else: PI.float32

proc heroPosition(seat: int): Vec3 =
  ## Places each hero beside its own creature row.
  vec3(if seat == 0: -7.0'f else: 7.0'f, 0.02,
    seat.towerSide * 1.65'f)

proc handPoses(view: TowerArenaView, seat, count, viewedSeat: int):
    seq[CardPose] =
  ## Fans either hand toward the current camera without changing its owner.
  let
    side = seat.towerSide
    cameraSide = viewedSeat.towerSide
    hand = (if seat == viewedSeat: view.nearHand
      else: view.farHand).mirrored(side)
    camera = view.camera.mirrored(cameraSide)
    pitch = arctan2(camera.distance - hand.distance,
      camera.height - hand.height) + hand.pitch
  fanPoses(count, vec3(hand.lateral, hand.height, hand.distance), pitch,
    cameraSide, viewedSeat.ownerYaw + cameraSide * hand.yaw, view.handRoll)

proc boardPoses(seat, count: int): seq[CardPose] =
  ## Fits a creature row on its half, lifting overlapping cards in order.
  if count <= 0:
    return
  let
    spacing =
      if count == 1: 0.0'f
      else: min(1.75'f, 9.0'f / (count - 1).float32)
    start = -spacing * (count - 1).float32 * 0.5'f
    lift = if spacing < CardWidth: RowOverlapLift else: 0.0'f
  for i in 0 ..< count:
    result.add CardPose(
      position: vec3(start + spacing * i.float32,
        CardPlaneY + lift * i.float32, seat.towerSide * 1.25'f),
      yaw: seat.ownerYaw)

proc spellPose(view: TowerArenaView, seat: int): CardPose =
  ## Floats a played spell just past its caster's creature row.
  let
    side = seat.towerSide
    spell = view.spell.mirrored(side)
  CardPose(position: vec3(spell.lateral, spell.height, spell.distance),
    yaw: seat.ownerYaw + side * view.spell.yaw, pitch: view.spell.pitch)

proc pilePose(seat, viewedSeat: int, x: float32): CardPose =
  ## Keeps each pile on its stone pad and readable from the current camera.
  CardPose(position: vec3(x, PileCardY, seat.towerSide * 3.7'f),
    yaw: viewedSeat.ownerYaw)

proc towerTable*(getView: proc(): TowerArenaView,
    viewedSeat: proc(): int): TableLayout =
  ## Reads the camera live so turn changes also update in-flight card poses.
  TableLayout(
    handPoses: proc(player, count: int): seq[CardPose] =
      getView().handPoses(player, count, viewedSeat()),
    boardPoses: boardPoses,
    deckPose: proc(player: int): CardPose =
      pilePose(player, viewedSeat(), -7.25),
    discardPose: proc(player: int): CardPose =
      pilePose(player, viewedSeat(), 7.25),
    spellPose: proc(player: int): CardPose =
      getView().spellPose(player),
    heroPosition: heroPosition,
    handVisible: proc(player: int): bool =
      player == viewedSeat(),
    overBoard: proc(point: Vec3): bool =
      abs(point.x) <= BoardWidth * 0.5'f and
        abs(point.z) <= BoardDepth * 0.5'f,
    heroLungePoint: proc(fromPose: CardPose, hero: Vec3): Vec3 =
      vec3(fromPose.position.x * 0.3, CardPlaneY + 0.3, hero.z * 0.7))
