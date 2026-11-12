import vmath
import ../[minimaporders, maps]

# Right click moves; an armed A-click attacks without panning the camera.
doAssert minimapOrder(true, false, false, false) == MinimapWalk
doAssert minimapOrder(true, false, true, false) == MinimapAttackMove
doAssert minimapOrder(false, true, true, false) == MinimapAttackMove
doAssert minimapOrder(false, true, false, false) == NoMinimapOrder
# Spell and item targeting must not leak into movement orders.
doAssert minimapOrder(true, false, true, true) == NoMinimapOrder
let destination = minimapDestination(vec2(12.75'f, -8.25'f))
let half = (mapTiles() div 2).int32
doAssert destination.x == half + 12 and destination.y == half - 9
# Absolute command cells are bounded even when the cursor crosses the map edge.
doAssert minimapDestination(vec2(-10000'f, 10000'f)) ==
  (0.int32, (mapTiles() - 1).int32)
# The feedback belongs at the commanded tile, not beneath the HUD cursor.
let marker = minimapMarker(destination, 3.5'f)
doAssert marker == vec3(12.5'f, 3.5'f, -8.5'f)
echo "Minimap order routing and world feedback passed"
