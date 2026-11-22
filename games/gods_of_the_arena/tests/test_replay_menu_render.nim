import
  std/[importutils, os, times],
  opengl, pixie, silky, vmath, windy/internal,
  polyworld/[chrome, lobbies, viewers],
  ../[content, homes, replaylibraries, replaymenus, replays]

privateAccess(Window)

proc verifyReplayMenu(size: IVec2, screenshot: string, zoom = 0) =
  ## Exercises production replay controls with real UI input and rendering.
  let
    savedMode = uiScaleMode
    savedPercent = uiScalePercent
  if zoom > 0:
    uiScaleMode = CustomUiScale
    uiScalePercent = zoom
  defer:
    uiScaleMode = savedMode
    uiScalePercent = savedPercent
  let window = newWindow("GotA replay browser test", size, visible = false)
  defer:
    window.close()
  window.makeContextCurrent()
  loadExtensions()
  let builder = newHudAtlas(4096)
  builder.addDefaultFonts()
  builder.addLobbyFonts()
  builder.addHomeAssets()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.applyThemePatches()
  var
    browser = ReplayBrowserUi()
    entries: seq[ReplayEntry]
    framebuffer, texture: GLuint
  for index in 0 ..< 12:
    entries.add ReplayEntry(
      path: "/test/arena-" & $index & ".replay",
      name: "Arena match " & $(index + 1) & ".replay",
      modified: fromUnix(1795200000 - int64(index * 3600)),
      gameVersion: ReplayGameVersion,
      ticks: TickRate * 60 * 12,
      playable: true
    )
  entries[1].playable = false
  entries[1].gameVersion = ReplayGameVersion - 1
  entries[1].problem = "Game version " & $entries[1].gameVersion &
    " (requires " & $ReplayGameVersion & ")"
  entries[2].playable = false
  entries[2].problem = "The replay file is incomplete."
  glGenFramebuffers(1, framebuffer.addr)
  glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.GLint, size.x.GLsizei, size.y.GLsizei,
    0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, texture, 0)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  defer:
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glDeleteTextures(1, texture.addr)
    glDeleteFramebuffers(1, framebuffer.addr)

  proc input(point = vec2(-100), pressed = false, released = false,
      key = ButtonUnknown) =
    ## Updates only the transient events consumed by the real menu widgets.
    window.state.perFrame = PerFrame()
    window.state.buttonDown = {}
    window.state.mousePos = (point * sk.uiScale).ivec2
    window.state.mousePrevPos = window.state.mousePos
    if pressed:
      window.state.perFrame.buttonPressed.incl MouseLeft
      window.state.buttonDown.incl MouseLeft
    if released:
      window.state.perFrame.buttonReleased.incl MouseLeft
    if key != ButtonUnknown:
      window.state.perFrame.buttonPressed.incl key

  proc render(point = vec2(-100), pressed = false, released = false,
      key = ButtonUnknown): ReplayBrowserResult =
    ## Renders the browser without performing its returned filesystem actions.
    input(point, pressed, released, key)
    result = sk.drawReplayBrowser(window, browser, entries,
      "User folder / Polyworld / Gods of the Arena / Replays")
    sk.endUi()

  proc click(point: Vec2): ReplayBrowserResult =
    ## Sends a complete mouse press and release through the renderer.
    discard render(point, pressed = true)
    render(point, released = true)

  discard render()
  let layout = replayBrowserLayout(window.size.vec2 / sk.uiScale)
  doAssert layout.back.y + layout.back.h < window.size.y.float32 / sk.uiScale
  doAssert layout.folderButton.x + layout.folderButton.w < layout.refresh.x
  doAssert layout.panel.y + layout.panel.h < layout.back.y
  let watch = layout.rows.xy + vec2(layout.rows.w - 96, 48)
  let live = click(watch)
  doAssert live.action == PlayReplay and live.path == entries[0].path
  doAssert click(watch + vec2(0, ReplayRowHeight)).action == StayReplayBrowser
  doAssert click(watch + vec2(0, ReplayRowHeight * 2)).action == StayReplayBrowser
  discard render(key = KeyDown)
  doAssert browser.selectedPath == entries[0].path
  discard render(key = KeyDown)
  doAssert browser.selectedPath == entries[3].path
  doAssert render(key = KeyEnter).path == entries[3].path
  for index in 0 ..< 10:
    discard render(key = KeyDown)
  doAssert browser.selectedPath == entries[^1].path
  doAssert browser.scroll.scrollPos.y > 0
  doAssert render(key = KeyEnter).path == entries[^1].path
  doAssert click(layout.importButton.xy + vec2(60, 20)).action == ImportReplayFile
  doAssert click(layout.folderButton.xy + vec2(70, 20)).action == OpenReplayFolder
  doAssert click(layout.refresh.xy + vec2(70, 20)).action == RefreshReplays
  doAssert click(layout.back.xy + vec2(70, 20)).action == BackFromReplays
  doAssert render(key = KeyEscape).action == BackFromReplays
  browser = ReplayBrowserUi()
  discard render()
  if screenshot.len > 0:
    let image = newImage(size.x, size.y)
    glReadPixels(0, 0, size.x.GLsizei, size.y.GLsizei,
      GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)
    image.flipVertical()
    createDir(screenshot.parentDir)
    image.writeFile(screenshot)
  entries.setLen(0)
  browser.selectedPath = "/test/no-longer-present.replay"
  doAssert render(key = KeyEnter).action == StayReplayBrowser
  doAssert browser.selectedPath.len == 0
  doAssert click(layout.importButton.xy + vec2(60, 20)).action == ImportReplayFile
  var focus = 2
  input(key = KeyEnter)
  doAssert sk.drawGotaHome(window, focus) == GotaOpenReplays
  sk.endUi()
  input(key = KeyDown)
  doAssert sk.drawGotaHome(window, focus) == GotaStayHome
  doAssert focus == 3
  sk.endUi()
  input(key = KeyEnter)
  doAssert sk.drawGotaHome(window, focus) == GotaOpenSettings
  sk.endUi()

verifyReplayMenu(ivec2(1280, 900),
  getEnv("GOTA_REPLAY_MENU_SCREENSHOT", "/tmp/gota-replay-browser.png"))
verifyReplayMenu(ivec2(800, 600), "")
verifyReplayMenu(ivec2(800, 600), "", zoom = 300)
echo "Replay browser mouse, keyboard, disabled versions, and scrolling passed."
