## Shader interface descriptions with target-specific byte layouts.

import
  std/[json, strutils, tables],
  shady/[errors, layouts]

type
  ShaderMetadataError* = object of CatchableError
  ShaderField* = object
    name*, kind*: string
    ## All offsets, element sizes, and strides below are measured in bytes.
    offset*, size*, stride*, matrixStride*: int
    components*, columns*, count*, scalarBytes*: int
  ShaderTextureBinding* = object
    name*: string
    index*, samplerIndex*: int
    comparison*: bool
  ShaderInputBinding* = object
    name*: string
    index*: int
  ShaderLayout* = object
    fields*: seq[ShaderField]
    textures*: seq[ShaderTextureBinding]
    inputs*: seq[ShaderInputBinding]
    size*: int
    fieldIndices: Table[string, int]

proc indexFields*(layout: var ShaderLayout) =
  ## Builds a reusable name lookup after declaring a stage's fields.
  layout.fieldIndices.clear()
  for i, field in layout.fields:
    if field.name in layout.fieldIndices:
      raise newException(ShaderMetadataError,
        "Duplicate shader uniform: " & field.name)
    layout.fieldIndices[field.name] = i

proc fieldIndex*(layout: ShaderLayout, name: string): int =
  ## Returns the cached field index, or minus one when the stage omits it.
  layout.fieldIndices.getOrDefault(name, -1)

proc fieldIndex*(layout: ShaderLayout, index: int): int =
  ## Accepts a previously resolved field index without a second name lookup.
  if index >= 0 and index < layout.fields.len: index else: -1

proc shape(kind: string): tuple[components, columns: int] =
  ## Describes scalar, vector, and square-matrix component counts.
  result = (1, 1)
  let cross = kind.find('x')
  if cross > 0 and cross + 1 < kind.len:
    result.columns = ord(kind[cross - 1]) - ord('0')
    result.components = ord(kind[cross + 1]) - ord('0')
  elif kind.len > 0 and kind[^1] in {'2' .. '4'}:
    result.components = ord(kind[^1]) - ord('0')

proc attributeIndex(line, marker: string): int =
  ## Reads a generated stage attribute without depending on a graphics API.
  let start = line.find(marker)
  if start < 0:
    return -1
  let finish = line.find(')', start)
  if finish < start + marker.len:
    raise newException(ShaderMetadataError, "Invalid shader attribute: " & line)
  try:
    result = parseInt(line[start + marker.len ..< finish])
  except ValueError as error:
    raise newException(ShaderMetadataError, error.msg)

proc metalShaderLayout*(source: string): ShaderLayout =
  ## Adapts Shady's MSL layout and attributes into a common stage description.
  var native: UniformLayout
  try:
    native = metalUniformLayout(source)
  except ShadyError as error:
    raise newException(ShaderMetadataError, error.msg)
  result.size = native.size
  for field in native.fields:
    let dimensions = shape(field.kind)
    result.fields.add ShaderField(
      name: field.name, kind: field.kind, offset: field.offset,
      size: field.size, stride: field.size,
      matrixStride: (if dimensions.columns > 1: 16 else: 0),
      components: dimensions.components, columns: dimensions.columns,
      count: field.count, scalarBytes: (if field.kind == "bool": 1 else: 4)
    )
  for line in source.splitLines():
    let
      texture = attributeIndex(line, "[[texture(")
      input = attributeIndex(line, "[[attribute(")
    if texture < 0 and input < 0:
      continue
    let words = line.strip().splitWhitespace()
    if words.len < 2:
      raise newException(ShaderMetadataError, "Invalid shader binding: " & line)
    if texture >= 0:
      result.textures.add ShaderTextureBinding(
        name: words[1], index: texture, samplerIndex: texture,
        comparison: words[0].startsWith("depth")
      )
    if input >= 0:
      result.inputs.add ShaderInputBinding(name: words[1], index: input)
  for line in source.splitLines():
    let sampler = attributeIndex(line, "[[sampler(")
    if sampler < 0:
      continue
    let words = line.strip().splitWhitespace()
    if words.len < 2:
      raise newException(ShaderMetadataError, "Invalid shader sampler: " & line)
    for binding in result.textures.mitems:
      if words[1] == binding.name & "Sampler":
        binding.samplerIndex = sampler
  result.indexFields()

proc reflectedKind(kind: string): string =
  ## Normalizes reflected GLSL names while retaining the scalar kind.
  if kind.startsWith("mat"):
    let dimensions = kind[3 .. ^1]
    if 'x' in dimensions:
      return "float" & dimensions
    return "float" & dimensions & "x" & dimensions
  for pair in [("ivec", "int"), ("uvec", "uint"), ("bvec", "bool"),
      ("vec", "float")]:
    if kind.startsWith(pair[0]):
      return pair[1] & kind[pair[0].len .. ^1]
  kind

proc reflectedShaderLayout*(module: JsonNode): ShaderLayout =
  ## Adapts compiler reflection with its actual offsets and array strides.
  try:
    for texture in module{"textures"}.getElems():
      let index = texture["binding"].getInt()
      result.textures.add ShaderTextureBinding(
        name: texture["name"].getStr(), index: index, samplerIndex: index,
        comparison: texture["type"].getStr().endsWith("Shadow")
      )
    for input in module{"inputs"}.getElems():
      result.inputs.add ShaderInputBinding(
        name: input["name"].getStr(), index: input["location"].getInt()
      )
    for ubo in module{"ubos"}.getElems():
      result.size = ubo["block_size"].getInt()
      for member in module["types"][ubo["type"].getStr()]["members"]:
        let
          kind = reflectedKind(member["type"].getStr())
          dimensions = shape(kind)
          matrixStride =
            if dimensions.columns > 1: member{"matrix_stride"}.getInt(16)
            else: 0
          size =
            if dimensions.columns > 1: dimensions.columns * matrixStride
            else: dimensions.components * 4
          dims = member{"array"}
        result.fields.add ShaderField(
          name: member["name"].getStr(), kind: kind,
          offset: member["offset"].getInt(), size: size,
          count: (if dims == nil: 1 else: dims[0].getInt()),
          stride: (if dims == nil: size else: member["array_stride"].getInt()),
          matrixStride: matrixStride, components: dimensions.components,
          columns: dimensions.columns, scalarBytes: 4
        )
    result.indexFields()
  except KeyError, ValueError, IndexDefect:
    raise newException(ShaderMetadataError,
      "Invalid shader reflection: " & getCurrentExceptionMsg())
