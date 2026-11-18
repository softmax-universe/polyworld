import
  polyworld/soundassets,
  ../[audios, sim]

echo "Simultaneous rewards play one personal gold-first cue."
block:
  let world = World()
  var audio: RewardAudio
  audio.syncRewardAudio(world, 100)
  inc world.tick
  world.rewardEffects = @[
    RewardEffect(heroId: 100, victimId: 1000, xp: 5),
    RewardEffect(heroId: 100, victimId: 1001, gold: 10, xp: 5),
    RewardEffect(heroId: 100, victimId: 1002, gold: 10, xp: 5),
    RewardEffect(heroId: 101, victimId: 1003, gold: 100)
  ]
  audio.queueRewardSounds(world, 100)
  audio.queueRewardSounds(world, 100)
  let events = audio.takeRewardSound(1)
  doAssert events.len == 1 and events[0].cue == LastHitGoldSound
  doAssert not events[0].spatial
  doAssert audio.takeRewardSound(1).len == 0
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2).len == 0

  inc world.tick
  world.rewardEffects = @[
    RewardEffect(heroId: 100, victimId: 1004, xp: 5),
    RewardEffect(heroId: 101, victimId: 1004, gold: 10),
    RewardEffect(heroId: 100, victimId: 1005, xp: 3)
  ]
  audio.queueRewardSounds(world, 100)
  let experience = audio.takeRewardSound(2)
  doAssert experience.len == 1 and experience[0].cue == ExperienceSound

  inc world.tick
  world.rewardEffects = @[
    RewardEffect(heroId: 101, victimId: 1006, gold: 10, xp: 5),
    RewardEffect(heroId: 100, victimId: 1006)
  ]
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(3).len == 0

echo "Catch-up ticks share one frame batch with gold priority in either order."
block:
  for goldFirst in [false, true]:
    let world = World()
    var audio: RewardAudio
    audio.syncRewardAudio(world, 100)
    for tick in 1 .. 4:
      inc world.tick
      world.rewardEffects = @[
        RewardEffect(
          heroId: 100,
          victimId: 1000 + tick.int32,
          xp: 5,
          gold: if (tick == 1 and goldFirst) or
            (tick == 4 and not goldFirst): 10 else: 0
        )
      ]
      audio.queueRewardSounds(world, 100)
    let events = audio.takeRewardSound(1)
    doAssert events.len == 1 and events[0].cue == LastHitGoldSound
    doAssert audio.takeRewardSound(1).len == 0

echo "Gold and XP share a cooldown without leaving deferred reward sounds."
block:
  let world = World()
  var audio: RewardAudio
  audio.syncRewardAudio(world, 100)
  for (time, gold, expected) in [
      (1.0, 10, 1), (1.05, 0, 0), (1.10, 10, 0),
      (1.21, 0, 1), (1.25, 10, 0)]:
    inc world.tick
    world.rewardEffects = @[
      RewardEffect(heroId: 100, victimId: world.tick, xp: 5, gold: gold)
    ]
    audio.queueRewardSounds(world, 100)
    doAssert audio.takeRewardSound(time).len == expected
  doAssert audio.takeRewardSound(10).len == 0

echo "Loads, seeks, muted frames and perspective changes never replay rewards."
block:
  let world = World(rewardEffects: @[
    RewardEffect(heroId: 100, victimId: 1000, gold: 10, xp: 5)
  ])
  var audio: RewardAudio
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(1).len == 0
  world.tick = 100
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(2).len == 0
  world.tick = 50
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(3).len == 0
  inc world.tick
  audio.queueRewardSounds(world, 100, enabled = false)
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(4).len == 0

  inc world.tick
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(5, enabled = false).len == 0
  doAssert audio.takeRewardSound(6).len == 0

  inc world.tick
  audio.queueRewardSounds(world, 100)
  audio.queueRewardSounds(world, 100, enabled = false)
  doAssert audio.takeRewardSound(7).len == 0

  inc world.tick
  audio.queueRewardSounds(world, 100)
  audio.syncRewardAudio(world, 100)
  doAssert audio.takeRewardSound(8).len == 0

  inc world.tick
  audio.queueRewardSounds(world, 101)
  audio.queueRewardSounds(world, 100)
  doAssert audio.takeRewardSound(9).len == 0

  let replacement = World(tick: world.tick + 1,
    rewardEffects: world.rewardEffects)
  audio.queueRewardSounds(replacement, 100)
  doAssert audio.takeRewardSound(10).len == 0
  inc replacement.tick
  audio.queueRewardSounds(replacement, 0)
  doAssert audio.takeRewardSound(11).len == 0

echo "Reward audio checks passed."
