## Native production HUD selection/ownership and inspection regressions.
include ../ui

run = Game(world: World(phase: Playing, heroes: @[
  Hero(id: 104, team: RedTeam, slot: 3, class: VanguardKnight),
  Hero(id: 109, team: BlueTeam, slot: 4, class: VanguardKnight)]))
options.playerSlot = 1
var primary = 104'i32
var picked = @[104'i32]
var follow = true
selectHeroCard(primary, picked, follow, 109, false)
doAssert primary == 109 and picked == @[109'i32]
doAssert not follow, "Human ribbon inspection must release selection follow"
run.replayMode = true
selectHeroCard(primary, picked, follow, 104, false)
doAssert follow, "Replay ribbon selection must retain follow"
echo "PASS human inspection ribbon and replay follow"

run.replayMode = false
var director = ActionCam(enabled: true, locked: true, lockId: 109)
doAssert hudDetailId(109, director) == 104,
  "Permanent abilities/details must use the own packed hero, not inspection/director"
run.replayMode = true
doAssert hudDetailId(104, director) == 109
run.replayMode = false
options.playerSlot = 9
doAssert localHudHeroId() == 0
options.playerSlot = 1
let saved = run
run = nil
doAssert localHudHeroId() == 0
run = Game()
doAssert localHudHeroId() == 0
run = saved
echo "PASS own packed detail identity, director/replay and sparse/nil guards"

run.world.heroes[1].hp = 321
run.world.heroes[1].maxHp = 700
run.world.heroes[1].mana = 42
run.world.heroes[1].maxMana = 90
run.world.heroes[1].xp = 180
# Sparse config is allowed; actual names come from packed config when present.
run.replayData.config.players.setLen(2)
run.replayData.config.players[1].name = "mason :)"
run.world.teamVisible[RedTeam.ord] = newSeq[uint8](mapTiles() * mapTiles())
for cell in run.world.teamVisible[RedTeam.ord].mitems: cell = 255
let info = inspectionInfo(109, 0)
doAssert info.id == 109 and info.name == "mason :)"
doAssert "Lv " in info.title and info.hp == "HP 321 / 700"
doAssert info.mana == "Mana 42 / 90"
doAssert inspectionInfo(104, 0).id == 0
# Human inspection always uses human sight even if the external mode is omniscient.
run.world.teamVisible[RedTeam.ord].setLen(0)
doAssert inspectionInfo(109, 0).id == 0,
  "Unseen enemy must not leak through omniscient input mode"
run.world.heroes[1].team = RedTeam
run.world.heroes[1].state = Dying
doAssert inspectionInfo(109, 0).id == 0, "Dead inspected units retire immediately"
run.world.footmen = @[Footman(id: 201, team: RedTeam, hp: 80, state: Marching)]
let creepInfo = inspectionInfo(201, 0)
doAssert creepInfo.id == 201 and creepInfo.mana.len == 0
doAssert "Lv" notin creepInfo.title and creepInfo.hp.startsWith("HP 80 / ")
run.networked = false
doAssert not transportAvailable(), "Local human play must not reserve an invisible replay footer"
run.replayMode = true
doAssert transportAvailable()
run.replayMode = false
options.playerSlot = 0
doAssert transportAvailable(), "Local watch retains playback controls"
echo "PASS current sight, unit kind/no mana, dead inspection, local human/watch footer"

options.playerSlot = 1
run.world.heroes[0].inventory[0] = RangerBoots
let ownSelection = selectedUnit(hudDetailId(109, director), 0)
doAssert ownSelection.id == 104 and ownSelection.inventory[0] == RangerBoots
doAssert ownSelection.abilities == HeroSpecs[VanguardKnight].abilities
# Production ability tooltip route must continue to use the same bound details selection.
let source = readFile("games/gods_of_the_arena/ui.nim")
doAssert "let detailId = hudDetailId(primaryId, actionCam)" in source
doAssert "abilityDetails(ability, selection.abilityLevels[slot])" in source
let beforeNil = run
run = nil
doAssert selectedUnit(1, 0).id == 0
run = Game(world: World(phase: Playing, heroes: @[Hero(nil)]))
doAssert localHudHeroId() == 0 and selectedUnit(1, 0).id == 0
run = beforeNil
options.playerSlot = 9
run.replayMode = false
# Out-of-range packed slot must never claim ownership of an arbitrary inspection.
doAssert localHudHeroId() == 0
options.playerSlot = 1
run.world.heroes[0].hp = 80
run.world.heroes[0].maxHp = 100
doAssert hudSelection(109, director, 2).id == 104,
  "Own hero details stay visible even with an externally switched view mode"
