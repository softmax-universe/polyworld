## Shared CPU effect geometry, included by each rendering backend.

proc clear*(renderer: var VfxRenderer) =
  renderer.vertices.setLen(0)
  renderer.materialVertices.setLen(0)

proc addQuad(renderer: var VfxRenderer, corners: array[4, Vec3],
    uvs: array[4, Vec2], ink: Vec4, style: float32, dimensions = vec2(1)) =
  for i in [0, 1, 2, 0, 2, 3]:
    let p = corners[i]
    renderer.vertices.add [p.x, p.y, p.z, uvs[i].x, uvs[i].y,
      ink.x, ink.y, ink.z, ink.w, style, dimensions.x, dimensions.y]

proc addMaterialQuad(renderer: var VfxRenderer, corners: array[4, Vec3],
    uvs: array[4, Vec2], ink: Vec4, style: float32, dimensions = vec2(1)) =
  for i in [0, 1, 2, 0, 2, 3]:
    let p = corners[i]
    renderer.materialVertices.add [p.x, p.y, p.z, uvs[i].x, uvs[i].y,
      ink.x, ink.y, ink.z, ink.w, style, dimensions.x, dimensions.y]

proc addCardHalo*(renderer: var VfxRenderer, center, right, down: Vec3,
    size: Vec2, ink: Vec4, strength = 1.0'f) =
  let
    half = size * 0.5'f
    extent = half + vec2(0.4)
    x = right * extent.x
    y = down * extent.y
  renderer.addQuad([center - x - y, center - x + y,
    center + x + y, center + x - y],
    [vec2(-extent.x, -extent.y), vec2(-extent.x, extent.y),
      extent, vec2(extent.x, -extent.y)],
    vec4(ink.xyz, ink.w * strength), 2, half)

proc addHudHalo*(renderer: var VfxRenderer, origin, size: Vec2,
    pixelsPerUnit: float32, ink: Vec4, strength = 1.0'f) =
  ## addCardHalo around a screen rectangle given in pixels, y down. Draw it
  ## with hudHaloProjection. `pixelsPerUnit` scales the world-sized glow to
  ## the screen, which sets how far beyond the rectangle it reaches.
  let center = origin + size * 0.5'f
  renderer.addCardHalo(vec3(center.x, center.y, 0),
    vec3(pixelsPerUnit, 0, 0), vec3(0, pixelsPerUnit, 0),
    size / pixelsPerUnit, ink, strength)

proc hudHaloProjection*(windowSize: Vec2): Mat4 =
  ## Window pixels, y down, for addHudHalo.
  ortho(0'f, windowSize.x, windowSize.y, 0'f, -1'f, 1'f)

proc addLine(renderer: var VfxRenderer, a, b, eye: Vec3,
    width: float32, ink: Vec4) =
  let normal = cross(b - a, eye - (a + b) * 0.5'f)
  if length(normal) < 0.00001'f: return
  let side = normalize(normal) * width
  renderer.addQuad([a - side, b - side, b + side, a + side],
    [vec2(0, -1), vec2(1, -1), vec2(1, 1), vec2(0, 1)], ink, 1)

proc addGlowLine(renderer: var VfxRenderer, a, b, eye: Vec3,
    width: float32, ink: Vec4) =
  renderer.addLine(a, b, eye, width * 4, vec4(ink.xyz, ink.w * 0.24))
  renderer.addLine(a, b, eye, width * 1.8, vec4(ink.xyz, ink.w * 0.55))
  renderer.addLine(a, b, eye, width * 0.45,
    vec4(mix(ink.xyz, vec3(1), 0.72'f), ink.w))

proc addBillboard(renderer: var VfxRenderer, center: Vec3, radius: float32,
    eye: Vec3, ink: Vec4, style: float32) =
  let
    forward = normalize(eye - center)
    right = normalize(cross(vec3(0, 1, 0), forward)) * radius
    up = normalize(cross(forward, right)) * radius
  renderer.addQuad([center - right + up, center - right - up,
    center + right - up, center + right + up],
    [vec2(-1, -1), vec2(-1, 1), vec2(1, 1), vec2(1, -1)], ink, style)

proc addLevelUpArrow*(renderer: var VfxRenderer, base, eye: Vec3,
    size, alpha: float32, ink: Vec4) =
  ## A glowing arrow pointing up, drawn beside a hero that levelled up.
  if alpha <= 0.01'f:
    return
  let
    forward = normalize(eye - base)
    right = normalize(cross(vec3(0, 1, 0), forward)) * size
    up = vec3(0, size, 0)
    tip = base + up
    glow = vec4(ink.xyz, ink.w * alpha)
  renderer.addGlowLine(base - up * 0.6'f, tip, eye, size * 0.1'f, glow)
  renderer.addGlowLine(tip, tip - up * 0.55'f - right * 0.5'f, eye,
    size * 0.1'f, glow)
  renderer.addGlowLine(tip, tip - up * 0.55'f + right * 0.5'f, eye,
    size * 0.1'f, glow)

proc addTargetingArrow*(renderer: var VfxRenderer, start, finish, eye: Vec3,
    time, strength: float32, scale = 1'f) =
  ## A fat, dotted red arc from a card to what it aims at, its dots flowing
  ## toward an arrowhead. `strength` brightens it over a legal target and
  ## fades it; `scale` sizes it for a farther camera.
  let distance = length(finish - start)
  if distance < 0.25'f or strength <= 0.01'f:
    return
  const Steps = 48
  # A long throw arches over the table; a short hop bows out sideways
  # instead, since from the camera above a tall hump would only climb onto
  # the card it aims at.
  let
    ground = vec3(finish.x - start.x, 0, finish.z - start.z)
    across =
      if length(ground) > 0.001'f: normalize(cross(ground, vec3(0, 1, 0)))
      else: vec3(0)
    control = (start + finish) * 0.5'f +
      vec3(0, 0.3'f + distance * 0.25'f, 0) +
      across * max(0'f, 1.4'f - distance * 0.15'f)
  # The curve, sampled with how far along it each sample lies.
  var
    points: array[Steps + 1, Vec3]
    along: array[Steps + 1, float32]
  for i in 0 .. Steps:
    let
      t = i.float32 / Steps
      u = 1 - t
    points[i] = start * (u * u) + control * (2 * u * t) + finish * (t * t)
    if i > 0:
      along[i] = along[i - 1] + length(points[i] - points[i - 1])
  let total = along[Steps]
  proc pointAt(d: float32): Vec3 =
    var i = 1
    while i < Steps and along[i] < d:
      inc i
    let
      span = max(along[i] - along[i - 1], 0.00001'f)
      f = clamp((d - along[i - 1]) / span, 0, 1)
    mix(points[i - 1], points[i], f)
  let
    red = TargetRed.xyz
    hot = mix(red, vec3(1, 0.7, 0.6), 0.22'f)
    head = min(0.7'f * scale, total * 0.3'f)
    spacing = 0.3'f * scale
  # Dots, moving toward the target.
  var d = fract(time * 1.4'f) * spacing
  while d < total - head * 0.8'f:
    let p = pointAt(d)
    renderer.addBillboard(p, 0.36 * scale, eye,
      vec4(red, 0.5'f * strength), 4)
    renderer.addBillboard(p, 0.17 * scale, eye,
      vec4(hot, 0.8'f * strength), 4)
    d += spacing
  # A filled arrowhead lying flat over the target, pointing the way the
  # arc travels across the table, so the camera above reads its shape.
  let
    tip = finish
    approach = tip - pointAt(total - head)
    flat = vec3(approach.x, 0, approach.z)
  if length(flat) < 0.00001'f:
    return
  let
    forward = normalize(flat) * head
    side = normalize(cross(forward, vec3(0, 1, 0))) * head * 0.7'f
    back = tip - forward
    fill = vec4(red, 0.5'f * strength)
  renderer.addQuad([back - side, tip, tip, back + side],
    [vec2(0), vec2(0), vec2(0), vec2(0)], fill, 0)
  let edge = vec4(red, 0.55'f * strength)
  renderer.addLine(back - side, tip, eye, 0.07 * scale, edge)
  renderer.addLine(back + side, tip, eye, 0.07 * scale, edge)
  renderer.addLine(back - side, back + side, eye, 0.07 * scale, edge)

proc addTargetRing*(renderer: var VfxRenderer, center, eye: Vec3,
    radius: float32, strength: float32) =
  for i in 0 ..< 64:
    let
      a = i.float32 * 2 * PI.float32 / 64
      b = (i + 1).float32 * 2 * PI.float32 / 64
    renderer.addGlowLine(center + vec3(cos(a), 0, sin(a)) * radius,
      center + vec3(cos(b), 0, sin(b)) * radius, eye, 0.025,
      vec4(TargetRed.xyz, strength))

proc newVfx*(kind: VfxKind, target: Choice, position: Vec3, seed: int): ActiveVfx =
  ActiveVfx(kind: kind, target: target, position: position, seed: seed,
    duration: case kind
      of LightningVfx: 0.95'f
      of BubbleVfx: 1.05'f
      of DamageFlashVfx: 0.55'f
      of ArrowVfx: 0.75'f
      of ManyArrowsVfx: 1.1'f
      of SwordsIntoTheWindVfx: 1.55'f
      of MightyShieldsVfx: 1.1'f
      of SwordAndShieldVfx: 1.4'f
      of MeleeVfx: 1.35'f
      of SwordClashVfx: 1.25'f
      of SwordBreakVfx: 1.4'f
      of OozeSplatVfx: 1.8'f
      of ExplosionVfx: 0.95'f
      of StabVfx: 0.6'f
      of PrizeVfx: 1.3'f
      # Presentation cues the table draws itself, not particle effects.
      of NoVfx, DeathVfx, DrawVfx, SummonVfx, BounceVfx, TossVfx,
          HeroDeathVfx, LevelUpVfx, GainControlVfx: 0.0'f)

proc advance*(effects: var seq[ActiveVfx], dt: float32) =
  for effect in effects.mitems:
    effect.elapsed += dt
  for i in countdown(effects.high, 0):
    if effects[i].elapsed >= effects[i].duration:
      effects.delete(i)

proc flashStrength*(effects: openArray[ActiveVfx], target: Choice): float32 =
  for effect in effects:
    if effect.kind == DamageFlashVfx and effect.target == target:
      # Hold the impact long enough to read, then smoothly restore the model.
      let fade = clamp((effect.duration - effect.elapsed) / 0.35'f,
        0.0'f, 1.0'f)
      result = max(result, fade * fade * (3 - 2 * fade))

proc particleNoise(index, salt, seed: int): float32 =
  ## A stable hash keeps each particle's trajectory continuous across frames.
  ## Only a new cast gets a new seed; drawing never consumes a random stream.
  var bits = uint32(seed) xor (uint32(index + 1) * 0x9e3779b9'u32) xor
    (uint32(salt) * 0x85ebca6b'u32)
  bits = (bits xor (bits shr 16)) * 0x7feb352d'u32
  bits = (bits xor (bits shr 15)) * 0x846ca68b'u32
  bits = bits xor (bits shr 16)
  (bits shr 8).float32 / 16777216.0'f

proc addLightningTexture(renderer: var VfxRenderer, start, finish, eye: Vec3,
    age, strength: float32, seed, discharge: int) =
  if strength <= 0.002'f: return
  let
    axis = finish - start
    normal = cross(axis, eye - (start + finish) * 0.5'f)
  if length(normal) < 0.00001'f: return
  let
    side = normalize(normal)
    packet = discharge * 64
    mirrored = particleNoise(packet, 20, seed) > 0.5'f
    leftU = if mirrored: 1.0'f else: 0.0'f
    rightU = 1.0'f - leftU
    halfWidth = length(axis) / 0.9'f * renderer.lightningAspect * 0.5'f *
      (0.78'f + particleNoise(packet, 21, seed) * 0.32'f)
  # Midpoint displacement creates large bends with progressively smaller kinks.
  # Both endpoints stay at zero, anchoring every discharge to the same target.
  var offsets: array[17, float32]
  var
    step = 16
    spread = length(axis) * 0.16'f
  while step > 1:
    let half = step div 2
    for left in countup(0, 16 - step, step):
      let middle = left + half
      offsets[middle] = (offsets[left] + offsets[left + step]) * 0.5'f +
        (particleNoise(packet + middle, step + 22, seed) * 2 - 1) * spread
    step = half
    spread *= 0.52'f
  var
    centers: array[35, Vec3]
    widths: array[35, Vec3]
    rows: array[35, float32]
  for row in 0 ..< 35:
    # Include the transparent caps and exact 5%/95% texture terminals.
    let
      t = if row == 0: -0.05'f / 0.9'f
        elif row == 34: 1 + 0.05'f / 0.9'f
        else: (row - 1).float32 / 32
      along = clamp(t, 0.0'f, 1.0'f) * 16
      knot = min(15, int(along))
      offset = mix(offsets[knot], offsets[knot + 1], along - knot.float32)
    centers[row] = start + axis * t + side * offset
    widths[row] = side * halfWidth
    rows[row] = 0.05'f + t * 0.9'f
  for row in 0 ..< 34:
    renderer.addQuad([centers[row] - widths[row], centers[row + 1] - widths[row + 1],
      centers[row + 1] + widths[row + 1], centers[row] + widths[row]],
      [vec2(leftU, rows[row]), vec2(leftU, rows[row + 1]),
        vec2(rightU, rows[row + 1]), vec2(rightU, rows[row])],
      vec4(1.15, 1.2, 1.3, strength), 5,
      vec2(age * 45, (seed mod 4096 + discharge * 37).float32))

proc addLightning(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  let
    age = effect.elapsed
    seed = effect.seed
    cameraRight = normalize(cross(vec3(0, 1, 0), normalize(eye - effect.position)))
    inward = if dot(effect.position, cameraRight) > 0: -1.0'f else: 1.0'f
    start = effect.position + cameraRight * inward * (1.25'f + particleNoise(0, 30, seed) * 1.75'f) +
      vec3(0, 4.6'f + particleNoise(0, 31, seed) * 0.55'f, 0)
    interval = 0.055'f + particleNoise(0, 32, seed) * 0.025'f
    discharge = int(age / interval)
    phase = age / interval - discharge.float32
    strikeFade = clamp(1 - age / 0.43'f, 0.0'f, 1.0'f)
    flicker = 0.72'f + 0.28'f * exp(-phase * 5)
    restrikeTime = 0.11'f + particleNoise(0, 33, seed) * 0.07'f
    restrike = exp(-pow((age - restrikeTime) / 0.04'f, 2.0'f))
    pulse = strikeFade * flicker + restrike * 0.35'f
  renderer.addLightningTexture(start, effect.position, eye, age, pulse, seed, discharge)
  # Shapes snap on a time-based cadence, leaving only a short, faint afterimage.
  if discharge > 0:
    renderer.addLightningTexture(start, effect.position, eye, age,
      strikeFade * 0.18'f * exp(-phase * 8), seed, discharge - 1)
  renderer.addBillboard(effect.position, 1.55, eye,
    vec4(0.25, 0.63, 1.0, pulse * 1.15'f), 4)
  renderer.addBillboard(effect.position, 0.46, eye,
    vec4(0.8, 0.93, 1.0, pulse * 1.7'f), 4)

  # 88 ballistic sparks: varied launch times, directions, speeds, lengths,
  # and lifetimes give the impact a dense, irregular shower of white/cyan fire.
  for i in 0 ..< 88:
    let
      delay = particleNoise(i, 1, seed) * 0.07'f
      elapsed = age - delay
      lifetime = 0.28'f + particleNoise(i, 2, seed) * 0.48'f
    if elapsed < 0 or elapsed >= lifetime: continue
    let
      angle = particleNoise(i, 3, seed) * 2 * PI.float32
      elevation = particleNoise(i, 4, seed) * 1.7'f - 0.3'f
      speed = 2.3'f + particleNoise(i, 5, seed) * 4.8'f
      velocity = normalize(vec3(cos(angle), elevation, sin(angle))) * speed
      tailTime = max(0.0'f, elapsed - 0.018'f - particleNoise(i, 6, seed) * 0.024'f)
      head = effect.position + velocity * elapsed + vec3(0, -2.3'f * elapsed * elapsed, 0)
      tail = effect.position + velocity * tailTime + vec3(0, -2.3'f * tailTime * tailTime, 0)
      fade = clamp((lifetime - elapsed) / 0.2'f, 0.0'f, 1.0'f)
      width = 0.009'f + particleNoise(i, 7, seed) * 0.016'f
      ink = mix(vec3(0.09, 0.43, 1.0), vec3(0.5, 0.94, 1.0), particleNoise(i, 8, seed))
    renderer.addGlowLine(tail, head, eye, width, vec4(ink, fade * 0.92'f))
    if i mod 3 == 0:
      renderer.addBillboard(head, width * 5, eye, vec4(0.7, 0.9, 1, fade), 4)

  # 40 slower ions hang around the impact after the trunk has burned away.
  for i in 0 ..< 40:
    let
      delay = particleNoise(i, 11, seed) * 0.13'f
      elapsed = age - delay
      lifetime = 0.45'f + particleNoise(i, 12, seed) * 0.36'f
    if elapsed < 0 or elapsed >= lifetime: continue
    let
      angle = particleNoise(i, 13, seed) * 2 * PI.float32
      velocity = vec3(cos(angle), particleNoise(i, 14, seed) * 1.3'f, sin(angle)) *
        (0.8'f + particleNoise(i, 15, seed) * 1.7'f)
      position = effect.position + velocity * elapsed + vec3(0, elapsed * 0.3'f, 0)
      fade = pow(max(0.0'f, 1 - elapsed / lifetime), 0.7'f)
      shimmer = 0.6'f + 0.4'f * abs(sin(elapsed * 29 + i.float32))
    renderer.addBillboard(position, 0.035'f + particleNoise(i, 16, seed) * 0.07'f,
      eye, vec4(0.16, 0.65, 1.0, fade * shimmer), 4)

proc addBubble(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  let
    t = effect.elapsed / effect.duration
    appear = min(1.0'f, effect.elapsed / 0.12'f)
    pop = clamp((t - 0.8'f) / 0.2'f, 0.0'f, 1.0'f)
    radius = (1.27'f + sin(t * 10) * 0.035'f + pop * 0.55'f) *
      (0.45'f + appear * 0.55'f)
  renderer.addBillboard(effect.position, radius, eye,
    vec4(1, 1, 1, appear * (1 - pop)), 3)
  for i in 0 ..< 9:
    let
      angle = i.float32 * 2 * PI.float32 / 9 + t * 0.9'f
      offset = vec3(cos(angle), sin(angle) * 0.65'f + 0.15'f,
        sin(angle) * 0.5'f) * (radius + pop * 0.7'f)
    renderer.addBillboard(effect.position + offset, 0.07'f + pop * 0.045'f,
      eye, vec4(0.5, 0.8, 1, appear * (1 - pop)), 3)

proc addArrowShot(renderer: var VfxRenderer, target, start: Vec3,
    age: float32, seed: int, eye: Vec3, lift = 1.1'f, glow = 1.0'f) =
  ## One fletched arrow flies from `start`, sticks in `target`, then splinters.
  const flight = 0.22'f
  let
    t = min(1.0'f, age / flight)
    tip = mix(start, target, t) + vec3(0, lift * 4 * t * (1 - t), 0)
    direction = normalize(target - start +
      vec3(0, lift * 4 * (1 - 2 * t), 0))
    impactAge = age - flight
    fade = if impactAge < 0: 1.0'f
      else: clamp(1 - impactAge / 0.4'f, 0.0'f, 1.0'f)
    normal = cross(direction, eye - tip)
  if fade > 0.002'f and length(normal) > 0.00001'f:
    let
      side = normalize(normal)
      tail = tip - direction * 1.05'f
      barb = tip - direction * 0.22'f
      ink = vec4(1.0, 0.72, 0.32, fade)
    if impactAge < 0:
      # A short streak behind the arrow sells its speed during flight.
      let
        t0 = max(0.0'f, t - 0.45'f)
        trail = mix(start, target, t0) +
          vec3(0, lift * 4 * t0 * (1 - t0), 0)
      renderer.addLine(trail, tail, eye, 0.035, vec4(1.0, 0.85, 0.55, 0.22))
    renderer.addGlowLine(tail, tip, eye, 0.016, ink)
    renderer.addGlowLine(barb + side * 0.11'f, tip, eye, 0.013, ink)
    renderer.addGlowLine(barb - side * 0.11'f, tip, eye, 0.013, ink)
    for offset in [-0.1'f, 0.1'f]:
      renderer.addGlowLine(tail + direction * 0.2'f, tail + side * offset,
        eye, 0.011, vec4(1.0, 0.9, 0.7, fade * 0.8'f))
  if impactAge < 0: return

  renderer.addBillboard(target, 0.95, eye,
    vec4(1.0, 0.62, 0.22, exp(-impactAge * 9) * 1.1'f * glow), 4)
  # Splinters kick back toward the shooter, falling under a light gravity.
  for i in 0 ..< 36:
    let
      delay = particleNoise(i, 42, seed) * 0.04'f
      elapsed = impactAge - delay
      lifetime = 0.2'f + particleNoise(i, 43, seed) * 0.3'f
    if elapsed < 0 or elapsed >= lifetime: continue
    let
      angle = particleNoise(i, 44, seed) * 2 * PI.float32
      scatter = vec3(cos(angle), particleNoise(i, 45, seed) * 1.4'f, sin(angle))
      speed = 1.8'f + particleNoise(i, 46, seed) * 3.2'f
      velocity = normalize(scatter - direction * 1.2'f) * speed
      tailTime = max(0.0'f, elapsed - 0.02'f)
      head = target + velocity * elapsed +
        vec3(0, -3.0'f * elapsed * elapsed, 0)
      back = target + velocity * tailTime +
        vec3(0, -3.0'f * tailTime * tailTime, 0)
      sparkFade = clamp((lifetime - elapsed) / 0.15'f, 0.0'f, 1.0'f)
      ink = mix(vec3(0.95, 0.42, 0.12), vec3(1.0, 0.86, 0.5),
        particleNoise(i, 47, seed))
    renderer.addGlowLine(back, head, eye,
      0.008'f + particleNoise(i, 48, seed) * 0.012'f,
      vec4(ink, sparkFade * 0.9'f))

proc addArrow(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  ## A fletched arrow arcs in from the table side, sticks, then splinters.
  let
    seed = effect.seed
    cameraRight = normalize(cross(vec3(0, 1, 0), normalize(eye - effect.position)))
    inward = if dot(effect.position, cameraRight) > 0: -1.0'f else: 1.0'f
    start = effect.position +
      cameraRight * inward * (4.5'f + particleNoise(0, 40, seed)) +
      vec3(0, 1.4'f + particleNoise(0, 41, seed) * 0.6'f, 0)
  renderer.addArrowShot(effect.position, start, effect.elapsed, seed, eye)

proc addArrowVolley(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  ## A staggered volley drops steeply around the target from overhead.
  const volley = 5
  for i in 0 ..< volley:
    let
      delay = i.float32 * 0.07'f + particleNoise(i, 50, effect.seed) * 0.05'f
      age = effect.elapsed - delay
    if age < 0: continue
    let
      angle = particleNoise(i, 51, effect.seed) * 2 * PI.float32
      around = vec3(cos(angle), 0, sin(angle))
      target = effect.position +
        around * (0.2'f + particleNoise(i, 52, effect.seed) * 0.45'f)
      start = target + around * 1.1'f +
        vec3(0, 5.0'f + particleNoise(i, 53, effect.seed), 0)
    renderer.addArrowShot(target, start, age, effect.seed + i * 7919, eye,
      lift = 0.25'f, glow = 0.55'f)

include warriorvfx

include oozevfx

proc addExplosion(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  ## A minion bursts: a white-hot core that blooms and dies, embers thrown
  ## out on ballistic arcs, and a shock ring racing across the ground.
  const
    CoreLife = 0.22'f
    Embers = 22
  let
    age = effect.elapsed
    life = clamp(age / effect.duration, 0.0'f, 1.0'f)
    center = effect.position + vec3(0, 0.34, 0)
  if age < CoreLife:
    let bloom = age / CoreLife
    renderer.addBillboard(center, 0.45'f + bloom * 1.55'f, eye,
      vec4(1.0, 0.56, 0.18, (1 - bloom) * 0.85'f), 4)
    renderer.addBillboard(center, 0.26'f + bloom * 0.78'f, eye,
      vec4(1.0, 0.95, 0.78, (1 - bloom) * 0.95'f), 4)
  for index in 0 ..< Embers:
    let
      angle = particleNoise(index, 17, effect.seed) * 2 * PI.float32
      speed = 1.9'f + particleNoise(index, 29, effect.seed) * 2.7'f
      rise = 1.7'f + particleNoise(index, 41, effect.seed) * 2.5'f
      course = vec3(cos(angle), 0, sin(angle)) * speed +
        vec3(0, rise - 9.5'f * age, 0)
      spark = center + vec3(cos(angle), 0, sin(angle)) * (speed * age) +
        vec3(0, rise * age - 4.75'f * age * age, 0)
    if spark.y <= effect.position.y:
      continue
    let fade = clamp(1 - age / (effect.duration * 0.85'f), 0.0'f, 1.0'f)
    renderer.addGlowLine(spark - course * 0.05'f, spark, eye, 0.022'f,
      vec4(1.0, 0.45'f + 0.35'f * fade, 0.16'f, fade * 0.9'f))
  let
    ring = 0.35'f + life * 2.6'f
    ringFade = clamp(1 - life * 1.5'f, 0.0'f, 1.0'f)
  if ringFade > 0.01'f:
    const Segments = 36
    for i in 0 ..< Segments:
      let
        a = i.float32 * 2 * PI.float32 / Segments
        b = (i + 1).float32 * 2 * PI.float32 / Segments
        ground = effect.position + vec3(0, 0.035, 0)
      renderer.addGlowLine(ground + vec3(cos(a), 0, sin(a)) * ring,
        ground + vec3(cos(b), 0, sin(b)) * ring, eye, 0.02'f,
        vec4(1.0, 0.6'f, 0.22'f, ringFade * 0.65'f))

proc addStab(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  ## A blade thrusts out of the dark, bites, and flicks back, leaving a
  ## bright slash across its target.
  const Thrust = 0.16'f
  let
    age = effect.elapsed
    center = effect.position + vec3(0, 0.42'f, 0)
    lean = particleNoise(0, 61, effect.seed) * 2 * PI.float32
    aside = vec3(cos(lean), 0, sin(lean))
    axes = facing(center, eye)
  if age < Thrust:
    # The thrust: a lean blade driving in from off to one side.
    let
      drive = age / Thrust
      tip = center + aside * (0.35'f - drive * 0.35'f)
      hilt = tip + aside * 0.95'f + vec3(0, 0.22'f, 0)
    renderer.addGlowLine(hilt, tip, eye, 0.028'f,
      vec4(0.86'f, 0.92'f, 1.0, 0.25'f + drive * 0.75'f))
    return
  let
    after = age - Thrust
    fade = clamp(1 - after / (effect.duration - Thrust), 0.0'f, 1.0'f)
    reach = 0.52'f * (0.4'f + fade * 0.6'f)
    slash = axes.right * reach + axes.up * reach * 0.75'f
  # The cut itself, and a spark where the blade bit.
  renderer.addGlowLine(center - slash, center + slash, eye, 0.03'f * fade,
    vec4(1.0, 0.96'f, 0.92'f, fade * 0.95'f))
  renderer.addBillboard(center, 0.22'f + (1 - fade) * 0.5'f, eye,
    vec4(0.9'f, 0.95'f, 1.0, fade * fade * 0.45'f), 4)

proc addPrize(renderer: var VfxRenderer, effect: ActiveVfx, eye: Vec3) =
  ## A gift changes hands: a gold ribbon ties a cross over the card, a bow
  ## blooms at the knot, then confetti bursts up and tumbles down.
  const
    Tie = 0.3'f
    Confetti = 34
    LoopSteps = 16
    Colors = [vec3(1.0, 0.8, 0.3), vec3(1.0, 0.36, 0.42),
      vec3(0.4, 0.78, 1.0), vec3(0.56, 1.0, 0.56), vec3(1.0, 0.96, 0.86)]
  let
    age = effect.elapsed
    life = clamp(age / effect.duration, 0.0'f, 1.0'f)
    fade = clamp((1 - life) / 0.35'f, 0.0'f, 1.0'f)
    knot = effect.position + vec3(0, 0.3, 0)
    axes = facing(knot, eye)
    tied = clamp(age / Tie, 0.0'f, 1.0'f)
    gold = vec4(1.0, 0.8'f, 0.3'f, fade * 0.95'f)
    across = axes.right * (0.62'f * tied)
    down = axes.up * (0.85'f * tied)
  # The ribbon, drawn out from the knot to the card's edges.
  renderer.addGlowLine(knot - across, knot + across, eye, 0.035'f, gold)
  renderer.addGlowLine(knot - down, knot + down, eye, 0.035'f, gold)
  if age < Tie:
    return
  let
    after = age - Tie
    bloom = clamp(after / 0.18'f, 0.0'f, 1.0'f)
  # The bow: a loop out to either side of the knot, and a tail below each.
  for side in [-1.0'f, 1.0'f]:
    let
      wide = axes.right * (side * 0.21'f * bloom)
      tall = axes.up * (0.12'f * bloom)
      middle = knot + wide + axes.up * (0.05'f * bloom)
    for k in 0 ..< LoopSteps:
      let
        a = k.float32 / LoopSteps * 2 * PI.float32
        b = (k + 1).float32 / LoopSteps * 2 * PI.float32
      renderer.addGlowLine(middle + wide * cos(a) + tall * sin(a),
        middle + wide * cos(b) + tall * sin(b), eye, 0.03'f, gold)
    renderer.addGlowLine(knot, knot + (axes.right * (side * 0.16'f) -
      axes.up * 0.34'f) * bloom, eye, 0.03'f, gold)
  renderer.addBillboard(knot, 0.12'f, eye,
    vec4(1.0, 0.95'f, 0.75'f, fade), 4)
  # Confetti on ballistic arcs, each fleck twinkling as it turns.
  for i in 0 ..< Confetti:
    let
      angle = particleNoise(i, 23, effect.seed) * 2 * PI.float32
      speed = 0.9'f + particleNoise(i, 37, effect.seed) * 1.6'f
      rise = 2.4'f + particleNoise(i, 53, effect.seed) * 2.0'f
      fleck = knot + vec3(cos(angle), 0, sin(angle)) * (speed * after) +
        vec3(0, rise * after - 3.6'f * after * after, 0)
      hue = Colors[i mod Colors.len]
      twinkle = 0.65'f + 0.35'f * abs(sin(after * 17 + i.float32))
    renderer.addBillboard(fleck, 0.07'f, eye,
      vec4(hue.x, hue.y, hue.z, fade * twinkle), 4)

proc addEffects*(renderer: var VfxRenderer, effects: openArray[ActiveVfx],
    eye: Vec3) =
  for effect in effects:
    case effect.kind
    of LightningVfx: renderer.addLightning(effect, eye)
    of BubbleVfx: renderer.addBubble(effect, eye)
    of ArrowVfx: renderer.addArrow(effect, eye)
    of ManyArrowsVfx: renderer.addArrowVolley(effect, eye)
    of SwordsIntoTheWindVfx: renderer.addSwordsIntoTheWind(effect, eye)
    of MightyShieldsVfx: renderer.addMightyShields(effect, eye)
    of SwordAndShieldVfx: renderer.addSwordAndShield(effect, eye)
    of MeleeVfx: renderer.addMelee(effect, eye)
    of SwordClashVfx: renderer.addSwordClash(effect, eye)
    of SwordBreakVfx: renderer.addSwordBreak(effect, eye)
    of OozeSplatVfx: renderer.addOozeSplat(effect, eye)
    of ExplosionVfx: renderer.addExplosion(effect, eye)
    of StabVfx: renderer.addStab(effect, eye)
    of PrizeVfx: renderer.addPrize(effect, eye)
    of DamageFlashVfx:
      let t = effect.elapsed / effect.duration
      renderer.addBillboard(effect.position, 1.2'f + t * 0.8'f, eye,
        vec4(1, 0.025, 0.05, (1 - t) * 0.38'f), 4)
    of NoVfx, DeathVfx, DrawVfx, SummonVfx, BounceVfx, TossVfx,
        HeroDeathVfx, LevelUpVfx, GainControlVfx: discard
