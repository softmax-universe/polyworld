## Team colors and winner labels follow authoritative assignments.

import
  std/strutils,
  ../[content, diplomacies, factions, game, multiplayer, presets, sim,
    teamlooks, ui]

block appearances:
  let
    settings = DiplomacySettings(teams: @[0'i32, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1, 0])
    order = factionOrder(47)
    looks = playerFactions(47, settings, settings.teams.len)
  for player, team in settings.teams:
    doAssert looks[player] == order[Faction(team)]
  doAssert looks[8] != looks[0]
  doAssert looks[11] == looks[0]
  var negotiated = settings
  negotiated.enabled = true
  let individualLooks = playerFactions(47, negotiated, settings.teams.len)
  for player, look in individualLooks:
    doAssert look == order[Faction(player mod FactionFiles.len)]
  run = Game(world: World(diplomacy: initDiplomacy(settings.teams.len, settings)))
  for player, team in settings.teams:
    doAssert buildingPortraitKey(player.int32, TownHallBuilding) ==
      buildingPortraitSlotKey(team, TownHallBuilding)
  doAssert buildingPortraitKey(8, TownHallBuilding) !=
    buildingPortraitKey(0, TownHallBuilding)
  doAssert buildingPortraitKey(11, TownHallBuilding) ==
    buildingPortraitKey(0, TownHallBuilding)
  doAssert buildingPortraitKey(-1, GoldMineBuilding) == "lvd_b_mine"
  run = nil

block sparseTeam:
  let
    settings = DiplomacySettings(teams: @[7'i32, 7])
    looks = playerFactions(2026, settings, 2)
  doAssert looks[0] == looks[1]
  doAssert settings.teamLabel(0) == "Team 8"
  run = Game(world: World(diplomacy: initDiplomacy(2, settings)))
  doAssert buildingPortraitKey(0, FarmBuilding) ==
    buildingPortraitSlotKey(7, FarmBuilding)
  run = nil

block results:
  var config = defaultConfig(4)
  config.diplomacySettings.teams = @[0'i32, 1, 0, 1]
  config.players[0].name = "First commander"
  run = newLocalMatch(config, ["", "", "", ""])
  run.world.over = true
  run.world.winner = 0
  run.world.players[2].defeated = true
  doAssert matchResultHeadline() == "Team 1 wins"
  doAssert describeResult().startsWith("Team 1 wins (score ")
  doAssert currentStatsOptions().headline == "Team 1"
  doAssert currentStatsOptions().individualPlayers
  let table = currentStats()
  doAssert table.rows[0].team == table.rows[2].team
  doAssert table.rows[0].subtitle == "Team 1"
  doAssert table.rows[1].subtitle == "Team 2"
  doAssert table.winner == 0
  run.world.diplomacy.settings.enabled = true
  doAssert matchResultHeadline() == "First commander wins"
  run.world.diplomacy.settings.enabled = false
  run.world.diplomacy.settings.teams = @[]
  doAssert matchResultHeadline() == "First commander wins"
  run.world.winner = -1
  doAssert matchResultHeadline() == "Draw"
  run = nil

echo "Team appearance, portrait, and result presentation passed"
