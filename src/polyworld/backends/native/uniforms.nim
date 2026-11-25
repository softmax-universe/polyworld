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

proc put*(data: var GpuConstants, name: string,
  value: openArray[float32], index = 0) =
  ## Stores vector or matrix components with the native column and array stride.
  let fieldIndex = data.layout.findField(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index >= 0 and index < field.count and
    value.len == field.components * field.columns,
    "Incorrect uniform shape: " & name
  for col in 0 ..< field.columns:
    for row in 0 ..< field.components:
      let offset = field.offset + index * field.stride +
        col * (if field.columns > 1: 4 else: 0) + row
      data.words[offset] = cast[uint32](value[col * field.components + row])

proc put*(data: var GpuConstants, name: string, value: float32, index = 0) =
  ## Stores one floating-point parameter when declared by the program.
  data.put(name, [value], index)

proc put*(data: var GpuConstants, name: string, value: int, index = 0) =
  ## Stores integer bits without converting their representation to float.
  let fieldIndex = data.layout.findField(name)
  if fieldIndex < 0:
    return
  let field = data.layout.fields[fieldIndex].unsafeAddr
  doAssert index in 0 ..< field.count and field.components == 1 and field.columns == 1
  data.words[field.offset + index * field.stride] = cast[uint32](value.int32)

proc put*(data: var GpuConstants, name: string, value: bool, index = 0) =
  ## Stores a native shader boolean as a four-byte integer.
  data.put(name, value.ord, index)

proc put*(data: var GpuConstants, name: string, value: Vec2, index = 0) =
  ## Stores the two ordered components of a vector.
  data.put(name, [value.x, value.y], index)

proc put*(data: var GpuConstants, name: string, value: Vec3, index = 0) =
  ## Stores three vector components at an optional array index.
  data.put(name, [value.x, value.y, value.z], index)

proc put*(data: var GpuConstants, name: string, value: Vec4, index = 0) =
  ## Stores four vector components at an optional array index.
  data.put(name, [value.x, value.y, value.z, value.w], index)

proc put*(data: var GpuConstants, name: string, value: Color, index = 0) =
  ## Stores authored RGBA components without changing their color space.
  data.put(name, [value.r, value.g, value.b, value.a], index)

proc put*(data: var GpuConstants, name: string, value: Mat4, index = 0) =
  ## Stores a four-column transform with the native matrix column stride.
  var values: array[16, float32]
  for col in 0 ..< 4:
    for row in 0 ..< 4:
      values[col * 4 + row] = value[col, row]
  data.put(name, values, index)

proc put*(data: var GpuConstants, name: string, value: Mat3, index = 0) =
  ## Stores a three-column transform with native matrix padding.
  var values: array[9, float32]
  for col in 0 ..< 3:
    for row in 0 ..< 3:
      values[col * 3 + row] = value[col, row]
  data.put(name, values, index)

proc put*(data: var GpuConstants, name: string, value: int32, index = 0) =
  ## Packs a signed integer uniform without changing its representation.
  data.put(name, value.int, index)
