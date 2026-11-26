import
  vmath,
  ../../shadermetadata

type
  PolyworldMetalUniformError* = object of CatchableError
  UniformBuffer* = object
    layout*: ShaderLayout
    data*: seq[byte]

proc initUniformBuffer*(source: string): UniformBuffer =
  ## Allocates the native Metal layout of a generated Shady uniform block.
  try:
    result.layout = metalShaderLayout(source)
  except ShaderMetadataError as error:
    raise newException(PolyworldMetalUniformError, error.msg)
  result.data = newSeq[byte](result.layout.size)

proc requireKind(field: ShaderField, kind: string) =
  ## Rejects a host value that does not match the shader field type.
  if field.kind != kind:
    raise newException(
      PolyworldMetalUniformError,
      "Uniform " & field.name & " expects " & field.kind & ", got " & kind
    )

proc store[T](buffer: var UniformBuffer, offset: int, value: T) =
  ## Copies a single native scalar into an aligned uniform field.
  copyMem(buffer.data[offset].addr, value.unsafeAddr, sizeof(T))

proc writeValue[T](
  buffer: var UniformBuffer,
  field: ShaderField,
  offset: int,
  value: T
) =
  ## Packs one scalar, vector, or matrix using Metal's native alignment.
  when T is bool:
    field.requireKind("bool")
    buffer.store(offset, uint8(value))
  elif T is SomeFloat:
    field.requireKind("float")
    buffer.store(offset, float32(value))
  elif T is SomeSignedInt:
    case field.kind
    of "int":
      if int64(value) < int32.low.int64 or int64(value) > int32.high.int64:
        raise newException(
          PolyworldMetalUniformError,
          "Uniform " & field.name & " exceeds the int32 range"
        )
      buffer.store(offset, int32(value))
    of "uint":
      if int64(value) < 0 or uint64(value) > uint32.high.uint64:
        raise newException(
          PolyworldMetalUniformError,
          "Uniform " & field.name & " exceeds the uint32 range"
        )
      buffer.store(offset, uint32(value))
    else:
      field.requireKind("int")
  elif T is SomeUnsignedInt:
    case field.kind
    of "int":
      if uint64(value) > int32.high.uint64:
        raise newException(
          PolyworldMetalUniformError,
          "Uniform " & field.name & " exceeds the int32 range"
        )
      buffer.store(offset, int32(value))
    of "uint":
      if uint64(value) > uint32.high.uint64:
        raise newException(
          PolyworldMetalUniformError,
          "Uniform " & field.name & " exceeds the uint32 range"
        )
      buffer.store(offset, uint32(value))
    else:
      field.requireKind("uint")
  elif T is Vec2 or T is Vec3 or T is Vec4 or
    T is IVec2 or T is IVec3 or T is IVec4 or
    T is UVec2 or T is UVec3 or T is UVec4:
      const
        dimensions =
          when T is Vec2 or T is IVec2 or T is UVec2: 2
          elif T is Vec3 or T is IVec3 or T is UVec3: 3
          else: 4
        kind =
          when T is Vec2 or T is Vec3 or T is Vec4: "float"
          elif T is IVec2 or T is IVec3 or T is IVec4: "int"
          else: "uint"
      field.requireKind(kind & $dimensions)
      for i in 0 ..< dimensions:
        buffer.store(offset + i * 4, value[i])
  elif T is Mat3 or T is Mat4:
    const dimensions = when T is Mat3: 3 else: 4
    field.requireKind("float" & $dimensions & "x" & $dimensions)
    for column in 0 ..< dimensions:
      for row in 0 ..< dimensions:
        buffer.store(offset + column * field.matrixStride + row * 4,
          value[column, row])
  else:
    raise newException(
      PolyworldMetalUniformError,
      "Uniform " & field.name & " has an unsupported host type"
    )

proc setUniform*[T](
  buffer: var UniformBuffer,
  name: string or int,
  value: T
): bool =
  ## Updates a named field, returning false when this stage has no such field.
  let index = buffer.layout.fieldIndex(name)
  if index < 0:
    return false
  let field = buffer.layout.fields[index]
  when T is Vec2 or T is Vec3 or T is Vec4 or
    T is IVec2 or T is IVec3 or T is IVec4 or
    T is UVec2 or T is UVec3 or T is UVec4 or
    T is Mat3 or T is Mat4:
      if field.count != 1:
        raise newException(
          PolyworldMetalUniformError,
          "Uniform " & field.name & " expects " & $field.count & " elements"
        )
      buffer.writeValue(field, field.offset, value)
  elif T is array or T is seq:
    if value.len != field.count:
      raise newException(
        PolyworldMetalUniformError,
        "Uniform " & field.name & " expects " & $field.count &
          " elements, got " & $value.len
      )
    var offset = field.offset
    for item in value:
      buffer.writeValue(field, offset, item)
      offset += field.stride
  else:
    if field.count != 1:
      raise newException(
        PolyworldMetalUniformError,
        "Uniform " & field.name & " expects " & $field.count & " elements"
      )
    buffer.writeValue(field, field.offset, value)
  true
