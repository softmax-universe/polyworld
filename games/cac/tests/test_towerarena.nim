## Tower Arena's card layout stays usable from either seat without a window.
import
  std/math,
  vmath,
  ../src/scene/[towerarena, table, courtyard], ../src/play

const Tolerance = 0.0002'f

proc onScreen(point: Vec3, viewProjection: Mat4): bool =
  ## Checks the complete clip volume, including points behind the camera.
  let clip = viewProjection * vec4(point, 1)
  clip.w > 0 and abs(clip.x) <= clip.w and abs(clip.y) <= clip.w and
    abs(clip.z) <= clip.w

iterator corners(pose: CardPose): Vec3 =
  ## Uses the same card footprint and transform as rendering and hit tests.
  for x in [-CardWidth * 0.5'f, CardWidth * 0.5'f]:
    for z in [-CardDepth * 0.5'f, CardDepth * 0.5'f]:
      yield pose.position + pose.transformCardVector(vec3(x, 0, z))

var
  currentView = DefaultTowerArenaView
  viewedSeat = 0
let layout = towerTable(proc(): TowerArenaView = currentView,
  proc(): int = viewedSeat)

echo "Testing Tower Arena's cards fit the courtyard from both seats"
for seat in 0 .. 1:
  for count in [0, 1, 7, 12]:
    let row = layout.boardPoses(seat, count)
    doAssert row.len == count
    for pose in row:
      for corner in pose.corners:
        doAssert layout.overBoard(corner)
        doAssert corner.y >= BoardSurfaceY
  for pose in [layout.deckPose(seat), layout.discardPose(seat)]:
    for corner in pose.corners:
      doAssert abs(corner.x) < PavingHalfWidth
      doAssert abs(corner.z) < PavingHalfDepth
      doAssert corner.y >= PadSurfaceY
  let hero = layout.heroPosition(seat)
  doAssert abs(hero.x) < PavingHalfWidth and abs(hero.z) < PavingHalfDepth
  let lunge = layout.heroLungePoint(layout.boardPoses(1 - seat, 1)[0], hero)
  doAssert layout.overBoard(lunge)

echo "Testing both cameras frame cards, piles and heroes"
for viewer in 0 .. 1:
  viewedSeat = viewer
  let
    eye = currentView.camera.seatEye(viewer.towerSide)
    target = currentView.camera.seatTarget(viewer.towerSide)
    view = lookAt(eye, target, vec3(0, 1, 0))
  for aspect in [1.5'f, 1.6'f, 16.0'f / 9.0'f]:
    let vp = perspective(42.0'f, aspect, 0.1'f, 100.0'f) * view
    for seat in 0 .. 1:
      doAssert layout.handVisible(seat) == (seat == viewer)
      doAssert layout.drawFaceUp(seat) == (seat == viewer)
      for pose in layout.handPoses(seat, 7) & layout.boardPoses(seat, 7) &
          @[layout.deckPose(seat), layout.discardPose(seat)]:
        for corner in pose.corners:
          doAssert corner.onScreen(vp)
      for pose in layout.handPoses(seat, 7):
        doAssert dot(pose.cardNormal, normalize(eye - pose.position)) > 0.5
      let hero = layout.heroPosition(seat)
      doAssert hero.onScreen(vp)
      doAssert (hero + vec3(0, 2.8, 0)).onScreen(vp)

echo "Testing a retained layout follows spectator turns and live tuning"
viewedSeat = 0
let
  originalHand = layout.handPoses(0, 1)[0]
  originalPile = layout.deckPose(0)
  originalBoard = layout.boardPoses(0, 7)
  originalHero = layout.heroPosition(0)
viewedSeat = 1
doAssert not layout.handVisible(0) and layout.handVisible(1)
doAssert not layout.drawFaceUp(0) and layout.drawFaceUp(1)
doAssert layout.handPoses(0, 1)[0] != originalHand
doAssert abs(layout.deckPose(0).yaw - originalPile.yaw - PI.float32) <
  Tolerance
doAssert layout.deckPose(0).position == originalPile.position
doAssert layout.boardPoses(0, 7) == originalBoard
doAssert layout.heroPosition(0) == originalHero
viewedSeat = 0
currentView.nearHand.height += 0.5
doAssert abs(layout.handPoses(0, 1)[0].position.y -
  originalHand.position.y - 0.5'f) < Tolerance
let normalBeforeCameraMove = layout.handPoses(0, 1)[0].cardNormal
currentView.camera.distance += 3
doAssert length(layout.handPoses(0, 1)[0].cardNormal -
  normalBeforeCameraMove) > 0.01

echo "PASS Tower Arena framing, card zones and live seat changes"
