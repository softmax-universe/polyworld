## Bounded GPU particle effects shared by Polyworld game renderers.

import
  std/math,
  shady, vmath,
  particleshaders

include backends/passes/particles_types

const
  MaximumParticleEffects = 192

type
  ParticleError* = object of CatchableError

  ParticleEffect = object
    kind: ParticleEffectKind
    origin: Vec3
    target: Vec3
    startTime: float32
    travelTime: float32
    endTime: float32
    seed: uint32
    owner: int32
    anchor: int32
      ## What the effect travels with, or 0; see `followParticleAnchors`.

  ParticleSystem* = object
    gpu: ParticleGpu
    effects: seq[ParticleEffect]
    time: float32
    nextSeed: uint32

proc effectParticleCount(kind: ParticleEffectKind): int =
  ## Returns the bounded instance count for one semantic effect.
  case kind
  of CombatSparks:
    24
  of MagicBolt:
    36
  of MagicBurst, PortalBurst, PoisonBurst:
    32
  of Fireball:
    52
  of FireBurst:
    40
  of ArrowWake:
    24
  of PoisonCapsule:
    24
  of LeafBolt, LeafBurst:
    12
  of HealingAura, ManaAura, PoisonAura:
    48
  of BloomSeed:
    24
  of BloomPetals:
    56
  of RootLeaves:
    36
  of SolarOrb:
    48
  of SolarFlames:
    112
  of MendingAura:
    40
  of BladeFlame:
    24
  of FireWave:
    160
  of HeatEmbers:
    40
  of IceShard:
    28
  of FrostBurst:
    30
  of IceShatter:
    90
  of BlizzardShards:
    48
  of SnowSquall:
    220
  of LightningBolt:
    LightningParticleCount

proc effectLifetime(
    kind: ParticleEffectKind,
    travelTime: float32
): float32 =
  ## Returns how long one effect must remain available for drawing.
  case kind
  of CombatSparks:
    0.9'f
  of MagicBolt:
    travelTime + 0.7'f
  of MagicBurst, PortalBurst, PoisonBurst:
    1.25'f
  of Fireball:
    travelTime + 0.8'f
  of FireBurst:
    1.0'f
  of ArrowWake:
    travelTime + 0.35'f
  of PoisonCapsule:
    travelTime + 0.25'f
  of LeafBolt:
    travelTime
  of LeafBurst:
    0.6'f
  of BloomSeed, SolarOrb:
    travelTime + 0.1'f
  of BloomPetals, RootLeaves:
    1.8'f
  of SolarFlames:
    1.65'f
  of HealingAura, ManaAura, PoisonAura, MendingAura:
    1.75'f
  of BladeFlame:
    0.5'f
  of FireWave:
    0.55'f
  of HeatEmbers:
    1.25'f
  of IceShard:
    travelTime + 0.6'f
  of FrostBurst:
    0.9'f
  of IceShatter:
    1.3'f
  of BlizzardShards:
    travelTime + 0.4'f
  of SnowSquall:
    travelTime + 0.1'f
  of LightningBolt:
    0.45'f

proc addParticleEffect(
    system: var ParticleSystem,
    kind: ParticleEffectKind,
    origin,
    target: Vec3,
    travelTime,
    delay: float32,
    anchor = 0'i32,
    owner = -1'i32
) =
  ## Adds one effect while keeping the presentation queue bounded.
  if system.effects.len >= MaximumParticleEffects:
    system.effects.delete(0)
  let startTime = system.time + max(delay, 0.0'f)
  system.effects.add ParticleEffect(
    kind: kind,
    origin: origin,
    target: target,
    startTime: startTime,
    travelTime: max(travelTime, 0.05'f),
    endTime: startTime + kind.effectLifetime(travelTime),
    seed: system.nextSeed,
    anchor: anchor,
    owner: owner
  )
  inc system.nextSeed

proc emitParticleBurst*(
    system: var ParticleSystem,
    kind: ParticleEffectKind,
    position: Vec3,
    delay = 0.0'f,
    anchor = 0'i32,
    owner = -1'i32
) =
  ## Emits one burst now or after a short presentation delay. It stays
  ## where it was emitted unless it has an anchor to follow.
  system.addParticleEffect(
    kind,
    position,
    position,
    0.05'f,
    delay,
    anchor,
    owner
  )

proc emitParticleSpan*(
    system: var ParticleSystem,
    kind: ParticleEffectKind,
    origin,
    target: Vec3,
    delay = 0.0'f
) =
  ## Emits one effect that spreads between two points without travelling.
  system.addParticleEffect(
    kind,
    origin,
    target,
    0.05'f,
    delay
  )

proc emitParticleFlight*(
    system: var ParticleSystem,
    kind: ParticleEffectKind,
    origin, target: Vec3,
    travelTime: float32
) =
  ## A travelling visual whose impact is emitted by the simulation event.
  system.addParticleEffect(kind, origin, target,
    max(travelTime, 0.05'f), 0.0'f)

proc emitParticleProjectile*(
    system: var ParticleSystem,
    projectile,
    impact: ParticleEffectKind,
    origin,
    target: Vec3,
    travelTime: float32,
    owner = -1'i32
) =
  ## Emits a travelling effect and a matching impact at its destination.
  let duration = max(travelTime, 0.05'f)
  system.addParticleEffect(
    projectile,
    origin,
    target,
    duration,
    0.0'f,
    owner = owner
  )
  system.emitParticleBurst(impact, target, duration, owner = owner)

proc followParticleAnchors*(
    system: var ParticleSystem,
    place: proc(anchor: int32, position: var Vec3): bool
) =
  ## Moves every anchored effect to where `place` puts its anchor now, so
  ## it travels with whatever it was emitted on. An anchor `place` no
  ## longer finds leaves its effects where they last were.
  for effect in system.effects.mitems:
    if effect.anchor == 0:
      continue
    var position = effect.origin
    if place(effect.anchor, position):
      effect.target += position - effect.origin
      effect.origin = position

proc advanceParticles*(system: var ParticleSystem, delta: float32) =
  ## Advances presentation time and removes every finished effect.
  system.time += max(delta, 0.0'f)
  var index = system.effects.high
  while index >= 0:
    if system.effects[index].endTime <= system.time:
      system.effects.delete(index)
    dec index

proc clearParticles*(system: var ParticleSystem) =
  ## Removes all active effects without rewinding presentation time.
  system.effects.setLen(0)

proc particlePathVisible*(
    origin, target: Vec3,
    visibility: openArray[uint8],
    width: int,
    mapOrigin: Vec2,
    padding = 0
): bool =
  ## Hides an effect if any part of its travel path enters unseen tiles.
  if visibility.len == 0:
    return true
  if width <= 0 or visibility.len != width * width:
    return false
  let
    delta = target - origin
    steps = max(1, int(ceil(max(abs(delta.x), abs(delta.z)) * 2)))
  for i in 0 .. steps:
    let
      point = origin + delta * (i.float32 / steps.float32)
      x = int(floor(point.x - mapOrigin.x))
      z = int(floor(point.z - mapOrigin.y))
    if x < 0 or z < 0 or x >= width or z >= width or
      visibility[z * width + x] == 0:
        return false
    if padding > 0:
      for row in z-padding .. z+padding:
        for col in x-padding .. x+padding:
          if col < 0 or row < 0 or col >= width or row >= width or
              visibility[row * width + col] == 0: return false
  true

include backends/passes/particles
