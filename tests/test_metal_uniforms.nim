import polyworld/backends/metal/uniforms, vmath

const Source = """
struct ShadyUniforms {
  bool enabled;
  int signedNumber;
  uint unsignedNumber;
  float exposure;
  float2 viewport;
  float3 light;
  float4 color;
  int2 tile;
  int3 direction;
  int4 rectangle;
  uint2 size;
  uint3 group;
  uint4 bounds;
  float3x3 normal;
  float4x4 model;
  float3 lights[2];
  float4x4 joints[128];
  float weights[3];
};
"""

proc read[T](buffer: UniformBuffer, offset: int): T =
  ## Reads a packed scalar without assuming pointer alignment.
  copyMem(result.addr, buffer.data[offset].unsafeAddr, sizeof(T))

proc offset(buffer: UniformBuffer, name: string): int =
  ## Finds the starting byte offset of a shader field.
  for field in buffer.layout.fields:
    if field.name == name:
      return field.offset
  doAssert false

var buffer = initUniformBuffer(Source)
doAssert buffer.setUniform("enabled", true)
doAssert buffer.setUniform("signedNumber", -7)
doAssert buffer.setUniform("unsignedNumber", 42)
doAssert buffer.setUniform("exposure", 2.5)
doAssert buffer.setUniform("viewport", vec2(120, 80))
doAssert buffer.setUniform("light", vec3(1, 2, 3))
doAssert buffer.setUniform("color", vec4(1, 2, 3, 4))
doAssert buffer.setUniform("tile", ivec2(1, 2))
doAssert buffer.setUniform("direction", ivec3(1, 2, 3))
doAssert buffer.setUniform("rectangle", ivec4(1, 2, 3, 4))
doAssert buffer.setUniform("size", uvec2(1, 2))
doAssert buffer.setUniform("group", uvec3(1, 2, 3))
doAssert buffer.setUniform("bounds", uvec4(1, 2, 3, 4))
var normal = mat3()
for column in 0 ..< 3:
  for row in 0 ..< 3:
    normal[column, row] = float32(column * 3 + row + 1)
doAssert buffer.setUniform("normal", normal)
doAssert buffer.setUniform("model", mat4())
doAssert buffer.setUniform("lights", [vec3(1, 2, 3), vec3(4, 5, 6)])
var joints: array[128, Mat4]
for i in 0 ..< joints.len:
  joints[i] = mat4()
  joints[i][3, 0] = i.float32
doAssert buffer.setUniform("joints", joints)
doAssert buffer.setUniform("weights", @[1.0'f, 2.0'f, 3.0'f])
doAssert not buffer.setUniform("missing", 1)
doAssert read[uint8](buffer, buffer.offset("enabled")) == 1
doAssert read[int32](buffer, buffer.offset("signedNumber")) == -7
doAssert read[uint32](buffer, buffer.offset("unsignedNumber")) == 42
doAssert read[float32](buffer, buffer.offset("exposure")) == 2.5'f
doAssert read[float32](buffer, buffer.offset("normal") + 16) == 4.0'f
doAssert read[float32](buffer, buffer.offset("normal") + 44) == 0.0'f
doAssert read[float32](buffer, buffer.offset("lights") + 16) == 4.0'f
doAssert read[float32](buffer, buffer.offset("joints") + 127 * 64 + 48) == 127.0'f
for bad in [-1'i64, 0x100000000'i64]:
  try:
    discard buffer.setUniform("unsignedNumber", bad)
    doAssert false
  except PolyworldMetalUniformError:
    discard
try:
  discard buffer.setUniform("light", vec4(1, 2, 3, 4))
  doAssert false
except PolyworldMetalUniformError:
  discard
try:
  discard buffer.setUniform("lights", @[vec3(1, 2, 3)])
  doAssert false
except PolyworldMetalUniformError:
  discard
echo "Metal uniform packing passed"
