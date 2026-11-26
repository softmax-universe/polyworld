## Bodies seen through scenery with a screen-door dither.
##
## Walls draw whole. Whatever part of a body sits behind them shows through
## on a fixed Bayer 4x4 pattern, so a fighter in a corridor stays readable
## without cutting holes in the level.
##
## How it works, for a game that draws straight to the window:
##
## 1. `beginXrayBodies` binds an offscreen colour and depth target and
##    clears it. The game draws its bodies again, with any look it likes
##    (a side colour, say). Their own depth test keeps the nearest surface,
##    so an arm behind a torso stays behind it.
## 2. `finishXrayBodies` lays that target over the window with the depth
##    test inverted: a texel lands only where the body is behind what the
##    window already holds, and only on the pattern's pixels. Visible bodies
##    sit at their own depth and fail the test, so they are never covered.
##
## The pattern is anchored to window pixels, not to the world, so it
## doesn't crawl as the camera pans. Nothing writes depth, so particles and
## gizmos drawn later still sort against the walls.
##
## `xrayBodySettings` reads PREFIX=0 (off), PREFIX_COVERAGE and PREFIX_CELL
## (points per cell).

import backends/passes/xraybodies
export xraybodies
