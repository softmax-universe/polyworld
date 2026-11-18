## Check the production TAB renderer, including its separate timer and kill rows.
import
  std/[importutils, os],
  opengl, windy/internal,
  polyworld/viewers,
  ../replays

include ../ui
privateAccess(Window)

let builder = newHudAtlas(2048)
builder.addDefaultFonts()
for heroClass in HeroClass:
  doAssert builder.addImage(
    HeroPortraitKeys[heroClass],
    readImage(HeroPortraitPaths[heroClass]).resize(128, 128)
  )

run = newGame(generateMap(7), 100000, 10, false, ReplayData(), drafting = false)
run.networked = true
run.world.tick = 258 * TickRate
run.replayData.config.maxTicks = 1200 * TickRate
run.replayData.config.players.setLen(10)
options.playerSlot = 6
let
  names = ["Ember", "Aster", "Flint", "Rook", "Vesper",
    "Rowan", "Lyra", "Orion", "Sage", "Vale"]
  kills = [7, 4, 6, 5, 5, 3, 5, 4, 2, 4]
  deaths = [3, 4, 2, 5, 4, 7, 6, 5, 4, 5]
for slot, hero in run.world.heroes:
  run.replayData.config.players[slot].name = names[slot]
  hero.level = int32(12 + slot mod 5)
  run.world.stats.values[slot][GoldMetric] = 9100 + slot * 435
  run.world.stats.values[slot][KillsMetric] = kills[slot]
  run.world.stats.values[slot][LossesMetric] = deaths[slot]
  run.world.stats.values[slot][AssistsMetric] = 3 + slot mod 7
  run.world.stats.values[slot][DamageMetric] = 18000 + slot * 3700
  run.world.teamHeroKills[hero.team.ord] += kills[slot]
  run.world.teamHeroDeaths[hero.team.ord] += deaths[slot]
run.sampleMetrics(true)

proc assertChangesInside(before, after: Image, panel: GameUiPanel,
    scale: float32, description: string) =
  ## Compare real pixels so a renderer ignoring its layout cannot pass.
  doAssert before.width == after.width and before.height == after.height
  var changed = 0
  for y in 0 ..< before.height:
    for x in 0 ..< before.width:
      let index = y * before.width + x
      if before.data[index] != after.data[index]:
        inc changed
        let point = vec2(x.float32 + 0.5'f, y.float32 + 0.5'f) / scale
        doAssert panel.contains(point),
          description & " changed pixels outside its own row at " & $point
  doAssert changed > 0, description & " must change visible scoreboard pixels"

proc verifyScoreboard(size: IVec2): Image =
  ## Exercise the actual game entry point without claiming native input focus.
  let window = newWindow("GotA scoreboard layout", size, visible = false)
  window.makeContextCurrent()
  loadExtensions()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.applyThemePatches()
  sk.uiScale = gameUiScale(window)
  statsState = StatsState(toggled: true)
  window.state.perFrame = PerFrame()
  window.state.buttonDown = {}
  let
    width = window.size.x.int
    height = window.size.y.int
    scale = statsScale(sk.uiScale)
    viewport = statsViewport(currentLayout(window), sk.uiScale)
    slots = statsLayout(viewport, currentStats(), matchStatsOptions())
  doAssert currentStats().rows.len == 10
  doAssert slots.headline.origin.y + slots.headline.size.y <= slots.kills.origin.y
  doAssert slots.kills.origin.y + slots.kills.size.y <= slots.header.origin.y
  doAssert slots.header.origin.y + slots.header.size.y <= slots.body.origin.y
  var framebuffer, texture: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, width.GLsizei, height.GLsizei,
    0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, texture, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

  proc render(): Image =
    ## Read the production overlay from an offscreen native GL framebuffer.
    glClearColor(0.035, 0.045, 0.065, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    sk.drawStatsOverlay(window)
    result = newImage(width, height)
    glReadPixels(0, 0, width.GLsizei, height.GLsizei,
      GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
    result.flipVertical()

  try:
    result = render()
    doAssert result.data == render().data, "An unchanged scoreboard is stable"
    run.replayData.config.maxTicks += TickRate
    let nextTimer = render()
    assertChangesInside(result, nextTimer, slots.headline, scale, "Timer")
    run.replayData.config.maxTicks -= TickRate
    inc run.world.teamHeroKills[BlueTeam.ord]
    let nextKills = render()
    assertChangesInside(result, nextKills, slots.kills, scale, "Team kills")
    dec run.world.teamHeroKills[BlueTeam.ord]
    if viewport.size.x >= 1000:
      inc run.world.stats.values[0][LossesMetric]
      let nextDeaths = render()
      assertChangesInside(result, nextDeaths, slots.body, scale, "Player deaths")
      dec run.world.stats.values[0][LossesMetric]
    statsState.toggled = false
    doAssert result.data != render().data, "Closing TAB removes the scoreboard"
  finally:
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glDeleteTextures(1, texture.addr)
    glDeleteFramebuffers(1, framebuffer.addr)
    window.close()

let screenshot = verifyScoreboard(ivec2(1600, 1000))
discard verifyScoreboard(ivec2(640, 720))
let output = getEnv("GOTA_SCOREBOARD_FIXTURES", getCurrentDir() / "output")
createDir(output)
screenshot.writeFile(output / "gota-scoreboard-fixed.png")
echo "PASS production TAB renderer: timer, kills, and deaths occupy separate rows"
