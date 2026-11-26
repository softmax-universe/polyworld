## Owns OpenGL resource storage for the shared scene passes.

import pixie
import passtypes
export passtypes

when defined(emscripten):
  {.emit: "#include <emscripten.h>\n#include <emscripten/html5_webgl.h>".}
  proc currentContext(): cint {.
    importc: "emscripten_webgl_get_current_context",
    header: "<emscripten/html5_webgl.h>"
  .}
    ## Returns the browser context whose extensions control sampler support.
  proc enableExtension(context: cint, extension: cstring): bool {.
    importc: "emscripten_webgl_enable_extension",
    header: "<emscripten/html5_webgl.h>"
  .}
    ## Enables an optional browser extension before its tokens are queried.

type
  UnpackState = object
    alignment, rowLength, imageHeight: GLint
    skipPixels, skipRows, skipImages, buffer: GLint

proc bindingName(target: GLenum): GLenum =
  ## Returns the texture-binding query corresponding to a resource target.
  case target
  of GL_TEXTURE_2D: GL_TEXTURE_BINDING_2D
  of GL_TEXTURE_2D_ARRAY: GL_TEXTURE_BINDING_2D_ARRAY
  of GL_TEXTURE_CUBE_MAP: GL_TEXTURE_BINDING_CUBE_MAP
  of GL_TEXTURE_2D_MULTISAMPLE: GL_TEXTURE_BINDING_2D_MULTISAMPLE
  else:
    raise newException(GpuError, "Unsupported OpenGL texture target")

proc saveUnpack(): UnpackState =
  ## Selects tightly packed client bytes while remembering caller upload state.
  glGetIntegerv(GL_UNPACK_ALIGNMENT, result.alignment.addr)
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, result.rowLength.addr)
  glGetIntegerv(GL_UNPACK_IMAGE_HEIGHT, result.imageHeight.addr)
  glGetIntegerv(GL_UNPACK_SKIP_PIXELS, result.skipPixels.addr)
  glGetIntegerv(GL_UNPACK_SKIP_ROWS, result.skipRows.addr)
  glGetIntegerv(GL_UNPACK_SKIP_IMAGES, result.skipImages.addr)
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, result.buffer.addr)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
  glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, 0)
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
  glPixelStorei(GL_UNPACK_SKIP_IMAGES, 0)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)

proc restoreUnpack(state: UnpackState) =
  ## Restores the complete unpack configuration after an upload.
  glPixelStorei(GL_UNPACK_ALIGNMENT, state.alignment)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, state.rowLength)
  glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, state.imageHeight)
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, state.skipPixels)
  glPixelStorei(GL_UNPACK_SKIP_ROWS, state.skipRows)
  glPixelStorei(GL_UNPACK_SKIP_IMAGES, state.skipImages)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, state.buffer.GLuint)

proc glFormat*(format: TextureFormat):
    tuple[internal: GLint, external, kind: GLenum] =
  ## Maps a shared texel description to OpenGL storage and upload formats.
  case format
  of Rgba8: (GL_RGBA8.GLint, GL_RGBA, GL_UNSIGNED_BYTE)
  of Bgra8: (GL_RGBA8.GLint, GL_RGBA, GL_UNSIGNED_BYTE)
  of Rgba16f: (GL_RGBA16F.GLint, GL_RGBA, cGL_FLOAT)
  of Rg32f: (GL_RG32F.GLint, GL_RG, cGL_FLOAT)
  of Rgba32f: (GL_RGBA32F.GLint, GL_RGBA, cGL_FLOAT)
  of R8: (GL_R8.GLint, GL_RED, GL_UNSIGNED_BYTE)
  of Rg8: (GL_RG8.GLint, GL_RG, GL_UNSIGNED_BYTE)
  of R32f: (GL_R32F.GLint, GL_RED, cGL_FLOAT)
  of Depth32f: (GL_DEPTH_COMPONENT32F.GLint, GL_DEPTH_COMPONENT, cGL_FLOAT)
  of DepthStencil:
    (GL_DEPTH24_STENCIL8.GLint, GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8)

proc mipCount*(width, height: int): int =
  ## Counts mip levels through the final one-pixel image.
  var size = max(width, height)
  while size > 0:
    inc result
    size = size shr 1

proc destroy*(buffer: VertexBuffer) =
  ## Releases owned buffer storage without changing caller bindings.
  if buffer != nil and buffer.handle != 0:
    glDeleteBuffers(1, buffer.handle.addr)
    buffer.handle = 0
    buffer.size = 0

proc initializeIndexBuffer(buffer: VertexBuffer) =
  ## Establishes WebGL's index-data role without altering the caller's VAO.
  var previous: GLint
  var temporary: GLuint
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, previous.addr)
  glGenVertexArrays(1, temporary.addr)
  defer:
    glBindVertexArray(previous.GLuint)
    glDeleteVertexArrays(1, temporary.addr)
  glBindVertexArray(temporary)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer.handle)

proc updateBuffer*[T](buffer: VertexBuffer, values: openArray[T]) =
  ## Replaces bytes while retaining the buffer's explicit vertex or index role.
  if buffer == nil:
    raise newException(GpuError, "Cannot upload to a nil OpenGL buffer")
  if values.len > int.high div sizeof(T):
    raise newException(GpuError, "OpenGL buffer size exceeds address space")
  if buffer.target == 0.GLenum:
    buffer.target = GL_ARRAY_BUFFER
  if buffer.handle == 0:
    glGenBuffers(1, buffer.handle.addr)
    if buffer.target == GL_ELEMENT_ARRAY_BUFFER:
      initializeIndexBuffer(buffer)
  let
    target =
      if buffer.target == GL_ELEMENT_ARRAY_BUFFER: GL_COPY_WRITE_BUFFER
      else: GL_ARRAY_BUFFER
    binding =
      if buffer.target == GL_ELEMENT_ARRAY_BUFFER: GL_COPY_WRITE_BUFFER_BINDING
      else: GL_ARRAY_BUFFER_BINDING
  var previous: GLint
  glGetIntegerv(binding, previous.addr)
  defer: glBindBuffer(target, previous.GLuint)
  glBindBuffer(target, buffer.handle)
  let size = values.len * sizeof(T)
  glBufferData(target, size.GLsizeiptr,
    (if size == 0: nil else: values[0].unsafeAddr), GL_DYNAMIC_DRAW)
  buffer.size = size

proc newBuffer*[T](values: openArray[T]): VertexBuffer =
  ## Creates vertex or streamed storage with a stable non-index binding role.
  result = VertexBuffer(target: GL_ARRAY_BUFFER)
  result.updateBuffer(values)

proc newIndexBuffer*[T](values: openArray[T]): VertexBuffer =
  ## Creates index storage with the role required by WebGL element draws.
  result = VertexBuffer(target: GL_ELEMENT_ARRAY_BUFFER)
  result.updateBuffer(values)

proc destroy*(image: GpuImage) =
  ## Releases the sampler and any texture storage owned by this wrapper.
  if image == nil:
    return
  if image.sampler != 0:
    glDeleteSamplers(1, image.sampler.addr)
    image.sampler = 0
  if image.ownsHandle and image.handle != 0:
    glDeleteTextures(1, image.handle.addr)
  image.handle = 0

proc textureAddress(address: TextureAddress): GLint =
  ## Translates one explicitly authored sampler addressing mode.
  case address
  of ClampEdge: GL_CLAMP_TO_EDGE.GLint
  of Repeat: GL_REPEAT.GLint
  of MirrorRepeat: GL_MIRRORED_REPEAT.GLint

proc supportsAnisotropy(): bool =
  ## Enables browser anisotropy or checks native support before querying tokens.
  when defined(emscripten):
    let context = currentContext()
    if context != 0:
      return enableExtension(context, "EXT_texture_filter_anisotropic") or
        enableExtension(context, "WEBKIT_EXT_texture_filter_anisotropic") or
        enableExtension(context, "MOZ_EXT_texture_filter_anisotropic")
  else:
    var count: GLint
    glGetIntegerv(GL_NUM_EXTENSIONS, count.addr)
    for i in 0 ..< count.int:
      let extension = glGetStringi(GL_EXTENSIONS, i.GLuint)
      if extension != nil and $cast[cstring](extension) in [
          "GL_EXT_texture_filter_anisotropic",
          "GL_ARB_texture_filter_anisotropic"]:
        return true

proc setTextureSampling*(image: GpuImage, state: SamplerState) =
  ## Translates the complete shared sampler description to OpenGL state.
  if image == nil or image.handle == 0:
    return
  when not defined(emscripten):
    if image.target == GL_TEXTURE_2D_MULTISAMPLE:
      return
  if image.sampler == 0:
    glGenSamplers(1, image.sampler.addr)
  let
    magnify = if state.magLinear: GL_LINEAR else: GL_NEAREST
    minify =
      if state.mipmaps and image.levels > 1:
        if state.mipLinear:
          if state.minLinear: GL_LINEAR_MIPMAP_LINEAR
          else: GL_NEAREST_MIPMAP_LINEAR
        else:
          if state.minLinear: GL_LINEAR_MIPMAP_NEAREST
          else: GL_NEAREST_MIPMAP_NEAREST
      else:
        if state.minLinear: GL_LINEAR else: GL_NEAREST
  glSamplerParameteri(image.sampler, GL_TEXTURE_MAG_FILTER, magnify.GLint)
  glSamplerParameteri(image.sampler, GL_TEXTURE_MIN_FILTER, minify.GLint)
  glSamplerParameteri(image.sampler, GL_TEXTURE_WRAP_S,
    textureAddress(state.wrapS))
  glSamplerParameteri(image.sampler, GL_TEXTURE_WRAP_T,
    textureAddress(state.wrapT))
  glSamplerParameteri(image.sampler, GL_TEXTURE_WRAP_R,
    textureAddress(state.wrapR))
  glSamplerParameteri(image.sampler, GL_TEXTURE_COMPARE_MODE,
    (if state.comparison: GL_COMPARE_REF_TO_TEXTURE else: GL_NONE).GLint)
  glSamplerParameteri(image.sampler, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL.GLint)
  when compiles(state.maxAnisotropy):
    let requested = max(1.0'f, state.maxAnisotropy.float32)
    if (requested > 1 or image.anisotropy > 1) and supportsAnisotropy():
      var limit: GLfloat
      glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, limit.addr)
      image.anisotropy = min(requested, limit)
      glSamplerParameterf(image.sampler, GL_TEXTURE_MAX_ANISOTROPY_EXT,
        image.anisotropy)

proc setTextureSampling*(image: GpuImage, linear: bool, repeat = false) =
  ## Applies the common texture convenience policy through a full sampler.
  let wrap = if repeat: Repeat else: ClampEdge
  image.setTextureSampling(SamplerState(minLinear: linear, magLinear: linear,
    mipLinear: linear, mipmaps: image != nil and image.levels > 1,
    wrapS: wrap, wrapT: wrap, wrapR: wrap))

proc setComparisonSampling*(image: GpuImage, linear = true) =
  ## Selects depth comparison for an explicitly declared shadow sampler.
  image.setTextureSampling(SamplerState(minLinear: linear, magLinear: linear,
    mipLinear: linear, mipmaps: image != nil and image.levels > 1,
    comparison: true))

proc setPassSampling*(image: GpuImage, linear = true, repeat = false,
    comparison = false) =
  ## Applies the shared scene pass's filtering and comparison intent.
  if comparison:
    image.setComparisonSampling(linear)
  else:
    image.setTextureSampling(linear, repeat)

proc textureFromNative*(handle: GLuint, width, height: int,
    format = Rgba8, target = GL_TEXTURE_2D, ownsHandle = false,
    linear = true, repeat = false, layers = 1, levels = 1): GpuImage =
  ## Wraps borrowed or transferred texture storage with independent sampling.
  if handle == 0:
    return nil
  result = GpuImage(handle: handle, width: width, height: height,
    pixelFormat: format, target: target, ownsHandle: ownsHandle,
    nativeFormat: glFormat(format).internal.GLenum,
    layers: layers, levels: levels)
  result.setTextureSampling(linear, repeat)

converter borrowedTexture*(handle: GLuint): GpuImage =
  ## Borrows legacy texture handles without changing their sampling or lifetime.
  if handle != 0:
    result = GpuImage(handle: handle, target: GL_TEXTURE_2D,
      levels: 1, layers: 1, pixelFormat: Rgba8, nativeFormat: GL_RGBA8)

proc allocateImage*(width, height: int, format: TextureFormat,
    linear = true, repeat = false, layers = 1, levels = 1,
    arrayTexture = false, cube = false, samples = 1): GpuImage =
  ## Allocates explicit texture storage without disturbing caller bindings.
  if width <= 0 or height <= 0 or layers <= 0 or levels <= 0 or samples <= 0:
    raise newException(GpuError, "OpenGL texture dimensions must be positive")
  if levels > mipCount(width, height):
    raise newException(GpuError, "OpenGL texture has too many mip levels")
  if cube and (width != height or layers != 6):
    raise newException(GpuError, "OpenGL cubemaps need six square faces")
  if samples > 1 and (arrayTexture or cube or levels != 1):
    raise newException(GpuError, "Unsupported multisample texture shape")
  var target =
    if cube: GL_TEXTURE_CUBE_MAP
    elif arrayTexture or layers > 1: GL_TEXTURE_2D_ARRAY
    else: GL_TEXTURE_2D
  if samples > 1:
    when defined(emscripten):
      raise newException(GpuError, "WebGL multisampling uses renderbuffers")
    else:
      target = GL_TEXTURE_2D_MULTISAMPLE
  var previous: GLint
  glGetIntegerv(bindingName(target), previous.addr)
  let unpack = saveUnpack()
  defer:
    restoreUnpack(unpack)
    glBindTexture(target, previous.GLuint)
  result = GpuImage(width: width, height: height, layers: layers,
    levels: levels, target: target, pixelFormat: format, ownsHandle: true,
    nativeFormat: glFormat(format).internal.GLenum)
  glGenTextures(1, result.handle.addr)
  glBindTexture(target, result.handle)
  let spec = glFormat(format)
  if samples > 1:
    when not defined(emscripten):
      glTexImage2DMultisample(target, samples.GLsizei, spec.internal,
        width.GLsizei, height.GLsizei, GL_TRUE)
  else:
    for level in 0 ..< levels:
      let
        w = max(1, width shr level).GLsizei
        h = max(1, height shr level).GLsizei
      if cube:
        for face in 0 ..< 6:
          glTexImage2D((GL_TEXTURE_CUBE_MAP_POSITIVE_X.uint + face.uint).GLenum,
            level.GLint, spec.internal, w, h, 0, spec.external, spec.kind, nil)
      elif target == GL_TEXTURE_2D_ARRAY:
        glTexImage3D(target, level.GLint, spec.internal, w, h, layers.GLsizei,
          0, spec.external, spec.kind, nil)
      else:
        glTexImage2D(target, level.GLint, spec.internal, w, h,
          0, spec.external, spec.kind, nil)
    glTexParameteri(target, GL_TEXTURE_BASE_LEVEL, 0)
    glTexParameteri(target, GL_TEXTURE_MAX_LEVEL, (levels - 1).GLint)
  let error = glGetError()
  if error != GL_NO_ERROR:
    result.destroy()
    raise newException(GpuError,
      "OpenGL texture allocation failed: " & $error.uint32)
  result.setTextureSampling(linear, repeat)

proc uploadLevel*(texture: GpuImage, layer, level, width, height: int,
    data: pointer) =
  ## Uploads one complete mip or layer using tightly packed client bytes.
  if texture == nil or texture.handle == 0 or data == nil:
    raise newException(GpuError, "OpenGL texture upload needs storage and bytes")
  if layer < 0 or layer >= texture.layers or level < 0 or
      level >= texture.levels or width != max(1, texture.width shr level) or
      height != max(1, texture.height shr level):
    raise newException(GpuError, "OpenGL texture upload shape does not match")
  var previous: GLint
  glGetIntegerv(bindingName(texture.target), previous.addr)
  let unpack = saveUnpack()
  defer:
    restoreUnpack(unpack)
    glBindTexture(texture.target, previous.GLuint)
  glBindTexture(texture.target, texture.handle)
  let spec = glFormat(texture.pixelFormat)
  if texture.target == GL_TEXTURE_2D_ARRAY:
    glTexSubImage3D(texture.target, level.GLint, 0, 0, layer.GLint,
      width.GLsizei, height.GLsizei, 1, spec.external, spec.kind, data)
  else:
    let target =
      if texture.target == GL_TEXTURE_CUBE_MAP:
        (GL_TEXTURE_CUBE_MAP_POSITIVE_X.uint + layer.uint).GLenum
      else:
        texture.target
    glTexSubImage2D(target, level.GLint, 0, 0, width.GLsizei, height.GLsizei,
      spec.external, spec.kind, data)

proc generateMipmaps*(texture: GpuImage) =
  ## Generates the allocated mip chain while preserving the current binding.
  if texture == nil or texture.handle == 0 or texture.levels <= 1:
    return
  var previous: GLint
  glGetIntegerv(bindingName(texture.target), previous.addr)
  defer: glBindTexture(texture.target, previous.GLuint)
  glBindTexture(texture.target, texture.handle)
  glGenerateMipmap(texture.target)

proc uploadImage*(texture: GpuImage, image: Image, layer = 0) =
  ## Uploads straight RGBA image bytes and all allocated mip levels.
  if image == nil or texture == nil or texture.pixelFormat != Rgba8:
    raise newException(GpuError, "OpenGL image uploads need RGBA8 storage")
  var mip = image
  for level in 0 ..< texture.levels:
    texture.uploadLevel(layer, level, mip.width, mip.height, mip.data[0].addr)
    if level + 1 < texture.levels:
      mip = mip.resize(max(1, mip.width div 2), max(1, mip.height div 2))

proc newTexture*(image: Image, linear = true, repeat = false,
    mipmaps = false): GpuImage =
  ## Creates a sampled texture from authored RGBA image bytes.
  if image == nil:
    raise newException(GpuError, "Cannot create an OpenGL texture from nil")
  result = allocateImage(image.width, image.height, Rgba8, linear, repeat,
    levels = (if mipmaps: mipCount(image.width, image.height) else: 1))
  result.uploadImage(image)

proc updateTexture*(texture: GpuImage, image: Image) =
  ## Updates an existing image and its allocated mip levels.
  texture.uploadImage(image)
