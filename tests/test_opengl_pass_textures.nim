## Checks shared texture views retain legacy sampling intent.

import
  pixie, shady, vmath, windy,
  polyworld/backends/opengl/[passapi, passtextures]
from polyworld/backends/shaders/screens import fullscreenPosition

proc textureLod(source: Uniform[Sampler2DArray], uv: Vec3,
    lod: float32): Vec4 =
  ## Declares the array sampling intrinsic for Shady's GLSL compiler.
  discard

proc sampleArray(source: Uniform[Sampler2DArray], uv: Uniform[Vec3],
    lod: Uniform[float32], fragColor: var Vec4) =
  ## Samples explicit array coordinates and levels for filtering checks.
  fragColor = textureLod(source, uv, lod)

proc sampleData(source: Uniform[Sampler2D], uv: Uniform[Vec2],
    fragColor: var Vec4) =
  ## Samples halfway between distinct data records.
  fragColor = texture(source, uv)

proc samplerValue(image: GpuImage, field: GLenum): GLint =
  ## Reads the independent sampler that overrides texture storage parameters.
  glGetSamplerParameteriv(image.sampler, field, result.addr)

proc main() =
  ## Runs real sampler and pixel checks without displaying a window.
  let window = newWindow("Shared texture sampling", ivec2(16), visible = false)
  defer: window.close()
  window.makeContextCurrent()
  loadExtensions()
  initNative(window)
  let
    target = newRenderTarget(1, 1, depth = false)
    arrayProgram = newProgram(nativeStage(fullscreenPosition, shaderVertex),
      nativeStage(sampleArray, shaderFragment))
    dataProgram = newProgram(nativeStage(fullscreenPosition, shaderVertex),
      nativeStage(sampleData, shaderFragment))
    base = newImage(2, 1)
    mip = newImage(1, 1)
  defer:
    destroy(arrayProgram)
    destroy(dataProgram)
    destroy(target)
  base[0, 0] = rgbx(255, 0, 0, 255)
  base[1, 0] = rgbx(0, 0, 255, 255)
  mip[0, 0] = rgbx(0, 255, 0, 255)
  setTarget(target)
  for repeat in [false, true]:
    let image = createTextureArray(@[@[base, mip]], repeat)
    defer: image.destroy()
    doAssert image.levels == 2 and image.layers == 1
    doAssert image.samplerValue(GL_TEXTURE_MIN_FILTER) ==
      GL_LINEAR_MIPMAP_LINEAR.GLint
    doAssert image.samplerValue(GL_TEXTURE_WRAP_S) ==
      (if repeat: GL_REPEAT else: GL_CLAMP_TO_EDGE).GLint
    arrayProgram.bindTexture("source", image)
    arrayProgram.setUniform("uv", vec3(1.25, 0.5, 0))
    arrayProgram.setUniform("lod", 0.0'f)
    draw(arrayProgram, nil, 3)
    doAssert captureTargetImage(target)[0, 0] ==
      (if repeat: base[0, 0] else: base[1, 0])
    arrayProgram.setUniform("lod", 1.0'f)
    draw(arrayProgram, nil, 3)
    doAssert captureTargetImage(target)[0, 0] == mip[0, 0]
  var data = createR8Texture(2, 1, [0'u8, 255], linear = false)
  defer: data.destroy()
  dataProgram.setUniform("uv", vec2(0.5))
  for linear in [false, true, false]:
    updateR8Texture(data, 2, 1, [0'u8, 255], linear = linear)
    doAssert data.samplerValue(GL_TEXTURE_MIN_FILTER) ==
      (if linear: GL_LINEAR else: GL_NEAREST).GLint
    dataProgram.bindTexture("source", data)
    draw(dataProgram, nil, 3)
    let value = captureTargetImage(target)[0, 0].r.int
    doAssert abs(value - (if linear: 128 else: 255)) <= 1
  var records = createRgba32fTexture(1, 1, [0.0'f, 1, 0, 1])
  defer: records.destroy()
  records.setTextureSampling(linear = true)
  updateRgba32fTexture(records, 1, 1, [0.0'f, 1, 0, 1])
  doAssert records.samplerValue(GL_TEXTURE_MIN_FILTER) == GL_NEAREST.GLint
  var floatData = createR32fTexture(1, 1, [1.0'f], linear = false)
  var rgData = createRg8Texture(1, 1, [1'u8, 2], linear = false)
  var rgbaData = createRgba8Texture(1, 1, [1'u8, 2, 3, 4], linear = false)
  defer:
    floatData.destroy()
    rgData.destroy()
    rgbaData.destroy()
  for image in [floatData, rgData, rgbaData]:
    doAssert image.samplerValue(GL_TEXTURE_MIN_FILTER) == GL_NEAREST.GLint
  # Typed updates may replace storage while retaining the resource wrapper.
  updateR32fTexture(data, 1, 1, [0.25'f], linear = false)
  doAssert data.pixelFormat == R32f and data.nativeFormat == GL_R32F
  dataProgram.bindTexture("source", data)
  draw(dataProgram, nil, 3)
  doAssert abs(captureTargetImage(target)[0, 0].r.int - 64) <= 1
  updateRg8Texture(data, 1, 1, [64'u8, 128], linear = false)
  doAssert data.pixelFormat == Rg8 and data.nativeFormat == GL_RG8
  updateRgba8Texture(data, 1, 1, [64'u8, 128, 192, 255])
  doAssert data.pixelFormat == Rgba8 and data.nativeFormat == GL_RGBA8
  updateRgba32fTexture(data, 1, 1, [0.25'f, 0.5, 0.75, 1])
  doAssert data.pixelFormat == Rgba32f and data.nativeFormat == GL_RGBA32F
  updateR8Texture(data, 1, 1, [255'u8])
  doAssert data.pixelFormat == R8 and data.nativeFormat == GL_R8
  doAssert glGetError() == GL_NO_ERROR
  echo "Shared texture repeat, mip levels, and updated filtering passed."

main()
