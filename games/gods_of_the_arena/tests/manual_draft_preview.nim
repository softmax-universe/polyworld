## Captures the production hero picker with real art and a fixed draft roster.
import
  std/[importutils, os, times],
  opengl, pixie, silky, vmath, windy, windy/internal,
  polyworld/configs,
  ../[content, drafts, game, graphics, layouts, presets, sim]

privateAccess(Window)

const
  Width = 1600
  Height = 1000
  OutputRoot = currentSourcePath().parentDir.parentDir.parentDir.parentDir /
    "output"

options.windowWidth = Width
options.windowHeight = Height
initializeGraphics()
window.visible = false
window.makeContextCurrent()
pollEvents()
sk.uiScale = 1
var framebuffer, texture: GLuint
glGenFramebuffers(1, framebuffer.addr)
glGenTextures(1, texture.addr)
glBindTexture(GL_TEXTURE_2D, texture)
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, Width, Height,
  0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
  GL_TEXTURE_2D, texture, 0)
doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

run = Game(world: World(phase: Drafting, draftMode: UniqueDraft,
  draftOrder: @[0, 5, 1, 6, 2, 7, 3, 8, 4, 9], draftTurn: 2,
  draftTurnTicks: TickRate * 2))
for i in 0 ..< 10:
  run.world.heroes.add Hero(id: int32(100 + i),
    team: if i < 5: RedTeam else: BlueTeam, slot: int32(i mod 5))
  run.replayData.config.players.add PlayerConfig(name:
    if i == 0: "Mason"
    elif i == 1: "Avery"
    elif i == 5: "Sky"
    else: "Player " & $(i + 1))
run.world.heroes[0].drafted = true
run.world.heroes[0].class = VanguardKnight
run.world.heroes[5].drafted = true
run.world.heroes[5].class = DeathKnight

proc handleButtonPress(window: Window, button: Button) =
  ## Feeds a real mouse press into the native input backend.
  handleButtonPressTemplate()

proc handleButtonRelease(window: Window, button: Button) =
  ## Ends the mouse press before rendering the selected state.
  handleButtonReleaseTemplate()

proc render(playerSlot: int32, pointer = vec2(-100)): Image =
  ## Renders the actual picker with either the active or a waiting local player.
  options.playerSlot = playerSlot
  sk.beginUi(window, ivec2(Width, Height))
  sk.mousePos = pointer
  glClearColor(0, 0, 0, 1)
  glClear(GL_COLOR_BUFFER_BIT)
  sk.drawDraft(window, vec2(Width, Height), true)
  sk.endUi()
  result = newImage(Width, Height)
  glReadPixels(0, 0, Width, Height, GL_RGBA, GL_UNSIGNED_BYTE,
    result.data[0].addr)
  result.flipVertical()

createDir(OutputRoot)
let ready = render(2)
ready.writeFile(OutputRoot / "gota-hero-picker-ready.png")
let
  scale = draftScale(vec2(Width, Height))
  layout = draftPanels(vec2(Width, Height) / scale)
  pointer = (layout.heroes[2].origin + vec2(60)) * scale
window.state.perFrame = PerFrame()
window.state.mousePos = ivec2(int32(pointer.x), int32(pointer.y))
window.handleButtonPress(MouseLeft)
discard render(2, pointer)
window.state.perFrame = PerFrame()
window.handleButtonRelease(MouseLeft)
let selected = render(2)
selected.writeFile(OutputRoot / "gota-hero-picker-selected.png")
doAssert selected.data != ready.data
let waiting = render(3)
waiting.writeFile(OutputRoot / "gota-hero-picker-waiting.png")
doAssert waiting.data != ready.data
doAssert render(2).data == ready.data,
  "The selected badge and border must clear when the local turn ends."
echo "Saved ready, selected and waiting hero picker previews to ", OutputRoot
glDeleteTextures(1, texture.addr)
glDeleteFramebuffers(1, framebuffer.addr)
window.close()
