import
  std/json,
  vmath, chroma

type
  UniformField* = object
    name*: string
    offset*, components*, columns*, count*, stride*: int # In 32-bit words.
  ShaderLayout* = object
    fields*: seq[UniformField]
    textures*: seq[string] # Indexed by shader register/binding.
    words*: int
  GpuConstants* = ref object
    ## Mutable reusable block; assignment shares storage until draw copies it.
    layout*: ShaderLayout
    words*: seq[uint32]

proc uniformLayout*(module: JsonNode): ShaderLayout =
  for texture in module{"textures"}.getElems():
    let binding = texture["binding"].getInt()
    if result.textures.len <= binding: result.textures.setLen(binding + 1)
    result.textures[binding] = texture["name"].getStr()
  for ubo in module{"ubos"}.getElems():
    result.words = (ubo["block_size"].getInt() + 3) div 4
    for member in module["types"][ubo["type"].getStr()]["members"]:
      let kind = member["type"].getStr()
      let components = if kind[^1] in {'2'..'4'}: ord(kind[^1]) - ord('0') else: 1
      let columns = if kind.len >= 4 and kind[0..2] == "mat": components else: 1
      let dims = member{"array"}
      result.fields.add UniformField(name: member["name"].getStr(),
        offset: member["offset"].getInt() div 4, components: components,
        columns: columns, count: (if dims == nil: 1 else: dims[0].getInt()),
        stride: (if dims == nil: components * columns else: member["array_stride"].getInt() div 4))

proc constants*(layout: ShaderLayout): GpuConstants =
  ## Allocates zeroed uniform words using the reflected native layout.
  GpuConstants(layout: layout, words: newSeq[uint32](layout.words))

proc findField(layout: ShaderLayout, name: string): int =
  ## Resolves a field index without copying its owned name string.
  for i, field in layout.fields:
    if field.name == name:
      return i
  -1

func findField(layout: ShaderLayout, index: int): int {.inline.} = index

proc put*(data: var GpuConstants, name: string or int,
  value: openArray[float32], index = 0) =
  ## Stores vector or matrix components with the native column and array stride.
  let fieldIndex = data.layout.findField(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index >= 0 and index < field.count and
    value.len == field.components * field.columns,
    "Incorrect uniform shape: " & field.name
  if field.columns == 1 or field.components == 4:
    copyMem(data.words[field.offset + index * field.stride].addr, value[0].unsafeAddr, value.len * sizeof(float32))
    return
  for col in 0 ..< field.columns:
    for row in 0 ..< field.components:
      let offset = field.offset + index * field.stride +
        col * (if field.columns > 1: 4 else: 0) + row
      data.words[offset] = cast[uint32](value[col * field.components + row])

proc put*(data: var GpuConstants, name: string or int, value: float32, index = 0) =
  ## Stores one floating-point parameter when declared by the program.
  data.put(name, [value], index)

proc put*(data: var GpuConstants, name: string or int, value: int, index = 0) =
  ## Stores integer bits without converting their representation to float.
  let fieldIndex = data.layout.findField(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index in 0 ..< field.count and field.components == 1 and field.columns == 1
  data.words[field.offset + index * field.stride] = cast[uint32](value.int32)

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
  let index = data.layout.findField(name)
  if index < 0 or values.len == 0: return
  let field = data.layout.fields[index]
  static: doAssert sizeof(Mat4) == 16 * sizeof(float32)
  doAssert field.components == 4 and field.columns == 4 and field.stride == 16 and values.len <= field.count
  copyMem(data.words[field.offset].addr, values[0].unsafeAddr, values.len * sizeof(Mat4))
