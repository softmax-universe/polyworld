## Shader programs and draw encoding for the shared OpenGL passes.

import
  std/[strutils, tables],
  chroma, shady, vmath,
  passtypes, passresources, ../../shadermetadata

type
  SavedStencil = object
    function, reference, valueMask, writeMask: GLint
    fail, depthFail, depthPass: GLint
  SavedDraw = object
    program, vertexArray, arrayBuffer, activeTexture: GLint
    depth, cull, blend, stencil: GLboolean
    depthMask: GLboolean
    depthFunction, cullMode, frontFace: GLint
    blendFunctions: array[4, GLint]
    blendEquations: array[2, GLint]
    frontStencil, backStencil: SavedStencil
    when not defined(emscripten):
      polygonMode: array[2, GLint]
  SavedTexture = object
    unit: int
    target: GLenum
    texture, sampler: GLint

var
  drawScopeDepth = 0
  savedTextures: seq[SavedTexture]
  sceneDrawsActive = false
  gameFrameActive = false
  sceneState: SavedDraw
  drawStateKnown = false
  lastDrawState: DrawState

proc invalidateDrawState*() =
  ## The frame owner can also change depth and stencil outside shared draws.
  drawStateKnown = false

proc restoreTextures() =
  ## A unit's sampler is shared by texture targets. Unwind in reverse order.
  for index in countdown(savedTextures.high, 0):
    let item = savedTextures[index]
    glActiveTexture((GL_TEXTURE0.uint32 + item.unit.uint32).GLenum)
    glBindTexture(item.target, item.texture.GLuint)
    glBindSampler(item.unit.GLuint, item.sampler.GLuint)
  savedTextures.setLen(0)

proc depthFragment(gl_FragCoord: Vec4, gl_FragDepth: var float32) =
  ## Supplies an explicit fragment entry point for shared depth-only passes.
  gl_FragDepth = gl_FragCoord.z

const DepthFragmentSource = toShader(depthFragment,
  when defined(emscripten): glsl3WebGL else: glsl4Desktop, shaderFragment)

proc compileStage(kind: GLenum, source: string): GLuint =
  ## Compiles a generated stage and includes its source in failures.
  result = glCreateShader(kind)
  var strings = allocCStringArray([source])
  defer: deallocCStringArray(strings)
  glShaderSource(result, 1, strings, nil)
  glCompileShader(result)
  var valid: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, valid.addr)
  if valid == 0:
    var length: GLint
    glGetShaderiv(result, GL_INFO_LOG_LENGTH, length.addr)
    var message = newString(max(1, length.int))
    glGetShaderInfoLog(result, message.len.GLsizei, nil, message.cstring)
    glDeleteShader(result)
    raise newException(GpuError, "OpenGL shader compilation failed:\n" &
      message.strip(chars = {'\0'}) & "\n" & source)

proc samplerTarget(kind: GLenum): GLenum =
  ## Maps active sampler declarations to their native texture binding target.
  case kind
  of GL_SAMPLER_2D, GL_SAMPLER_2D_SHADOW, GL_INT_SAMPLER_2D,
      GL_UNSIGNED_INT_SAMPLER_2D:
    GL_TEXTURE_2D
  of GL_SAMPLER_2D_ARRAY, GL_SAMPLER_2D_ARRAY_SHADOW,
      GL_INT_SAMPLER_2D_ARRAY, GL_UNSIGNED_INT_SAMPLER_2D_ARRAY:
    GL_TEXTURE_2D_ARRAY
  of GL_SAMPLER_CUBE, GL_SAMPLER_CUBE_SHADOW, GL_INT_SAMPLER_CUBE,
      GL_UNSIGNED_INT_SAMPLER_CUBE:
    GL_TEXTURE_CUBE_MAP
  else:
    when not defined(emscripten):
      if kind in [GL_SAMPLER_BUFFER, GL_INT_SAMPLER_BUFFER,
          GL_UNSIGNED_INT_SAMPLER_BUFFER]:
        return GL_TEXTURE_BUFFER
    0.GLenum

proc uniformName(name: string): string =
  ## Uses the same field name for a declared array and its first element.
  if name.endsWith("[0]"): name[0 ..< name.len - 3]
  else: name

proc uniformField(name: string, kind: GLenum, count: int): ShaderField =
  ## Describes GL upload values separately from their non-byte locations.
  result = ShaderField(name: name, offset: -1, count: count,
    components: 1, columns: 1, scalarBytes: 4)
  case kind
  of cGL_FLOAT: result.kind = "float"
  of GL_FLOAT_VEC2: result.kind = "float2"; result.components = 2
  of GL_FLOAT_VEC3: result.kind = "float3"; result.components = 3
  of GL_FLOAT_VEC4: result.kind = "float4"; result.components = 4
  of cGL_INT: result.kind = "int"
  of GL_INT_VEC2: result.kind = "int2"; result.components = 2
  of GL_INT_VEC3: result.kind = "int3"; result.components = 3
  of GL_INT_VEC4: result.kind = "int4"; result.components = 4
  of GL_UNSIGNED_INT: result.kind = "uint"
  of GL_UNSIGNED_INT_VEC2: result.kind = "uint2"; result.components = 2
  of GL_UNSIGNED_INT_VEC3: result.kind = "uint3"; result.components = 3
  of GL_UNSIGNED_INT_VEC4: result.kind = "uint4"; result.components = 4
  of GL_BOOL: result.kind = "bool"
  of GL_BOOL_VEC2: result.kind = "bool2"; result.components = 2
  of GL_BOOL_VEC3: result.kind = "bool3"; result.components = 3
  of GL_BOOL_VEC4: result.kind = "bool4"; result.components = 4
  of GL_FLOAT_MAT2:
    result.kind = "float2x2"; result.components = 2; result.columns = 2
  of GL_FLOAT_MAT3:
    result.kind = "float3x3"; result.components = 3; result.columns = 3
  of GL_FLOAT_MAT4:
    result.kind = "float4x4"; result.components = 4; result.columns = 4
  of GL_FLOAT_MAT2x3:
    result.kind = "float2x3"; result.components = 3; result.columns = 2
  of GL_FLOAT_MAT2x4:
    result.kind = "float2x4"; result.components = 4; result.columns = 2
  of GL_FLOAT_MAT3x2:
    result.kind = "float3x2"; result.components = 2; result.columns = 3
  of GL_FLOAT_MAT3x4:
    result.kind = "float3x4"; result.components = 4; result.columns = 3
  of GL_FLOAT_MAT4x2:
    result.kind = "float4x2"; result.components = 2; result.columns = 4
  of GL_FLOAT_MAT4x3:
    result.kind = "float4x3"; result.components = 3; result.columns = 4
  else:
    result.kind = "unknown"
  result.size = result.components * result.columns * result.scalarBytes
  result.stride = result.size
  if result.columns > 1:
    result.matrixStride = result.components * result.scalarBytes

proc newProgram*(vertexSource, fragmentSource: string,
    layout = VertexLayout()): ShaderProgram =
  ## Links shared shader stages and caches active parameter descriptions.
  let fragmentCode =
    if fragmentSource.len == 0: DepthFragmentSource
    else: fragmentSource
  let vertex = compileStage(GL_VERTEX_SHADER, vertexSource)
  defer: glDeleteShader(vertex)
  let fragment = compileStage(GL_FRAGMENT_SHADER, fragmentCode)
  defer: glDeleteShader(fragment)
  result = ShaderProgram(handle: glCreateProgram(), layout: layout,
    vertexSource: vertexSource, fragmentSource: fragmentCode)
  glAttachShader(result.handle, vertex)
  glAttachShader(result.handle, fragment)
  glLinkProgram(result.handle)
  var valid: GLint
  glGetProgramiv(result.handle, GL_LINK_STATUS, valid.addr)
  if valid == 0:
    var length: GLint
    glGetProgramiv(result.handle, GL_INFO_LOG_LENGTH, length.addr)
    var message = newString(max(1, length.int))
    glGetProgramInfoLog(result.handle, message.len.GLsizei, nil,
      message.cstring)
    glDeleteProgram(result.handle)
    result.handle = 0
    raise newException(GpuError, "OpenGL program linking failed:\n" &
      message.strip(chars = {'\0'}) & "\nVertex source:\n" & vertexSource &
      "\nFragment source:\n" & fragmentCode)
  var count, capacity: GLint
  glGetProgramiv(result.handle, GL_ACTIVE_UNIFORMS, count.addr)
  glGetProgramiv(result.handle, GL_ACTIVE_UNIFORM_MAX_LENGTH, capacity.addr)
  for index in 0 ..< count.int:
    var
      name = newString(max(1, capacity.int))
      length: GLsizei
      size: GLint
      kind: GLenum
    glGetActiveUniform(result.handle, index.GLuint, name.len.GLsizei,
      length.addr, size.addr, kind.addr, name.cstring)
    name.setLen(length.int)
    let location = glGetUniformLocation(result.handle, name.cstring)
    result.uniforms[name] = location
    let arrayField = name.endsWith("[0]")
    name = uniformName(name)
    result.uniforms[name] = location
    let target = samplerTarget(kind)
    if target != 0.GLenum and location >= 0:
      let unit = result.samplerUnits.len
      result.samplerUnits[name] = unit
      result.samplers.add (location, target, GpuImage(nil))
      result.reflection.textures.add ShaderTextureBinding(
        name: name, index: unit, samplerIndex: unit,
        comparison: kind in [GL_SAMPLER_2D_SHADOW,
          GL_SAMPLER_2D_ARRAY_SHADOW, GL_SAMPLER_CUBE_SHADOW]
      )
    elif location >= 0:
      result.reflection.fields.add uniformField(name, kind, size.int)
      result.fieldLocations.add location
      result.fieldArrays.add arrayField
  result.reflection.indexFields()
  glGetProgramiv(result.handle, GL_ACTIVE_ATTRIBUTES, count.addr)
  glGetProgramiv(result.handle, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, capacity.addr)
  for index in 0 ..< count.int:
    var
      name = newString(max(1, capacity.int))
      length: GLsizei
      size: GLint
      kind: GLenum
    glGetActiveAttrib(result.handle, index.GLuint, name.len.GLsizei,
      length.addr, size.addr, kind.addr, name.cstring)
    name.setLen(length.int)
    let location = glGetAttribLocation(result.handle, name.cstring)
    result.attributes[name] = location
    result.reflection.inputs.add ShaderInputBinding(name: name,
      index: location.int)

proc destroy*(program: ShaderProgram) =
  ## Releases the program and its private vertex-array binding state.
  if program == nil:
    return
  if program.vao != 0:
    glDeleteVertexArrays(1, program.vao.addr)
    program.vao = 0
  if program.handle != 0:
    glDeleteProgram(program.handle)
    program.handle = 0
  program.samplers.setLen(0)
  program.values.clear()
  program.stream.destroy()
  program.stream = nil

proc setVertexLayout*(program: ShaderProgram, layout: VertexLayout) =
  ## Selects the default vertex description for following draws.
  program.layout = layout
  program.defaultInputs = nil

proc location(program: ShaderProgram, name: string): GLint =
  ## Resolves each parameter name once, including inactive parameters.
  program.uniforms.withValue(name, cached):
    return cached[]
  result = glGetUniformLocation(program.handle, name.cstring)
  program.uniforms[name] = result

proc storeUniform(program: ShaderProgram, name: string, kind: UniformKind,
    components, count: int, data: pointer, words: int) =
  ## Retains parameter bytes until draw time without changing GL bindings.
  if count == 0:
    return
  var
    field = program.reflection.fieldIndex(name)
    uniformLocation = if field >= 0: program.fieldLocations[field] else: program.location(name)
    first = 0
  if uniformLocation < 0: return
  if field < 0 and name.endsWith("]"):
    let bracket = name.rfind('[')
    if bracket >= 0:
      let fieldName = name[0 ..< bracket]
      try:
        first = parseInt(name[bracket + 1 ..< name.len - 1])
        field = program.reflection.fieldIndex(fieldName)
      except ValueError:
        raise newException(GpuError, "Invalid uniform array index: " & name)
  let
    elementWords = words div count
    arrayField = field >= 0 and first >= 0 and
      program.fieldArrays[field] and
      program.reflection.fields[field].components *
        program.reflection.fields[field].columns == elementWords
  if arrayField:
    uniformLocation = program.fieldLocations[field]
  let value = addr program.values.mgetOrPut(uniformLocation, UniformValue())
  var total = count
  if arrayField:
    # Array and element setters share one payload, including element zero.
    # Keep supplied counts when GL optimizes unused trailing elements away.
    total = max(value.count,
      max(program.reflection.fields[field].count, first + count))
  else:
    first = 0
  let offset = first * elementWords
  if value.count == total and value.kind == kind and value.components == components and
      value.words.len == total * elementWords and
      equalMem(value.words[offset].addr, data, words * sizeof(uint32)):
    return
  value.kind = kind
  value.components = components
  value.count = total
  value.words.setLen(total * elementWords)
  if words > 0:
    copyMem(value.words[offset].addr, data, words * sizeof(uint32))
  if value.dirtyCount == 0:
    program.dirtyUniforms.add uniformLocation
  value.dirtyCount = if arrayField: max(value.dirtyCount, first + count) else: count

proc setUniform*[T](program: ShaderProgram, name: string,
    values: openArray[T])
  ## Stores a contiguous array of shared uniform values.

proc setUniform*[T](program: ShaderProgram, name: string, value: T) =
  ## Stores scalar, vector, color, or matrix parameters in their native form.
  when T is bool or T is SomeSignedInt or T is enum:
    var number = int32(value)
    program.storeUniform(name, UniformSigned, 1, 1, number.addr, 1)
  elif T is SomeUnsignedInt:
    var number = uint32(value)
    program.storeUniform(name, UniformUnsigned, 1, 1, number.addr, 1)
  elif T is SomeFloat:
    var number = float32(value)
    program.storeUniform(name, UniformFloat, 1, 1, number.addr, 1)
  elif T is Color:
    var numbers = [value.r, value.g, value.b, value.a]
    program.storeUniform(name, UniformFloat, 4, 1, numbers[0].addr, 4)
  elif T is Vec2 or T is Vec3 or T is Vec4:
    const count = sizeof(T) div sizeof(float32)
    program.storeUniform(name, UniformFloat, count, 1,
      value.unsafeAddr, count)
  elif T is IVec2 or T is IVec3 or T is IVec4:
    const count = sizeof(T) div sizeof(int32)
    program.storeUniform(name, UniformSigned, count, 1,
      value.unsafeAddr, count)
  elif T is UVec2 or T is UVec3 or T is UVec4:
    const count = sizeof(T) div sizeof(uint32)
    program.storeUniform(name, UniformUnsigned, count, 1,
      value.unsafeAddr, count)
  elif T is Mat3:
    program.storeUniform(name, UniformMat3, 3, 1, value.unsafeAddr, 9)
  elif T is Mat4:
    program.storeUniform(name, UniformMat4, 4, 1, value.unsafeAddr, 16)
  elif T is array or T is seq:
    if value.len > 0:
      setUniform(program, name, value.toOpenArray(0, value.high))
  else:
    {.error: "Unsupported shared OpenGL uniform type".}

proc setUniform*[T](program: ShaderProgram, name: string,
    values: openArray[T]) =
  ## Stores contiguous uniform arrays while preserving matrix column order.
  if values.len == 0:
    return
  when T is Mat4:
    program.storeUniform(name, UniformMat4, 4, values.len,
      values[0].unsafeAddr, values.len * 16)
  elif T is Mat3:
    program.storeUniform(name, UniformMat3, 3, values.len,
      values[0].unsafeAddr, values.len * 9)
  elif T is float32 or T is Vec2 or T is Vec3 or T is Vec4:
    const count = sizeof(T) div sizeof(float32)
    program.storeUniform(name, UniformFloat, count, values.len,
      values[0].unsafeAddr, values.len * count)
  elif T is int32 or T is IVec2 or T is IVec3 or T is IVec4:
    const count = sizeof(T) div sizeof(int32)
    program.storeUniform(name, UniformSigned, count, values.len,
      values[0].unsafeAddr, values.len * count)
  elif T is uint32 or T is UVec2 or T is UVec3 or T is UVec4:
    const count = sizeof(T) div sizeof(uint32)
    program.storeUniform(name, UniformUnsigned, count, values.len,
      values[0].unsafeAddr, values.len * count)
  else:
    {.error: "Unsupported shared OpenGL uniform array type".}

proc bindTexture*(program: ShaderProgram, name: string, image: GpuImage) =
  ## Records a sampled image without disturbing the caller's GL bindings.
  let key = uniformName(name)
  program.samplerUnits.withValue(key, unit):
    program.samplers[unit[]].image = image

proc bindTexture*(program: ShaderProgram, name: string, image: GLuint) =
  ## Borrows an existing GL texture using its reflected sampler target.
  let key = uniformName(name)
  program.samplerUnits.withValue(key, unit):
    let slot = addr program.samplers[unit[]]
    if slot.image == nil or slot.image.handle != image or slot.image.sampler != 0:
      slot.image = GpuImage(handle: image, target: slot.target)

proc setEnabled(capability: GLenum, enabled: GLboolean) =
  ## Applies a capability without assuming prior state.
  if enabled:
    glEnable(capability)
  else:
    glDisable(capability)

proc saveDraw(bindingsOnly = false): SavedDraw =
  ## Game draws describe their raster state. Only foreign GL scopes borrow it.
  glGetIntegerv(GL_CURRENT_PROGRAM, result.program.addr)
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, result.vertexArray.addr)
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, result.arrayBuffer.addr)
  glGetIntegerv(GL_ACTIVE_TEXTURE, result.activeTexture.addr)
  if bindingsOnly: return
  result.depth = glIsEnabled(GL_DEPTH_TEST)
  result.cull = glIsEnabled(GL_CULL_FACE)
  result.blend = glIsEnabled(GL_BLEND)
  result.stencil = glIsEnabled(GL_STENCIL_TEST)
  glGetBooleanv(GL_DEPTH_WRITEMASK, result.depthMask.addr)
  glGetIntegerv(GL_DEPTH_FUNC, result.depthFunction.addr)
  glGetIntegerv(GL_CULL_FACE_MODE, result.cullMode.addr)
  glGetIntegerv(GL_FRONT_FACE, result.frontFace.addr)
  glGetIntegerv(GL_BLEND_SRC_RGB, result.blendFunctions[0].addr)
  glGetIntegerv(GL_BLEND_DST_RGB, result.blendFunctions[1].addr)
  glGetIntegerv(GL_BLEND_SRC_ALPHA, result.blendFunctions[2].addr)
  glGetIntegerv(GL_BLEND_DST_ALPHA, result.blendFunctions[3].addr)
  glGetIntegerv(GL_BLEND_EQUATION_RGB, result.blendEquations[0].addr)
  glGetIntegerv(GL_BLEND_EQUATION_ALPHA, result.blendEquations[1].addr)
  glGetIntegerv(GL_STENCIL_FUNC, result.frontStencil.function.addr)
  glGetIntegerv(GL_STENCIL_REF, result.frontStencil.reference.addr)
  glGetIntegerv(GL_STENCIL_VALUE_MASK, result.frontStencil.valueMask.addr)
  glGetIntegerv(GL_STENCIL_WRITEMASK, result.frontStencil.writeMask.addr)
  glGetIntegerv(GL_STENCIL_FAIL, result.frontStencil.fail.addr)
  glGetIntegerv(GL_STENCIL_PASS_DEPTH_FAIL, result.frontStencil.depthFail.addr)
  glGetIntegerv(GL_STENCIL_PASS_DEPTH_PASS, result.frontStencil.depthPass.addr)
  glGetIntegerv(GL_STENCIL_BACK_FUNC, result.backStencil.function.addr)
  glGetIntegerv(GL_STENCIL_BACK_REF, result.backStencil.reference.addr)
  glGetIntegerv(GL_STENCIL_BACK_VALUE_MASK, result.backStencil.valueMask.addr)
  glGetIntegerv(GL_STENCIL_BACK_WRITEMASK, result.backStencil.writeMask.addr)
  glGetIntegerv(GL_STENCIL_BACK_FAIL, result.backStencil.fail.addr)
  glGetIntegerv(GL_STENCIL_BACK_PASS_DEPTH_FAIL, result.backStencil.depthFail.addr)
  glGetIntegerv(GL_STENCIL_BACK_PASS_DEPTH_PASS, result.backStencil.depthPass.addr)
  when not defined(emscripten):
    glGetIntegerv(GL_POLYGON_MODE, result.polygonMode[0].addr)

proc restoreStencil(face: GLenum, state: SavedStencil) =
  ## Restores independent front or back stencil operations and masks.
  glStencilFuncSeparate(face, state.function.GLenum, state.reference,
    state.valueMask.GLuint)
  glStencilMaskSeparate(face, state.writeMask.GLuint)
  glStencilOpSeparate(face, state.fail.GLenum, state.depthFail.GLenum,
    state.depthPass.GLenum)

proc restoreDraw(state: SavedDraw, bindingsOnly = false) =
  glUseProgram(state.program.GLuint)
  glBindVertexArray(state.vertexArray.GLuint)
  glBindBuffer(GL_ARRAY_BUFFER, state.arrayBuffer.GLuint)
  glActiveTexture(state.activeTexture.GLenum)
  if bindingsOnly: return
  setEnabled(GL_DEPTH_TEST, state.depth)
  setEnabled(GL_CULL_FACE, state.cull)
  setEnabled(GL_BLEND, state.blend)
  setEnabled(GL_STENCIL_TEST, state.stencil)
  glDepthMask(state.depthMask)
  glDepthFunc(state.depthFunction.GLenum)
  glCullFace(state.cullMode.GLenum)
  glFrontFace(state.frontFace.GLenum)
  glBlendFuncSeparate(state.blendFunctions[0].GLenum,
    state.blendFunctions[1].GLenum, state.blendFunctions[2].GLenum,
    state.blendFunctions[3].GLenum)
  glBlendEquationSeparate(state.blendEquations[0].GLenum,
    state.blendEquations[1].GLenum)
  restoreStencil(GL_FRONT, state.frontStencil)
  restoreStencil(GL_BACK, state.backStencil)
  when not defined(emscripten):
    glPolygonMode(GL_FRONT_AND_BACK, state.polygonMode[0].GLenum)

proc endSceneDraws*() =
  ## Return ownership of the context to external code, including Silky.
  if sceneDrawsActive:
    doAssert drawScopeDepth == 1
    dec drawScopeDepth
    restoreTextures()
    restoreDraw(sceneState, bindingsOnly = gameFrameActive)
    if gameFrameActive:
      # Silky sets its blend factors and assumes ordinary filled, untested UI.
      glDisable(GL_DEPTH_TEST)
      glDepthMask(GL_TRUE)
      glDisable(GL_CULL_FACE)
      glDisable(GL_STENCIL_TEST)
      glStencilMask(0xff)
      glDisable(GL_BLEND)
      glBlendEquation(GL_FUNC_ADD)
      when not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
    sceneDrawsActive = false
    invalidateDrawState()

proc beginSceneDraws*() =
  ## Share borrowed bindings across passes, preserving raster state for foreign callers.
  if not sceneDrawsActive:
    doAssert drawScopeDepth == 0
    sceneState = saveDraw(bindingsOnly = gameFrameActive)
    inc drawScopeDepth
    sceneDrawsActive = true
    invalidateDrawState()

proc beginGameFrameDraws*() =
  ## Defer acquiring GL bindings until the first shared pass actually draws.
  if not gameFrameActive:
    doAssert drawScopeDepth == 0
    gameFrameActive = true

proc endGameFrameDraws*() =
  endSceneDraws()
  gameFrameActive = false

proc gameOwnsDrawState*(): bool =
  gameFrameActive

template withClearWriteMasks*(depth, stencil: bool, body: untyped) =
  ## Borrow masks from the preceding node, or from GL in a foreign scope.
  block:
    if gameFrameActive and (depth or stencil): beginSceneDraws()
    let known = sceneDrawsActive and drawStateKnown
    var depthMask: GLboolean
    var frontMask, backMask: GLint
    if depth:
      if known: depthMask = lastDrawState.depthWrite
      elif not gameFrameActive: glGetBooleanv(GL_DEPTH_WRITEMASK, depthMask.addr)
      glDepthMask(GL_TRUE)
    if stencil:
      if known:
        frontMask = if lastDrawState.stencilWrite: 0xff else: 0
        backMask = frontMask
      elif not gameFrameActive:
        glGetIntegerv(GL_STENCIL_WRITEMASK, frontMask.addr)
        glGetIntegerv(GL_STENCIL_BACK_WRITEMASK, backMask.addr)
      glStencilMask(0xff)
    try:
      body
    finally:
      # With no previous game draw, the first node establishes both masks.
      if known or not gameFrameActive:
        if depth: glDepthMask(depthMask)
        if stencil:
          glStencilMaskSeparate(GL_FRONT, frontMask.GLuint)
          glStencilMaskSeparate(GL_BACK, backMask.GLuint)

template preserveDrawState*(body: untyped) =
  ## Restores caller state once around a nested sequence of shared draws.
  block:
    let
      foreignScope = not gameFrameActive
      ownsState = foreignScope and drawScopeDepth == 0
    var savedState: SavedDraw
    if ownsState:
      savedState = saveDraw()
      invalidateDrawState()
    if foreignScope: inc drawScopeDepth
    try:
      body
    finally:
      if foreignScope: dec drawScopeDepth
      if ownsState:
        restoreTextures()
        restoreDraw(savedState)
        invalidateDrawState()

proc nativeCompare(value: DepthCompare): GLenum =
  ## Maps logical depth and stencil comparisons to the selected driver.
  case value
  of LessEqual: GL_LEQUAL
  of Less: GL_LESS
  of Always: GL_ALWAYS
  of Equal: GL_EQUAL
  of Greater: GL_GREATER

proc applyDraw(state: DrawState) =
  ## Encode differences from the previous draw while this scope owns raster state.
  template changed(field: untyped): bool =
    not drawStateKnown or state.field != lastDrawState.field
  if changed(depthTest) or changed(depthWrite):
    setEnabled(GL_DEPTH_TEST, state.depthTest or state.depthWrite)
  if changed(depthTest) or changed(depthCompare):
    glDepthFunc(if state.depthTest: nativeCompare(state.depthCompare) else: GL_ALWAYS)
  if changed(depthWrite): glDepthMask(state.depthWrite)
  if changed(cull):
    setEnabled(GL_CULL_FACE, state.cull != CullNone)
    if state.cull != CullNone:
      glCullFace(if state.cull == CullFront: GL_FRONT else: GL_BACK)
  if not drawStateKnown: glFrontFace(GL_CCW)
  if changed(blend): setEnabled(GL_BLEND, state.blend != Opaque)
  if changed(blend) and state.blend != Opaque:
    var
      source = GL_SRC_ALPHA
      destination = GL_ONE_MINUS_SRC_ALPHA
      alphaSource = GL_ONE
      alphaDestination = GL_ONE_MINUS_SRC_ALPHA
    case state.blend
    of PremultipliedAlpha:
      source = GL_ONE
    of Additive:
      destination = GL_ONE
      alphaSource = GL_ZERO
      alphaDestination = GL_ONE
    of StraightAlpha:
      alphaSource = GL_SRC_ALPHA
    of AlphaBlendPreserveAlpha:
      alphaSource = GL_ZERO
      alphaDestination = GL_ONE
    of Multiply:
      source = GL_DST_COLOR
      destination = GL_ZERO
      alphaSource = GL_ZERO
      alphaDestination = GL_ONE
    else:
      discard
    glBlendFuncSeparate(source, destination, alphaSource, alphaDestination)
    glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD)
  if changed(stencilTest) or changed(stencilWrite):
    setEnabled(GL_STENCIL_TEST, state.stencilTest or state.stencilWrite)
  if changed(stencilCompare) or changed(stencilReference):
    glStencilFunc(nativeCompare(state.stencilCompare), state.stencilReference.GLint, 0xff)
  if changed(stencilWrite):
    glStencilMask(if state.stencilWrite: 0xff.GLuint else: 0.GLuint)
    glStencilOp(GL_KEEP, GL_KEEP, if state.stencilWrite: GL_REPLACE else: GL_KEEP)
  when not defined(emscripten):
    if changed(wireframe):
      glPolygonMode(GL_FRONT_AND_BACK, if state.wireframe: GL_LINE else: GL_FILL)

proc uploadUniforms(program: ShaderProgram) =
  ## Uploads staged parameter bytes after binding their owning program.
  for uniformLocation in program.dirtyUniforms:
    let value = addr program.values[uniformLocation]
    let
      data = value.words[0].unsafeAddr
      count = value.dirtyCount.GLsizei
    case value.kind
    of UniformFloat:
      let numbers = cast[ptr GLfloat](data)
      case value.components
      of 1: glUniform1fv(uniformLocation, count, numbers)
      of 2: glUniform2fv(uniformLocation, count, numbers)
      of 3: glUniform3fv(uniformLocation, count, numbers)
      of 4: glUniform4fv(uniformLocation, count, numbers)
      else: discard
    of UniformSigned:
      let numbers = cast[ptr GLint](data)
      case value.components
      of 1: glUniform1iv(uniformLocation, count, numbers)
      of 2: glUniform2iv(uniformLocation, count, numbers)
      of 3: glUniform3iv(uniformLocation, count, numbers)
      of 4: glUniform4iv(uniformLocation, count, numbers)
      else: discard
    of UniformUnsigned:
      let numbers = cast[ptr GLuint](data)
      case value.components
      of 1: glUniform1uiv(uniformLocation, count, numbers)
      of 2: glUniform2uiv(uniformLocation, count, numbers)
      of 3: glUniform3uiv(uniformLocation, count, numbers)
      of 4: glUniform4uiv(uniformLocation, count, numbers)
      else: discard
    of UniformMat3:
      glUniformMatrix3fv(uniformLocation, count, GL_FALSE,
        cast[ptr GLfloat](data))
    of UniformMat4:
      glUniformMatrix4fv(uniformLocation, count, GL_FALSE,
        cast[ptr GLfloat](data))
    value.dirtyCount = 0
  program.dirtyUniforms.setLen(0)

proc bindingQuery(target: GLenum): GLenum =
  ## Returns the state query for a sampled texture target.
  case target
  of GL_TEXTURE_2D_ARRAY: GL_TEXTURE_BINDING_2D_ARRAY
  of GL_TEXTURE_CUBE_MAP: GL_TEXTURE_BINDING_CUBE_MAP
  else:
    when not defined(emscripten):
      if target == GL_TEXTURE_BUFFER:
        return GL_TEXTURE_BINDING_BUFFER
    GL_TEXTURE_BINDING_2D

proc bindTextures(program: ShaderProgram) =
  ## Save each affected binding once for the entire shared pass.
  for unit, slot in program.samplers:
    if not program.samplersInitialized:
      glUniform1i(slot.location, unit.GLint)
    let image = slot.image
    let target = slot.target
    if image == nil:
      # An unassigned sampler sees the caller's binding for this unit.
      var restoredSampler = false
      for item in savedTextures:
        if item.unit != unit: continue
        if not restoredSampler:
          glBindSampler(unit.GLuint, item.sampler.GLuint)
          restoredSampler = true
        if item.target == target:
          glActiveTexture((GL_TEXTURE0.uint32 + unit.uint32).GLenum)
          glBindTexture(target, item.texture.GLuint)
          break
      continue
    var saved = SavedTexture(unit: unit, target: target)
    glActiveTexture((GL_TEXTURE0.uint32 + unit.uint32).GLenum)
    var found = false
    for item in savedTextures:
      if item.unit == unit and item.target == saved.target:
        found = true
        break
    if not found:
      glGetIntegerv(bindingQuery(saved.target), saved.texture.addr)
      glGetIntegerv(GL_SAMPLER_BINDING, saved.sampler.addr)
      savedTextures.add saved
    glBindTexture(saved.target, image.handle)
    glBindSampler(unit.GLuint, image.sampler)
  program.samplersInitialized = true

proc vertexInputs(program: ShaderProgram, layout: VertexLayout): VertexInputs =
  ## Resolve semantics once per linked program and vertex layout.
  result = VertexInputs(stride: layout.stride)
  for attribute in layout.attributes:
    if attribute.name notin program.attributes:
      program.attributes[attribute.name] = glGetAttribLocation(program.handle, attribute.name.cstring)
    let location = program.attributes[attribute.name]
    if location >= 0:
      result.attributes.add (location.GLuint, attribute.format, attribute.offset)

proc bindVertices(program: ShaderProgram, vertices: VertexBuffer, layout: VertexLayout) =
  ## Buffer-owned VAOs persist across material, pass and program changes.
  if vertices == nil:
    if program.vao == 0:
      glGenVertexArrays(1, program.vao.addr)
    glBindVertexArray(program.vao)
    return
  var inputs: VertexInputs
  if layout.stride == 0:
    if program.defaultInputs == nil:
      program.defaultInputs = program.vertexInputs(program.layout)
    inputs = program.defaultInputs
  else:
    for item in program.otherInputs:
      if item.layout == layout:
        inputs = item.inputs
        break
    if inputs == nil:
      inputs = program.vertexInputs(layout)
      program.otherInputs.add (layout, inputs)
  for binding in vertices.arrays:
    if binding.inputs == inputs or binding.inputs[] == inputs[]:
      glBindVertexArray(binding.vao)
      return
  var vao: GLuint
  glGenVertexArrays(1, vao.addr)
  glBindVertexArray(vao)
  glBindBuffer(GL_ARRAY_BUFFER, vertices.handle)
  for attribute in inputs.attributes:
    let
      slot = attribute.slot
      count = case attribute.format
        of Float1, UInt1: 1
        of Float2, UInt2: 2
        of Float3, UInt3: 3
        of Float4, UInt4, Unorm8x4: 4
      pointer = cast[pointer](attribute.offset)
    glEnableVertexAttribArray(slot)
    if attribute.format in {UInt1, UInt2, UInt3, UInt4}:
      glVertexAttribIPointer(slot, count.GLint, GL_UNSIGNED_INT,
        inputs.stride.GLsizei, pointer)
    else:
      glVertexAttribPointer(slot, count.GLint,
        if attribute.format == Unorm8x4: GL_UNSIGNED_BYTE else: cGL_FLOAT,
        attribute.format == Unorm8x4, inputs.stride.GLsizei, pointer)
  vertices.arrays.add (inputs, vao)

proc draw*(program: ShaderProgram, vertices: VertexBuffer, count: int,
    state = DrawState(), indices: VertexBuffer = nil, first = 0,
    index32 = true, instanceCount = 1, layout = VertexLayout()) =
  ## Draws shared geometry while preserving the caller's OpenGL state.
  if program == nil or program.handle == 0 or count <= 0 or instanceCount <= 0:
    return
  if gameFrameActive: beginSceneDraws()
  let ownsState = drawScopeDepth == 0
  var saved: SavedDraw
  if ownsState:
    saved = saveDraw()
    invalidateDrawState()
  defer:
    if ownsState:
      restoreTextures()
      restoreDraw(saved)
      invalidateDrawState()
  var effective = state
  if gpuRenderer.hasStencilOverride:
    effective.stencilTest = gpuRenderer.stencilOverride.stencilTest
    effective.stencilWrite = gpuRenderer.stencilOverride.stencilWrite
    effective.stencilCompare = gpuRenderer.stencilOverride.stencilCompare
    effective.stencilReference = gpuRenderer.stencilOverride.stencilReference
  if not sceneDrawsActive:
    invalidateDrawState()
  if not drawStateKnown or lastDrawState != effective:
    applyDraw(effective)
    lastDrawState = effective
    drawStateKnown = true
  glUseProgram(program.handle)
  bindVertices(program, vertices, layout)
  program.uploadUniforms()
  program.bindTextures()
  let primitive = case effective.primitive
    of Triangles: GL_TRIANGLES
    of Lines: GL_LINES
    of Points: GL_POINTS
    of TriangleStrip: GL_TRIANGLE_STRIP
  if indices == nil:
    glDrawArraysInstanced(primitive, first.GLint, count.GLsizei,
      instanceCount.GLsizei)
  else:
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indices.handle)
    glDrawElementsInstanced(primitive, count.GLsizei,
      if index32: GL_UNSIGNED_INT else: GL_UNSIGNED_SHORT,
      cast[pointer](first * (if index32: 4 else: 2)), instanceCount.GLsizei)

proc drawStream*[T](program: ShaderProgram, values: openArray[T], count: int,
    state: DrawState) =
  ## Uploads and draws transient shared geometry with explicit ownership.
  if values.len == 0 or count <= 0:
    return
  if program.stream == nil:
    program.stream = newBuffer(values)
  else:
    program.stream.updateBuffer(values)
  draw(program, program.stream, count, state)
