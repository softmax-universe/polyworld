## Shared selection outline settings and Shady shaders.

import shady, vmath, screens

type
  SelectionOutlineError* = object of CatchableError

  OutlineVisibility* = enum
    AlwaysOutline, OccludedOutline


var
  selectionTexture: Uniform[Sampler2d]
  selectionDepth: Uniform[Sampler2d]
  selectionResolution: Uniform[Vec2]
  selectionColor: Uniform[Vec3]
  selectionYTransform: Uniform[Vec2]

const
  SelectionOutlineColor* = vec3(1.0, 0.78, 0.12)
  AttackOutlineColor* = vec3(0.92, 0.16, 0.14)
  OccludedOutlineColor* = vec3(0.55, 0.85, 1.0)

proc occlusionFragment*(
    fragColor: var Vec4,
    gl_FragDepth: var float32,
    texturePosition: Vec2
) =
  ## Keeps silhouette edges only where scenery hides the selected body.
  let
    pixel = vec2(2.0'f) / selectionResolution
    center = texture(selectionTexture, screenCoordinates(texturePosition, selectionYTransform)).a
  var
    nearby = 0.0'f
    nearestDepth = 1.0'f
  for y in -1 .. 1:
    for x in -1 .. 1:
      let
        uv = texturePosition + vec2(float32(x), float32(y)) * pixel
        alpha = texture(selectionTexture, screenCoordinates(uv, selectionYTransform)).a
        depth = texture(selectionDepth, screenCoordinates(uv, selectionYTransform)).r
      if alpha > 0.5'f and depth < 1.0'f:
        nearby = max(nearby, alpha)
        nearestDepth = min(nearestDepth, depth)
  let edge = clamp(nearby - center, 0.0'f, 1.0'f)
  if edge <= 0.0'f:
    discardFragment()
  # Bias the silhouette's depth without writing the scene depth.
  gl_FragDepth = max(nearestDepth - 0.0000001'f, 0.0'f)
  fragColor = vec4(selectionColor, edge)

proc selectionVertex*(
    gl_Position: var Vec4,
    texturePosition: var Vec2,
    vertexPosition: Vec2
) =
  ## Emits one full-screen triangle vertex for the selection outline.
  texturePosition = vertexPosition * 0.5'f + 0.5'f
  gl_Position = vec4(vertexPosition.x, vertexPosition.y, 0, 1)

proc selectionFragment*(fragColor: var Vec4, texturePosition: Vec2) =
  ## Finds the outside edge of the selected object's exact silhouette.
  let
    pixel = vec2(1, 1) / selectionResolution
    center = texture(selectionTexture, screenCoordinates(texturePosition, selectionYTransform)).a
  var nearby = 0.0'f
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(-2, -2) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(0, -2) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(2, -2) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(-2, 0) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(2, 0) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(-2, 2) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(0, 2) * pixel, selectionYTransform)
    ).a
  )
  nearby = max(
    nearby,
    texture(
      selectionTexture,
      screenCoordinates(texturePosition + vec2(2, 2) * pixel, selectionYTransform)
    ).a
  )
  let edge = clamp(nearby - center, 0, 1)
  fragColor = vec4(selectionColor, edge)
