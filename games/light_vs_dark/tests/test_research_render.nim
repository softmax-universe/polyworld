## Native FBO proof of every generated research icon, contrast, and progress.
import std/[os, tables, unittest]
import chroma, pixie, silky, vmath, windy, opengl
import polyworld/[gameuis, viewers]
import ../[content, researchpresentation]

let window = newWindow("LvD research cards", ivec2(340, 680), visible = false)
window.makeContextCurrent()
loadExtensions()
pollEvents()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
for keys in ResearchIconKeys:
  for key in keys:
    doAssert builder.atlas.entries.hasKey(key), "Missing research icon: " & key
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, window.size.x, window.size.y,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
sk.beginUi(window, window.size)
sk.drawRect(vec2(0), window.size.vec2, rgbx(20,24,32,255))
for kind in ResearchKind:
  let slots = researchPanels(GameUiPanel(
    origin: vec2(11, (8 + kind.ord * 168).float32), size: vec2(318, 160)
  ))
  for i in 0 .. 2:
    let
      cost = researchStats(kind, i.int32 + 1)
      card = ResearchCard(
        name: researchName(kind), icon: ResearchIconKeys[kind][i],
        level: (if i == 2: MaxResearchLevel else: i.int32),
        allowed: i == 0, active: i == 1,
        gold: cost.gold, wood: cost.wood,
        ticks: cost.ticks, ticksRemaining: cost.ticks div 2
      )
    sk.drawResearchCard(slots[i], card, TickRate)
sk.endUi()
let image = newImage(window.size.x, window.size.y)
glReadPixels(0,0,window.size.x,window.size.y,GL_RGBA,GL_UNSIGNED_BYTE,image.data[0].addr)
image.flipVertical()
let output = getEnv("LVD_RESEARCH_FIXTURE", "output/lvd-research-icons-in-game.png")
createDir(output.parentDir)
image.writeFile(output)

suite "Native research card rendering":
  test "ready border brighter than unavailable border":
    check image[11, 9].r > image[119, 9].r
  test "all twelve generated glyphs render within icon wells":
    for row in 0 ..< ResearchKind.high.ord + 1:
      for i in 0 .. 2:
        var bright = 0
        for y in (13 + row * 168) ..< (61 + row * 168):
          for x in (38 + i * 108) ..< (86 + i * 108):
            if image[x, y].r > 70:
              inc bright
        check bright > 30
  test "active progress fills half the card with gold":
    check image[140, 165].r > 180
    check image[200, 165].r < 100
  test "cards never draw outside the command contents":
    check image[10,50] == rgbx(20,24,32,255)
    check image[329,50] == rgbx(20,24,32,255)
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
