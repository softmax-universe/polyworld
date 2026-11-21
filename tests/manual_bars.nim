## Captures actual themed bars for local visual inspection, outside CI.
## Run with an optional output directory; each image uses native GL pixels.

import
  std/[os, strformat],
  chroma, opengl, silky, vmath, windy,
  polyworld/[actioncam, chrome, gameuis, player, viewers]

const
  CanvasSize = vec2(1600, 800)
  BarWidth = 164.0'f
  ColumnWidth = 190.0'f
  Purple = rgbx(151, 82, 199, 255)
  Blue = rgbx(96, 132, 190, 255)
  Green = rgbx(92, 185, 101, 255)
  Captures = [
    (0.5'f, "0.5"), (1.0'f, "1"), (1.25'f, "1.25"), (2.0'f, "2")
  ]
  Heights = [6.0'f, 12.0'f, 24.0'f]
  Colors = [("Replay", Purple), ("Playback", Blue), ("Resource", Green)]
  Labels = ["Zero", "0.25 px", "1 px", "2 px", "5 px", "50%", "100%"]
  FillPixels = [0.0'f, 0.25'f, 1.0'f, 2.0'f, 5.0'f]
  EdgeLabels = ["1 px", "2 px", "3 px", "9 px", "10 px", "11 px", "12 px"]
  EdgePixels = [1.0'f, 2.0'f, 3.0'f, 9.0'f, 10.0'f, 11.0'f, 12.0'f]

proc drawMatrix(sk: Silky, edges: bool) =
  ## Draws the production bar primitive using requested physical fill widths.
  sk.drawLabel("Actual theme bars", vec2(24, 16), vec2(600, 32), font = "H1")
  sk.drawLabel(
    "Columns request physical fill pixels; rows use logical bar heights.",
    vec2(24, 54), vec2(900, 24)
  )
  let labels = if edges: EdgeLabels else: Labels
  for column, label in labels:
    sk.drawLabel(label, vec2(240 + column.float32 * ColumnWidth, 82),
      vec2(BarWidth, 24))
  for colorIndex, (name, color) in Colors:
    for heightIndex, height in Heights:
      let
        row = colorIndex * Heights.len + heightIndex
        position = vec2(240, 120 + row.float32 * 42)
        inset = min(3.0'f, height / 6)
        innerWidth = BarWidth - inset * 2
      sk.drawLabel(name & "  h=" & $height.int,
        vec2(24, position.y - 8), vec2(200, 28), color)
      for column in 0 ..< Labels.len:
        let ratio =
          if edges:
            EdgePixels[column] / sk.uiScale / innerWidth
          elif column < FillPixels.len:
            FillPixels[column] / sk.uiScale / innerWidth
          elif column == 5:
            0.5'f
          else:
            1.0'f
        sk.drawBar(position + vec2(column.float32 * ColumnWidth, 0),
          vec2(BarWidth, height), ratio, 1, color)

proc drawTransports(sk: Silky, window: Window) =
  ## Draws real shared live transports, including the six-pixel purple strip.
  var
    actionCam = ActionCam()
    followSelection = false
    transport = initPlayer(live = true, durationTicks = 10000)
  transport.sync(3500, 5000, false)
  sk.drawLabel("Production live transport / half recorded", vec2(24, 518),
    vec2(900, 24))
  transport.drawTransport(sk, window,
    GameUiPanel(origin: vec2(16, 550), size: vec2(1568, TransportHeight)),
    actionCam, followSelection)
  transport.sync(1, 35, false)
  sk.drawLabel("Production live transport / tiny recorded fill", vec2(24, 650),
    vec2(900, 24))
  transport.drawTransport(sk, window,
    GameUiPanel(origin: vec2(16, 682), size: vec2(1568, TransportHeight)),
    actionCam, followSelection)

proc captureBars(directory: string, scale: float32, label: string,
    edges: bool) =
  ## Renders into the shared hidden target and saves its untouched framebuffer.
  let
    suffix = if edges: "-edges" else: ""
    path = directory / "bars-scale-" & label & suffix & ".png"
    size = (CanvasSize * scale).ivec2
  configureCapture(ScreenshotOptions(path: path, frames: 1))
  let window = newWindow("Small bar visual diagnostic", size,
    visible = false, vsync = false, msaa = msaaDisabled)
  defer:
    window.close()
  window.makeContextCurrent()
  loadExtensions()
  let builder = newHudAtlas(2048)
  builder.addDefaultFonts()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.applyThemePatches()
  sk.uiScale = scale
  var
    target: ScreenshotTarget
    frame: int
  defer:
    target.releaseScreenshotTarget()
  discard target.beginScreenshotFrame(window)
  sk.beginUi(window, window.size)
  sk.clearScreen(rgbx(20, 23, 30, 255))
  sk.drawMatrix(edges)
  sk.drawTransports(window)
  sk.endUi()
  doAssert glGetError() == GL_NO_ERROR
  doAssert window.captureFrame(frame)
  echo &"Captured scale {scale}: {window.size.x}x{window.size.y}"

let outputDirectory =
  if paramCount() > 0:
    absolutePath(paramStr(1))
  else:
    getTempDir() / "polyworld-small-bars" / "current"
for (scale, label) in Captures:
  captureBars(outputDirectory, scale, label, false)
  captureBars(outputDirectory, scale, label, true)
