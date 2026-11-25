## Shared screen-door shader and settings for the X-ray body pass.

import
  std/[os, strutils],
  shady, vmath

type
  XrayBodyError* = object of CatchableError

  XrayBodySettings* = object
    enabled*: bool
    coverage*: float32
      ## Share of the pattern's pixels that show the body, 0 .. 1. Half is
      ## a checkerboard.
    cell*: float32
      ## Points per pattern cell; `finishXrayBodies` multiplies it by the
      ## window's content scale, so a cell is the same size on every screen.
    clearance*: float32
      ## World units a body must sit behind scenery before it shows, so a
      ## visible body never speckles over itself.

var
  bodyColor: Uniform[Sampler2d]
  bodyDepth: Uniform[Sampler2d]
  coverage: Uniform[float32]
  cell: Uniform[float32]
  depthTerms: Uniform[Vec4]
  clearance: Uniform[float32]
  patternYTransform: Uniform[Vec2]

proc fullscreenVertex*(gl_Position: var Vec4) =
  ## Covers the target with one triangle generated from the vertex index.
  let corner = vec2(
    float32((gl_VertexID mod 2) * 2),
    float32((gl_VertexID div 2) * 2)
  )
  gl_Position = vec4(
    corner.x * 2.0'f - 1.0'f,
    corner.y * 2.0'f - 1.0'f,
    0.0'f,
    1.0'f
  )

proc compositeFragment*(
    gl_FragCoord: Vec4,
    gl_FragDepth: var float32,
    fragColor: var Vec4
) =
  ## Draws hidden body texels through the fixed screen-door pattern.
  let
    patternPixel = vec2(gl_FragCoord.x,
      gl_FragCoord.y * patternYTransform.x + patternYTransform.y)
    pattern = ivec2(floor(patternPixel / cell) mod 4.0'f)
    lowX = pattern.x mod 2
    lowY = pattern.y mod 2
    highX = pattern.x div 2
    highY = pattern.y div 2
    # Expand the two recursive Bayer levels without a shader array.
    bayer = abs(lowX - lowY) * 8 + lowY * 4 +
      abs(highX - highY) * 2 + highY
  if (float32(bayer) + 0.5'f) / 16.0'f >= coverage:
    discardFragment()
  let
    texel = ivec2(gl_FragCoord.xy)
    body = texelFetch(bodyColor, texel, 0)
  if body.a <= 0.0'f:
    discardFragment()
  # Pull toward the eye in view space for either projection type.
  let ndc = texelFetch(bodyDepth, texel, 0).r * 2.0'f - 1.0'f
  var z = (depthTerms.y - ndc * depthTerms.w) /
    (ndc * depthTerms.z - depthTerms.x)
  z += clearance
  let nearer = (depthTerms.x * z + depthTerms.y) /
    (depthTerms.z * z + depthTerms.w)
  gl_FragDepth = clamp(nearer * 0.5'f + 0.5'f, 0.0'f, 1.0'f)
  fragColor = vec4(body.rgb, 1.0'f)

proc defaultXrayBodySettings*(): XrayBodySettings =
  ## A checkerboard in three-point cells.
  XrayBodySettings(enabled: true, coverage: 0.5, cell: 3, clearance: 0.2)

proc envFlag(name: string, default: bool): bool =
  ## Reads a setting flag while preserving its default when absent.
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  ## Reads a numeric setting, preserving the default on invalid input.
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc xrayBodySettings*(
    prefix: string,
    defaults = defaultXrayBodySettings()
): XrayBodySettings =
  ## Applies PREFIX=0 (off), PREFIX_COVERAGE and PREFIX_CELL from the
  ## environment over the defaults.
  result = defaults
  result.enabled = envFlag(prefix, defaults.enabled)
  result.coverage = clamp(
    envFloat(prefix & "_COVERAGE", defaults.coverage), 0, 1)
  result.cell = max(1'f, envFloat(prefix & "_CELL", defaults.cell))
