import
  opengl, pixie,
  ../../[assets, texturedata]

type
  Texture* = GLuint
  TextureArray* = Texture

when defined(emscripten):
  {.emit: "#include <emscripten.h>\n#include <emscripten/html5_webgl.h>".}
  ## Returns the browser's active graphics context.
  proc currentContext(): cint {.
    importc: "emscripten_webgl_get_current_context",
    header: "<emscripten/html5_webgl.h>"
  .}
  ## Requests a WebGL extension for the given context.
  proc enableExtension(context: cint, extension: cstring): bool {.
    importc: "emscripten_webgl_enable_extension",
    header: "<emscripten/html5_webgl.h>"
  .}

proc supportsBc3(forceRgba: bool): bool =
  ## Enables browser compression only when available and requested.
  if forceRgba:
    return false
  when defined(webForceRgba):
    return false
  when defined(emscripten):
    var forced: cint
    {.emit: """
    `forced` = EM_ASM_INT({
      return new URLSearchParams(location.search).has('textureFallback');
    });
    """.}
    if forced != 0:
      return false
    result = enableExtension(currentContext(), "WEBGL_compressed_texture_s3tc")
  else:
    result = false

proc loadTerrainTextures*(
  paths: openArray[string], forceRgba = false
): tuple[texture: TextureArray, compressed: bool] =
  ## Uploads prebuilt terrain mips, decoding only for the compatibility path.
  result.compressed = supportsBc3(forceRgba)
  let plan = prepareTerrainTextures(paths, result.compressed)
  glGenTextures(1, result.texture.addr)
  glBindTexture(GL_TEXTURE_2D_ARRAY, result.texture)
  try:
    for level in 0 ..< plan.levelCount:
      let
        size = plan.mipSize(level)
        bytes = plan.packedTextureLevel(level)
      if result.compressed:
        glCompressedTexImage3D(
          GL_TEXTURE_2D_ARRAY, level.GLint, GL_COMPRESSED_RGBA_S3TC_DXT5_EXT,
          size.width.GLsizei, size.height.GLsizei, plan.layerCount.GLsizei, 0,
          bytes.len.GLsizei, unsafeAddr bytes[0]
        )
      else:
        glTexImage3D(
          GL_TEXTURE_2D_ARRAY, level.GLint, GL_RGBA8.GLint,
          size.width.GLsizei, size.height.GLsizei, plan.layerCount.GLsizei, 0,
          GL_RGBA, GL_UNSIGNED_BYTE, unsafeAddr bytes[0]
        )
      let error = glGetError()
      if error != GL_NO_ERROR:
        raise newException(
          AssetError, "Terrain upload failed: " & $error.uint32
        )
    glTexParameteri(
      GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, (plan.levelCount - 1).GLint
    )
    glTexParameteri(
      GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint
    )
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT.GLint)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT.GLint)
  except:
    glDeleteTextures(1, result.texture.addr)
    raise
  finally:
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0)

proc deleteTexture*(texture: var Texture) =
  ## Releases an owned texture and clears the caller's handle.
  if texture != 0:
    glDeleteTextures(1, texture.addr)
    texture = 0

proc textureId*(texture: Texture): uint =
  ## Returns a stable resource key while this texture is alive.
  texture.uint

proc createTextureArray*(
  layers: seq[seq[Image]], repeat: bool
): TextureArray =
  ## Uploads explicit RGBA mip chains without modifying their alpha channels.
  let plan = prepareTextureArray(layers)
  glGenTextures(1, result.addr)
  glBindTexture(GL_TEXTURE_2D_ARRAY, result)
  try:
    for level in 0 ..< plan.levelCount:
      let size = plan.mipSize(level)
      glTexImage3D(
        GL_TEXTURE_2D_ARRAY, level.GLint, GL_RGBA8.GLint,
        size.width.GLsizei, size.height.GLsizei, plan.layerCount.GLsizei,
        0, GL_RGBA, GL_UNSIGNED_BYTE, nil
      )
    for upload in plan.textureUploads():
      glTexSubImage3D(
        GL_TEXTURE_2D_ARRAY, upload.level.GLint, 0, 0, upload.layer.GLint,
        upload.width.GLsizei, upload.height.GLsizei, 1,
        GL_RGBA, GL_UNSIGNED_BYTE, upload.data()
      )
    glTexParameteri(
      GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, (plan.levelCount - 1).GLint
    )
    when not defined(emscripten):
      glTexParameterf(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_ANISOTROPY_EXT, 8.0)
    glTexParameteri(
      GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.GLint
    )
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    let wrap = if repeat: GL_REPEAT.GLint else: GL_CLAMP_TO_EDGE.GLint
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, wrap)
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, wrap)
    let error = glGetError()
    if error != GL_NO_ERROR:
      raise newException(
        AssetError, "Texture array upload failed: " & $error.uint32
      )
  except:
    deleteTexture(result)
    raise
  finally:
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0)

proc updateTextureArrayLayer*(
  texture: TextureArray, layer: int, levels: seq[Image]
) =
  ## Replaces one allocated array layer with its explicit RGBA mip chain.
  let plan = prepareTextureArray(@[levels])
  if texture == 0 or layer < 0:
    raise newException(AssetError, "Invalid texture array layer.")
  glBindTexture(GL_TEXTURE_2D_ARRAY, texture)
  try:
    for upload in plan.textureUploads():
      glTexSubImage3D(
        GL_TEXTURE_2D_ARRAY, upload.level.GLint, 0, 0, layer.GLint,
        upload.width.GLsizei, upload.height.GLsizei, 1,
        GL_RGBA, GL_UNSIGNED_BYTE, upload.data()
      )
    let error = glGetError()
    if error != GL_NO_ERROR:
      raise newException(
        AssetError, "Texture layer update failed: " & $error.uint32
      )
  finally:
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0)

proc updateDataTexture(
  texture: var Texture, width, height: int, data: pointer,
  format, internalFormat, dataType: GLenum, linear: bool
) =
  ## Uploads complete data texels while preserving byte-row alignment state.
  var unpackAlignment: GLint
  glGetIntegerv(GL_UNPACK_ALIGNMENT, unpackAlignment.addr)
  let created = texture == 0
  if texture == 0:
    glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  try:
    glTexImage2D(
      GL_TEXTURE_2D, 0, internalFormat.GLint, width.GLsizei, height.GLsizei,
      0, format, dataType, data
    )
    let filter = if linear: GL_LINEAR.GLint else: GL_NEAREST.GLint
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint)
    let error = glGetError()
    if error != GL_NO_ERROR:
      raise newException(
        AssetError, "Data texture upload failed: " & $error.uint32
      )
  except:
    if created:
      deleteTexture(texture)
    raise
  finally:
    glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlignment)
    glBindTexture(GL_TEXTURE_2D, 0)

proc updateRgba32fTexture*(
  texture: var Texture, width, height: int, pixels: openArray[float32]
) =
  ## Replaces nearest-filtered RGBA floating-point data records.
  validateTexturePixels(width, height, 4, pixels.len)
  updateDataTexture(
    texture, width, height, unsafeAddr pixels[0],
    GL_RGBA, GL_RGBA32F, cGL_FLOAT, false
  )

proc createRgba32fTexture*(
  width, height: int, pixels: openArray[float32]
): Texture =
  ## Creates nearest-filtered RGBA floating-point data records.
  updateRgba32fTexture(result, width, height, pixels)

proc updateR32fTexture*(
  texture: var Texture, width, height: int, pixels: openArray[float32],
  linear = true
) =
  ## Replaces a single-channel floating-point field.
  validateTexturePixels(width, height, 1, pixels.len)
  updateDataTexture(
    texture, width, height, unsafeAddr pixels[0],
    GL_RED, GL_R32F, cGL_FLOAT, linear
  )

proc createR32fTexture*(
  width, height: int, pixels: openArray[float32], linear = true
): Texture =
  ## Creates a single-channel floating-point field.
  updateR32fTexture(result, width, height, pixels, linear)

proc updateR8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a single-channel normalized byte texture.
  validateTexturePixels(width, height, 1, pixels.len)
  updateDataTexture(
    texture, width, height, unsafeAddr pixels[0],
    GL_RED, GL_R8, GL_UNSIGNED_BYTE, linear
  )

proc createR8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a single-channel normalized byte texture.
  updateR8Texture(result, width, height, pixels, linear)

proc updateRg8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a two-channel normalized byte texture.
  validateTexturePixels(width, height, 2, pixels.len)
  updateDataTexture(
    texture, width, height, unsafeAddr pixels[0],
    GL_RG, GL_RG8, GL_UNSIGNED_BYTE, linear
  )

proc createRg8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a two-channel normalized byte texture.
  updateRg8Texture(result, width, height, pixels, linear)

proc updateRgba8Texture*(
  texture: var Texture, width, height: int, pixels: openArray[uint8],
  linear = true
) =
  ## Replaces a four-channel normalized byte texture.
  validateTexturePixels(width, height, 4, pixels.len)
  updateDataTexture(
    texture, width, height, unsafeAddr pixels[0],
    GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE, linear
  )

proc createRgba8Texture*(
  width, height: int, pixels: openArray[uint8], linear = true
): Texture =
  ## Creates a four-channel normalized byte texture.
  updateRgba8Texture(result, width, height, pixels, linear)
