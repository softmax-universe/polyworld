## Captures the real arena renderer from a team's unexplored enemy base.
import
  std/os,
  windy,
  polyworld/menus,
  ../[content, game, graphics, maps, sim]

const
  GameRoot = currentSourcePath().parentDir.parentDir
  OutputRoot = GameRoot.parentDir.parentDir / "output"

createDir(OutputRoot)
options = parseGameOptions(@[
  "--player", "1", "--bot", GameRoot / "players/base.bas" & ":9",
  "--play", "false", "--mute", "--windowSize", "1600x1000",
  "--screenshot", getEnv("GOTA_STRUCTURE_PREVIEW",
    OutputRoot / "gota-structures-fog.png"), "--frames", "2"
])
configureSoundLaunch(true, true)
localPlayerName = "Structure preview"
initializeMatch()
for class in HeroClass:
  doAssert run.world.applyDraft(run.world.draftHeroId(), class.ord.int32)
doAssert run.world.phase == Playing
let observer = run.world.heroes[0].team
var hiddenTowers, hiddenBarracks: int
var destroyed = false
for building in run.world.buildings.mitems:
  if building.team == observer:
    continue
  doAssert not run.world.visible(observer, building.position)
  let
    x = (building.position.x div WorldScale).int + mapTiles() div 2
    z = (building.position.z div WorldScale).int + mapTiles() div 2
  doAssert run.world.teamExplored[observer.ord][z * mapTiles() + x] == 0
  case building.kind
  of TowerBuilding: inc hiddenTowers
  of BarracksBuilding: inc hiddenBarracks
  echo building.kind, " ", building.tier, " id=", building.id,
    " x=", building.position.x.float32 / WorldScale.float32,
    " z=", building.position.z.float32 / WorldScale.float32
  if not destroyed and building.kind == TowerBuilding and
    building.tier == GateTower and building.lane == 1 and
    not building.guardsGod and
    getEnv("GOTA_STRUCTURE_PREVIEW_DEAD", "1") == "1":
      building.hp = 0
      destroyed = true
run.world.syncBuildings()
doAssert hiddenTowers > 0 and hiddenBarracks > 0
if not existsEnv("CAM_X"):
  putEnv("CAM_X", "-38")
if not existsEnv("CAM_Z"):
  putEnv("CAM_Z", "37")
if not existsEnv("CAM_DIST"):
  putEnv("CAM_DIST", "14")
echo "Unexplored enemy towers=", hiddenTowers,
  " barracks=", hiddenBarracks, "; local observer=", observer
runGraphics()
releaseGotaCapture()
window.close()
