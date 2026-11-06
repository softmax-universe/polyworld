import
  std/[os, strutils],
  opengl, pixie, vmath, windy,
  polyworld/[characters, chargen, shadows, toon],
  ../../games/light_vs_dark/[appearances, assets, content, factions, resourcepacks]

const Size = 768

proc run() =
  ## Captures the actual merged LvD character through its runtime renderer.
  let
    output = getEnv("REVIEW_OUTPUT", "tmp/chargen/resource-packs/renders")
    window = newWindow(
      "Resource backpack review", ivec2(Size, Size),
      visible = false, vsync = false
    )
  defer:
    window.close()
  createDir(output)
  window.makeContextCurrent()
  loadExtensions()
  var framebuffer, texture, depth: GLuint
  glGenFramebuffers(1, framebuffer.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
  glGenTextures(1, texture.addr)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(
    GL_TEXTURE_2D, 0, GL_RGBA8.GLint, Size, Size, 0,
    GL_RGBA, GL_UNSIGNED_BYTE, nil
  )
  glFramebufferTexture2D(
    GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0
  )
  glGenRenderbuffers(1, depth.addr)
  glBindRenderbuffer(GL_RENDERBUFFER, depth)
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, Size, Size)
  glFramebufferRenderbuffer(
    GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth
  )
  doAssert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
  defer:
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glDeleteFramebuffers(1, framebuffer.addr)
    glDeleteTextures(1, texture.addr)
    glDeleteRenderbuffers(1, depth.addr)
  initSunShadows(20, 40)
  sunShadowsEnabled = false
  let
    scene = CharacterScene(toon: newToonContext(), shading: ToonCharacters)
    manifest = readManifest(ChargenLibrary)
    roster = readCharacterRoster([PeterRiver])
  var
    cache: UnitModelCache
    pose: CharacterPose
  scene.toon.cameraPosition = vec3(0, 1.65, 4)
  scene.toon.view = lookAt(
    scene.toon.cameraPosition, vec3(0, 0.64, 0), vec3(0, 1, 0)
  )
  scene.toon.proj = ortho(-0.83'f, 0.83'f, -0.83'f, 0.83'f, 0.01'f, 100'f)
  for pack in WoodPack .. GoldPack:
    let model = cache.loadUnitModel(
      manifest, roster.players[0][PeonUnit.ord], PeonUnit, pack = pack
    )
    doAssert model.mergedMeshes.len == 1
    for name in ["Idle_Loop", "Jog_Fwd_Loop", "Interact"]:
      let clip = model.clipIndex(name)
      for sample in 0 .. 3:
        for view, angle in [0'f, PI.float32 / 2, PI.float32,
            PI.float32 * 1.70]:
          scene.prepareCharacter(
            pose, model, vec3(0), angle, clip,
            model.clipDuration(clip) * sample.float32 / 4
          )
          glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
          glViewport(0, 0, Size, Size)
          glDepthMask(GL_TRUE)
          glClearColor(0.79, 0.78, 0.76, 1)
          glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
          scene.drawCharacter(pose)
          glFinish()
          doAssert glGetError() == GL_NO_ERROR
          let image = newImage(Size, Size)
          glReadPixels(
            0, 0, Size, Size, GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr
          )
          image.flipVertical()
          image.writeFile(output / (
            ($pack).toLowerAscii & "-" & name & "-" & $sample &
            "-" & $view & ".png"
          ))
    echo pack, ": merged poses rendered"

run()
