import
  polyworld/soundassets,
  ../[audios, sim]

echo "Successful local denies produce one cue for simultaneous deaths."
block:
  let world = World()
  var audio: RewardAudio
  audio.syncRewardAudio(world, 100)
  inc world.tick
  world.denyEffects = @[
    DenyEffect(heroId: 100, victimId: 1000),
    DenyEffect(heroId: 100, victimId: 1001),
    DenyEffect(heroId: 101, victimId: 1002)
  ]
  audio.queueRewardSounds(world, 100)
  audio.queueRewardSounds(world, 100)
  let events = audio.takeRewardSound(1)
  doAssert events.len == 1 and events[0].cue == DenySound
  doAssert not events[0].spatial
  doAssert audio.takeRewardSound(2).len == 0
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2).len == 0

echo "Deny feedback wins over gold and XP in either catch-up tick order."
block:
  for denyFirst in [false, true]:
    let world = World()
    var audio: RewardAudio
    audio.syncRewardAudio(world, 100)
    for tick in 1 .. 3:
      inc world.tick
      world.denyEffects.setLen(0)
      world.rewardEffects = @[
        RewardEffect(heroId: 100, victimId: 2000 + tick.int32,
          gold: 15, xp: 5)
      ]
      if (denyFirst and tick == 1) or (not denyFirst and tick == 3):
        world.denyEffects.add DenyEffect(heroId: 100, victimId: 1000)
      audio.queueRewardSounds(world, 100)
    let events = audio.takeRewardSound(1)
    doAssert events.len == 1 and events[0].cue == DenySound

echo "Other heroes, attack orders and nonlethal hits have no deny cue."
block:
  let world = World()
  var audio: RewardAudio
  audio.syncRewardAudio(world, 100)
  inc world.tick
  world.attackEffects = @[AttackEffect(sourceId: 100)]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(1).len == 0
  inc world.tick
  world.denyEffects = @[DenyEffect(heroId: 101, victimId: 1000)]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2).len == 0

echo "Deny, gold and XP share one cooldown without deferred playback."
block:
  let world = World()
  var audio: RewardAudio
  audio.syncRewardAudio(world, 100)
  inc world.tick
  world.denyEffects = @[DenyEffect(heroId: 100, victimId: 1000)]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(1)[0].cue == DenySound
  inc world.tick
  world.denyEffects.setLen(0)
  world.rewardEffects = @[RewardEffect(heroId: 100, gold: 15, xp: 5)]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(1.1).len == 0
  doAssert audio.takeRewardSound(2).len == 0
  inc world.tick
  world.denyEffects = @[DenyEffect(heroId: 100, victimId: 1001)]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2)[0].cue == DenySound

echo "Loads, seeks, muted frames and viewpoint changes discard old denies."
block:
  let world = World(
    denyEffects: @[DenyEffect(heroId: 100, victimId: 1000)]
  )
  var audio: RewardAudio
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(1).len == 0
  world.tick = 100
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 100, enabled = false)
  doAssert audio.takeRewardSound(3).len == 0
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(4).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(5, enabled = false).len == 0
  doAssert audio.takeRewardSound(6).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 101)
  doAssert audio.takeRewardSound(7).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(8).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 100)
  audio.syncRewardAudio(world, 100)
  doAssert audio.takeRewardSound(9).len == 0

echo "Deny feedback uses a bundled sound distinct from gold and XP."
block:
  var denyPath, goldPath, xpPath: string
  for clip in SoundClips:
    case clip.cue
    of DenySound: denyPath = clip.path
    of LastHitGoldSound: goldPath = clip.path
    of ExperienceSound: xpPath = clip.path
    else: discard
  doAssert denyPath.len > 0
  doAssert denyPath != goldPath and denyPath != xpPath
