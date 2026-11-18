## Render the actual reward feedback with packaged gold and the XP orb.

import
  std/[os, tables],
  chroma, opengl, pixie, silky, vmath, windy,
  polyworld/[chrome, viewers],
  ../[rewardtexts, sim]

let
  builder = newHudAtlas(2048)
  window = newWindow("GotA reward feedback", ivec2(1200, 720), visible = false)
builder.addDefaultFonts()
builder.addRewardIcons()
window.makeContextCurrent()
loadExtensions()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.uiScale = 1.5'f
let
  width = window.size.x.int
  height = window.size.y.int
  viewport = window.size.vec2
  projection = scale(vec3(0.1'f))
var
  framebuffer, texture: GLuint
  rewards = RewardTexts(entries: @[
    RewardText(position: WorldPoint(x: -6 * WorldScale, y: -2 * WorldScale),
      gold: 10, xp: 5),
    RewardText(position: WorldPoint(y: -2 * WorldScale), xp: 5),
    RewardText(position: WorldPoint(x: 6 * WorldScale, y: -2 * WorldScale),
      gold: 10, xp: 5),
    RewardText(position: WorldPoint(x: 6 * WorldScale, y: -2 * WorldScale),
      gold: 10, xp: 5)
  ])
doAssert "gold" in sk.atlas.entries
doAssert RewardOrbKey in sk.atlas.entries
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
  ## Draws the production labels into a hidden native framebuffer.
  glClearColor(0.047, 0.063, 0.09, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.beginUi(window, window.size)
  sk.drawLabel("Combat rewards", vec2(40, 30), vec2(720, 40),
    rgbx(242, 235, 214, 255), "H1")
  sk.drawLabel("Gold and XP rise together, on separate lines.",
    vec2(40, 76), vec2(720, 28), rgbx(158, 170, 192, 255), "Default")
  sk.drawRewardTexts(rewards, projection, viewport)
  for item in [(160'f, "Last hit"), (400'f, "Nearby XP"),
      (640'f, "Two simultaneous kills")]:
    sk.drawLabel(item[1], vec2(item[0] - 112, 290), vec2(224, 30),
      rgbx(202, 212, 228, 255), "Default", CenterAlign)
  sk.drawLabel("One gold sound per batch. XP-only rewards use one soft chime.",
    vec2(40, 350), vec2(720, 30), rgbx(158, 170, 192, 255),
    "Default", CenterAlign)
  sk.endUi()
  result = newImage(width, height)
  glReadPixels(0, 0, width.GLsizei, height.GLsizei,
    GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr)
  result.flipVertical()

let before = render()
rewards.advanceRewardTexts(0.2'f)
let after = render()
doAssert before.data != after.data, "Reward rows must visibly rise"
let output = getEnv("GOTA_REWARD_FIXTURES", getCurrentDir() / "output")
createDir(output)
before.writeFile(output / "gota-rewards.png")
glBindFramebuffer(GL_FRAMEBUFFER, 0)
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
echo "PASS native reward renderer: gold, XP orb and stacked simultaneous rewards"
