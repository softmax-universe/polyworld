## Minimap order routing and shared world-space feedback coordinates.
import std/math, vmath
import maps

type MinimapOrder* = enum
  NoMinimapOrder, MinimapWalk, MinimapAttackMove

proc minimapOrder*(rightPressed, leftPressed, attackArmed, targeting: bool): MinimapOrder =
  ## Leaves ordinary left-click camera navigation and aimed casts untouched.
  if targeting:
    return NoMinimapOrder
  if rightPressed or (leftPressed and attackArmed):
    return if attackArmed: MinimapAttackMove else: MinimapWalk

proc minimapDestination*(point: Vec2): tuple[x, y: int32] =
  ## Human commands use absolute map cells, not centered signed world tiles.
  ## Both teams share this frame; only bot observations rotate team coordinates.
  let half = mapTiles() div 2
  (int32(clamp(int(floor(point.x)) + half, 0, mapTiles() - 1)),
    int32(clamp(int(floor(point.y)) + half, 0, mapTiles() - 1)))

proc minimapMarker*(destination: tuple[x, y: int32], height: float32): Vec3 =
  ## Converts the absolute command cell back to centered world-space feedback.
  let half = (mapTiles() div 2).float32
  vec3(destination.x.float32 - half + 0.5'f, height,
    destination.y.float32 - half + 0.5'f)
