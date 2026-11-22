## Automatic Cleric healing runs through the real world tick, not UI commands.
import ../[content, maps, sim]

proc noDecisions(w: World) = discard
proc fixture(): World =
  result = newWorld(generateMap(DefaultSeed), TickRate * 120)
proc at(w: World, x, y: int32): Tile2 =
  tile2(w.map.side div 2 + x, w.map.side div 2 + y)
proc spawn(w: World, kind: UnitKind, x, y: int32, owner = 0'i32): Unit =
  let id = w.spawnUnit(owner, kind, w.at(x, y))
  w.units[w.unitIndex(id)]

block automaticHealing:
  let w = fixture()
  discard w.spawn(ClericUnit, 0, 0)
  let patient = w.spawn(SoldierUnit, 1, 0)
  patient.hp -= 20
  let hp = patient.hp
  w.tickWorld(noDecisions)
  doAssert patient.hp > hp, "a nearby damaged friendly must actually gain HP"
block cooldownAndRegeneration:
  let w = fixture()
  let cleric = w.spawn(ClericUnit, 0, 0)
  let patient = w.spawn(KnightUnit, 1, 0)
  patient.hp = 1
  doAssert cleric.mana == ClericMaxMana
  w.tickWorld(noDecisions)
  doAssert patient.hp == 1 + ClericHealAmount
  doAssert cleric.mana == ClericMaxMana - ClericHealManaCost
  for _ in 1 ..< ClericHealCooldown: w.tickWorld(noDecisions)
  doAssert patient.hp == 1 + ClericHealAmount
  w.tickWorld(noDecisions)
  doAssert patient.hp == 1 + 2 * ClericHealAmount
  doAssert cleric.mana == ClericMaxMana - 2 * ClericHealManaCost + 1
  cleric.mana = 0
  cleric.manaRegenTicks = 0
  cleric.healCooldown = 0
  let hp = patient.hp
  for _ in 1 ..< ClericHealManaCost * ClericManaRegenTicks:
    w.tickWorld(noDecisions)
  doAssert patient.hp == hp, "no free healing without mana"
  w.tickWorld(noDecisions)
  doAssert patient.hp == hp + ClericHealAmount
  doAssert cleric.mana == 0

block lowestRatioThenId:
  let w = fixture()
  let cleric = w.spawn(ClericUnit, 0, 0)
  let first = w.spawn(KnightUnit, 1, 0)
  let second = w.spawn(SoldierUnit, 0, 1)
  first.hp = 45 # 50%, despite more absolute HP
  second.hp = 36 # 60%
  w.tickWorld(noDecisions)
  doAssert first.hp == 45 + ClericHealAmount and second.hp == 36
  first.hp = 45
  second.hp = 30 # same ratio, earlier ID wins
  cleric.healCooldown = 0
  w.tickWorld(noDecisions)
  doAssert first.hp == 45 + ClericHealAmount and second.hp == 30

block alliedNotNeutralOrEnemy:
  for relation in [Neutral, AtWar, Allied, AllianceEnding]:
    let w = fixture()
    w.diplomacy.pairs[0].state = relation
    w.diplomacy.pairs[0].deadline = 1000
    let cleric = w.spawn(ClericUnit, 0, 0)
    let patient = w.spawn(SoldierUnit, 3, 0, 1)
    patient.hp = 10
    patient.holdPosition = true
    cleric.holdPosition = true
    w.tickWorld(noDecisions)
    doAssert patient.hp == (if relation in {Allied, AllianceEnding}: 18 else: 10)

block eligibilityAndNoWaste:
  let w = fixture()
  let cleric = w.spawn(ClericUnit, 0, 0)
  let machine = w.spawn(CatapultUnit, 1, 0)
  let corpse = w.spawn(SoldierUnit, 0, 1)
  let hidden = w.spawn(PeonUnit, -1, 0)
  let distant = w.spawn(SoldierUnit, ClericHealRange + 1, 0)
  machine.hp = 1
  corpse.hp = 0
  corpse.state = UnitDying
  corpse.deathTicks = 100
  hidden.hp = 1
  hidden.state = UnitInMine
  hidden.stateTicks = 100
  distant.hp = 1
  w.buildings[0].hp -= 10
  let buildingHp = w.buildings[0].hp
  w.tickWorld(noDecisions)
  doAssert machine.hp == 1 and corpse.hp == 0 and hidden.hp == 1 and distant.hp == 1
  doAssert w.buildings[0].hp == buildingHp
  doAssert cleric.mana == ClericMaxMana and cleric.healCooldown == 0
  let patient = w.spawn(SoldierUnit, 0, -1)
  patient.hp -= 1
  w.tickWorld(noDecisions)
  doAssert patient.hp == unitOf(0, SoldierUnit).hp
  doAssert cleric.mana == ClericMaxMana - ClericHealManaCost

block selfHealAndDeath:
  let w = fixture()
  let cleric = w.spawn(ClericUnit, 0, 0)
  cleric.hp -= 10
  w.tickWorld(noDecisions)
  doAssert cleric.hp == unitOf(0, ClericUnit).hp - 2
  cleric.hp = 0
  cleric.state = UnitDying
  cleric.deathTicks = 100
  let patient = w.spawn(SoldierUnit, 1, 0)
  patient.hp = 1
  let mana = cleric.mana
  for _ in 0 ..< ClericHealCooldown + 1: w.tickWorld(noDecisions)
  doAssert patient.hp == 1 and cleric.mana == mana

block multipleClericsDoNotWasteOrOverheal:
  let w = fixture()
  let first = w.spawn(ClericUnit, 0, 0)
  let second = w.spawn(ClericUnit, 0, 1)
  let patient = w.spawn(SoldierUnit, ClericHealRange, 0)
  patient.hp -= 1
  w.tickWorld(noDecisions)
  doAssert patient.hp == unitOf(0, SoldierUnit).hp
  doAssert first.mana == ClericMaxMana - ClericHealManaCost
  doAssert second.mana == ClericMaxMana and second.healCooldown == 0

block manaCapAndHashClone:
  let w = fixture()
  let cleric = w.spawn(ClericUnit, 0, 0)
  cleric.mana -= 1
  for _ in 0 ..< ClericManaRegenTicks * 2: w.tickWorld(noDecisions)
  doAssert cleric.mana == ClericMaxMana and cleric.manaRegenTicks == 0
  let before = Game(world: w).stateHash()
  for field in 0 .. 2:
    let copy = w.clone()
    let other = copy.units[copy.unitIndex(cleric.id)]
    case field
    of 0: dec other.mana
    of 1: inc other.manaRegenTicks
    else: inc other.healCooldown
    doAssert Game(world: copy).stateHash() != before
    doAssert Game(world: w).stateHash() == before
    copy.restore(w)
    doAssert Game(world: copy).stateHash() == before
  let copy = w.clone()
  for _ in 0 ..< TickRate * 3:
    w.tickWorld(noDecisions)
    copy.tickWorld(noDecisions)
    doAssert Game(world: w).stateHash() == Game(world: copy).stateHash()
echo "Cleric heal, ratio/ID, alliance, exclusions, cooldown, mana, clone/hash passed"
