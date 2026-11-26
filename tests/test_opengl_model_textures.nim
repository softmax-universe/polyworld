## Verifies model cubemaps ignore and preserve caller upload state.

import
  pixie, vmath, windy,
  polyworld/backends/opengl/[meshtextures, passapi]

proc main() =
  ## Runs real GPU upload and mip checks without displaying a window.
  let window = newWindow("Model texture uploads", ivec2(16), visible = false)
  defer: window.close()
  window.makeContextCurrent()
  loadExtensions()
  initNative(window)
  let
    previous = allocateImage(1, 1, Rgba8, layers = 6, cube = true)
    unpack = newBuffer([0'u32])
  defer:
    previous.destroy()
    unpack.destroy()
  glActiveTexture(GL_TEXTURE5)
  glBindTexture(GL_TEXTURE_CUBE_MAP, previous.handle)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpack.handle)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 8)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 9)
  glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, 7)
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 2)
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 3)
  glPixelStorei(GL_UNPACK_SKIP_IMAGES, 1)
  var faces: array[6, Image]
  for index in 0 ..< faces.len:
    faces[index] = newImage(4, 4)
    faces[index].fill(rgbx((index * 30 + 20).uint8, 90, 160, 255))
  let cube = newCubeTexture(faces)
  defer: cube.destroy()
  doAssert cube.layers == 6 and cube.levels == 3
  for (field, expected) in [
    (GL_ACTIVE_TEXTURE, GL_TEXTURE5.GLint),
    (GL_TEXTURE_BINDING_CUBE_MAP, previous.handle.GLint),
    (GL_PIXEL_UNPACK_BUFFER_BINDING, unpack.handle.GLint),
    (GL_UNPACK_ALIGNMENT, 8.GLint),
    (GL_UNPACK_ROW_LENGTH, 9.GLint),
    (GL_UNPACK_IMAGE_HEIGHT, 7.GLint),
    (GL_UNPACK_SKIP_PIXELS, 2.GLint),
    (GL_UNPACK_SKIP_ROWS, 3.GLint),
    (GL_UNPACK_SKIP_IMAGES, 1.GLint)
  ]:
    var actual: GLint
    glGetIntegerv(field, actual.addr)
    doAssert actual == expected, "Upload state changed: " & $field.uint32
  var framebuffer: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  defer: glDeleteFramebuffers(1, framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  for face in 0 ..< faces.len:
    for level in 0 ..< cube.levels:
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        (GL_TEXTURE_CUBE_MAP_POSITIVE_X.uint + face.uint).GLenum,
        cube.handle, level.GLint)
      doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
      var pixel: ColorRGBX
      glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.addr)
      doAssert pixel == faces[face].data[0],
        "Cubemap face " & $face & " mip " & $level & " changed texels."
  doAssert glGetError() == GL_NO_ERROR
  echo "OpenGL cubemap faces, mipmaps, and caller unpack state passed."

main()
