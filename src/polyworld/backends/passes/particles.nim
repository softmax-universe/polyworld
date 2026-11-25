proc closeParticles*(system: var ParticleSystem) =
  ## Releases the particle program and sight mask and clears simulation state.
  if system.gpu != nil:
    destroy(system.gpu.program)
    destroy(system.gpu.sightTexture)
  system = ParticleSystem()

proc initParticleSystem*(): ParticleSystem =
  ## Creates the procedural instanced-particle program and default sight mask.
  try:
    result.gpu = ParticleGpu()
    result.gpu.program = newProgram(
      nativeStage(gameParticleVertex, shaderVertex),
      nativeStage(gameParticleFragment, shaderFragment)
    )
    result.nextSeed = 1
    let white = newImage(1, 1)
    white.fill(rgba(255, 255, 255, 255))
    result.gpu.sightTexture = newTexture(white, linear = false)
  except CatchableError as error:
    result.closeParticles()
    raise newException(ParticleError, "Unable to create GPU particles: " &
      error.msg)

proc uploadParticleEffect(
    system: ParticleSystem,
    effect: ParticleEffect,
    viewProjection: Mat4,
    cameraRight,
    cameraUp,
    cameraForward: Vec3
) =
  ## Uploads one effect's deterministic simulation and camera parameters.
  let program = system.gpu.program
  setUniform(program, "uParticleViewProjection", viewProjection)
  setUniform(program, "uParticleCameraRight", cameraRight)
  setUniform(program, "uParticleCameraUp", cameraUp)
  setUniform(program, "uParticleCameraForward", cameraForward)
  setUniform(program, "uParticleTime", system.time)
  setUniform(program, "uParticleStartTime", effect.startTime)
  setUniform(program, "uParticleTravelTime", effect.travelTime)
  setUniform(program, "uParticleSeed", (effect.seed mod 65_521'u32).float32)
  setUniform(program, "uParticleEffectKind", effect.kind.ord.int32)
  setUniform(program, "uParticleOrigin", effect.origin)
  setUniform(program, "uParticleTarget", effect.target)

proc uploadParticleSight(system: ParticleSystem, visibility: openArray[uint8],
    width: int) =
  ## Replaces the nearest-filtered sight texture used for fragment clipping.
  let image = newImage(width, width)
  for index, value in visibility:
    image.data[index] = rgbx(value, value, value, 255)
  if system.gpu.sightTexture.width != width or
      system.gpu.sightTexture.height != width:
    destroy(system.gpu.sightTexture)
    system.gpu.sightTexture = newTexture(image, linear = false)
  else:
    updateTexture(system.gpu.sightTexture, image)

proc drawParticles*(
    system: ParticleSystem,
    viewProjection: Mat4,
    cameraRight,
    cameraUp,
    cameraForward: Vec3,
    visibility: openArray[uint8] = [],
    visibilityWidth = 0,
    visibilityOrigin = vec2(0),
    visibilityPadding = 0,
    viewer = -1'i32,
    clipToSight = false
) =
  ## Draws semantic particles with instancing, scene depth, and sight clipping.
  if system.gpu == nil or system.gpu.program == nil or system.effects.len == 0:
    return
  let clip = clipToSight and visibility.len > 0
  if clip and (visibilityWidth <= 0 or
      visibility.len != visibilityWidth * visibilityWidth):
    return
  let program = system.gpu.program
  if clip:
    system.uploadParticleSight(visibility, visibilityWidth)
    setUniform(program, "uParticleSightOrigin", visibilityOrigin)
    setUniform(program, "uParticleSightWidth", visibilityWidth.float32)
  bindTexture(program, "uParticleSight", system.gpu.sightTexture)
  for effect in system.effects:
    if effect.startTime > system.time:
      continue
    let owned = viewer >= 0 and effect.owner == viewer
    setUniform(program, "uParticleClipSight", int32(clip and not owned))
    if not clip and not owned and not particlePathVisible(
      effect.origin,
      effect.target,
      visibility,
      visibilityWidth,
      visibilityOrigin,
      visibilityPadding
    ):
      continue
    let blend =
      if effect.kind in {
        ArrowWake, LeafBolt, LeafBurst, BloomSeed, BloomPetals, RootLeaves,
        IceShard, FrostBurst, IceShatter, BlizzardShards, SnowSquall
      }:
        AlphaBlend
      else:
        Additive
    system.uploadParticleEffect(
      effect,
      viewProjection,
      cameraRight,
      cameraUp,
      cameraForward
    )
    draw(
      program,
      nil,
      4,
      DrawState(depthTest: true, blend: blend, primitive: TriangleStrip),
      instanceCount = effect.kind.effectParticleCount
    )
