## Verifies the same model pixels through every shared rendering backend.
import
  chroma, gltf, pixie, vmath, windy,
  polyworld/[characters, modelresources, shadows, toon],
  polyworld/backends/passes/common as gpu,
  polyworld/backends/passes/meshes

when not (defined(useMetal4) or defined(useDirectX) or defined(useVulkan)):
  import opengl

proc visibleNode(): Node =
  ## Creates a node with an explicit identity rest transform.
  Node(visible: true, baseVisible: true, scale: vec3(1), baseScale: vec3(1),
    rot: quat(), baseRot: quat())

proc main() =
  ## Reads real GPU pixels from the shared engine target without a drawable.
  let window = newWindow("Shared Toon pixels", ivec2(96, 64), visible = false)
  when not (defined(useMetal4) or defined(useDirectX) or defined(useVulkan)):
    window.makeContextCurrent()
    loadExtensions()
  gpu.initNative(window)
  let target = gpu.newRenderTarget(96, 64, stencil = true)
  gpu.pushTarget(target)
  let
    scene = CharacterScene(toon: newToonContext(), shading: ToonCharacters)
    root = visibleNode()
    joint = visibleNode()
    body = visibleNode()
    image = newImage(1, 1)
    material = Material(baseColor: image, baseColorFactor: color(1, 1, 1, 1),
      doubleSided: false, unlit: true,
      baseColorTransform: TextureTransform(scale: vec2(1)))
    primitive = gltf.Primitive(mode: TrianglesMode, material: material,
      points: @[vec3(-0.3, -0.6, 0), vec3(0.3, -0.6, 0), vec3(0, 0.6, 0)],
      normals: @[vec3(0, 0, 1), vec3(0, 0, 1), vec3(0, 0, 1)],
      jointIds: @[[0'u16, 0, 0, 0], [0'u16, 0, 0, 0], [0'u16, 0, 0, 0]],
      jointWeights: @[vec4(1, 0, 0, 0), vec4(1, 0, 0, 0), vec4(1, 0, 0, 0)])
  defer:
    clearModelResources()
    gpu.popTarget()
    gpu.destroy(target)
    when defined(useMetal4):
      gpu.shutdownMetal()
    elif defined(useDirectX) or defined(useVulkan):
      gpu.shutdownNative()
    window.close()
  image.data[0] = rgbx(255, 255, 255, 255)
  body.mesh = Mesh(primitives: @[primitive])
  body.skin = Skin(joints: @[joint], inverseBindMatrices: @[mat4()])
  root.nodes = @[joint, body]
  let
    view = lookAt(vec3(0, 0, 3), vec3(0), vec3(0, 1, 0))
    projection = ortho(-1.0'f, 1, -1, 1, 0.1, 10)
  scene.toon.view = view
  scene.toon.proj = projection
  scene.toon.cameraPosition = vec3(0, 0, 3)
  sunShadowsEnabled = false
  for mode in [ToonCharacters]:
    gpu.clear(color(0, 0, 0, 1))
    scene.shading = mode
    for index in 0 .. 1:
      let
        transform = translate(vec3(if index == 0: -0.45'f else: 0.45'f, 0, 0))
        tint = if index == 0: color(1, 0, 0, 1) else: color(0, 1, 0, 1)
      scene.toon.transform = transform
      scene.toon.tint = tint
      scene.toon.draw(root)
    let pixels = gpu.captureTargetImage()
    doAssert pixels[26, 36].r > 200 and pixels[26, 36].g < 20, $mode
    doAssert pixels[70, 36].g > 200 and pixels[70, 36].r < 20, $mode
    doAssert pixels[48, 36].r == 0 and pixels[48, 36].g == 0, $mode
  material.alphaMode = MaskAlphaMode
  material.alphaCutoff = 0.5
  image.data[0] = rgbx(255, 255, 255, 0)
  primitive.clearModelGpu()
  gpu.clear(color(0, 0, 0, 1))
  scene.toon.transform = mat4()
  scene.toon.tint = color(1, 1, 1, 1)
  scene.toon.draw(root)
  doAssert gpu.captureTargetImage()[48, 36] == rgbx(0, 0, 0, 255)
  image.data[0] = rgbx(255, 255, 255, 255)
  inc material.materialVersion
  joint.pos = vec3(0.45, 0, 0)
  gpu.clear(color(0, 0, 0, 1))
  scene.toon.draw(root)
  let skinned = gpu.captureTargetImage()
  doAssert skinned[70, 36].r > 200
  doAssert skinned[48, 36].r == 0
  material.alphaMode = BlendAlphaMode
  material.baseColorFactor = color(1, 1, 1, 0.5)
  gpu.clear(color(0, 0, 0, 1))
  scene.toon.draw(root)
  let transparent = gpu.captureTargetImage()[70, 36]
  doAssert abs(transparent.r.int - 128) <= 1
  when defined(useMetal4) or defined(useDirectX) or defined(useVulkan):
    doAssert transparent.a == 255
  else:
    doAssert abs(transparent.a.int - 191) <= 1
  echo "Shared Toon instances, cutouts, skinning, and alpha blending passed."

main()
