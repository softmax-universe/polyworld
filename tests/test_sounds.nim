import
  vmath,
  polyworld/sounds

echo "Testing combat bursts preserve order feedback"
block:
  var gate: SoundGate
  let combat = [SwordSound, ImpactSound, BowSound, MagicSound,
    FireSound, HealSound]
  for cue in combat:
    doAssert gate.acceptSound(cue, 1.0)
  doAssert not gate.acceptSound(HumanDeathSound, 1.01)
  doAssert gate.acceptSound(MoveOrderSound, 1.01)
  doAssert gate.acceptSound(DaybreakSound, 1.01)
  doAssert gate.acceptSound(NightfallSound, 1.01)
  doAssert not gate.acceptSound(MoveOrderSound, 1.02)
  doAssert gate.acceptSound(HumanDeathSound, 1.11)
  doAssert gate.acceptSound(MoveOrderSound, 1.20)

echo "Testing repeated events and replay time resets"
block:
  var gate: SoundGate
  doAssert gate.acceptSound(VictorySound, 10)
  doAssert not gate.acceptSound(VictorySound, 10.5)
  doAssert gate.acceptSound(VictorySound, 12.01)
  gate = SoundGate()
  doAssert gate.acceptSound(VictorySound, 0)

echo "Testing busy workers preserve combat and construction feedback"
block:
  var gate: SoundGate
  doAssert gate.acceptSound(ChopSound, 1.0)
  doAssert gate.acceptSound(MineSound, 1.0)
  doAssert not gate.acceptSound(DeliverWoodSound, 1.01)
  doAssert not gate.acceptSound(ChopSound, 1.1)
  doAssert gate.acceptSound(BuildStartSound, 1.01)
  doAssert gate.acceptSound(SwordSound, 1.01)
  doAssert gate.acceptSound(MoveOrderSound, 1.01)
  doAssert gate.acceptSound(DeliverWoodSound, 1.26)
  doAssert gate.acceptSound(DeliverGoldSound, 1.26)
  doAssert not gate.acceptSound(MineSound, 1.5)
  doAssert gate.acceptSound(MineSound, 1.61)
  doAssert gate.acceptSound(ChopSound, 0.0),
    "A restarted presentation clock must reset the worker burst window"

echo "Testing positional falloff and pan"
block:
  let
    center = spatialSoundMix(vec3(0), vec3(0), 20)
    east = spatialSoundMix(vec3(10, 0, 0), vec3(0), 20)
    west = spatialSoundMix(vec3(-10, 0, 0), vec3(0), 20)
    distant = spatialSoundMix(vec3(0, 0, 21), vec3(0), 20)
  doAssert center.gain == 1 and center.pan == 0
  doAssert east.gain == west.gain and east.gain < center.gain
  doAssert east.pan > 0 and west.pan < 0
  doAssert distant.gain == 0
  doAssert spatialSoundMix(vec3(0), vec3(0), 0).gain == 0

echo "Testing cue routing"
for cue in [ClickSound, SelectSound, MoveOrderSound, AttackOrderSound,
    PurchaseSound, ErrorSound, ReadySound, VictorySound, DefeatSound,
    DaybreakSound, NightfallSound, HoverSound]:
  doAssert cue.isInterfaceSound
for cue in [SwordSound, ImpactSound, BowSound, MagicSound, FireSound,
    HealSound, HumanDeathSound, CreatureDeathSound, BuildingDeathSound,
    ChopSound, MineSound, DeliverWoodSound, DeliverGoldSound,
    BuildPlaceSound, BuildStartSound]:
  doAssert not cue.isInterfaceSound
