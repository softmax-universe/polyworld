import ../[aiming, maps, sim]

echo "Missed clicks choose the nearest living visible target of the right team."
let
  world = World()
  enemy = Hero(id: 100, team: BlueTeam, hp: 100,
    position: WorldPoint(x: WorldScale))
  ally = Hero(id: 101, team: RedTeam, hp: 100,
    position: WorldPoint(x: WorldScale div 2))
world.heroes = @[enemy, ally]
for team in Team:
  world.teamVisible[team.ord] = newSeq[uint8](mapTiles() * mapTiles())
  for cell in world.teamVisible[team.ord].mitems:
    cell = 255
doAssert world.nearbyTarget(RedTeam, WorldPoint()) == enemy.id
doAssert world.nearbyTarget(RedTeam, WorldPoint(), healing = true) == ally.id
enemy.position.x = 2 * WorldScale
doAssert world.nearbyTarget(RedTeam, WorldPoint()) == enemy.id
inc enemy.position.x
doAssert world.nearbyTarget(RedTeam, WorldPoint()) == 0
enemy.position.x = WorldScale
enemy.hp = 0
doAssert world.nearbyTarget(RedTeam, WorldPoint()) == 0
enemy.hp = 100
for cell in world.teamVisible[RedTeam.ord].mitems:
  cell = 0
doAssert world.nearbyTarget(RedTeam, WorldPoint()) == 0
echo "Nearby click checks passed."

echo "Deny aiming includes allied creeps only for an explicit attack gesture."
block:
  let
    world = World()
    hero = Hero(id: 100, team: RedTeam, hp: 100)
  world.heroes = @[hero]
  world.footmen = @[
    Footman(id: 1000, team: RedTeam, hp: 1,
      position: WorldPoint(x: WorldScale div 2)),
    Footman(id: 1001, team: BlueTeam, hp: 100,
      position: WorldPoint(x: WorldScale))
  ]
  world.footmen[0].hp = world.footmen[0].unitMaxHp div 2 - 1
  for team in Team:
    world.teamVisible[team.ord] = newSeq[uint8](mapTiles() * mapTiles())
    for cell in world.teamVisible[team.ord].mitems:
      cell = 255
  doAssert world.nearbyTarget(RedTeam, WorldPoint()) == 1001
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    denyingHeroId = hero.id) == 1000
  inc world.footmen[0].hp
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    denyingHeroId = hero.id) == 1001
  dec world.footmen[0].hp
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    healing = true, denyingHeroId = hero.id) == hero.id
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    denyingHeroId = 999) == 1001
  hero.hp = 0
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    denyingHeroId = hero.id) == 1001
  hero.hp = 100
  for cell in world.teamVisible[RedTeam.ord].mitems:
    cell = 0
  doAssert world.nearbyTarget(RedTeam, WorldPoint(),
    denyingHeroId = hero.id) == 0
echo "Deny aiming checks passed."
