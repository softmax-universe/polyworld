## Native Metal ground capture and current-sight compositing.

import
  pixie, shady, vmath,
  polyworld/backends/metal/common,
  ../../strictfogshaders

type StrictFog* = object
  program: MetalProgram
  ground, target: RenderTarget
  sight: MetalTexture
  size: IVec2
  capturing: bool
  inverse: Mat4
  side: int

proc initStrictFog*(): StrictFog =
  ## Compiles the shared visibility shader for the active Metal device.
  result.program = newProgram(
    toShader(strictFogVertex, metalMSL, shaderVertex),
    toShader(strictFogFragment, metalMSL, shaderFragment)
  )

proc ensureSize(fog: var StrictFog, size: IVec2) =
  ## Keeps captured attachments compatible with the active frame target.
  let target = metalRenderer.target
  if target == nil or target.color == nil or target.depth == nil:
    raise newException(PolyworldMetalError,
      "Strict fog requires an active color and depth target")
  if fog.ground != nil and fog.size == size and
    fog.ground.color.pixelFormat == target.color.pixelFormat and
    fog.ground.stencil == target.stencil:
      return
  destroy(fog.ground)
  fog.size = size
  fog.ground = newRenderTarget(size.x, size.y,
    colorFormat = target.color.pixelFormat, stencil = target.stencil)

proc beginStrictGround*(fog: var StrictFog, size: IVec2) =
  ## Redirects the ground pass into preserved color and depth attachments.
  if fog.capturing:
    raise newException(PolyworldMetalError,
      "Strict fog ground capture is already active")
  fog.ensureSize(size)
  fog.target = metalRenderer.target
  pushTarget(fog.ground)
  fog.capturing = true

proc captureStrictGround*(
  fog: var StrictFog,
  size: IVec2,
  inverseView: Mat4,
  values: openArray[uint8],
  side: int
) =
  ## Completes ground capture and uploads the authoritative current sight.
  if side <= 0 or values.len != side * side:
    raise newException(PolyworldMetalError,
      "Strict fog sight dimensions must match the map")
  fog.inverse = inverseView
  if fog.capturing:
    popTarget()
    fog.capturing = false
  else:
    fog.ensureSize(size)
    fog.target = metalRenderer.target
    copyTarget(fog.target, fog.ground)
  let image = newImage(side, side)
  for i, value in values:
    image.data[i] = rgbx(value, value, value, 255)
  if fog.sight == nil or fog.side != side:
    destroy(fog.sight)
    fog.sight = newTexture(image, linear = false)
  else:
    fog.sight.updateTexture(image)
  fog.side = side

proc restoreHiddenGround*(fog: var StrictFog) =
  ## Restores hidden ground while retaining all visible scene pixels.
  if fog.ground == nil or fog.sight == nil:
    return
  setTarget(fog.target)
  fog.program.bindTexture("groundColor", fog.ground.color)
  fog.program.bindTexture("groundDepth", fog.ground.depth)
  fog.program.bindTexture("currentSight", fog.sight)
  fog.program.setUniform("inverseView", fog.inverse)
  fog.program.setUniform("mapSide", fog.side.float32)
  fog.program.setUniform("textureYTransform", vec2(-1, 1))
  draw(fog.program, nil, 3)

proc closeStrictFog*(fog: var StrictFog) =
  ## Releases captured attachments and the current-sight shader resources.
  if fog.capturing:
    popTarget()
  destroy(fog.program)
  destroy(fog.ground)
  destroy(fog.sight)
  fog = StrictFog()
