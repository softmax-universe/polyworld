## GPU coverage for shared screen AO on the native multisampled window.
import
  opengl, pixie, vmath, windy,
  polyworld/screenocclusions

type
  Fixture = object
    program, vertexArray, vertexBuffer: GLuint
    vertices: seq[Vec3]

proc shader(kind: GLenum, source: string): GLuint =
  ## Compiles the fixture's minimal solid-color geometry shader.
  result = glCreateShader(kind)
  let sources = allocCStringArray(["#version 410 core\n" & source])
  defer: deallocCStringArray(sources)
  glShaderSource(result, 1, sources, nil)
  glCompileShader(result)
  var compiled: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, compiled.addr)
  doAssert compiled != 0, "Fixture shader must compile"

proc initFixture(): Fixture =
  ## Creates a floor and box renderer without importing game assets.
  let
    vertex = shader(GL_VERTEX_SHADER, """
layout(location = 0) in vec3 position;
uniform mat4 viewProjection;
void main() { gl_Position = viewProjection * vec4(position, 1.0); }
""")
    fragment = shader(GL_FRAGMENT_SHADER, """
uniform vec3 color;
out vec4 fragColor;
void main() { fragColor = vec4(color, 1.0); }
""")
  result.program = glCreateProgram()
  glAttachShader(result.program, vertex)
  glAttachShader(result.program, fragment)
  glLinkProgram(result.program)
  glDeleteShader(vertex)
  glDeleteShader(fragment)
  var linked: GLint
  glGetProgramiv(result.program, GL_LINK_STATUS, linked.addr)
  doAssert linked != 0, "Fixture program must link"
  glGenVertexArrays(1, result.vertexArray.addr)
  glGenBuffers(1, result.vertexBuffer.addr)
  glBindVertexArray(result.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, result.vertexBuffer)
  glEnableVertexAttribArray(0)
  glVertexAttribPointer(0, 3, cGL_FLOAT, GL_FALSE, sizeof(Vec3).GLsizei, nil)

proc quad(fixture: var Fixture, a, b, c, d: Vec3) =
  ## Adds two opaque triangles with shared positions.
  fixture.vertices.add [a, b, c, a, c, d]

proc draw(fixture: var Fixture, viewProjection: Mat4, color: Vec3) =
  ## Writes unlit geometry and depth so only AO can change the colors.
  glUseProgram(fixture.program)
  var matrix = viewProjection
  glUniformMatrix4fv(glGetUniformLocation(fixture.program, "viewProjection"),
    1, GL_FALSE, cast[ptr float32](matrix.addr))
  glUniform3f(glGetUniformLocation(fixture.program, "color"),
    color.x, color.y, color.z)
  glBindVertexArray(fixture.vertexArray)
  glBindBuffer(GL_ARRAY_BUFFER, fixture.vertexBuffer)
  glBufferData(GL_ARRAY_BUFFER, fixture.vertices.len * sizeof(Vec3),
    fixture.vertices[0].addr, GL_DYNAMIC_DRAW)
  glDrawArrays(GL_TRIANGLES, 0, fixture.vertices.len.GLsizei)
  fixture.vertices.setLen(0)

proc capture(size: IVec2): Image =
  ## Reads the current window color without changing framebuffer state.
  result = newImage(size.x, size.y)
  glReadPixels(0, 0, size.x, size.y, GL_RGBA, GL_UNSIGNED_BYTE,
    result.data[0].addr)

proc depth(size: IVec2): seq[float32] =
  ## Reads scene depth to catch accidental depth writes by the post pass.
  result = newSeq[float32](size.x * size.y)
  glReadPixels(0, 0, size.x, size.y, GL_DEPTH_COMPONENT, cGL_FLOAT,
    result[0].addr)

proc verifyState(fixture: Fixture, size: IVec2) =
  ## Checks the state needed by the water, effects and HUD passes afterward.
  var
    viewport: array[4, GLint]
    readFramebuffer, drawFramebuffer, program, vertexArray: GLint
    depthMask: GLboolean
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, readFramebuffer.addr)
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, drawFramebuffer.addr)
  glGetIntegerv(GL_CURRENT_PROGRAM, program.addr)
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, vertexArray.addr)
  glGetBooleanv(GL_DEPTH_WRITEMASK, depthMask.addr)
  doAssert viewport == [3.GLint, 5.GLint, size.x - 6, size.y - 10]
  doAssert readFramebuffer == 0 and drawFramebuffer == 0
  doAssert program.GLuint == fixture.program
  doAssert vertexArray.GLuint == fixture.vertexArray
  doAssert glIsEnabled(GL_DEPTH_TEST) and depthMask == GL_TRUE
  doAssert glIsEnabled(GL_MULTISAMPLE)
  doAssert not glIsEnabled(GL_BLEND) and not glIsEnabled(GL_CULL_FACE)

proc main() =
  ## Exercises contact shadows, body masking, disabling and resized targets.
  let window = newWindow("Screen AO verification", ivec2(480, 320),
    visible = false, msaa = msaa4x)
  window.makeContextCurrent()
  loadExtensions()
  var
    fixture = initFixture()
    occlusion = initScreenOcclusion()
  defer:
    occlusion.closeScreenOcclusion()
    glDeleteBuffers(1, fixture.vertexBuffer.addr)
    glDeleteVertexArrays(1, fixture.vertexArray.addr)
    glDeleteProgram(fixture.program)
    window.close()
  var samples: GLint
  glGetIntegerv(GL_SAMPLES, samples.addr)
  doAssert samples >= 4, "Exercise the same MSAA depth resolve as GotA"

  for requestedSize in [ivec2(480, 320), ivec2(514, 318)]:
    let size = requestedSize
    window.size = size
    pollEvents()
    window.makeContextCurrent()
    doAssert window.size == size
    for orthographic in [false, true]:
      let
        aspect = size.x.float32 / size.y.float32
        projection =
          if orthographic: ortho(-4'f * aspect, 4'f * aspect, -4'f, 4'f,
            0.1'f, 50'f)
          else: perspective(45'f, aspect, 0.1'f, 50'f)
        view = lookAt(vec3(4, 5, 7), vec3(0, 0.5, 0), vec3(0, 1, 0))
        vp = projection * view

      proc frame(enabled: bool, body: float32,
          captureBodies = true): tuple[before, after: Image] =
        ## Separates static floor depth from a box standing on that floor.
        occlusion.settings.enabled = enabled
        occlusion.settings.bodyOcclusion = body
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glViewport(0, 0, size.x, size.y)
        glEnable(GL_MULTISAMPLE)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LESS)
        glDepthMask(GL_TRUE)
        glDisable(GL_BLEND)
        glDisable(GL_CULL_FACE)
        glClearColor(0.06, 0.08, 0.1, 1)
        glClearDepth(1)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
        fixture.quad(vec3(-4, 0, -4), vec3(-4, 0, 4),
          vec3(4, 0, 4), vec3(4, 0, -4))
        fixture.draw(vp, vec3(0.8))
        if captureBodies:
          occlusion.captureGround(size)
        for x in [-0.7'f, 0.7'f]:
          fixture.quad(vec3(x, 0, -0.7), vec3(x, 1.8, -0.7),
            vec3(x, 1.8, 0.7), vec3(x, 0, 0.7))
        for z in [-0.7'f, 0.7'f]:
          fixture.quad(vec3(-0.7, 0, z), vec3(-0.7, 1.8, z),
            vec3(0.7, 1.8, z), vec3(0.7, 0, z))
        fixture.quad(vec3(-0.7, 1.8, -0.7), vec3(-0.7, 1.8, 0.7),
          vec3(0.7, 1.8, 0.7), vec3(0.7, 1.8, -0.7))
        fixture.draw(vp, vec3(0.6, 0.7, 0.85))
        result.before = capture(size)
        let sceneDepth = depth(size)
        glViewport(3, 5, size.x - 6, size.y - 10)
        occlusion.applyScreenOcclusion(size, projection)
        fixture.verifyState(size)
        result.after = capture(size)
        doAssert depth(size) == sceneDepth,
          "AO must leave scene depth intact for later water and effects"
        doAssert glGetError() == GL_NO_ERROR,
          "AO must work with multisampled depth without GL errors"

      let
        disabled = frame(false, 1)
        full = frame(true, 1)
        protected = frame(true, 0)
        withoutGround = frame(true, 0, false)
      doAssert disabled.before.data == disabled.after.data,
        "Disabled AO must preserve the entire scene"
      doAssert full.before.data == disabled.before.data
      doAssert withoutGround.after.data == full.after.data,
        "Ground capture must not leak from the previous frame"
      var groundDarkened, bodyDarkened, groundUnchanged, skyUnchanged: int
      for i, pixel in full.before.data:
        let
          shaded = full.after.data[i]
          masked = protected.after.data[i]
          ground = pixel.r == 204 and pixel.g == 204 and pixel.b == 204
          body = pixel.r == 153 and pixel.g in [178'u8, 179'u8] and
            pixel.b == 217
        if ground:
          if shaded.r.int < pixel.r.int - 3:
            inc groundDarkened
          elif shaded == pixel:
            inc groundUnchanged
          doAssert shaded == masked,
            "Protecting bodies must retain their contact shadows on ground"
        elif body:
          if shaded.r.int < pixel.r.int - 3:
            inc bodyDarkened
          doAssert masked == pixel,
            "Zero body occlusion must preserve character colors"
        elif pixel.r < 25 and pixel.b < 30:
          if shaded == pixel:
            inc skyUnchanged
      doAssert groundDarkened > 200, "Contacts must visibly darken the floor"
      doAssert bodyDarkened > 100, "Body strength must control visible shading"
      doAssert groundUnchanged > 2000, "Distant floor must stay unchanged"
      doAssert skyUnchanged > 2000, "Background must stay unchanged"
      echo "PASS screen AO ", size, " ortho=", orthographic,
        ": ", groundDarkened, " ground / ", bodyDarkened, " body pixels"

main()
