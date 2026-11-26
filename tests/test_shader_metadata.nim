import
  std/json,
  vmath,
  polyworld/shadermetadata,
  polyworld/backends/metal/uniforms as metalUniforms,
  polyworld/backends/native/uniforms as nativeUniforms

const MetalSource = """
struct ShadyUniforms {
  bool enabled;
  bool visible;
  float3 light;
  float3x3 normal;
  float weights[2];
  float4x4 joints[2];
};
struct VertexInput {
  float3 position [[attribute(3)]];
};
fragment float4 fragmentMain(
  depth2d<float> shadowMap [[texture(2)]],
  sampler shadowMapSampler [[sampler(5)]]
) {}
"""

let reflection = %*{
  "inputs": [{"name": "position", "location": 3}],
  "textures": [{"name": "shadowMap", "binding": 2,
    "type": "sampler2DShadow"}],
  "ubos": [{"type": "_uniforms", "block_size": 256}],
  "types": {"_uniforms": {"members": [
    {"name": "enabled", "type": "bool", "offset": 0},
    {"name": "visible", "type": "bool", "offset": 4},
    {"name": "light", "type": "vec3", "offset": 16},
    {"name": "normal", "type": "mat3", "offset": 32,
      "matrix_stride": 16},
    {"name": "weights", "type": "float", "offset": 80,
      "array": [2], "array_stride": 16},
    {"name": "joints", "type": "mat4", "offset": 128,
      "matrix_stride": 16, "array": [2], "array_stride": 64}
  ]}}
}

proc readMetal[T](buffer: metalUniforms.UniformBuffer, offset: int): T =
  ## Reads one scalar from the Metal byte ABI without alignment assumptions.
  copyMem(result.addr, buffer.data[offset].unsafeAddr, sizeof(T))

proc nativeFloat(buffer: nativeUniforms.GpuConstants, offset: int): float32 =
  ## Reads a reflected native byte offset from its four-byte storage words.
  cast[float32](buffer.words[offset div 4])

var
  metal = metalUniforms.initUniformBuffer(MetalSource)
  native = nativeUniforms.constants(reflectedShaderLayout(reflection))

for name in ["enabled", "visible", "light", "normal", "weights", "joints"]:
  let index = metal.layout.fieldIndex(name)
  doAssert index == native.layout.fieldIndex(name)
  doAssert metal.layout.fields[index].kind == native.layout.fields[index].kind
  doAssert metal.layout.fieldIndex(index) == index
doAssert metal.layout.fieldIndex("absent") == -1
doAssert native.layout.fieldIndex(-1) == -1
doAssert native.layout.fieldIndex(99) == -1
doAssert metal.layout.fields[0].scalarBytes == 1
doAssert native.layout.fields[0].scalarBytes == 4
doAssert metal.layout.fields[1].offset == 1
doAssert native.layout.fields[1].offset == 4
doAssert metal.layout.fields[4].stride == 4
doAssert native.layout.fields[4].stride == 16
doAssert metal.layout.inputs == native.layout.inputs
doAssert metal.layout.inputs[0].index == 3
doAssert metal.layout.textures[0].name == "shadowMap"
doAssert metal.layout.textures[0].index == 2
doAssert metal.layout.textures[0].samplerIndex == 5
doAssert native.layout.textures[0].samplerIndex == 2
doAssert metal.layout.textures[0].comparison
doAssert native.layout.textures[0].comparison

doAssert metal.setUniform("enabled", true)
doAssert metal.setUniform("visible", true)
native.put("enabled", true)
native.put("visible", true)
doAssert readMetal[uint8](metal, 0) == 1
doAssert readMetal[uint8](metal, 1) == 1
doAssert native.words[0] == 1 and native.words[1] == 1

doAssert metal.setUniform("weights", [2.0'f, 7.0'f])
native.put("weights", 2.0'f, 0)
native.put("weights", 7.0'f, 1)
doAssert readMetal[float32](metal, 84) == 7.0'f
doAssert native.nativeFloat(96) == 7.0'f
doAssert native.words[21] == 0

var matrix = mat3()
for column in 0 ..< 3:
  for row in 0 ..< 3:
    matrix[column, row] = float32(column * 3 + row + 1)
doAssert metal.setUniform(metal.layout.fieldIndex("normal"), matrix)
native.put(native.layout.fieldIndex("normal"), matrix)
for column in 0 ..< 3:
  for row in 0 ..< 3:
    let offset = 32 + column * 16 + row * 4
    doAssert readMetal[float32](metal, offset) == matrix[column, row]
    doAssert native.nativeFloat(offset) == matrix[column, row]
doAssert native.words[11] == 0

var joints = [mat4(), mat4()]
joints[1][3, 0] = 17.0'f
doAssert metal.setUniform("joints", joints)
native.putMatrices("joints", joints)
doAssert readMetal[float32](metal, 96 + 64 + 48) == 17.0'f
doAssert native.nativeFloat(128 + 64 + 48) == 17.0'f
doAssert not metal.setUniform("absent", 3.0'f)
native.put("absent", 3.0'f)

let rectangularReflection = %*{
  "ubos": [{"type": "_uniforms", "block_size": 128}],
  "types": {"_uniforms": {"members": [
    {"name": "transforms", "type": "mat2x3", "offset": 0,
      "matrix_stride": 32, "array": [2], "array_stride": 64}
  ]}},
  "textures": [
    {"name": "baseColor", "binding": 0, "type": "sampler2D"},
    {"name": "environment", "binding": 7, "type": "samplerCube"}
  ]
}
var rectangular = nativeUniforms.constants(
  reflectedShaderLayout(rectangularReflection)
)
doAssert rectangular.layout.fields[0].components == 3
doAssert rectangular.layout.fields[0].columns == 2
doAssert rectangular.layout.fields[0].matrixStride == 32
doAssert rectangular.layout.fields[0].stride == 64
doAssert rectangular.layout.textures.len == 2
doAssert rectangular.layout.textures[1].index == 7
doAssert not rectangular.layout.textures[1].comparison
rectangular.put("transforms", [1.0'f, 2, 3, 4, 5, 6], 0)
rectangular.put("transforms", [7.0'f, 8, 9, 10, 11, 12], 1)
doAssert rectangular.nativeFloat(0) == 1.0'f
doAssert rectangular.nativeFloat(32) == 4.0'f
doAssert rectangular.nativeFloat(64) == 7.0'f
doAssert rectangular.nativeFloat(96) == 10.0'f
doAssert rectangular.words[3] == 0 and rectangular.words[11] == 0

let scalarReflection = %*{
  "ubos": [{"type": "_uniforms", "block_size": 12}],
  "types": {"_uniforms": {"members": [
    {"name": "signedNumber", "type": "int", "offset": 0},
    {"name": "unsignedNumber", "type": "uint", "offset": 4},
    {"name": "exposure", "type": "float", "offset": 8}
  ]}}
}
var scalar = nativeUniforms.constants(reflectedShaderLayout(scalarReflection))
doAssert scalar.layout.fields[0].kind == "int"
doAssert scalar.layout.fields[1].kind == "uint"
doAssert scalar.layout.fields[2].kind == "float"
scalar.put("signedNumber", -7)
scalar.put("unsignedNumber", 42)
scalar.put("exposure", 2.5'f)
doAssert cast[int32](scalar.words[0]) == -7
doAssert scalar.words[1] == 42
doAssert scalar.nativeFloat(8) == 2.5'f

var empty: ShaderLayout
empty.indexFields()
doAssert empty.fieldIndex("absent") == -1
var duplicate = ShaderLayout(fields: @[
  ShaderField(name: "color"), ShaderField(name: "color")
])
try:
  duplicate.indexFields()
  doAssert false
except ShaderMetadataError:
  discard

echo "Shared shader metadata and target-specific uniform packing passed"
