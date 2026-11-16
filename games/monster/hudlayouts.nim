import
  vmath,
  polyworld/gameuis

const
  HudSourceSize* = vec2(2098, 749)
  HudArtworkBottom = 674'f
    ## The painted lower rim, excluding the PNG's transparent padding.
  HudBottomOverlap = 10'f
  HudSize = 0.6'f
    ## Shrinks the artwork, text, and input coordinates together.

type ChatLayout* = object
  frame*, panel*, history*, input*, send*, stats*, minimap*: GameUiPanel
  scrollbar*, portrait*, primaryMeter*, name*, primaryLabel*, carrying*: GameUiPanel
  utility*: GameUiPanel
  artScale*: float32

proc chatScale*(size: Vec2): float32 {.raises: [].} =
  ## Keeps the text and controls proportional to the compact artwork.
  min(clamp(size.y / 900, 0.75'f, 2'f),
    max(0.1'f, size.x / 1040)) * HudSize

proc sourcePanel(
  frame: GameUiPanel,
  x, y, width, height: float32
): GameUiPanel {.raises: [].} =
  ## Projects one source-image opening into the uniformly scaled HUD.
  let scale = frame.size.x / HudSourceSize.x
  GameUiPanel(origin: frame.origin + vec2(x, y) * scale,
    size: vec2(width, height) * scale)

proc chatLayout*(size: Vec2): ChatLayout {.raises: [].} =
  ## Aligns every live widget with its opening in the woodland frame.
  let
    width = min(size.x,
      size.y * 0.65'f * HudSourceSize.x / HudSourceSize.y) * HudSize
    scale = width / HudSourceSize.x
    frameSize = HudSourceSize * scale
  result.artScale = scale
  result.frame = GameUiPanel(
    origin: vec2((size.x - width) / 2,
      size.y - HudArtworkBottom * scale + HudBottomOverlap / HudSize),
    size: frameSize
  )
  let frame = result.frame
  result.panel = frame.sourcePanel(486, 140, 1070, 496)
  result.history = frame.sourcePanel(500, 156, 1010, 402)
  result.scrollbar = frame.sourcePanel(1520, 170, 24, 390)
  result.input = frame.sourcePanel(520, 590, 870, 28)
  result.send = frame.sourcePanel(1445, 591, 88, 28)
  result.stats = frame.sourcePanel(1590, 176, 414, 454)
  result.minimap = frame.sourcePanel(120, 232, 314, 338)
  result.portrait = frame.sourcePanel(1613, 185, 108, 108)
  result.name = frame.sourcePanel(1748, 184, 244, 46)
  result.primaryLabel = frame.sourcePanel(1767, 233, 224, 26)
  result.primaryMeter = frame.sourcePanel(1775, 273, 190, 12)
  result.carrying = frame.sourcePanel(1767, 302, 224, 26)
  result.utility = frame.sourcePanel(1612, 340, 376, 270)
