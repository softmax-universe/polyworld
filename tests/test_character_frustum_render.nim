## A skinned triangle at the edge of the same camera and light frustum.
import chroma, gltf, opengl, pixie, vmath, windy
import polyworld/[characters, frustums, shadows, toon]

proc node(): Node =
  Node(visible: true, baseVisible: true, rot: quat(), baseRot: quat(),
    scale: vec3(1), baseScale: vec3(1))

proc main() =
  let
    size = ivec2(64, 64)
    window = newWindow("Character frustum", size, visible = false)
  defer: window.close()
  window.makeContextCurrent()
  loadExtensions()
  initSunShadows()

  let
    scene = CharacterScene(shading: ToonCharacters, toon: newToonContext())
    root = node()
    joint = node()
    body = node()
    model = CharacterModel(file: GltfFile(root: root), baseTransform: mat4())
    weight = vec4(254'f32 / 255, 0, 0, 0)
    triangle = Primitive(mode: TrianglesMode,
      material: Material(doubleSided: true, alphaMode: OpaqueAlphaMode,
        baseColor: newImage(1, 1), baseColorFactor: color(1, 1, 1, 1)),
      points: @[vec3(1, -0.5, 0), vec3(2, -0.5, 0), vec3(1, 0.5, 0)],
      jointIds: @[[0'u16, 0, 0, 0], [0'u16, 0, 0, 0], [0'u16, 0, 0, 0]],
      jointWeights: @[weight, weight, weight])
  root.nodes = @[joint, body]
  body.mesh = Mesh(primitives: @[triangle])
  body.skin = Skin(joints: @[joint], inverseBindMatrices: @[mat4()])
  var pose: CharacterPose
  scene.prepareCharacter(pose, model, vec3(255, 0, 0), 0.4, 0, 0)
  doAssert pose.toon.boundsValid
  scene.toon.proj = ortho(-1'f32, 1, -1, 1, 0.1, 20)

  # A hidden window may have no drawable. Use a depth attachment to count
  # samples from the color shader without capturing an image.
  var framebuffer, depth, query: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  glGenRenderbuffers(1, depth.addr)
  defer:
    glDeleteFramebuffers(1, framebuffer.addr)
    glDeleteRenderbuffers(1, depth.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glBindRenderbuffer(GL_RENDERBUFFER, depth)
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, size.x, size.y)
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
    GL_RENDERBUFFER, depth)
  glDrawBuffer(GL_NONE)
  glReadBuffer(GL_NONE)
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  glGenQueries(1, query.addr)
  defer: glDeleteQueries(1, query.addr)
  for (cameraX, expected) in [(250'f32, false), (254.375'f32, true)]:
    let eye = vec3(cameraX, 0, 5)
    scene.toon.view = lookAt(eye, eye + vec3(0, 0, -1), vec3(0, 1, 0))
    sunLightMvp0 = scene.toon.proj * scene.toon.view
    doAssert pose.toon.bounds.inFrustum(sunLightMvp0) == expected
    for depthPass in [false, true]:
      scene.sunDepthPass = depthPass
      if depthPass:
        beginSunDepthPass(0)
      else:
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
      glViewport(0, 0, size.x, size.y)
      glClear(GL_DEPTH_BUFFER_BIT)
      glBeginQuery(GL_ANY_SAMPLES_PASSED, query)
      scene.drawCharacter(pose)
      glEndQuery(GL_ANY_SAMPLES_PASSED)
      var samples: GLuint
      glGetQueryObjectuiv(query, GL_QUERY_RESULT, samples.addr)
      if depthPass:
        endSunDepthPass(size)
      doAssert glGetError() == GL_NO_ERROR
      doAssert (samples != 0) == expected,
        "cameraX=" & $cameraX & " depthPass=" & $depthPass & " samples=" & $samples

main()
