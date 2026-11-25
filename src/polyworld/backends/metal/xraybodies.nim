## Metal implementation of the screen-door X-ray body pass.

import
  chroma, shady, vmath,
  common, ../shaders/xraybodies

export xraybodies

type
  XrayBodies* = object
    settings*: XrayBodySettings
    program: MetalProgram
    bodies: RenderTarget
    size: IVec2
    open: bool

proc initXrayBodies*(
    settings = defaultXrayBodySettings()
): XrayBodies =
  ## Compiles the composite and defers target allocation to the first frame.
  result.settings = settings
  result.program = newProgram(
    toShader(fullscreenVertex, metalMSL, shaderVertex),
    toShader(compositeFragment, metalMSL, shaderFragment)
  )

proc closeXrayBodies*(xray: var XrayBodies) =
  ## Releases the body target and composite program.
  if xray.open:
    popTarget()
  destroy(xray.bodies)
  destroy(xray.program)
  xray = XrayBodies()

proc ensureSize(xray: var XrayBodies, size: IVec2) =
  ## Matches the single-sample body target to the scene dimensions.
  if size == xray.size:
    return
  destroy(xray.bodies)
  xray.bodies = newRenderTarget(size.x.int, size.y.int)
  xray.size = size

proc beginXrayBodies*(xray: var XrayBodies, size: IVec2): bool =
  ## Binds and clears the body target, returning false for disabled passes.
  if xray.open:
    raise newException(XrayBodyError, "X-ray body pass is already open")
  if not xray.settings.enabled or size.x <= 0 or size.y <= 0:
    return false
  xray.ensureSize(size)
  pushTarget(xray.bodies)
  clear(color(0, 0, 0, 0))
  xray.open = true
  true

proc finishXrayBodies*(
    xray: var XrayBodies, projection: Mat4, contentScale = 1.0'f
) =
  ## Composites hidden body pixels without changing the scene depth.
  if not xray.open:
    return
  xray.open = false
  popTarget()
  let program = xray.program
  program.bindTexture("bodyColor", xray.bodies.color)
  program.bindTexture("bodyDepth", xray.bodies.depth)
  program.setUniform("coverage", xray.settings.coverage)
  program.setUniform("cell",
    max(1.0'f, round(xray.settings.cell * max(contentScale, 1.0'f))))
  program.setUniform("depthTerms", vec4(
    projection[2, 2], projection[3, 2], projection[2, 3], projection[3, 3]
  ))
  program.setUniform("clearance", xray.settings.clearance)
  program.setUniform("patternYTransform", vec2(-1.0'f, xray.size.y.float32))
  draw(program, nil, 3, DrawState(
    depthTest: true,
    depthWrite: false,
    depthCompare: Greater
  ))
