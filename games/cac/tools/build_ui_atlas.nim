## Bake the browser's UI texture and glyph metadata from the source art.
import std/os
import jsony, zippy
import ../src/app

if paramCount() != 2:
  quit("Usage: build_ui_atlas CARD_ASSETS OUTPUT_DIR", QuitFailure)

let
  builder = buildUiAtlas(paramStr(1))
  pixels = builder.atlasImage.data
  output = paramStr(2)
writeFile(output / "ui.atlas.json", builder.atlas.toJson())
writeFile(output / "ui.atlas.rgba.deflate",
  compress(pixels[0].unsafeAddr, pixels.len * sizeof(pixels[0]),
    BestCompression, dfZlib))
