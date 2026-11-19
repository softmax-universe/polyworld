## Shared menu chrome with the Cards and Casters moonlit table backdrop.
import
  std/os,
  pixie, silky, vmath,
  polyworld/[assets, common, lobbies, menus],
  ../paths

const
  FrontendBackgroundPath* =
    DataRoot & "/cac/loading/source/moonlit-table.png"
  FrontendBackgroundWidth = 1672

proc addHomeButton(builder: AtlasBuilder, name: string) =
  ## Trims transparent margins while preserving the generated button face.
  var picture = readImage(menuArtworkRoot() / (name & ".png"))
  var
    left = picture.width
    top = picture.height
    right, bottom: int
  for y in 0 ..< picture.height:
    for x in 0 ..< picture.width:
      if picture[x, y].a > 200:
        left = min(left, x)
        top = min(top, y)
        right = max(right, x)
        bottom = max(bottom, y)
  if left > right or top > bottom:
    raise newException(MenusError, "Empty CaC menu button: " & name)
  let padding = max(1, picture.width div 200)
  left = max(0, left - padding)
  top = max(0, top - padding)
  right = min(picture.width - 1, right + padding)
  bottom = min(picture.height - 1, bottom + padding)
  picture = picture.subImage(left, top, right - left + 1, bottom - top + 1)
  let ratio = min(1.0, 768.0 / picture.width.float)
  picture = picture.resize(
    max(1, int(picture.width.float * ratio)),
    max(1, int(picture.height.float * ratio))
  )
  if not builder.addImage("home-" & name, picture):
    raise newException(MenusError, "The UI atlas is too small for menu buttons")

proc addFrontendAssets*(builder: AtlasBuilder) =
  ## Adds CaC button artwork, display type, lobby fonts and the table backdrop.
  builder.addLobbyFonts()
  builder.addFont(DefaultFontPath, "MenuDefault", 18)
  builder.addFont(BoldFontPath, "MenuHeading", 32)
  builder.addFont(DefaultFontPath, "MenuHud", 15)
  builder.addFont(DefaultFontPath, "MenuSmall", 12)
  let displayFont = artworkRoot() / "cards/fonts/Grenze-SemiBold.ttf"
  builder.addFont(displayFont, "HomeTitle", 60)
  builder.addFont(displayFont, "HomeButton", 32)
  builder.addFont(displayFont, "MenuDisplay", 34)
  builder.addHomeButton("button-primary")
  builder.addHomeButton("button-secondary")
  let
    original = readImage(FrontendBackgroundPath)
    ratio = min(1.0, FrontendBackgroundWidth.float / original.width.float)
    background = original.resize(
      max(1, int(original.width.float * ratio)),
      max(1, int(original.height.float * ratio))
    )
    shade = newImage(256, 256)
    gradient = newPaint(RadialGradientPaint)
  gradient.gradientHandlePositions = @[
    vec2(128, 128), vec2(256, 128), vec2(128, 256)
  ]
  gradient.gradientStops = @[
    ColorStop(color: color(0, 0, 0, 0.68), position: 0),
    ColorStop(color: color(0, 0, 0, 0.42), position: 0.5),
    ColorStop(color: color(0, 0, 0, 0), position: 1)
  ]
  shade.fill(gradient)
  if not builder.addImage("home-background", background):
    raise newException(MenusError,
      "The UI atlas is too small for the menu background")
  if not builder.addImage("home-shade", shade):
    raise newException(MenusError,
      "The UI atlas is too small for the menu shade")
