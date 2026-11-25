## Verifies immediate model instances, skin palettes, and material invalidation.
import
  chroma, gltf, pixie, vmath, windy,
  polyworld/[characters, modelresources, shadows, toon],
  polyworld/backends/metal/common as metal

proc visibleNode(): Node =
  ## Creates a node with an explicit identity rest transform.
  Node(visible: true, baseVisible: true, scale: vec3(1), baseScale: vec3(1),
    rot: quat(), baseRot: quat())

proc main() =
  ## Reads real GPU pixels from the shared engine target without a drawable.
  let
    window = newWindow("Metal characters", ivec2(96, 64), visible = false)
    scene = newCharacterScene(window)
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
    metal.shutdownMetal()
    window.close()
  image.data[0] = rgbx(255, 255, 255, 255)
  body.mesh = Mesh(primitives: @[primitive])
  body.skin = Skin(joints: @[joint], inverseBindMatrices: @[mat4()])
  root.nodes = @[joint, body]
  let
    view = lookAt(vec3(0, 0, 3), vec3(0), vec3(0, 1, 0))
    projection = ortho(-1.0'f, 1, -1, 1, 0.1, 10)
  scene.beginCharacters(window, view, projection, vec3(0, 0, 3))
  sunShadowsEnabled = false
  for mode in [ToonCharacters, PbrCharacters]:
    metal.clear(color(0, 0, 0, 1))
    scene.shading = mode
    for index in 0 .. 1:
      let
        transform = translate(vec3(if index == 0: -0.45'f else: 0.45'f, 0, 0))
        tint = if index == 0: color(1, 0, 0, 1) else: color(0, 1, 0, 1)
      case mode
      of ToonCharacters:
        scene.toon.transform = transform
        scene.toon.tint = tint
        scene.toon.draw(root)
      of PbrCharacters:
        scene.context.transform = transform
        scene.context.tint = tint
        scene.renderer.drawPbr(scene.context, root)
    let pixels = metal.captureTargetImage()
    doAssert pixels[26, 36].r > 200 and pixels[26, 36].g < 20, $mode
    doAssert pixels[70, 36].g > 200 and pixels[70, 36].r < 20, $mode
    doAssert pixels[48, 36].r == 0 and pixels[48, 36].g == 0, $mode
  material.alphaMode = MaskAlphaMode
  material.alphaCutoff = 0.5
  image.data[0] = rgbx(255, 255, 255, 0)
  primitive.clearModelGpu()
  metal.clear(color(0, 0, 0, 1))
  scene.toon.transform = mat4()
  scene.toon.tint = color(1, 1, 1, 1)
  scene.toon.draw(root)
  doAssert metal.captureTargetImage()[48, 36] == rgbx(0, 0, 0, 255)
  image.data[0] = rgbx(255, 255, 255, 255)
  inc material.materialVersion
  joint.pos = vec3(0.45, 0, 0)
  metal.clear(color(0, 0, 0, 1))
  scene.toon.draw(root)
  let skinned = metal.captureTargetImage()
  doAssert skinned[70, 36].r > 200
  doAssert skinned[48, 36].r == 0
  echo "Metal toon/PBR instances, cutouts, cache invalidation, and skinning passed."

main()
