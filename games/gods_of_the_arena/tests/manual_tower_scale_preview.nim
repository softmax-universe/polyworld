## Captures the large tower and health bar at the normal player camera distance.
import
  std/os,
  windy,
  polyworld/menus,
  ../[content, game, graphics, sim]

const
  GameRoot = currentSourcePath().parentDir.parentDir
  OutputRoot = GameRoot.parentDir.parentDir / "output"

createDir(OutputRoot)
options = parseGameOptions(@[
  "--player", "1", "--bot", GameRoot / "players/base.bas" & ":9",
  "--play", "false", "--mute", "--windowSize", "1600x1000",
  "--screenshot", getEnv("GOTA_TOWER_PREVIEW",
    OutputRoot / "gota-tower-scale.png"), "--frames", "2"
])
configureSoundLaunch(true, true)
localPlayerName = "Tower scale"
initializeMatch()
for class in HeroClass:
  doAssert run.world.applyDraft(run.world.draftHeroId(), class.ord.int32)
doAssert run.world.phase == Playing
let hero = run.world.heroes[0]
var found = false
for building in run.world.buildings.mitems:
  if building.team == hero.team and building.kind == TowerBuilding and
    building.tier == GateTower and building.lane == 1 and
    not building.guardsGod:
      hero.position = building.position
      hero.position.x -= 3 * WorldScale
      hero.position.z -= WorldScale
      building.hp = building.maxHp * 3 div 4
      putEnv("CAM_X", $(building.position.x.float32 / WorldScale.float32))
      putEnv("CAM_Z", $(building.position.z.float32 / WorldScale.float32))
      found = true
      break
doAssert found
delEnv("CAM_DIST")
runGraphics()
releaseGotaCapture()
window.close()
