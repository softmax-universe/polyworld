import
  std/[os, tempfiles],
  gltf/ktx2, pixie,
  polyworld/[assets, texturedata]

proc uploadBytes(upload: TextureUpload): string =
  ## Copies a prepared payload for comparison without retaining borrowed memory.
  result = newString(upload.byteCount())
  copyMem(result[0].addr, upload.data(), result.len)

proc imageLevels(color: ColorRGBX): seq[Image] =
  ## Authors a nonsquare mip chain with a height value in its alpha channel.
  for size in [(3, 2), (1, 1)]:
    let image = newImage(size[0], size[1])
    image.fill(color)
    result.add image

let
  first = imageLevels(rgbx(200, 100, 50, 37))
  second = imageLevels(rgbx(20, 40, 80, 180))
  plan = prepareTextureArray(@[first, second])
doAssert (plan.width, plan.height, plan.layerCount, plan.levelCount) == (3, 2, 2, 2)
doAssert plan.encoding == TextureRgba8
var count = 0
for upload in plan.textureUploads():
  let
    image = @[first, second][upload.layer][upload.level]
    actual = upload.uploadBytes()
  doAssert (upload.width, upload.height) == (image.width, image.height)
  doAssert actual.len == image.data.len * 4
  for i, pixel in image.data:
    doAssert actual[i * 4].ord == pixel.r.int
    doAssert actual[i * 4 + 1].ord == pixel.g.int
    doAssert actual[i * 4 + 2].ord == pixel.b.int
    doAssert actual[i * 4 + 3].ord == pixel.a.int
  inc count
doAssert count == 4
for level in 0 ..< plan.levelCount:
  doAssert plan.packedTextureLevel(level) ==
    plan.textureUpload(0, level).uploadBytes() &
    plan.textureUpload(1, level).uploadBytes()

block:
  let directory = createTempDir("polyworld-upload-plans-", "")
  defer: removeDir(directory)
  var
    paths: seq[string]
    encoded: seq[string]
  for layer, color in [rgbx(210, 120, 80, 32), rgbx(30, 180, 100, 192)]:
    let image = newImage(8, 8)
    image.fill(color)
    let
      bytes = encodeKtx2Image(image, VkFormatBc3UnormBlock, straightAlpha = true)
      path = directory / ($layer & ".ktx2")
    writeFile(path, bytes)
    paths.add path
    encoded.add bytes
  let
    compressed = prepareTerrainTextures(paths, compressed = true)
    decoded = prepareTerrainTextures(paths)
  doAssert compressed.encoding == TextureBc3
  doAssert decoded.encoding == TextureRgba8
  doAssert compressed.layerCount == 2
  for upload in compressed.textureUploads():
    let
      info = parseKtx2(encoded[upload.layer])
      mip = info.levels[upload.level]
    doAssert upload.uploadBytes() == encoded[upload.layer][
      mip.byteOffset ..< mip.byteOffset + mip.byteLength
    ]
  for upload in decoded.textureUploads():
    let bytes = encoded[upload.layer]
    doAssert upload.uploadBytes() == decodeBc3(bytes, parseKtx2(bytes), upload.level)
  for level in 0 ..< compressed.levelCount:
    doAssert compressed.packedTextureLevel(level) ==
      compressed.textureUpload(0, level).uploadBytes() &
      compressed.textureUpload(1, level).uploadBytes()

template rejects(body: untyped) =
  ## Requires validation to report malformed CPU data before any GPU work.
  block:
    var rejected = false
    try:
      body
    except AssetError:
      rejected = true
    doAssert rejected

rejects: discard prepareTextureArray(@[])
rejects: discard prepareTextureArray(@[first, @[newImage(4, 2)]])
rejects: discard plan.textureUpload(-1, 0)
rejects: discard plan.textureUpload(2, 0)
rejects: discard plan.textureUpload(0, 2)
rejects: discard TextureUpload().data()

echo "Shared texture upload preparation and exact payloads passed"
