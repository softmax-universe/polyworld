var
  envHighlight: Uniform[Vec3]
  envShadow: Uniform[Vec3]
  envLightDirection: Uniform[Vec3]  # toward the light
  # Sun shadow map sampling, fed from polyworld/shadows each frame. Two
  # maps at neighbouring quantized sun steps, cross-faded by shadowStep so
  # shadows dissolve toward the next sun position instead of shimmering.
  shadowMvp0: Uniform[Mat4]
  shadowMvp1: Uniform[Mat4]
  shadowMapPcf0: Uniform[Sampler2dShadow]
  shadowMapPcf1: Uniform[Sampler2dShadow]
  shadowStep: Uniform[float32]
  shadowsOn: Uniform[float32]
  shadowStrength: Uniform[float32]
  shadowBias: Uniform[float32]
  shadowTexel: Uniform[float32]
  shadowSoftness: Uniform[float32]
  shadingStrength: Uniform[float32]
  envLightLevel: Uniform[float32]
  ambientMap: Uniform[Sampler2D]
  ambientBounds: Uniform[Vec4]
  ambientEnabled: Uniform[float32]

const EnvironmentExposure = 1.15'f32
  ## Lifts the palette-graded environment back to the brightness the old
  ## fixed half-lambert gave flat ground under the Day palette.

proc sunLitFraction0(shadowPos: Vec3): float32 =
  ## Raw lit fraction from the first shadow step, 0 shadowed .. 1 clear: a
  ## 3x3 grid of hardware-PCF taps, each itself bilinearly filtered by the
  ## comparison sampler. Positions outside the map count as lit.
  result = 1.0'f
  let
    shadowCoord: Vec4 = shadowMvp0 * vec4(shadowPos, 1.0'f)
    su = shadowCoord.x * 0.5'f + 0.5'f
    sv = shadowCoord.y * 0.5'f + 0.5'f
    sd = shadowCoord.z * 0.5'f + 0.5'f - shadowBias
  if su > 0.0'f and su < 1.0'f and sv > 0.0'f and sv < 1.0'f and sd < 1.0'f:
    let spread = shadowTexel * shadowSoftness
    var lit = 0.0'f32
    lit = lit + texture(shadowMapPcf0, vec3(su - spread, sv - spread, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su, sv - spread, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su + spread, sv - spread, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su - spread, sv, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su, sv, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su + spread, sv, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su - spread, sv + spread, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su, sv + spread, sd))
    lit = lit + texture(shadowMapPcf0, vec3(su + spread, sv + spread, sd))
    result = lit / 9.0'f

proc sunLitFraction1(shadowPos: Vec3): float32 =
  ## The same for the second shadow step.
  result = 1.0'f
  let
    shadowCoord: Vec4 = shadowMvp1 * vec4(shadowPos, 1.0'f)
    su = shadowCoord.x * 0.5'f + 0.5'f
    sv = shadowCoord.y * 0.5'f + 0.5'f
    sd = shadowCoord.z * 0.5'f + 0.5'f - shadowBias
  if su > 0.0'f and su < 1.0'f and sv > 0.0'f and sv < 1.0'f and sd < 1.0'f:
    let spread = shadowTexel * shadowSoftness
    var lit = 0.0'f32
    lit = lit + texture(shadowMapPcf1, vec3(su - spread, sv - spread, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su, sv - spread, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su + spread, sv - spread, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su - spread, sv, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su, sv, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su + spread, sv, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su - spread, sv + spread, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su, sv + spread, sd))
    lit = lit + texture(shadowMapPcf1, vec3(su + spread, sv + spread, sd))
    result = lit / 9.0'f

proc sampleSunShadow(shadowPos: Vec3): float32 =
  ## How lit by the sun a surface point is, cross-fading between the two
  ## quantized sun steps. The result already folds in the shadow strength.
  result = 1.0'f
  if shadowsOn > 0.5'f:
    var lit = sunLitFraction0(shadowPos)
    if shadowStep > 0:
      lit = mix(lit, sunLitFraction1(shadowPos), shadowStep)
    result = 1.0'f - (1.0'f - lit) * shadowStrength

proc ambientVisibility(position: Vec3): float32 =
  ## Samples baked sky visibility at the receiver height, fading above the map.
  result = 1.0'f
  if ambientEnabled > 0.5'f:
    let uv = (vec2(position.x, position.z) - ambientBounds.xy) / ambientBounds.zw
    if uv.x >= 0.0'f and uv.x <= 1.0'f and uv.y >= 0.0'f and uv.y <= 1.0'f:
      let values = texture(ambientMap, uv)
      if position.y < 1.0'f:
        result = mix(values.x, values.y, clamp(position.y, 0.0'f, 1.0'f))
      elif position.y < 3.0'f:
        result = mix(values.y, values.z, (position.y - 1.0'f) / 2.0'f)
      elif position.y < 7.0'f:
        result = mix(values.z, values.w, (position.y - 3.0'f) / 4.0'f)
      else:
        result = mix(values.w, 1.0'f, clamp((position.y - 7.0'f) / 4.0'f,
          0.0'f, 1.0'f))

proc envShade(albedo, normal: Vec3, sunFactor: float32): Vec3 =
  ## Palette-graded lighting: half-lambert toward the shared light scaled by
  ## the shadow test, softly stepped, choosing between the shadow and
  ## highlight colours. lightLevel fades only that directional term toward
  ## the shadow band, so the horizon swap does not flatten or black out.
  let
    halfLambert = dot(normalize(normal), envLightDirection) * 0.5'f + 0.5'f
    intensity =
      (1.0'f - shadingStrength + halfLambert * sunFactor * shadingStrength) *
      envLightLevel
    band = smoothstep(0.45'f, 0.8'f, intensity)
  result = albedo * mix(envShadow, envHighlight, band) * EnvironmentExposure

proc envShadeTwoSided(albedo, normal: Vec3, sunFactor: float32): Vec3 =
  ## The same for cards lit from either side (foliage).
  let
    halfLambert =
      abs(dot(normalize(normal), envLightDirection)) * 0.5'f + 0.5'f
    intensity =
      (1.0'f - shadingStrength + halfLambert * sunFactor * shadingStrength) *
      envLightLevel
    band = smoothstep(0.45'f, 0.8'f, intensity)
  result = albedo * mix(envShadow, envHighlight, band) * EnvironmentExposure

var
  mvp: Uniform[Mat4]
  propModel: Uniform[Mat4]
  borderWidthUniform: Uniform[float32]
  heightScale: Uniform[float32]
  edgesEnabled: Uniform[float32]
  texScale: Uniform[float32]
  blendDepth: Uniform[float32]
  heightBlend: Uniform[float32]
  terrainTextures: Uniform[Sampler2dArray]
  unboostedMaterial: Uniform[float32]
  generatedEnabled: Uniform[float32]
  heightBlendEnabled: Uniform[float32]
  splatsEnabled: Uniform[float32]
  splatAmount: Uniform[float32]
  splatColors: Uniform[Sampler2dArray]
  splatHeights: Uniform[Sampler2dArray]
  splatData: Uniform[Sampler2D]
  blendData: Uniform[Sampler2D]
  splatDataSize: Uniform[Vec2]
  blendDataSize: Uniform[Vec2]
  visibilityTex: Uniform[Sampler2D]
  visibilityOffset: Uniform[float32]
  visibilityScale: Uniform[float32]
  groundMask: Uniform[Sampler2D]
  groundMaskEnabled: Uniform[float32]
  groundLayers: Uniform[Vec4]
  groundRing: Uniform[Vec4]
  groundRingShape: Uniform[Vec3]
  propTint: Uniform[Vec4]

proc texture(buffer: Uniform[Sampler2dArray], position: Vec3): Vec4 =
  ## Provides Shady with the texture-array builtin signature.
  vec4(0)

proc atan(y, x: float32): float32 =
  ## Provides Shady with the two-argument atan builtin.
  arctan2(y, x)

proc textureLod(
    buffer: Uniform[Sampler2dArray], position: Vec3, lod: float32
): Vec4 =
  ## Provides Shady with the explicit-mip texture-array builtin signature.
  vec4(0)

proc blendFetch(index: float32): Vec4 =
  ## Reads one material neighborhood from a nearest-filtered data texture.
  let row = floor(index / blendDataSize.x)
  result = texture(blendData, vec2(
    (index - row * blendDataSize.x + 0.5) / blendDataSize.x,
    (row + 0.5) / blendDataSize.y
  ))

proc splatFetch(index: float32): Vec4 =
  ## Reads one brush record through the shared material data texture.
  let row = floor(index / splatDataSize.x)
  result = texture(splatData, vec2(
    (index - row * splatDataSize.x + 0.5) / splatDataSize.x,
    (row + 0.5) / splatDataSize.y
  ))

proc surfaceAmount(paint, baseHeight, detailHeight: float32): float32 =
  ## Shifts coverage toward higher details while preserving empty endpoints.
  result = paint
  if heightBlendEnabled > 0.5 and paint > 0.0 and paint < 1.0:
    let
      difference = 2.0 * paint - 1.0 +
        (detailHeight - baseHeight) * heightBlend
      ratio = clamp(difference / max(blendDepth, 0.0001), -1.0, 1.0)
      a = 1.0 - max(ratio, 0.0)
      b = 1.0 + min(ratio, 0.0)
    result = b / (a + b)

proc terrainVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    edgeMask: float32,
    normal: Vec3,
    tileColor: Vec3,
    materials: Vec4,
    cornerWeight: Vec4,
    splatRange: Vec3,
    worldPos: var Vec3,
    vertEdgeMask: var float32,
    vertNormal: var Vec3,
    vertColor: var Vec3,
    vertMaterials: var Vec4,
    vertWeights: var Vec4,
    vertSplatRange: var Vec3,
    shadowPos: var Vec3
) =
  ## Emits terrain vertex outputs for the selected shader backend.
  gl_Position = mvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  # Normal-offset shadows: sample the sun's maps slightly off the surface,
  # which suppresses self-shadow acne better than depth bias alone.
  shadowPos = vec3(
    vertPos.x + normal.x * 0.08,
    vertPos.y + normal.y * 0.08,
    vertPos.z + normal.z * 0.08
  )
  worldPos = vertPos
  vertEdgeMask = edgeMask
  vertNormal = normal
  vertColor = tileColor
  vertMaterials = materials
  vertWeights = cornerWeight
  vertSplatRange = splatRange

proc terrainSample(uv: Vec2, material, elevationGain: float32): Vec4 =
  ## Preserves the selected material's authored color before surface blending.
  result = texture(terrainTextures, vec3(uv, max(material, 0.0)))
  if unboostedMaterial >= 0.0 and abs(material - unboostedMaterial) < 0.5:
    result = vec4(
      result.xyz / (elevationGain * EnvironmentExposure), result.w)

proc terrainFrag(
    fragColor: var Vec4,
    worldPos: Vec3,
    vertEdgeMask: float32,
    vertNormal: Vec3,
    vertColor: Vec3,
    vertMaterials: Vec4,
    vertWeights: Vec4,
    vertSplatRange: Vec3,
    shadowPos: Vec3
) =
  ## Height-blends textured tile materials and applies visibility fog.
  let
    tilePos = vec2(worldPos.x, worldPos.z)
    h = clamp(
      worldPos.y / max(heightScale, 0.001) * 0.5 + 0.5,
      0.0,
      1.0
    )
    elevationGain = 0.75 + 0.5 * h
    absNormal = abs(vertNormal)
  var uv = vec2(worldPos.x, worldPos.z) * texScale
  if absNormal.y < 0.5:
    if absNormal.x > absNormal.z:
      uv = vec2(worldPos.z, -worldPos.y) * texScale
    else:
      uv = vec2(worldPos.x, -worldPos.y) * texScale
  var
    materials = vertMaterials
    spatial = vertWeights
  if generatedEnabled > 0.5 and vertSplatRange.z >= 0:
    let
      tileUv = tilePos - floor(tilePos)
      quadrant = floor(tileUv.x + 0.5) + floor(tileUv.y + 0.5) * 2.0
      centerUv = tilePos - floor(tilePos + vec2(0.5)) + vec2(0.5)
    materials = blendFetch(floor(vertSplatRange.z + 0.5) + quadrant)
    spatial = radialWeights(centerUv)
  let
    sample0 = terrainSample(uv, materials.x, elevationGain)
    sample1 = terrainSample(uv, materials.y, elevationGain)
    sample2 = terrainSample(uv, materials.z, elevationGain)
    sample3 = terrainSample(uv, materials.w, elevationGain)
    blend0 = vertWeights.x + sample0.w * heightBlend
    blend1 = vertWeights.y + sample1.w * heightBlend
    blend2 = vertWeights.z + sample2.w * heightBlend
    blend3 = vertWeights.w + sample3.w * heightBlend
    cutoff = max(
      max(blend0, blend1),
      max(blend2, blend3)
    ) - blendDepth
    weight0 = max(blend0 - cutoff, 0.0)
    weight1 = max(blend1 - cutoff, 0.0)
    weight2 = max(blend2 - cutoff, 0.0)
    weight3 = max(blend3 - cutoff, 0.0)
    totalWeight = weight0 + weight1 + weight2 + weight3
    blended = (
      sample0.xyz * weight0 +
      sample1.xyz * weight1 +
      sample2.xyz * weight2 +
      sample3.xyz * weight3
    ) / max(totalWeight, 0.001)
  # Ground mask: where a game baked stone and dirt coverage, cobbles are
  # discrete. A stone survives only while coverage beats its height, so the
  # rim is ragged whole stones with dirt showing between them, and dirt then
  # height-blends into grass.
  var
    ground = blended
    groundHeight = sample0.w
  let
    worldDx = dFdx(tilePos)
    worldDy = dFdy(tilePos)
  if generatedEnabled > 0.5:
    var weights = materialWeights(spatial, materials)
    if heightBlendEnabled > 0.5:
      weights = reliefWeights(
        weights, vec4(sample0.w, sample1.w, sample2.w, sample3.w),
        heightBlend, blendDepth
      )
    var surface = sample0 * weights.x + sample1 * weights.y +
      sample2 * weights.z + sample3 * weights.w
    if splatsEnabled > 0.5 and splatAmount > 0.0:
      var index = int(vertSplatRange.x + 0.5)
      let finish = index + int(vertSplatRange.y + 0.5)
      while index < finish:
        let
          placement = splatFetch(float32(index * 2))
          brush = splatFetch(float32(index * 2 + 1))
          delta = tilePos - placement.xy
          uvSplat = vec2(
            delta.x * placement.z + delta.y * placement.w,
            delta.y * placement.z - delta.x * placement.w
          ) + vec2(0.5)
          dx = vec2(
            worldDx.x * placement.z + worldDx.y * placement.w,
            worldDx.y * placement.z - worldDx.x * placement.w
          )
          dy = vec2(
            worldDy.x * placement.z + worldDy.y * placement.w,
            worldDy.y * placement.z - worldDy.x * placement.w
          )
        if uvSplat.x >= 0.0 and uvSplat.x <= 1.0 and
          uvSplat.y >= 0.0 and uvSplat.y <= 1.0:
            let
              position = vec3(uvSplat, brush.x)
              paint = textureGrad(splatColors, position, dx, dy)
              relief = textureGrad(splatHeights, position, dx, dy)
              alpha = paint.w
              detailHeight = relief.x / max(relief.w, 0.00001)
              amount = min(alpha, surfaceAmount(
                alpha * brush.y * splatAmount, surface.w, detailHeight
              ))
              source = vec4(paint.xyz / max(alpha, 0.00001), detailHeight)
            surface = surface * (1.0 - amount) + source * amount
        index += 1
    ground = surface.xyz
    groundHeight = surface.w
  if groundMaskEnabled > 0.5:
    let
      maskUv = vec2(
        (tilePos.x + visibilityOffset) * visibilityScale,
        (tilePos.y + visibilityOffset) * visibilityScale
      )
      mask = texture(groundMask, maskUv)
    if mask.x + mask.y > 0.002:
      let
        stone = texture(terrainTextures, vec3(uv.x, uv.y, groundLayers.x))
        dirt = texture(terrainTextures, vec3(uv.x, uv.y, groundLayers.y))
        grass = texture(terrainTextures, vec3(uv.x, uv.y, groundLayers.z))
      var maskBase = grass
      if generatedEnabled > 0.5:
        maskBase = vec4(ground, groundHeight)
      let
        dirtBlend = mask.y + dirt.w * heightBlend
        grassBlend = (1.0 - mask.y) + maskBase.w * heightBlend
        groundCutoff = max(dirtBlend, grassBlend) - blendDepth
        dirtWeight = max(dirtBlend - groundCutoff, 0.0)
        grassWeight = max(grassBlend - groundCutoff, 0.0)
        soilTotal = max(dirtWeight + grassWeight, 0.001)
        soil = (dirt.xyz * dirtWeight + maskBase.xyz * grassWeight) / soilTotal
        soilHeight = (dirt.w * dirtWeight + maskBase.w * grassWeight) / soilTotal
      ground = soil
      if generatedEnabled > 0.5:
        let gravelAmount = surfaceAmount(mask.x, soilHeight, stone.w)
        ground = soil * (1.0 - gravelAmount) + stone.xyz * gravelAmount
      elif stone.w >= 1.0 - mask.x:
          ground = stone.xyz
  # Ground ring: a curb of cut stones sampled around a circle rather than
  # across the world, one stone row spanning the band, dropping out past
  # the outer edge the same way the cobbles do. The polar coordinate jumps
  # at the angle seam and at every row change, which would send automatic
  # mip selection to the smallest level along those lines, so the mip is
  # chosen from the ring distance, which is smooth everywhere. Screen
  # derivatives are undefined inside a branch some pixels skip, so the
  # ring's derivative is taken before the band test.
  if groundRingShape.x > 0.5:
    let
      ringDx = tilePos.x - groundRing.x
      ringDz = tilePos.y - groundRing.y
      ringDistance = sqrt(ringDx * ringDx + ringDz * ringDz)
      tilesPerPixel = length(
        vec2(dFdx(ringDistance), dFdy(ringDistance)))
    if ringDistance >= groundRing.z:
      let cover = clamp(
        (groundRing.w + groundRingShape.z - ringDistance) / groundRingShape.z,
        0.0, 1.0)
      if cover > 0.0:
        let
          turns = atan(ringDz, ringDx) / 6.2831853 + 0.5
          along = turns * groundRingShape.x
          cells = groundRingShape.y
          sheetTurn = floor(along / cells)
          row = sheetTurn - cells * floor(sheetTurn / cells)
          across = clamp(
            (ringDistance - groundRing.z) / (groundRing.w - groundRing.z),
            0.0, 1.0)
          stoneTiles = 6.2831853 * (groundRing.z + groundRing.w) * 0.5 /
            groundRingShape.x
          texelsPerPixel = 1024.0 / cells * tilesPerPixel / stoneTiles
          lod = max(log2(max(texelsPerPixel, 0.0001)), 0.0)
          curb = textureLod(
            terrainTextures,
            vec3(along / cells, (row + across) / cells, groundLayers.w),
            lod)
        if curb.w >= 1.0 - cover:
          ground = curb.xyz
  var color = ground * vertColor * elevationGain
  # Passability borders draw on upward faces only (walls sit exactly on
  # integer x/z, so the fract test would classify their every pixel as
  # border), and only while the edge display is toggled on. Each strip is
  # colored by its edge's passability: green connected, red blocked. The
  # mask packs the four edges as bits: east 1, south 2, west 4, north 8.
  if edgesEnabled > 0.5 and vertNormal.y > 0.3:
    let
      fx = tilePos.x - floor(tilePos.x)
      fy = tilePos.y - floor(tilePos.y)
      edge = min(min(fx, 1.0 - fx), min(fy, 1.0 - fy))
    if edge < borderWidthUniform:
      var maskLeft = vertEdgeMask
      var northPass = 0.0'f32
      var westPass = 0.0'f32
      var southPass = 0.0'f32
      var eastPass = 0.0'f32
      if maskLeft >= 8.0:
        northPass = 1.0
        maskLeft = maskLeft - 8.0
      if maskLeft >= 4.0:
        westPass = 1.0
        maskLeft = maskLeft - 4.0
      if maskLeft >= 2.0:
        southPass = 1.0
        maskLeft = maskLeft - 2.0
      if maskLeft >= 1.0:
        eastPass = 1.0
      var passable = 0.0'f32
      if edge == fx:
        passable = westPass
      elif edge == 1.0 - fx:
        passable = eastPass
      elif edge == fy:
        passable = northPass
      else:
        passable = southPass
      if passable >= 0.5:
        color = vec3(0.10, 0.72, 0.22)
      else:
        color = vec3(0.88, 0.10, 0.08)
  # Palette-graded lighting: smooth vertex normals across connected
  # terrain, hard breaks at cliffs and walls, sun shadows folded in.
  color = envShade(color, vertNormal, sampleSunShadow(shadowPos)) *
    ambientVisibility(worldPos)
  let
    visibilityUv = vec2(
      (tilePos.x + visibilityOffset) * visibilityScale,
      (tilePos.y + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
    gray = dot(color, vec3(0.30, 0.59, 0.11)) * 0.32
  color = color * visibility +
    vec3(gray, gray, gray) * (1.0 - visibility)
  fragColor = vec4(color.x, color.y, color.z, 1.0)

## Water shader: transparent blue with a Blinn-Phong specular highlight.

var waterShaderOverride*: tuple[vertex, fragment: string]
  ## A game's own Shady-generated water vertex and fragment sources, used instead of the
  ## default when set before initTerrain (polyworld/waters sets it). It must read vertPos
  ## and may read normal; drawWater still sets mvp, cameraPos and the visibility uniforms.

var waterPremultipliedAlpha* = false
  ## Whether the water shader outputs premultiplied colour, so light it adds (a reflected
  ## sun) can exceed what straight alpha blending would allow.

var
  cameraPos: Uniform[Vec3]
  waterNormals: Uniform[Sampler2dArray]
  waterOffset: Uniform[Vec2]
  waterOpacity: Uniform[float32]
  waterHighlightOpacity: Uniform[float32]

proc waterVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    normal: Vec3,
    worldPos: var Vec3,
    waterNormal: var Vec3
) =
  ## Emits water vertex outputs for the selected shader backend.
  gl_Position = mvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  worldPos = vertPos
  waterNormal = normal

proc waterFrag(
    fragColor: var Vec4,
    worldPos: Vec3,
    waterNormal: Vec3
) =
  ## Shades drifting transparent water with a view-dependent highlight.
  let
    samplePos: Vec2 = vec2(worldPos.x, worldPos.z) - waterOffset
    normalA: Vec3 = texture(waterNormals, vec3(
      samplePos.x * 0.08, samplePos.y * 0.08, 0.0)).xyz * 2.0 - vec3(1.0)
    normalB: Vec3 = texture(waterNormals, vec3(
      samplePos.y * -0.13, samplePos.x * 0.13, 1.0)).xyz * 2.0 - vec3(1.0)
    detailNormal: Vec3 = normalize(vec3(
      normalA.x + normalB.x,
      normalA.z + normalB.z,
      normalA.y + normalB.y
    ))
    surfaceNormal: Vec3 = normalize(mix(
      normalize(waterNormal),
      detailNormal,
      clamp(waterNormal.y, 0.0, 1.0) * 0.38
    ))
    specular = pow(
    max(dot(
      surfaceNormal,
      normalize(normalize(cameraPos - worldPos) + envLightDirection)
    ), 0.0),
    48.0)
    visibilityUv = vec2(
      (worldPos.x + visibilityOffset) * visibilityScale,
      (worldPos.z + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
  let water: Vec3 = vec3(
    (0.05 + 0.08 * visibility) + specular * visibility * envLightLevel,
    (0.10 + 0.24 * visibility) + specular * visibility * envLightLevel,
    (0.16 + 0.42 * visibility) + specular * visibility * envLightLevel
  ) * envHighlight
  fragColor = vec4(water.x, water.y, water.z,
    clamp(waterOpacity + specular * envLightLevel * waterHighlightOpacity,
      0.0, 1.0))

## Prop shader: baked vertex colors with half-lambert lighting.

proc propVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    vertColor: Vec3,
    normal: Vec3,
    fragmentColor: var Vec3,
    fragmentNormal: var Vec3,
    fragmentPosition: var Vec3,
    shadowPos: var Vec3
) =
  ## Emits world-space lighting inputs for baked and standalone props.
  let
    worldPosition: Vec3 =
      (propModel * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)).xyz
    worldNormal: Vec3 = normalize(
      (propModel * vec4(normal.x, normal.y, normal.z, 0.0)).xyz)
  gl_Position = mvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  shadowPos = worldPosition + worldNormal * 0.08
  fragmentColor = vertColor
  fragmentNormal = worldNormal
  fragmentPosition = worldPosition

proc propFrag(
    fragColor: var Vec4,
    fragmentColor: Vec3,
    fragmentNormal,
    fragmentPosition: Vec3,
    shadowPos: Vec3
) =
  ## Shades baked prop colors with the palette-graded lighting.
  let
    visibilityUv = vec2(
      (fragmentPosition.x + visibilityOffset) * visibilityScale,
      (fragmentPosition.z + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
    litColor = envShade(
      fragmentColor, fragmentNormal, sampleSunShadow(shadowPos)) *
      ambientVisibility(fragmentPosition)
    gray = dot(litColor, vec3(0.30, 0.59, 0.11)) * 0.32
  fragColor = vec4(
    (litColor.x * visibility + gray * (1.0 - visibility)) * propTint.x,
    (litColor.y * visibility + gray * (1.0 - visibility)) * propTint.y,
    (litColor.z * visibility + gray * (1.0 - visibility)) * propTint.z,
    propTint.w
  )

## Tree shader: handpainted textured meshes whose foliage is alpha-cutout
## cards. The vertex stream carries uv plus the texture array layer; the
## fragment shader discards transparent texels, lights cards from either
## side, and applies the same visibility fade as the terrain.

var
  treeTextures: Uniform[Sampler2dArray]
  treeAlphaCutoff: Uniform[float32]

proc treeVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    vertUv: Vec3,
    normal: Vec3,
    vertBrightness: float32,
    fragUv: var Vec3,
    fragmentNormal: var Vec3,
    fragmentPosition: var Vec3,
    shadowPos: var Vec3,
    fragBrightness: var float32
) =
  ## Emits textured tree vertex outputs for the selected shader backend.
  gl_Position = mvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  shadowPos = vec3(
    vertPos.x + normal.x * 0.08,
    vertPos.y + normal.y * 0.08,
    vertPos.z + normal.z * 0.08
  )
  fragUv = vertUv
  fragBrightness = vertBrightness
  fragmentNormal = normal
  fragmentPosition = vertPos

proc treeFrag(
    fragColor: var Vec4,
    fragUv: Vec3,
    fragmentNormal,
    fragmentPosition: Vec3,
    shadowPos: Vec3,
    fragBrightness: float32
) =
  ## Cuts out foliage by alpha and shades the painting from either side.
  let texel = texture(treeTextures, fragUv)
  if texel.w < treeAlphaCutoff:
    discardFragment()
  let
    visibilityUv = vec2(
      (fragmentPosition.x + visibilityOffset) * visibilityScale,
      (fragmentPosition.z + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
    litColor = envShadeTwoSided(
      texel.xyz * fragBrightness, fragmentNormal, sampleSunShadow(shadowPos)) *
      ambientVisibility(fragmentPosition)
    gray = dot(litColor, vec3(0.30, 0.59, 0.11)) * 0.32
  fragColor = vec4(
    litColor.x * visibility + gray * (1.0 - visibility),
    litColor.y * visibility + gray * (1.0 - visibility),
    litColor.z * visibility + gray * (1.0 - visibility),
    1.0
  )

proc texturedPropVert(
    gl_Position: var Vec4,
    vertPos: Vec3,
    vertUv: Vec3,
    normal: Vec3,
    vertTint: Vec3,
    fragUv: var Vec3,
    fragmentNormal: var Vec3,
    fragmentPosition: var Vec3,
    shadowPos: var Vec3,
    fragTint: var Vec3
) =
  ## Emits world-space lighting inputs and a tint for textured props.
  let
    worldPosition: Vec3 =
      (propModel * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)).xyz
    worldNormal: Vec3 = normalize(
      (propModel * vec4(normal.x, normal.y, normal.z, 0.0)).xyz)
  gl_Position = mvp * vec4(vertPos.x, vertPos.y, vertPos.z, 1.0)
  shadowPos = worldPosition + worldNormal * 0.08
  fragUv = vertUv
  fragmentNormal = worldNormal
  fragmentPosition = worldPosition
  fragTint = vertTint

proc texturedPropFrag(
    fragColor: var Vec4,
    fragUv: Vec3,
    fragmentNormal,
    fragmentPosition: Vec3,
    shadowPos: Vec3,
    fragTint: Vec3
) =
  ## The tree cutout shading with the instance tint folded into the paint.
  let texel = texture(treeTextures, fragUv)
  if texel.w < treeAlphaCutoff:
    discardFragment()
  let
    visibilityUv = vec2(
      (fragmentPosition.x + visibilityOffset) * visibilityScale,
      (fragmentPosition.z + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
    paint = vec3(
      texel.x * fragTint.x, texel.y * fragTint.y, texel.z * fragTint.z)
    litColor = envShadeTwoSided(
      paint, fragmentNormal, sampleSunShadow(shadowPos)) *
      ambientVisibility(fragmentPosition)
    gray = dot(litColor, vec3(0.30, 0.59, 0.11)) * 0.32
  fragColor = vec4(
    litColor.x * visibility + gray * (1.0 - visibility),
    litColor.y * visibility + gray * (1.0 - visibility),
    litColor.z * visibility + gray * (1.0 - visibility),
    1.0
  )

proc texturedInstantFrag(
    fragColor: var Vec4,
    fragUv: Vec3,
    fragmentNormal,
    fragmentPosition: Vec3,
    shadowPos: Vec3,
    fragTint: Vec3
) =
  ## The tree cutout shading with the standalone prop tint folded in, for
  ## textured props drawn per frame rather than baked.
  let texel = texture(treeTextures, fragUv)
  if texel.w < treeAlphaCutoff:
    discardFragment()
  let
    visibilityUv = vec2(
      (fragmentPosition.x + visibilityOffset) * visibilityScale,
      (fragmentPosition.z + visibilityOffset) * visibilityScale
    )
    visibility = smoothstep(
      0.05,
      0.95,
      texture(visibilityTex, visibilityUv).x
    )
    paint = vec3(
      texel.x * propTint.x * fragTint.x,
      texel.y * propTint.y * fragTint.y,
      texel.z * propTint.z * fragTint.z)
    litColor = envShadeTwoSided(
      paint, fragmentNormal, sampleSunShadow(shadowPos)) *
      ambientVisibility(fragmentPosition)
    gray = dot(litColor, vec3(0.30, 0.59, 0.11)) * 0.32
  fragColor = vec4(
    litColor.x * visibility + gray * (1.0 - visibility),
    litColor.y * visibility + gray * (1.0 - visibility),
    litColor.z * visibility + gray * (1.0 - visibility),
    1.0
  )
