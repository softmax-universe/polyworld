## Screen-space distortion: explosion shockwaves, heat haze and shield bubbles
## that bend what is behind them, like the distortion pass in Recoil (Spring)
## games.
##
## It works on what the window already shows. One blit copies the finished
## scene, multisampled or not, into a texture. Each distortion is then a quad
## facing the camera that re-draws that copy shifted a few pixels:
##
## - `ShockwaveDistortion`: a ring that races from the center to the edge and
##   pushes the picture outward as it passes, fading as it grows.
## - `HeatDistortion`: rippling haze that rises and drifts, fading out.
## - `ShieldDistortion`: a bubble that magnifies the middle and bends hard at
##   its rim.
##
## Call `drawDistortions` after the world and its particles and before the HUD.
## Quads are depth tested without writing depth, pulled toward the camera by
## their radius, so hills and walls hide distortions behind them.

when defined(useDirectX):
  import backends/directx/renderer
elif defined(useVulkan):
  import backends/vulkan/renderer
elif defined(useMetal4):
  import backends/metal/distortions
else:
  import backends/opengl/distortions

when not defined(useDirectX) and not defined(useVulkan):
  export distortions
