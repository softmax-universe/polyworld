## Shared card cache and CPU triangle batching for the selected backend.

proc faceTexture(sk: Silky, state: FaceState): CardTexture =
  ## The face's texture, drawn the first time it is needed. Past the budget,
  ## the texture least recently shown is drawn over.
  if state in faceTextures:
    faceTextures[state].lastFrame = frame
    return faceTextures[state].texture
  var
    oldest = frame
    stale: FaceState
    found = false
  if faceTextures.len >= FaceTextureBudget:
    for key, face in faceTextures:
      if face.lastFrame < oldest:
        oldest = face.lastFrame
        stale = key
        found = true
  if found:
    result = faceTextures[stale].texture
    faceTextures.del stale
  else:
    result = newFaceTexture()
  sk.renderFace(state, result)
  faceTextures[state] = FaceTexture(texture: result, lastFrame: frame)

proc clear*(renderer: var CardRenderer) =
  ## Starts a frame's cards.
  renderer.vertices.setLen(0)
  renderer.batches.setLen(0)
  inc frame

proc quadCount*(renderer: CardRenderer): int =
  ## Quads queued this frame, for the benchmark.
  renderer.vertices.len div (6 * FloatsPerVertex)

proc addQuad(renderer: var CardRenderer, corners: array[4, Vec3],
    uvs: array[4, Vec2], brightness, damageFlash: float32, tint: Vec3,
    texture: CardTexture, size: Vec2) =
  let first = renderer.vertices.len div FloatsPerVertex
  if renderer.batches.len > 0 and renderer.batches[^1].texture == texture:
    renderer.batches[^1].count += 6
  else:
    renderer.batches.add Batch(texture: texture, size: size, first: first,
      count: 6)
  for i in [0, 1, 2, 0, 2, 3]:
    let p = corners[i]
    renderer.vertices.add [p.x, p.y, p.z, uvs[i].x, uvs[i].y,
      brightness * tint.x, brightness * tint.y, brightness * tint.z,
      damageFlash]

proc addSurface*(renderer: var CardRenderer, sk: Silky,
    corners: array[4, Vec3], imageKey: string, brightness = 1.0'f32,
    damageFlash = 0.0'f32, tint = vec3(1, 1, 1)) =
  ## One atlas image over these corners: top-left, bottom-left,
  ## bottom-right, top-right in card space. `tint` colours the image, for
  ## sprites that aren't card faces.
  let
    entry = sk.atlas.entries[imageKey]
    left = entry.x.float32 + 0.5'f32
    top = entry.y.float32 + 0.5'f32
    right = (entry.x + entry.width).float32 - 0.5'f32
    bottom = (entry.y + entry.height).float32 - 0.5'f32
    atlasSize = sk.atlasImageSize()
  renderer.addQuad(corners, [vec2(left, top), vec2(left, bottom),
    vec2(right, bottom), vec2(right, top)], brightness, damageFlash, tint,
    atlasTexture(sk), vec2(atlasSize.x.float32, atlasSize.y.float32))

proc addFace*(renderer: var CardRenderer, sk: Silky,
    corners: array[4, Vec3], state: FaceState, brightness = 1.0'f32,
    damageFlash = 0.0'f32) =
  ## Draws a cached face with half-texel insets and the backend's texture origin.
  const
    left = 0.5'f32
    right = CardFaceWidth.float32 - 0.5'f32
    top = FaceTextureTop
    bottom = FaceTextureBottom
  renderer.addQuad(corners, [vec2(left, top), vec2(left, bottom),
    vec2(right, bottom), vec2(right, top)], brightness, damageFlash,
    vec3(1, 1, 1), sk.faceTexture(state),
    vec2(CardFaceWidth.float32, CardFaceHeight.float32))

proc drawFace*(sk: Silky, state: FaceState, origin, size: Vec2,
    tint = rgbx(255, 255, 255, 255)) =
  ## A card face in the HUD: the face's texture, drawn over the HUD once
  ## silky has drawn it (`drawHudFaces`).
  hudFaces.add HudFace(texture: sk.faceTexture(state), origin: origin,
    size: size, tint: tint)

proc drawFlatFace*(sk: Silky, card: Card, origin, size: Vec2,
    tint = rgbx(255, 255, 255, 255)) =
  ## A printed face, for the choose screen.
  sk.drawFace(FaceState(card: card, power: -1, toughness: -1), origin, size,
    tint)
