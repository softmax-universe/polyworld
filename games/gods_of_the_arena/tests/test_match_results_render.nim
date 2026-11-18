## Render the production result screen and exercise its return button.
import
  std/[importutils, os],
  opengl, pixie, silky, vmath, windy, windy/internal,
  polyworld/[chrome, viewers],
  ../[assets, content, matchresults, sim]

privateAccess(Window)

let
  width = 1600
  height = 1000
  window = newWindow("GotA match results", ivec2(width.int32, height.int32),
    visible = false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(4096)
builder.addDefaultFonts()
builder.addResultFonts()
doAssert builder.addImage("result-backdrop", readImage(MenuRoot / "background.png"))
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
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
let game = Game(world: World(phase: Playing, heroes: @[
  Hero(id: 101, team: RedTeam), Hero(id: 105, team: BlueTeam)
]))
game.replayData.config.maxTicks = 600 * TickRate
game.world.tick = game.config.maxTicks
game.world.teamHeroKills = [18, 18]

proc render(ready = true, online = false): bool =
  ## Runs the exact result renderer over the game's packaged backdrop.
  glClearColor(0, 0, 0, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.beginUi(window, window.size)
  sk.drawSprite("result-backdrop", vec2(0), window.size.vec2)
  sk.endUi()
  result = sk.drawMatchResults(window, game, 101, online, ready)
  doAssert sk.mouseConsumed
  doAssert sk.uiScale == 1

proc capture(file: string) =
  ## Saves actual framebuffer pixels for visual review.
  let image = newImage(width, height)
  glReadPixels(0, 0, width.GLsizei, height.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
  image.flipVertical()
  image.writeFile(file)

let output = getEnv("GOTA_RESULTS_FIXTURES", getCurrentDir() / "output")
createDir(output)
window.state.mousePos = ivec2(0)
window.state.perFrame = PerFrame()
doAssert not render()
capture(output / "gota-results-draw.png")
game.world.gameOver = true
game.world.winner = RedTeam
game.world.teamHeroKills = [27, 14]
doAssert not render()
capture(output / "gota-results-victory.png")
game.world.winner = BlueTeam
game.world.teamHeroKills = [14, 27]
doAssert not render()
capture(output / "gota-results-defeat.png")
let
  button = resultReturnPanel(window.size.vec2)
  center = button.origin + button.size / 2
window.state.mousePos = ivec2(center.x.int32, center.y.int32)
window.state.perFrame = PerFrame(buttonPressed: {MouseLeft})
doAssert not render(ready = false, online = true),
  "Unconfirmed network results must not return to the lobby early"
window.state.mousePos = ivec2(0)
doAssert not render(), "Clicks outside the return button must stay on results"
window.state.mousePos = ivec2(center.x.int32, center.y.int32)
doAssert render(), "The explicit return button must leave the results screen"
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS result renderer: draw/victory/defeat pixels and explicit gated return"
