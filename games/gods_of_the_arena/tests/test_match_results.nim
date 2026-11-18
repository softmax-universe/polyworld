import vmath
import ../[content, matchresults, sim]

proc fixture(): Game =
  ## Builds only the state read by result classification.
  result = Game(world: World(phase: Playing, heroes: @[
    Hero(id: 101, team: RedTeam), Hero(id: 105, team: BlueTeam)
  ]))
  result.replayData.config.maxTicks = 600 * TickRate

let game = fixture()
doAssert not game.matchResult(101).finished
game.world.phase = Drafting
game.world.tick = 700 * TickRate
doAssert not game.matchResult(101).finished
game.world.phase = Playing
game.world.draftTicks = 60 * TickRate
game.world.preparationTicks = PreparationTicks
game.world.tick = 600 * TickRate
doAssert not game.matchResult(101).finished,
  "Drafting and preparation must not consume the battle time budget"
game.world.tick = game.config.maxTicks + game.world.draftTicks + PreparationTicks
let timeout = game.matchResult(101)
doAssert not game.world.gameOver and not game.world.draw
doAssert timeout.finished and timeout.outcome == MatchDraw
doAssert timeout.title == "DRAW" and timeout.duration == "10:00"
doAssert timeout.detail == "Time limit reached. Neither side claimed victory."
doAssert timeout.ownTeam == RedTeam.ord and timeout.winner == -1
for winner in Team:
  game.world.gameOver = true
  game.world.winner = winner
  for id in [101'i32, 105]:
    let summary = game.matchResult(id)
    doAssert summary.finished
    doAssert summary.outcome ==
      (if summary.ownTeam == winner.ord: MatchVictory else: MatchDefeat)
    doAssert summary.title ==
      (if summary.ownTeam == winner.ord: "VICTORY" else: "DEFEAT")
  doAssert game.matchResult().outcome == MatchTeamVictory
  doAssert game.matchResult().title ==
    (if winner == RedTeam: "RED TEAM WINS" else: "BLUE TEAM WINS")
game.world.draw = true
doAssert game.matchResult(101).outcome == MatchDraw
doAssert game.matchResult(105).outcome == MatchDraw
doAssert game.matchResult().outcome == MatchDraw
doAssert game.matchResult().detail == "Both gods fell. Neither side claimed victory."
for size in [vec2(640, 480), vec2(1280, 720), vec2(1600, 1000), vec2(3840, 2160)]:
  let
    scale = resultScale(size, 1.5)
    panel = ResultPanelSize * scale
  doAssert panel.x <= size.x - 31 and panel.y <= size.y - 31
echo "PASS results: timeout, preparation, victory/defeat perspectives, draws and viewport fit"
