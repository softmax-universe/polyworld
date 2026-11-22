## Match warnings use the client's applied simulation clock without a relay.
import
  polyworld/configs,
  ../[content, humancommunication, replays, sim]

proc clockGame(duration: int32, networked = false): Game =
  ## Builds the presentation state shared by live and replay clients.
  Game(world: World(maximumTicks: duration), maximumTicks: duration,
    networked: networked, replayData: ReplayData(config: GameConfig(
      maxTicks: duration, players: @[PlayerConfig(name: "Alice")])))

const Duration = 180 * TickRate + 4

block independentClocks:
  let games = [clockGame(Duration, true), clockGame(Duration, true)]
  var feeds: array[2, HumanCommunication]
  for tick in 0 .. 3:
    games[0].world.tick = int32(tick)
    feeds[0].syncChatFeed(games[0])
    doAssert feeds[0].feed.len == 0
  games[0].world.tick = 4
  feeds[0].syncChatFeed(games[0])
  feeds[1].syncChatFeed(games[1])
  doAssert feeds[0].feed.len == 1
  doAssert feeds[1].feed.len == 0, "A lagging client uses its own applied tick"
  let notice = feeds[0].feed[0]
  doAssert notice.localNotice and notice.player == -1
  doAssert notice.name == "Match" and notice.text == "3 minutes remain"
  for i in 0 .. 5:
    feeds[0].syncChatFeed(games[0])
  doAssert feeds[0].feed.len == 1, "Pause and reconnect redraws cannot repeat it"
  games[1].world.tick = 4
  feeds[1].syncChatFeed(games[1])
  doAssert feeds[1].feed == feeds[0].feed
  doAssert games[0].replayData.actions.len == 0
  echo "PASS independent applied clocks, local attribution and deduplication"

block replayAndNewMatch:
  let game = clockGame(Duration)
  game.replayMode = true
  game.historyPlayback = true
  game.replayData.actions = @[
    ReplayAction(kind: ActionChat, tick: 2, playerId: 0, target: -2, text: "before"),
    ReplayAction(kind: ActionChat, tick: 6, playerId: 0, target: -2, text: "after")
  ]
  let transcript = game.replayData.actions
  var feed: HumanCommunication
  game.world.tick = 7
  feed.syncChatFeed(game)
  doAssert feed.feed.len == 3
  doAssert feed.feed[0].text == "before"
  doAssert feed.feed[1].localNotice
  doAssert feed.feed[2].text == "after"
  game.world.tick = 3
  feed.syncChatFeed(game)
  doAssert feed.feed.len == 1 and feed.feed[0].text == "before"
  game.world.tick = 4
  feed.syncChatFeed(game)
  feed.syncChatFeed(game)
  doAssert feed.feed.len == 2 and feed.feed[1].localNotice
  doAssert game.replayData.actions == transcript, "The warning is never recorded"
  let fresh = clockGame(Duration)
  feed.syncChatFeed(fresh)
  doAssert feed.feed.len == 0
  fresh.world.tick = 4
  feed.syncChatFeed(fresh)
  doAssert feed.feed.len == 1
  echo "PASS replay ordering, rewind, forward seek and new-match reset"

block shortAndFinishedGames:
  for duration in [0'i32, 1'i32, 180 * TickRate]:
    let game = clockGame(duration)
    game.world.tick = duration
    game.world.over = true
    var feed: HumanCommunication
    feed.syncChatFeed(game)
    doAssert feed.feed.len == 0
  let game = clockGame(Duration)
  game.world.tick = 3
  game.world.over = true
  var feed: HumanCommunication
  feed.syncChatFeed(game)
  doAssert feed.feed.len == 0, "An early finish cannot cross the warning tick"
  echo "PASS short matches and early completion"

block boundedFeed:
  let game = clockGame(Duration)
  for index in 0 ..< MaxHumanChatLines + 5:
    game.replayData.actions.add ReplayAction(kind: ActionChat, tick: uint32(index + 5),
      playerId: 0, target: -2, text: "later " & $index)
  game.world.tick = MaxHumanChatLines + 10
  var feed: HumanCommunication
  feed.syncChatFeed(game)
  doAssert feed.feed.len == MaxHumanChatLines
  for line in feed.feed:
    doAssert not line.localNotice, "Old warnings age out like other feed lines"
  feed.syncChatFeed(game)
  doAssert feed.feed.len == MaxHumanChatLines
  echo "PASS bounded feed never reinserts an aged-out warning"
