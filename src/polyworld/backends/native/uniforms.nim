import
  std/json,
  vmath, chroma,
  ../../shadermetadata

export shadermetadata

type
  GpuConstants* = ref object
    ## Mutable reusable block; assignment shares storage until draw copies it.
    layout*: ShaderLayout
    words*: seq[uint32]

proc uniformLayout*(module: JsonNode): ShaderLayout =
  ## Reads the common stage metadata while retaining the compiler's byte ABI.
  reflectedShaderLayout(module)

proc constants*(layout: ShaderLayout): GpuConstants =
  ## Allocates zeroed uniform words using the reflected native layout.
  GpuConstants(layout: layout, words: newSeq[uint32]((layout.size + 3) div 4))

proc put*(data: var GpuConstants, name: string or int,
  value: openArray[float32], index = 0) =
  ## Stores vector or matrix components with the native column and array stride.
  let fieldIndex = data.layout.fieldIndex(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index >= 0 and index < field.count and
    value.len == field.components * field.columns,
    "Incorrect uniform shape: " & field.name
  if field.columns == 1 or field.matrixStride == field.components * 4:
    copyMem(data.words[(field.offset + index * field.stride) div 4].addr,
      value[0].unsafeAddr, value.len * sizeof(float32))
    return
  for col in 0 ..< field.columns:
    for row in 0 ..< field.components:
      let offset = field.offset + index * field.stride +
        col * field.matrixStride + row * 4
      data.words[offset div 4] = cast[uint32](value[col * field.components + row])

proc put*(data: var GpuConstants, name: string or int, value: float32, index = 0) =
  ## Stores one floating-point parameter when declared by the program.
  data.put(name, [value], index)

proc put*(data: var GpuConstants, name: string or int, value: int, index = 0) =
  ## Stores integer bits without converting their representation to float.
  let fieldIndex = data.layout.fieldIndex(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index in 0 ..< field.count and field.components == 1 and field.columns == 1
  data.words[(field.offset + index * field.stride) div 4] = cast[uint32](value.int32)

proc put*(data: var GpuConstants, name: string or int, value: bool, index = 0) =
  ## Stores a native shader boolean as a four-byte integer.
  data.put(name, value.ord, index)

proc put*(data: var GpuConstants, name: string or int, value: Vec2, index = 0) =
  ## Stores the two ordered components of a vector.
  data.put(name, [value.x, value.y], index)

proc put*(data: var GpuConstants, name: string or int, value: Vec3, index = 0) =
  ## Stores three vector components at an optional array index.
  data.put(name, [value.x, value.y, value.z], index)

proc put*(data: var GpuConstants, name: string or int, value: Vec4, index = 0) =
  ## Stores four vector components at an optional array index.
  data.put(name, [value.x, value.y, value.z, value.w], index)

proc put*(data: var GpuConstants, name: string or int, value: Color, index = 0) =
  ## Stores authored RGBA components without changing their color space.
  data.put(name, [value.r, value.g, value.b, value.a], index)

proc put*(data: var GpuConstants, name: string or int, value: Mat4, index = 0) =
  ## Stores a four-column transform with the native matrix column stride.
  static: doAssert sizeof(Mat4) == 16 * sizeof(float32)
  data.put(name, cast[ptr array[16, float32]](value.unsafeAddr)[], index)

proc put*(data: var GpuConstants, name: string or int, value: Mat3, index = 0) =
  ## Stores a three-column transform with native matrix padding.
  var values: array[9, float32]
  for col in 0 ..< 3:
    for row in 0 ..< 3:
      values[col * 3 + row] = value[col, row]
  data.put(name, values, index)

proc put*(data: var GpuConstants, name: string or int, value: int32, index = 0) =
  ## Packs a signed integer uniform without changing its representation.
  data.put(name, value.int, index)

proc putMatrices*(data: GpuConstants, name: string or int, values: openArray[Mat4]) =
  ## mat4 arrays are contiguous in the reflected std140 and HLSL layouts.
  let index = data.layout.fieldIndex(name)
  if index < 0 or values.len == 0: return
  let field = data.layout.fields[index]
  static: doAssert sizeof(Mat4) == 16 * sizeof(float32)
  doAssert field.components == 4 and field.columns == 4 and
    field.stride == 64 and field.matrixStride == 16 and values.len <= field.count
  copyMem(data.words[field.offset div 4].addr, values[0].unsafeAddr,
    values.len * sizeof(Mat4))
