import
  std/strutils,
  chroma, pixie, silky, vmath, windy,
  polyworld/[assets, chrome, gameuis],
  content, sim

const
  ResultPanelSize* = vec2(760, 520)
  ResultGold = rgbx(239, 213, 151, 255)
  ResultInk = rgbx(239, 235, 222, 255)
  ResultMuted = rgbx(172, 170, 157, 255)
  TeamInk = [rgbx(237, 119, 106, 255), rgbx(116, 183, 237, 255)]

type
  MatchOutcome* = enum
    MatchPending, MatchVictory, MatchDefeat, MatchDraw, MatchTeamVictory
  MatchResult* = object
    finished*: bool
    outcome*: MatchOutcome
    title*, detail*, duration*: string
    ownTeam*, winner*: int
    kills*: array[2, int]

proc matchResult*(game: Game, heroId = 0'i32): MatchResult =
  ## Classifies the final simulation state, including time-limit draws.
  result.ownTeam = -1
  result.winner = -1
  if game == nil or game.world == nil or not game.finished():
    return
  let world = game.world
  result.finished = true
  result.kills = world.teamHeroKills
  for hero in world.heroes:
    if hero.id == heroId and heroId != 0:
      result.ownTeam = hero.team.ord
      break
  var ticks = max(0'i32, world.battleTick())
  if game.maximumTicks() > 0:
    ticks = min(ticks, game.maximumTicks())
  let seconds = ticks div TickRate
  result.duration = $(seconds div 60) & ":" &
    align($(seconds mod 60), 2, '0')
  if world.draw or not world.gameOver:
    result.outcome = MatchDraw
    result.title = "DRAW"
    result.detail =
      if world.gameOver:
        "Both gods fell. Neither side claimed victory."
      else:
        "Time limit reached. Neither side claimed victory."
  else:
    result.winner = world.winner.ord
    if result.ownTeam < 0:
      result.outcome = MatchTeamVictory
      result.title =
        if world.winner == RedTeam: "RED TEAM WINS"
        else: "BLUE TEAM WINS"
      result.detail = "The opposing god has fallen."
    elif result.ownTeam == result.winner:
      result.outcome = MatchVictory
      result.title = "VICTORY"
      result.detail = "Your team has defeated the enemy god."
    else:
      result.outcome = MatchDefeat
      result.title = "DEFEAT"
      result.detail = "Your god has fallen. The enemy team wins."

proc addResultFonts*(builder: AtlasBuilder) =
  ## Adds the prominent result title and compact final-score numerals.
  builder.addFont(BoldFontPath, "ResultTitle", 64)
  builder.addFont(BoldFontPath, "ResultNumber", 38)

proc resultScale*(size: Vec2, preferred: float32): float32 =
  ## Keeps the complete result card inside even a small game viewport.
  max(0.05'f, min(preferred,
    min((size.x - 32) / ResultPanelSize.x,
      (size.y - 32) / ResultPanelSize.y)))

proc resultReturnPanel*(view: Vec2): GameUiPanel =
  ## Shares the exact visible return-button bounds with interaction tests.
  GameUiPanel(
    origin: (view - ResultPanelSize) / 2 + vec2(204, 420),
    size: vec2(352, 54)
  )

proc drawMatchResults*(
    sk: Silky,
    window: Window,
    game: Game,
    heroId: int32,
    online: bool,
    ready = true
): bool =
  ## Draws a modal result pass and accepts only an explicit return click.
  let summary = game.matchResult(heroId)
  if not summary.finished:
    return false
  let
    oldScale = sk.uiScale
    oldMouse = sk.mousePos
  sk.uiScale = resultScale(window.size.vec2, oldScale)
  sk.beginUi(window, window.size)
  let
    view = window.size.vec2 / sk.uiScale
    origin = (view - ResultPanelSize) / 2
    accent =
      case summary.outcome
      of MatchVictory: rgbx(179, 220, 134, 255)
      of MatchDefeat: rgbx(239, 133, 119, 255)
      of MatchTeamVictory: TeamInk[summary.winner]
      else: ResultGold
  sk.drawRect(vec2(0), view, rgbx(5, 8, 14, 188))
  sk.drawRect(origin + vec2(8, 10), ResultPanelSize, rgbx(0, 0, 0, 95))
  sk.draw9Patch("window.9patch", sk.theme.windowPatch, origin, ResultPanelSize)
  sk.drawRect(origin + vec2(312, 0), vec2(136, 3), accent)
  sk.drawLabel("MATCH COMPLETE", origin + vec2(40, 29), vec2(680, 28),
    ResultMuted, "Bold", CenterAlign)
  sk.drawLabel(summary.title, origin + vec2(24, 69), vec2(712, 90),
    accent, "ResultTitle", CenterAlign)
  sk.drawLabel(summary.detail, origin + vec2(32, 168), vec2(696, 30),
    ResultInk, "Default", CenterAlign)
  sk.drawLabel("BATTLE TIME  " & summary.duration,
    origin + vec2(40, 207), vec2(680, 28), ResultGold, "Bold", CenterAlign)
  sk.drawRect(origin + vec2(48, 253), vec2(664, 1), rgbx(127, 111, 77, 150))
  for index, team in [BlueTeam, RedTeam]:
    let
      at = origin + vec2(40 + index.float32 * 352, 278)
      size = vec2(328, 108)
      label = (if team == BlueTeam: "BLUE TEAM" else: "RED TEAM") &
        (if summary.ownTeam == team.ord: "  /  YOUR TEAM" else: "")
    sk.draw9Patch("frame.9patch", sk.theme.framePatch, at, size)
    sk.drawRect(at + vec2(1, 12), vec2(3, 84), TeamInk[team.ord])
    sk.drawLabel(label, at + vec2(20, 11), vec2(288, 24),
      TeamInk[team.ord], "Bold", CenterAlign)
    sk.drawLabel($summary.kills[team.ord], at + vec2(20, 36), vec2(288, 46),
      ResultInk, "ResultNumber", CenterAlign)
    sk.drawLabel("HERO KILLS", at + vec2(20, 80), vec2(288, 18),
      ResultMuted, "Small", CenterAlign)
  let
    button = resultReturnPanel(view)
    hovered = button.contains(sk.mousePos)
    patch =
      if not ready: "button.disabled.9patch"
      elif hovered and window.buttonDown[MouseLeft]: "button.down.9patch"
      elif hovered: "button.hover.9patch"
      else: "button.9patch"
  sk.draw9Patch(patch, sk.theme.buttonPatch, button.origin, button.size)
  sk.drawLabel(if online: "Return to lobby" else: "Return to menu",
    button.origin, button.size,
    if ready: ResultGold else: ResultMuted, "Bold", CenterAlign)
  if not ready:
    sk.drawLabel("Waiting for match confirmation...",
      origin + vec2(40, 481), vec2(680, 22), ResultMuted, "Small", CenterAlign)
  result = ready and hovered and window.buttonPressed[MouseLeft]
  sk.mouseConsumed = true
  sk.endUi()
  sk.uiScale = oldScale
  sk.mousePos = oldMouse
