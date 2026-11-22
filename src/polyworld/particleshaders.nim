## Shady shaders for bounded one-shot game particle effects.

import
  shady, vmath

type ParticleEffectKind* = enum
  CombatSparks,
  MagicBolt,
  MagicBurst,
  Fireball,
  FireBurst,
  ArrowWake,
  HealingAura,
  ManaAura,
  PoisonAura,
  PortalBurst,
  PoisonCapsule,
  PoisonBurst,
  LeafBolt,
  LeafBurst,
  BladeFlame,
    ## Flames licking off the straight run from origin to target.
  FireWave,
    ## A bounded forward flame front spanning a ninety-degree cone.
  HeatEmbers,
    ## Embers rising off a disc round the origin, as wide as the target is far.
  BloomSeed, BloomPetals, RootLeaves, SolarOrb, SolarFlames,
  MendingAura,
    ## A HealingAura held close round one body, under half as wide.
  IceShard,
    ## A thrown shard of ice that sheds frost as it flies.
  FrostBurst,
    ## Ice splinters and a puff of cold where a shard breaks.
  IceShatter,
    ## A block of ice bursting: chunks flung over a disc as wide as the
    ## target is far, and a ring of frost rolling out over it.
  BlizzardShards,
    ## One wave of ice shards falling out of the sky over a disc as wide as
    ## the target is far, landing as the travel time runs out.
  SnowSquall,
    ## Snow whirling over a disc as wide as the target is far, for as long
    ## as the travel time.
  LightningBolt
    ## A forked bolt from the origin down to the target, flickering, with a
    ## flash and sparks where it strikes.

var
  uParticleViewProjection*: Uniform[Mat4]
  uParticleCameraRight*: Uniform[Vec3]
  uParticleCameraUp*: Uniform[Vec3]
  uParticleCameraForward*: Uniform[Vec3]
  uParticleTime*: Uniform[float32]
  uParticleStartTime*: Uniform[float32]
  uParticleTravelTime*: Uniform[float32]
  uParticleSeed*: Uniform[float32]
  uParticleEffectKind*: Uniform[int32]
  uParticleOrigin*: Uniform[Vec3]
  uParticleTarget*: Uniform[Vec3]
  uParticleSight*: Uniform[Sampler2D]
  uParticleSightOrigin*: Uniform[Vec2]
  uParticleSightWidth*: Uniform[float32]
  uParticleClipSight*: Uniform[int32]

func particleHash(value: float32): float32 =
  ## Produces a repeatable zero-to-one value for one particle.
  var fraction = fract(value * 0.1031'f)
  fraction *= fraction + 33.33'f
  fraction *= fraction + fraction
  result = fract(fraction)

proc particleRandom(state: var float32): float32 =
  ## Advances one shader-local random stream.
  state += 1.0'f
  result = particleHash(state)

proc particleDirection(state: var float32): Vec3 =
  ## Produces one uniformly distributed unit vector.
  let
    y = particleRandom(state) * 2.0'f - 1.0'f
    angle = particleRandom(state) * 6.28318530718'f
    radius = sqrt(max(0.0'f, 1.0'f - y * y))
  result = vec3(cos(angle) * radius, y, sin(angle) * radius)

func safeParticleDirection(value: Vec3): Vec3 =
  ## Normalizes a vector with a stable upward fallback.
  let valueLength = length(value)
  if valueLength < 0.0001'f:
    result = vec3(0.0'f, 1.0'f, 0.0'f)
  else:
    result = value / valueLength

const
  BoltKnees = 11.0'f
  BoltCoreEnd = 66.0'f
  BoltFlashEnd = 69.0'f
  BoltSparkEnd = 88.0'f
  BoltRingEnd = 120.0'f
  BoltForkEnd = 168.0'f
  LightningParticleCount* = 180

func cloudNoise(point: Vec2): float32 =
  ## Smooth value noise for the soft lobes in a cloud puff.
  let
    cell: Vec2 = floor(point)
    offset: Vec2 = fract(point)
    weight: Vec2 = offset * offset * (vec2(3.0'f) - offset * 2.0'f)
    seed = cell.x * 13.73'f + cell.y * 47.11'f
    bottom = mix(particleHash(seed), particleHash(seed + 13.73'f), weight.x)
    top = mix(particleHash(seed + 47.11'f), particleHash(seed + 60.84'f), weight.x)
  result = mix(bottom, top, weight.y)

func boltKnee(origin, target: Vec3, knee, flash, seed: float32): Vec3 =
  ## Stable bends with a smaller, fast-moving electrical jitter.
  let
    swing = clamp(min(knee, BoltKnees - knee), 0.0'f, 1.0'f) *
      min(length(target - origin) * 0.28'f, 0.85'f)
    a = particleHash(seed * 0.37'f + knee * 7.13'f) - 0.5'f
    b = particleHash(seed * 0.53'f + knee * 5.17'f + 11.0'f) - 0.5'f
    jitter = particleHash(knee * 9.17'f + flash * 3.71'f + seed) - 0.5'f
    arch = if abs(target.y - origin.y) < 0.3'f:
      sin(knee / BoltKnees * 3.14159265'f) * min(length(target - origin) * 0.25'f, 0.85'f)
      else: 0.0'f
  result = mix(origin, target, knee / BoltKnees) +
    vec3((a + jitter * 0.44'f) * swing, arch, (b - jitter * 0.34'f) * swing)

proc evaluateParticle(
    particleId: float32,
    position: var Vec3,
    velocity: var Vec3,
    size: var float32,
    color: var Vec4,
    life: var float32,
    alive: var float32
) =
  ## Evaluates one semantic particle entirely on the GPU.
  position = uParticleOrigin
  velocity = vec3(0.0'f)
  size = 0.0'f
  color = vec4(0.0'f)
  life = 0.0'f
  alive = 0.0'f
  let elapsed: float32 = uParticleTime - uParticleStartTime
  if elapsed < 0.0'f:
    return
  var state: float32 = particleId * 17.0'f +
    uParticleSeed * 0.123'f

  if uParticleEffectKind == LeafBolt.ord.int32 or
    uParticleEffectKind == LeafBurst.ord.int32:
      let
        phase = particleRandom(state) * 6.2831853'f
        tint = particleRandom(state)
      if uParticleEffectKind == LeafBolt.ord.int32:
        let travel = max(uParticleTravelTime, 0.05'f)
        if elapsed > travel:
          return
        let t = elapsed / travel
        position = mix(uParticleOrigin, uParticleTarget, t) + vec3(
          cos(phase + elapsed * 5.0'f) * 0.16'f,
          sin(phase * 2.0'f + elapsed * 6.0'f) * 0.12'f,
          sin(phase + elapsed * 5.0'f) * 0.16'f
        )
        color = vec4(0.12'f + tint * 0.12'f, 0.35'f + tint * 0.25'f, 0.06'f, 1.0'f)
      else:
        if elapsed > 0.6'f:
          return
        position = uParticleOrigin + vec3(
          cos(phase) * elapsed * 1.2'f,
          elapsed * 0.6'f - elapsed * elapsed * 2.0'f,
          sin(phase) * elapsed * 1.2'f
        )
        color = vec4(0.15'f, 0.45'f + tint * 0.15'f, 0.06'f,
          1.0'f - elapsed / 0.6'f)
      size = 0.13'f + tint * 0.045'f
      life = phase + elapsed * 4.0'f
      alive = 1.0'f
      return

  if uParticleEffectKind == CombatSparks.ord.int32:
    let
      birth = particleId * 0.0025'f
      age = elapsed - birth
      lifetime = 0.22'f + particleRandom(state) * 0.18'f
    if age < 0.0'f or age >= lifetime:
      return
    var direction = particleDirection(state)
    direction.y = abs(direction.y) * 0.72'f + 0.28'f
    direction = safeParticleDirection(direction)
    let speed = 0.8'f + particleRandom(state) * 1.2'f
    velocity = direction * speed + vec3(0.0'f, -5.4'f * age, 0.0'f)
    position = uParticleOrigin + direction * speed * age +
      vec3(0.0'f, -2.7'f * age * age, 0.0'f)
    life = age / lifetime
    size = 0.018'f * (0.75'f + particleRandom(state) * 0.7'f)
    color = mix(
      vec4(1.0'f, 0.96'f, 0.48'f, 1.0'f),
      vec4(1.0'f, 0.16'f, 0.01'f, 0.0'f),
      life
    )
    alive = 1.0'f
    return

  if uParticleEffectKind == PortalBurst.ord.int32 and particleId < 1.0'f:
    if elapsed < 0.0'f or elapsed >= 0.4'f:
      return
    life = elapsed / 0.4'f
    position = uParticleOrigin
    size = mix(1.5'f, 2.8'f, life)
    color = vec4(0.85'f, 0.8'f, 1.0'f, (1.0'f - life) * 0.9'f)
    alive = 1.0'f
    return

  if uParticleEffectKind == MagicBurst.ord.int32 or
    uParticleEffectKind == PortalBurst.ord.int32 or
    uParticleEffectKind == PoisonBurst.ord.int32:
    let
      birth = particleId * 0.0035'f
      age = elapsed - birth
      lifetime = 0.72'f + particleRandom(state) * 0.38'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      direction = particleDirection(state)
      progress = age / lifetime
      radius = sin(progress * 3.14159265359'f) *
        (0.45'f + particleRandom(state) * 0.85'f)
    position = uParticleOrigin + direction * radius +
      vec3(0.0'f, age * 0.38'f, 0.0'f)
    velocity = direction * 1.8'f + vec3(0.0'f, 0.38'f, 0.0'f)
    life = progress
    size = mix(0.095'f, 0.025'f, progress) *
      (0.72'f + particleRandom(state) * 0.65'f)
    color = mix(
      vec4(0.26'f, 0.82'f, 1.0'f, 0.95'f),
      vec4(0.85'f, 0.18'f, 1.0'f, 0.0'f),
      progress
    )
    if uParticleEffectKind == PoisonBurst.ord.int32:
      color = mix(
        vec4(0.72'f, 0.24'f, 1.0'f, 0.95'f),
        vec4(0.18'f, 0.03'f, 0.28'f, 0.0'f),
        progress
      )
    alive = 1.0'f
    return

  if uParticleEffectKind == FireBurst.ord.int32:
    let
      birth = particleId * 0.002'f
      age = elapsed - birth
      lifetime = 0.5'f + particleRandom(state) * 0.35'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      direction = particleDirection(state)
      speed = 1.8'f + particleRandom(state) * 3.2'f
      progress = age / lifetime
    position = uParticleOrigin + direction * speed * age +
      vec3(0.0'f, 0.7'f * age, 0.0'f)
    velocity = direction * speed + vec3(0.0'f, 0.7'f, 0.0'f)
    life = progress
    size = mix(0.16'f, 0.045'f, progress) *
      (0.72'f + particleRandom(state) * 0.62'f)
    color = mix(
      vec4(1.0'f, 0.86'f, 0.18'f, 1.0'f),
      vec4(1.0'f, 0.08'f, 0.01'f, 0.0'f),
      progress
    )
    alive = 1.0'f
    return

  if uParticleEffectKind == BloomSeed.ord.int32 or
      uParticleEffectKind == BloomPetals.ord.int32 or
      uParticleEffectKind == RootLeaves.ord.int32:
    let
      seedFlight = uParticleEffectKind == BloomSeed.ord.int32
      roots = uParticleEffectKind == RootLeaves.ord.int32
      travel = max(uParticleTravelTime, 0.05'f)
      birth = particleId * 0.006'f
      age = elapsed - birth
      lifetime = 0.85'f + particleRandom(state) * 0.5'f
    if age < 0.0'f or (not seedFlight and age >= lifetime) or
        (seedFlight and elapsed > travel): return
    let
      progress = clamp(age / lifetime, 0.0'f, 1.0'f)
      turn = particleId * 2.39996'f + age * 2.4'f
      radius = (0.18'f + particleRandom(state) * 0.7'f) *
        sin(progress * 3.14159265'f)
      drift = vec3(cos(turn) * radius, 0.12'f + age * 0.85'f, sin(turn) * radius)
    position = uParticleOrigin + drift
    if roots:
      position = uParticleOrigin + vec3(cos(turn) * radius * 1.7'f,
        0.12'f + sin(progress * 3.14159265'f) * 0.7'f, sin(turn) * radius * 1.7'f)
    if seedFlight:
      let t = clamp(elapsed / travel, 0.0'f, 1.0'f)
      position = mix(uParticleOrigin, uParticleTarget, t) +
        vec3(cos(turn) * 0.13'f, sin(t * 3.14159265'f) * 0.65'f +
          sin(turn) * 0.12'f, sin(turn) * 0.13'f)
    velocity = vec3(cos(turn), 0.7'f, sin(turn))
    life = progress
    size = (0.065'f + particleRandom(state) * 0.045'f) *
      (1.0'f - progress * 0.45'f)
    let fade = sin(progress * 3.14159265'f) * 0.82'f
    color = vec4(1.0'f, 0.75'f, 0.82'f, fade)
    if particleRandom(state) < 0.3'f:
      color = vec4(0.3'f, 0.78'f, 0.20'f, fade)
    if roots:
      color = vec4(0.35'f, 0.85'f, 0.24'f, fade)
      size *= 0.7'f
    if seedFlight: color = vec4(0.72'f, 1.0'f, 0.44'f, 0.65'f)
    if not seedFlight and not roots and particleId < 8.0'f:
      # The first petals open into a flower beneath the healed ally;
      # the rest lift away. Both travel with the same actor anchor.
      let turn = particleId * 6.2831853'f / 8.0'f
      let grow = clamp(age / 0.18'f, 0.0'f, 1.0'f)
      let opening = 1.0'f - (1.0'f - grow) * (1.0'f - grow)
      position = uParticleOrigin + vec3(cos(turn) * 0.28'f * opening,
        0.11'f, sin(turn) * 0.28'f * opening)
      size = 0.12'f * opening
      color = vec4(1.0'f, 0.74'f, 0.82'f,
        0.62'f * clamp((lifetime - age) / 0.35'f, 0.0'f, 1.0'f))
    alive = 1.0'f
    return

  if uParticleEffectKind == SolarOrb.ord.int32:
    let
      travel = max(uParticleTravelTime, 0.05'f)
      progress = clamp(elapsed / travel, 0.0'f, 1.0'f)
      turn = particleId * 2.39996'f + elapsed * 3.0'f
      age = elapsed - particleRandom(state) * 0.055'f
    if age < 0.0'f or elapsed > travel: return
    let
      t = max(0.0'f, progress - particleRandom(state) * 0.38'f)
      radius = 0.10'f + particleRandom(state) * 0.12'f
    position = mix(uParticleOrigin, uParticleTarget, t) +
      vec3(cos(turn) * radius, sin(t * 3.14159265'f) * 1.1'f +
        sin(turn) * radius, sin(turn) * radius)
    size = 0.055'f + particleRandom(state) * 0.045'f
    color = vec4(1.0'f, 0.52'f, 0.045'f, 0.24'f)
    if particleId < 2.0'f:
      position = mix(uParticleOrigin, uParticleTarget, progress) +
        vec3(0.0'f, sin(progress * 3.14159265'f) * 1.1'f, 0.0'f)
      size = 0.18'f + particleId * 0.14'f
      color = vec4(1.0'f, 0.84'f, 0.32'f, 0.85'f - particleId * 0.55'f)
    # The sun's rays orbit a distinct core, rather than reading as a
    # plain golden missile. Camera-plane rays stay legible at board scale.
    if particleId >= 2.0'f and particleId < 14.0'f:
      let corona = (particleId - 2.0'f) * 6.2831853'f / 12.0'f + elapsed * 2.5'f
      position = mix(uParticleOrigin, uParticleTarget, progress) +
        vec3(0.0'f, sin(progress * 3.14159265'f) * 1.1'f, 0.0'f) +
        (uParticleCameraRight * cos(corona) + uParticleCameraUp * sin(corona)) * 0.29'f
      size = 0.027'f
      color = vec4(1.0'f, 0.68'f, 0.16'f, 0.8'f)
    life = progress
    velocity = vec3(cos(turn), 0.5'f, sin(turn))
    alive = 1.0'f
    return

  if uParticleEffectKind == SolarFlames.ord.int32:
    # Each flame is born across a fixed footprint and moves upward only.
    # Staggered births sustain a bed of fire instead of a radial blast.
    let
      birth = particleId * 0.007'f
      age = elapsed - birth
      lifetime = 0.48'f + particleRandom(state) * 0.36'f
    if age < 0.0'f or age >= lifetime: return
    let
      progress = age / lifetime
      angle = particleRandom(state) * 6.2831853'f
      radius = sqrt(particleRandom(state)) * max(length(uParticleTarget - uParticleOrigin), 0.25'f)
      width = 0.08'f + particleRandom(state) * 0.06'f
      fade = sin(progress * 3.14159265'f)
      sway = sin(age * 10.0'f + angle) * 0.045'f
    size = width * (1.0'f - progress * 0.3'f)
    position = uParticleOrigin + vec3(cos(angle) * radius + sway,
      size * 4.6'f + age * 0.85'f, sin(angle) * radius)
    velocity = vec3(0.0'f, 0.85'f, 0.0'f)
    color = mix(vec4(1.0'f, 0.65'f, 0.075'f, fade * 0.30'f),
      vec4(0.95'f, 0.09'f, 0.008'f, fade * 0.20'f), progress)
    life = progress
    alive = 1.0'f
    return

  if uParticleEffectKind == HealingAura.ord.int32 or
      uParticleEffectKind == ManaAura.ord.int32 or
      uParticleEffectKind == PoisonAura.ord.int32 or
      uParticleEffectKind == MendingAura.ord.int32:
    let
      birth = particleId * 0.008'f
      age = elapsed - birth
      lifetime = 0.9'f + particleRandom(state) * 0.45'f
    if age < 0.0'f or age >= lifetime:
      return
    var spread = 1.0'f
    if uParticleEffectKind == MendingAura.ord.int32:
      spread = 0.45'f
    let
      progress = age / lifetime
      angle = particleRandom(state) * 6.28318530718'f + age * 4.2'f
      radius = (0.28'f + particleRandom(state) * 0.62'f) * spread
    position = uParticleOrigin + vec3(
      cos(angle) * radius,
      particleRandom(state) * 0.35'f + age * 1.25'f,
      sin(angle) * radius
    )
    velocity = vec3(
      -sin(angle) * radius * 4.2'f,
      1.25'f,
      cos(angle) * radius * 4.2'f
    )
    life = progress
    size = mix(0.075'f, 0.025'f, progress) *
      (0.75'f + particleRandom(state) * 0.55'f)
    color = mix(
      vec4(0.42'f, 1.0'f, 0.48'f, 0.95'f),
      vec4(1.0'f, 0.88'f, 0.24'f, 0.0'f),
      progress
    )
    if uParticleEffectKind == ManaAura.ord.int32:
      color = mix(
        vec4(0.25'f, 0.65'f, 1.0'f, 0.95'f),
        vec4(0.75'f, 0.9'f, 1.0'f, 0.0'f), progress
      )
    elif uParticleEffectKind == PoisonAura.ord.int32:
      color = mix(
        vec4(0.65'f, 0.25'f, 0.95'f, 0.95'f),
        vec4(0.18'f, 0.03'f, 0.28'f, 0.0'f), progress
      )
    alive = 1.0'f
    return

  if uParticleEffectKind == IceShard.ord.int32:
    let
      travel = max(uParticleTravelTime, 0.05'f)
      path = uParticleTarget - uParticleOrigin
      forward = safeParticleDirection(path)
    if particleId < 3.0'f:
      # The shard itself: a bright core with two dimmer lengths behind it.
      if elapsed > travel:
        return
      let t = clamp(elapsed / travel, 0.0'f, 1.0'f)
      position = mix(uParticleOrigin, uParticleTarget, t) -
        forward * particleId * 0.09'f
      velocity = forward * max(length(path) / travel, 4.0'f)
      size = 0.088'f - particleId * 0.024'f
      color = vec4(0.45'f, 0.80'f, 1.0'f, 0.84'f - particleId * 0.28'f)
      life = t
      alive = 1.0'f
      return
    let
      birth = (particleId - 3.0'f) / 25.0'f * travel
      age = elapsed - birth
      lifetime = 0.3'f + particleRandom(state) * 0.25'f
    if age < 0.0'f or age >= lifetime or birth > travel:
      return
    life = age / lifetime
    position = mix(uParticleOrigin, uParticleTarget,
      clamp(birth / travel, 0.0'f, 1.0'f)) +
      particleDirection(state) * 0.05'f + vec3(0.0'f, -0.35'f * age, 0.0'f)
    velocity = vec3(0.0'f, -0.35'f, 0.0'f)
    size = mix(0.045'f, 0.012'f, life)
    color = mix(vec4(0.7'f, 0.92'f, 1.0'f, 0.8'f),
      vec4(0.4'f, 0.6'f, 1.0'f, 0.0'f), life)
    alive = 1.0'f
    return

  if uParticleEffectKind == FrostBurst.ord.int32:
    let
      birth = particleId * 0.002'f
      age = elapsed - birth
      lifetime = 0.45'f + particleRandom(state) * 0.35'f
    if age < 0.0'f or age >= lifetime:
      return
    var direction = particleDirection(state)
    direction.y = abs(direction.y) * 0.8'f + 0.1'f
    direction = safeParticleDirection(direction)
    let
      speed = 1.2'f + particleRandom(state) * 2.2'f
      progress = age / lifetime
    life = progress
    if particleId < 6.0'f:
      # A puff of cold air where the ice broke.
      position = uParticleOrigin + direction * 0.15'f +
        vec3(0.0'f, age * 0.3'f, 0.0'f)
      size = mix(0.22'f, 0.42'f, progress)
      color = vec4(0.75'f, 0.9'f, 1.0'f, 0.22'f * (1.0'f - progress))
      alive = 1.0'f
      return
    position = uParticleOrigin + direction * speed * age +
      vec3(0.0'f, -3.2'f * age * age, 0.0'f)
    velocity = direction * speed + vec3(0.0'f, -6.4'f * age, 0.0'f)
    size = mix(0.065'f, 0.018'f, progress) *
      (0.7'f + particleRandom(state) * 0.6'f)
    color = mix(vec4(0.92'f, 0.98'f, 1.0'f, 0.95'f),
      vec4(0.35'f, 0.65'f, 1.0'f, 0.0'f), progress)
    alive = 1.0'f
    return

  if uParticleEffectKind == IceShatter.ord.int32:
    let reach = max(length(uParticleTarget - uParticleOrigin), 0.5'f)
    if particleId < 48.0'f:
      # Chunks of the block flung out over the disc, falling as they go.
      let
        age = elapsed - particleRandom(state) * 0.03'f
        lifetime = 0.55'f + particleRandom(state) * 0.35'f
      if age < 0.0'f or age >= lifetime:
        return
      let
        angle = particleRandom(state) * 6.2831853'f
        outward = vec3(cos(angle), 0.0'f, sin(angle))
        distance = reach * (0.3'f + particleRandom(state) * 0.7'f)
        height = 0.25'f + particleRandom(state) * 0.6'f
        t = age / lifetime
        climb = 1.4'f
      position = uParticleOrigin + outward * distance * t +
        vec3(0.0'f, height + climb * t - (height + climb) * t * t, 0.0'f)
      velocity = outward * distance / lifetime +
        vec3(0.0'f, (climb - 2.0'f * (height + climb) * t) / lifetime, 0.0'f)
      size = (0.06'f + particleRandom(state) * 0.08'f) * (1.0'f - 0.3'f * t)
      color = vec4(0.84'f, 0.96'f, 1.0'f,
        0.9'f * (1.0'f - smoothstep(0.75'f, 1.0'f, t)))
      life = t
      alive = 1.0'f
      return
    # Frost rolling out over the whole disc.
    let
      age = elapsed - particleRandom(state) * 0.05'f
      lifetime = 0.9'f + particleRandom(state) * 0.3'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      progress = age / lifetime
      angle = (particleId - 48.0'f) / 42.0'f * 6.2831853'f +
        particleRandom(state) * 0.2'f
      radius = reach * clamp(age / 0.35'f, 0.0'f, 1.0'f) *
        (0.8'f + particleRandom(state) * 0.2'f)
    position = uParticleOrigin + vec3(cos(angle) * radius,
      0.12'f + particleRandom(state) * 0.25'f + age * 0.2'f,
      sin(angle) * radius)
    size = 0.22'f + particleRandom(state) * 0.15'f
    color = vec4(0.75'f, 0.9'f, 1.0'f, 0.24'f * (1.0'f - progress))
    life = progress
    alive = 1.0'f
    return

  if uParticleEffectKind == BlizzardShards.ord.int32:
    let
      travel = max(uParticleTravelTime, 0.05'f)
      reach = length(uParticleTarget - uParticleOrigin)
      birth = particleRandom(state) * min(0.08'f, travel * 0.4'f)
      age = elapsed - birth
      fallTime = travel - birth
      angle = particleRandom(state) * 6.2831853'f
      radius = sqrt(particleRandom(state)) * reach
      landing = uParticleOrigin +
        vec3(cos(angle) * radius, 0.05'f, sin(angle) * radius)
      fall = vec3(1.2'f, 5.0'f, 0.5'f)
      tint = particleRandom(state)
    if age < 0.0'f:
      return
    if age < fallTime:
      let t = age / fallTime
      position = landing + fall * (1.0'f - t)
      velocity = -fall / fallTime
      size = 0.063'f + tint * 0.047'f
      color = vec4(0.36'f + tint * 0.43'f, 0.73'f + tint * 0.22'f, 1.0'f, 0.96'f)
      life = t
      alive = 1.0'f
      return
    let splash = age - fallTime
    if splash >= 0.25'f:
      return
    life = splash / 0.25'f
    position = landing + vec3(0.0'f, splash * 0.4'f, 0.0'f)
    size = mix(0.07'f, 0.18'f, life)
    color = vec4(0.8'f, 0.93'f, 1.0'f, 0.55'f * (1.0'f - life))
    alive = 1.0'f
    return

  if uParticleEffectKind == SnowSquall.ord.int32:
    # Irregular puffs drift with the wind. Snow falls beneath them.
    if particleId < 36.0'f:
      let
        duration = max(uParticleTravelTime, 0.05'f)
        fade = smoothstep(0.0'f, 0.23'f, elapsed) *
          (1.0'f - smoothstep(duration - 0.32'f, duration, elapsed))
        reach = length(uParticleTarget - uParticleOrigin)
        radius = sqrt(particleId / 36.0'f) * reach * 0.76'f
        turn = particleId * 2.3999632'f
        crest = particleRandom(state)
        drift = (elapsed - duration * 0.5'f) * (0.27'f + crest * 0.15'f)
      if elapsed >= duration: return
      position = uParticleOrigin + vec3(cos(turn) * radius + drift,
        3.02'f + crest * 0.72'f + sin(elapsed * 2.1'f + turn) * 0.12'f,
        sin(turn) * radius - drift * 0.37'f)
      velocity = vec3(0.38'f, 0.0'f, -0.14'f)
      size = 0.34'f + crest * 0.25'f
      color = vec4(0.62'f, 0.76'f, 0.92'f, 0.37'f * fade)
      life = elapsed + particleId * 0.47'f
      alive = 1.0'f
      return
    let
      duration = max(uParticleTravelTime, 0.05'f)
      reach = length(uParticleTarget - uParticleOrigin)
      birth = particleRandom(state) * max(duration - 1.2'f, 0.1'f)
      age = elapsed - birth
      lifetime = 0.8'f + particleRandom(state) * 0.4'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      progress = age / lifetime
      radius = (0.08'f + sqrt(particleRandom(state)) * 0.92'f) * reach
      angle = particleRandom(state) * 6.2831853'f
      height = 0.4'f + particleRandom(state) * 2.4'f
    position = uParticleOrigin + vec3(cos(angle) * radius + age * 0.43'f,
      height - age * 0.9'f, sin(angle) * radius - age * 0.18'f)
    velocity = vec3(0.43'f, -0.9'f, -0.18'f)
    size = 0.03'f + particleRandom(state) * 0.03'f
    color = vec4(0.92'f, 0.97'f, 1.0'f,
      0.75'f * sin(progress * 3.14159265'f))
    life = progress
    alive = 1.0'f
    return

  if uParticleEffectKind == LightningBolt.ord.int32:
    if elapsed >= 0.4'f:
      return
    let
      flashes = elapsed * 18.0'f
      flash = flashes - fract(flashes)
      fade = 1.0'f - smoothstep(0.12'f, 0.4'f, elapsed)
    if particleId >= BoltForkEnd:
      let
        knee = particleId - BoltForkEnd
        delay = particleRandom(state) * 0.13'f
        shimmer = sin(clamp((elapsed - delay) / 0.14'f, 0.0'f, 1.0'f) * 3.14159265'f)
      position = boltKnee(uParticleOrigin, uParticleTarget, knee, flash, uParticleSeed)
      size = 0.075'f + particleRandom(state) * 0.055'f
      color = vec4(0.68'f, 0.86'f, 1.0'f, 0.45'f * shimmer * fade)
      life = elapsed / 0.4'f
      alive = 1.0'f
      return
    if particleId >= BoltRingEnd:
      # Three tapered forks branch off the main channel.
      let
        branchIndex = particleId - BoltRingEnd
        fork = floor(branchIndex / 16.0'f)
        along = (branchIndex - fork * 16.0'f + 0.5'f) / 16.0'f * 4.0'f
        knee = floor(along)
        root = boltKnee(uParticleOrigin, uParticleTarget, 2.0'f + fork * 3.0'f,
          flash, uParticleSeed)
        side = if fork == 1.0'f: 1.0'f else: -1.0'f
        tip: Vec3 = mix(root, uParticleTarget, 0.62'f) +
          uParticleCameraRight * (side * (0.58'f + fork * 0.19'f))
        top = boltKnee(root, tip, knee * BoltKnees / 4.0'f, flash, uParticleSeed + 4.0'f)
        bottom = boltKnee(root, tip, (knee + 1.0'f) * BoltKnees / 4.0'f,
          flash, uParticleSeed + 4.0'f)
      position = mix(top, bottom, fract(along))
      velocity = (bottom - top) * 8.0'f
      size = mix(0.027'f, 0.014'f, along / 4.0'f)
      color = vec4(0.45'f, 0.65'f, 1.0'f, 0.64'f * fade * (1.0'f - along * 0.15'f))
      life = elapsed / 0.4'f
      alive = 1.0'f
      return
    if particleId >= BoltSparkEnd:
      # Each downward strike leaves an expanding electric ring at its foot.
      if abs(uParticleTarget.y - uParticleOrigin.y) < 0.3'f:
        return
      let
        t = elapsed / 0.4'f
        turn = (particleId - BoltSparkEnd) * 6.2831853'f / 32.0'f
        radius = 0.20'f + 0.54'f * sqrt(t)
      position = uParticleTarget + vec3(cos(turn) * radius, 0.06'f,
        sin(turn) * radius)
      velocity = vec3(-sin(turn), 0.0'f, cos(turn))
      size = 0.040'f
      color = vec4(0.36'f, 0.68'f, 1.0'f, 0.85'f * fade)
      life = t
      alive = 1.0'f
      return
    if particleId < BoltCoreEnd:
      # The bolt: dashes laid end to end down the jagged main channel.
      let
        along = (particleId + 0.5'f) / BoltCoreEnd * BoltKnees
        knee = along - fract(along)
        top = boltKnee(uParticleOrigin, uParticleTarget, knee, flash,
          uParticleSeed)
        bottom = boltKnee(uParticleOrigin, uParticleTarget, knee + 1.0'f,
          flash, uParticleSeed)
        flicker = 0.65'f + 0.35'f * particleHash(flash * 1.7'f +
          uParticleSeed)
      position = mix(top, bottom, fract(along))
      velocity = (bottom - top) * 8.0'f
      size = 0.041'f
      color = vec4(0.85'f, 0.92'f, 1.0'f, 0.95'f * flicker * fade)
      life = elapsed / 0.4'f
      alive = 1.0'f
      return
    if particleId < BoltFlashEnd:
      # The flash where it strikes.
      life = elapsed / 0.4'f
      position = uParticleTarget + vec3(0.0'f, 0.25'f, 0.0'f)
      size = mix(0.3'f, 0.6'f, life) * (1.0'f + (particleId - BoltCoreEnd) * 0.3'f)
      color = vec4(0.62'f, 0.76'f, 1.0'f, 0.30'f * fade)
      alive = 1.0'f
      return
    let
      age = elapsed - particleRandom(state) * 0.04'f
      lifetime = 0.2'f + particleRandom(state) * 0.18'f
    if age < 0.0'f or age >= lifetime:
      return
    var direction = particleDirection(state)
    direction.y = abs(direction.y) * 0.7'f + 0.3'f
    direction = safeParticleDirection(direction)
    let speed = 1.5'f + particleRandom(state) * 2.0'f
    velocity = direction * speed + vec3(0.0'f, -5.0'f * age, 0.0'f)
    position = uParticleTarget + direction * speed * age +
      vec3(0.0'f, -2.5'f * age * age, 0.0'f)
    life = age / lifetime
    size = 0.02'f * (0.75'f + particleRandom(state) * 0.7'f)
    color = mix(vec4(0.9'f, 0.95'f, 1.0'f, 1.0'f),
      vec4(0.35'f, 0.45'f, 1.0'f, 0.0'f), life)
    alive = 1.0'f
    return

  let
    travel: float32 = max(uParticleTravelTime, 0.05'f)
    path: Vec3 = uParticleTarget - uParticleOrigin
    pathDirection: Vec3 = safeParticleDirection(path)
    pathSpeed: float32 = length(path) / travel
    progress: float32 = clamp(elapsed / travel, 0.0'f, 1.0'f)

  if uParticleEffectKind == PoisonCapsule.ord.int32:
    let
      arcHeight = clamp(length(path) * 0.3'f, 0.6'f, 2.2'f)
      delay = max(0.0'f, particleId - 2.0'f) * 0.009'f
      age = elapsed - delay
    if age < 0.0'f or age > travel:
      return
    let t = clamp(age / travel, 0.0'f, 1.0'f)
    position = mix(uParticleOrigin, uParticleTarget, t) +
      vec3(0.0'f, 4.0'f * arcHeight * t * (1.0'f - t), 0.0'f)
    velocity = path / travel +
      vec3(0.0'f, 4.0'f * arcHeight * (1.0'f - 2.0'f * t) / travel, 0.0'f)
    if particleId < 3.0'f:
      position += vec3(0.0'f, (particleId - 1.0'f) * 0.08'f, 0.0'f)
      size = 0.10'f
      color = vec4(0.42'f, 0.08'f, 0.65'f, 1.0'f)
    else:
      position += particleDirection(state) * 0.06'f
      size = mix(0.065'f, 0.015'f, particleId / 24.0'f)
      color = vec4(0.6'f, 0.2'f, 0.85'f,
        (1.0'f - particleId / 24.0'f) * 0.55'f)
    life = t
    alive = 1.0'f
    return

  if uParticleEffectKind == MagicBolt.ord.int32:
    if particleId < 4.0'f:
      if elapsed > travel:
        return
      let angle = particleId * 1.57079632679'f + elapsed * 13.0'f
      position = mix(uParticleOrigin, uParticleTarget, progress) + vec3(
        cos(angle) * 0.08'f,
        sin(angle * 1.31'f) * 0.08'f,
        sin(angle) * 0.08'f
      )
      velocity = pathDirection * pathSpeed
      size = 0.13'f
      color = vec4(0.35'f, 0.78'f, 1.0'f, 0.96'f)
      life = progress
      alive = 1.0'f
      return
    let
      birth = (particleId - 4.0'f) / 31.0'f * travel
      age = elapsed - birth
      lifetime = 0.32'f + particleRandom(state) * 0.25'f
    if age < 0.0'f or age >= lifetime or birth > travel:
      return
    let
      birthProgress = clamp(birth / travel, 0.0'f, 1.0'f)
      angle = particleRandom(state) * 6.28318530718'f + age * 11.0'f
      radius = 0.05'f + particleRandom(state) * 0.11'f
    position = mix(uParticleOrigin, uParticleTarget, birthProgress) + vec3(
      cos(angle) * radius,
      sin(angle * 1.37'f) * radius,
      sin(angle) * radius
    )
    velocity = pathDirection * pathSpeed
    life = age / lifetime
    size = mix(0.085'f, 0.025'f, life)
    color = mix(
      vec4(0.22'f, 0.78'f, 1.0'f, 0.88'f),
      vec4(0.82'f, 0.22'f, 1.0'f, 0.0'f),
      life
    )
    alive = 1.0'f
    return

  if uParticleEffectKind == Fireball.ord.int32:
    if particleId < 5.0'f:
      if elapsed > travel:
        return
      let angle = particleId * 1.25663706144'f + elapsed * 17.0'f
      position = mix(uParticleOrigin, uParticleTarget, progress) + vec3(
        cos(angle) * 0.10'f,
        sin(angle * 1.19'f) * 0.10'f,
        sin(angle) * 0.10'f
      )
      velocity = pathDirection * pathSpeed
      size = 0.18'f
      color = vec4(1.0'f, 0.72'f, 0.12'f, 1.0'f)
      life = progress
      alive = 1.0'f
      return
    let
      birth = (particleId - 5.0'f) / 46.0'f * travel
      age = elapsed - birth
      lifetime = 0.38'f + particleRandom(state) * 0.3'f
    if age < 0.0'f or age >= lifetime or birth > travel:
      return
    let
      birthProgress = clamp(birth / travel, 0.0'f, 1.0'f)
      direction = particleDirection(state)
    position = mix(uParticleOrigin, uParticleTarget, birthProgress) +
      direction * particleRandom(state) * 0.13'f +
      vec3(0.0'f, age * 0.35'f, 0.0'f)
    velocity = pathDirection * pathSpeed + vec3(0.0'f, 0.35'f, 0.0'f)
    life = age / lifetime
    size = mix(0.12'f, 0.035'f, life) *
      (0.7'f + particleRandom(state) * 0.7'f)
    color = mix(
      vec4(1.0'f, 0.86'f, 0.18'f, 0.95'f),
      vec4(1.0'f, 0.09'f, 0.01'f, 0.0'f),
      life
    )
    alive = 1.0'f
    return

  if uParticleEffectKind == ArrowWake.ord.int32:
    if particleId < 2.0'f:
      if elapsed > travel:
        return
      position = mix(uParticleOrigin, uParticleTarget, progress)
      velocity = pathDirection * max(pathSpeed, 4.0'f)
      size = 0.032'f
      color = vec4(0.82'f, 0.93'f, 1.0'f, 0.72'f)
      life = progress
      alive = 1.0'f
      return
    let
      birth = (particleId - 2.0'f) / 21.0'f * travel
      age = elapsed - birth
      lifetime = 0.12'f + particleRandom(state) * 0.12'f
    if age < 0.0'f or age >= lifetime or birth > travel:
      return
    let birthProgress = clamp(birth / travel, 0.0'f, 1.0'f)
    position = mix(uParticleOrigin, uParticleTarget, birthProgress) -
      pathDirection * age * 0.35'f +
      particleDirection(state) * 0.025'f
    velocity = pathDirection * max(pathSpeed, 4.0'f)
    life = age / lifetime
    size = mix(0.038'f, 0.012'f, life)
    color = mix(
      vec4(0.78'f, 0.9'f, 1.0'f, 0.35'f),
      vec4(0.42'f, 0.58'f, 0.78'f, 0.0'f),
      life
    )
    alive = 1.0'f

  if uParticleEffectKind == BladeFlame.ord.int32:
    let
      lifetime = 0.2'f + particleRandom(state) * 0.24'f
      along = particleRandom(state)
    if elapsed >= lifetime:
      return
    let
      progress = elapsed / lifetime
      climb = 0.9'f + particleRandom(state) * 1.5'f
    position = mix(uParticleOrigin, uParticleTarget, along) +
      particleDirection(state) * (0.02'f + progress * 0.1'f) +
      vec3(0.0'f, climb * elapsed, 0.0'f)
    velocity = vec3(0.0'f, climb, 0.0'f)
    life = progress
    size = mix(0.14'f, 0.025'f, progress) *
      (0.7'f + particleRandom(state) * 0.7'f) *
      mix(1.0'f, 0.6'f, along)
    color = mix(
      mix(
        vec4(1.0'f, 0.72'f, 0.18'f, 0.23'f),
        vec4(1.0'f, 0.22'f, 0.01'f, 0.18'f),
        clamp(progress * 2.5'f, 0.0'f, 1.0'f)
      ),
      vec4(0.8'f, 0.03'f, 0.0'f, 0.0'f),
      clamp((progress - 0.4'f) * 1.67'f, 0.0'f, 1.0'f)
    )
    alive = 1.0'f
    return

  if uParticleEffectKind == FireWave.ord.int32:
    let
      birth = particleRandom(state) * 0.035'f
      age = elapsed - birth
      lifetime = 0.32'f + particleRandom(state) * 0.15'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      path = uParticleTarget - uParticleOrigin
      reach = length(path)
      forward = safeParticleDirection(path)
      side = vec3(forward.z, 0.0'f, -forward.x)
      angle = ((particleId + particleRandom(state)) / 160.0'f - 0.5'f) * 1.57079632679'f
      outward = forward * cos(angle) + side * sin(angle)
      travel = clamp(age / 0.125'f, 0.0'f, 1.0'f)
      radius = max(0.0'f, reach * travel - particleRandom(state) * 0.38'f)
      rise = particleRandom(state) * 0.48'f
      progress = age / lifetime
      fade = 1.0'f - smoothstep(0.28'f, 1.0'f, progress)
    position = uParticleOrigin + outward * radius +
      vec3(0.0'f, rise * sin(progress * 3.14159265'f), 0.0'f)
    velocity = outward * 3.0'f + vec3(0.0'f, 1.8'f, 0.0'f)
    life = progress
    size = (0.10'f + particleRandom(state) * 0.08'f) * (1.0'f - progress * 0.55'f)
    color = mix(vec4(1.0'f, 0.72'f, 0.12'f, 0.28'f * fade),
      vec4(1.0'f, 0.075'f, 0.005'f, 0.12'f * fade), progress)
    alive = 1.0'f
    return

  if uParticleEffectKind == HeatEmbers.ord.int32:
    let
      birth = particleId * 0.006'f
      age = elapsed - birth
      lifetime = 0.5'f + particleRandom(state) * 0.45'f
    if age < 0.0'f or age >= lifetime:
      return
    let
      angle = particleRandom(state) * 6.28318530718'f
      radius = sqrt(particleRandom(state)) *
        length(uParticleTarget - uParticleOrigin)
      climb = 0.5'f + particleRandom(state) * 1.1'f
      progress = age / lifetime
    position = uParticleOrigin +
      vec3(cos(angle) * radius, 0.06'f + climb * age, sin(angle) * radius)
    velocity = vec3(0.0'f, climb, 0.0'f)
    life = progress
    size = mix(0.1'f, 0.025'f, progress) *
      (0.7'f + particleRandom(state) * 0.6'f)
    color = mix(
      vec4(1.0'f, 0.62'f, 0.12'f, 0.9'f),
      vec4(1.0'f, 0.1'f, 0.01'f, 0.0'f),
      progress
    )
    alive = 1.0'f
    return

proc gameParticleVertex*(
    gl_Position: var Vec4,
    fragmentUv: var Vec2,
    fragmentColor: var Vec4,
    fragmentLife: var float32,
    fragmentAlive: var float32,
    fragmentBotanical: var float32,
    fragmentFlame: var float32,
    fragmentLeaf: var float32,
    fragmentCrystal: var float32,
    fragmentCloud: var float32,
    fragmentElectric: var float32,
    fragmentWorldXZ: var Vec2
) =
  ## Expands one GPU instance into a camera-facing particle quad.
  let
    vertexId = gl_VertexID
    particleId = gl_InstanceID.float32
  # Pass the material family as a float varying; sharing the integer
  # effect uniform across stages gives WebGL mismatched default precision.
  fragmentBotanical = 0.0'f
  fragmentFlame = 0.0'f
  fragmentLeaf = 0.0'f
  fragmentCrystal = 0.0'f
  fragmentCloud = 0.0'f
  fragmentElectric = 0.0'f
  if uParticleEffectKind == SnowSquall.ord.int32 and particleId < 36.0'f:
    fragmentCloud = 1.0'f
  if uParticleEffectKind == LightningBolt.ord.int32 and
      (particleId < BoltCoreEnd or particleId >= BoltSparkEnd):
    fragmentElectric = 1.0'f
    if particleId >= BoltForkEnd:
      fragmentElectric = 2.0'f
  if uParticleEffectKind == LeafBolt.ord.int32 or
      uParticleEffectKind == LeafBurst.ord.int32:
    fragmentLeaf = 1.0'f
  if uParticleEffectKind == SolarFlames.ord.int32:
    fragmentFlame = 1.0'f
  if uParticleEffectKind == BloomPetals.ord.int32 or
      uParticleEffectKind == BloomSeed.ord.int32 or
      uParticleEffectKind == RootLeaves.ord.int32:
    fragmentBotanical = 1.0'f
  fragmentUv = vec2(
    (vertexId mod 2'i32).float32,
    (vertexId div 2'i32).float32
  )
  var
    position: Vec3
    velocity: Vec3
    size: float32
  evaluateParticle(
    particleId,
    position,
    velocity,
    size,
    fragmentColor,
    fragmentLife,
    fragmentAlive
  )
  if fragmentAlive < 0.5'f:
    gl_Position = vec4(2.0'f, 2.0'f, 2.0'f, 1.0'f)
    return
  if (uParticleEffectKind == IceShard.ord.int32 and particleId < 1.0'f) or
      (uParticleEffectKind == FrostBurst.ord.int32 and particleId >= 6.0'f) or
      (uParticleEffectKind == IceShatter.ord.int32 and particleId < 48.0'f) or
      (uParticleEffectKind == BlizzardShards.ord.int32 and length(velocity) > 0.001'f):
    fragmentCrystal = 1.0'f
  size *= 2.0'f
  let corner: Vec2 = fragmentUv * 2.0'f - 1.0'f
  var
    right: Vec3 = uParticleCameraRight
    up: Vec3 = uParticleCameraUp
    lengthScale: float32 = 1.0'f
  if uParticleEffectKind == CombatSparks.ord.int32 or
      uParticleEffectKind == ArrowWake.ord.int32 or
      uParticleEffectKind == IceShard.ord.int32 or
      uParticleEffectKind == BlizzardShards.ord.int32 or
      uParticleEffectKind == LightningBolt.ord.int32 or
      fragmentCrystal > 0.5'f or fragmentCloud > 0.5'f:
    var along: Vec3 = velocity
    along -= uParticleCameraForward * dot(
      velocity,
      uParticleCameraForward
    )
    let alongLength: float32 = length(along)
    if alongLength > 0.0001'f:
      along = along / alongLength
    else:
      along = uParticleCameraUp
    var side: Vec3 = cross(uParticleCameraForward, along)
    let sideLength: float32 = length(side)
    if sideLength > 0.0001'f:
      side = side / sideLength
    else:
      side = uParticleCameraRight
    right = side
    up = along
    if uParticleEffectKind == ArrowWake.ord.int32:
      lengthScale = 7.0'f
    elif uParticleEffectKind == IceShard.ord.int32:
      lengthScale = 1.0'f
      if particleId < 3.0'f:
        lengthScale = 4.6'f
    elif uParticleEffectKind == BlizzardShards.ord.int32:
      if fragmentCrystal > 0.5'f:
        lengthScale = 5.0'f
    elif uParticleEffectKind == LightningBolt.ord.int32:
      lengthScale = 1.0'f
      if fragmentElectric > 0.5'f and fragmentElectric < 1.5'f:
        lengthScale = 3.2'f
    elif fragmentCloud > 0.5'f:
      lengthScale = 1.30'f
    else:
      lengthScale = 1.0'f + length(velocity) * 0.1'f
  if uParticleEffectKind == BloomPetals.ord.int32 or
      uParticleEffectKind == BloomSeed.ord.int32 or
      uParticleEffectKind == RootLeaves.ord.int32:
    let spin = particleId * 2.39996'f + uParticleTime * 1.8'f
    right = uParticleCameraRight * cos(spin) + uParticleCameraUp * sin(spin)
    up = uParticleCameraUp * cos(spin) - uParticleCameraRight * sin(spin)
    lengthScale = 1.6'f
  if uParticleEffectKind == BloomPetals.ord.int32 and particleId < 8.0'f:
    let turn = particleId * 6.2831853'f / 8.0'f
    right = vec3(-sin(turn), 0.0'f, cos(turn))
    up = vec3(cos(turn), 0.0'f, sin(turn))
    lengthScale = 1.8'f
  if uParticleEffectKind == SolarOrb.ord.int32 and
      particleId >= 2.0'f and particleId < 14.0'f:
    let elapsed = uParticleTime - uParticleStartTime
    let turn = (particleId - 2.0'f) * 6.2831853'f / 12.0'f + elapsed * 2.5'f
    right = uParticleCameraUp * cos(turn) - uParticleCameraRight * sin(turn)
    up = uParticleCameraRight * cos(turn) + uParticleCameraUp * sin(turn)
    lengthScale = 2.8'f
  if uParticleEffectKind == SolarFlames.ord.int32:
    up = vec3(0.0'f, 1.0'f, 0.0'f)
    lengthScale = 2.3'f
  let worldPosition: Vec3 = position +
    right * corner.x * size +
    up * corner.y * size * lengthScale
  fragmentWorldXZ = vec2(worldPosition.x, worldPosition.z)
  gl_Position = uParticleViewProjection * vec4(worldPosition, 1.0'f)

proc gameParticleFragment*(
    fragmentUv: Vec2,
    fragmentColor: Vec4,
    fragmentLife: float32,
    fragmentAlive: float32,
    fragmentBotanical: float32,
    fragmentFlame: float32,
    fragmentLeaf: float32,
    fragmentCrystal: float32,
    fragmentCloud: float32,
    fragmentElectric: float32,
    fragmentWorldXZ: Vec2,
    fragColor: var Vec4
) =
  ## Draws a feathered particle with a bright center.
  if fragmentAlive < 0.5'f:
    discardFragment()
  if uParticleClipSight != 0:
    let cell = floor(fragmentWorldXZ - uParticleSightOrigin)
    if cell.x < 0.0'f or cell.y < 0.0'f or
        cell.x >= uParticleSightWidth or cell.y >= uParticleSightWidth:
      discardFragment()
    if texture(uParticleSight, (cell + vec2(0.5'f)) / uParticleSightWidth).x < 0.5'f:
      discardFragment()
  if fragmentLeaf > 0.5'f:
    let
      raw: Vec2 = fragmentUv * 2.0'f - 1.0'f
      angle = fragmentLife
      point: Vec2 = vec2(
        raw.x * cos(angle) - raw.y * sin(angle),
        raw.x * sin(angle) + raw.y * cos(angle)
      )
      width = max(0.0'f, 0.5'f * (1.0'f - point.y * point.y))
      edge = min(width - abs(point.x), 0.9'f - abs(point.y))
      alpha = smoothstep(0.0'f, 0.06'f, edge) * fragmentColor.w
      vein = 1.0'f - smoothstep(0.0'f, 0.025'f, abs(point.x))
    if alpha < 0.004'f:
      discardFragment()
    fragColor = vec4(fragmentColor.xyz + vec3(0.08'f, 0.12'f, 0.025'f) * vein, alpha)
    return
  if fragmentCloud > 0.5'f:
    let
      p: Vec2 = fragmentUv * 2.0'f - 1.0'f
      coarse = cloudNoise(p * 2.2'f + vec2(fragmentLife * 0.34'f, fragmentLife * 0.09'f))
      detail = cloudNoise(p * 5.2'f + vec2(fragmentLife * 0.22'f, -fragmentLife * 0.13'f))
      lobes = coarse * 0.73'f + detail * 0.27'f
      envelope = 1.0'f - dot(p, p)
      edge = smoothstep(0.0'f, 0.69'f, envelope) *
        smoothstep(0.15'f, 0.71'f, envelope + (lobes - 0.5'f) * 0.68'f)
      density = smoothstep(0.12'f, 0.76'f, lobes)
      alpha = edge * density * fragmentColor.w
      lit = smoothstep(0.24'f, 0.85'f, lobes + p.y * 0.14'f)
      tint: Vec3 = mix(vec3(0.20'f, 0.29'f, 0.43'f),
        vec3(0.68'f, 0.80'f, 0.91'f), lit)
    if alpha < 0.004'f: discardFragment()
    fragColor = vec4(tint, alpha)
    return
  if fragmentElectric > 1.5'f:
    let
      p: Vec2 = fragmentUv * 2.0'f - 1.0'f
      horizontal = exp(-abs(p.y) * 24.0'f - abs(p.x) * 3.4'f)
      vertical = exp(-abs(p.x) * 24.0'f - abs(p.y) * 3.4'f)
      halo = exp(-dot(p, p) * 7.0'f) * 0.32'f
      fade = 1.0'f - smoothstep(0.48'f, 1.0'f, dot(p, p))
      alpha = min(horizontal + vertical + halo, 1.0'f) * fade * fragmentColor.w
    if alpha < 0.004'f: discardFragment()
    fragColor = vec4(0.86'f, 0.94'f, 1.0'f, alpha)
    return
  if fragmentElectric > 0.5'f:
    let
      p: Vec2 = fragmentUv * 2.0'f - 1.0'f
      crossfade = 1.0'f - smoothstep(0.08'f, 1.0'f, abs(p.x))
      endfade = 1.0'f - smoothstep(0.60'f, 1.0'f, abs(p.y))
      core = 1.0'f - smoothstep(0.08'f, 0.32'f, abs(p.x))
      alpha = crossfade * endfade * fragmentColor.w
    if alpha < 0.004'f: discardFragment()
    fragColor = vec4(mix(vec3(0.13'f, 0.37'f, 1.0'f),
      vec3(0.92'f, 0.98'f, 1.0'f), core), alpha)
    return
  if fragmentCrystal > 0.5'f:
    let
      point: Vec2 = fragmentUv * 2.0'f - 1.0'f
      width = min((0.98'f - point.y) * 0.78'f, (0.92'f + point.y) * 1.32'f)
      edge = width - abs(point.x)
      coverage = smoothstep(0.0'f, 0.065'f, edge)
      seam = point.x + point.y * 0.15'f
      face = smoothstep(-0.09'f, 0.06'f, seam)
      rim = 1.0'f - smoothstep(0.055'f, 0.21'f, edge)
      streak = exp(-abs(seam) * 37.0'f) * exp(-abs(point.y - 0.24'f) * 2.8'f)
      highlight = clamp(rim * 0.76'f + streak * 0.92'f, 0.0'f, 1.0'f)
      opacity = mix(0.29'f + face * 0.13'f, 0.94'f, highlight)
      alpha = coverage * opacity * fragmentColor.w
      tint: Vec3 = mix(vec3(0.18'f, 0.47'f, 0.74'f), fragmentColor.xyz, face)
    if alpha < 0.004'f: discardFragment()
    fragColor = vec4(mix(tint, vec3(0.93'f, 0.98'f, 1.0'f), highlight), alpha)
    return
  if fragmentFlame > 0.5'f:
    let
      p = fragmentUv * 2.0'f - 1.0'f
      height = fragmentUv.y
      bend = sin(height * 7.0'f - fragmentLife * 9.0'f) * height * 0.14'f
      width = (1.0'f - height) * 0.72'f + 0.035'f
      shape = 1.0'f - abs(p.x - bend) / width
      feather = smoothstep(0.0'f, 0.32'f, shape) * sin(height * 3.14159265'f)
      core = exp(-abs(p.x - bend) * 9.0'f) * (1.0'f - height)
    if feather < 0.004'f: discardFragment()
    fragColor = vec4(mix(fragmentColor.xyz, vec3(1.0'f, 0.86'f, 0.32'f), core * 0.6'f),
      fragmentColor.w * feather)
    return
  if fragmentBotanical > 0.5'f:
    let p = fragmentUv * 2.0'f - 1.0'f
    let shape = 1.0'f - abs(p.x) - p.y * p.y
    if shape < 0.0'f: discardFragment()
    let vein = exp(-abs(p.x) * 28.0'f) * 0.22'f
    fragColor = vec4(fragmentColor.xyz + vec3(vein),
      fragmentColor.w * smoothstep(0.0'f, 0.16'f, shape))
    return
  let
    point = fragmentUv * 2.0'f - 1.0'f
    radiusSquared = dot(point, point)
    glow = exp(-radiusSquared * 3.4'f)
    core = exp(-radiusSquared * 15.0'f)
    flicker = 0.9'f + 0.1'f * sin(fragmentLife * 19.0'f)
    edgeFade = 1.0'f - smoothstep(0.65'f, 1.0'f, radiusSquared)
    alpha = fragmentColor.w * min(1.0'f, glow + core) * flicker * edgeFade
  if alpha < 0.004'f:
    discardFragment()
  fragColor = vec4(
    fragmentColor.xyz * (0.72'f + core * 0.72'f),
    alpha
  )
