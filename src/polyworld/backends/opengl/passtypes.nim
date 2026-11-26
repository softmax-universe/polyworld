## OpenGL resource ownership for shared rendering passes.

import
  std/tables,
  opengl, vmath, windy,
  ../../[renderdescriptions, pixelformats, shadermetadata]

export opengl, renderdescriptions, pixelformats

type
  UniformKind* = enum
    UniformFloat, UniformSigned, UniformUnsigned, UniformMat3, UniformMat4
  UniformValue* = object
    kind*: UniformKind
    components*, count*: int
    words*: seq[uint32]
    dirtyCount*: int
  VertexInputs* = ref object
    stride*: int
    attributes*: seq[tuple[slot: GLuint, format: VertexFormat, offset: int]]
  VertexBuffer* = ref object
    handle*: GLuint
    target*: GLenum
    size*: int
    arrays*: seq[tuple[inputs: VertexInputs, vao: GLuint]]
  GpuImage* = ref object
    handle*, sampler*: GLuint
    target*, nativeFormat*: GLenum
    width*, height*, layers*, levels*: int
    anisotropy*: float32
    pixelFormat*: TextureFormat
    ownsHandle*: bool
  RenderTarget* = ref object
    framebuffer*: GLuint
    width*, height*, samples*: int
    color*, depth*: GpuImage
    multisampleFramebuffer*, multisampleColor*, multisampleDepth*: GLuint
    stencil*, borrowsColor*, borrowsDepth*, resolved*, ownsFramebuffer*: bool
  ShaderProgram* = ref object
    handle*, vao*: GLuint
    stream*: VertexBuffer
    vertexSource*, fragmentSource*: string
    layout*: VertexLayout
    ## Default-block uniforms have no byte offsets; locations stay separate.
    reflection*: ShaderLayout
    fieldLocations*: seq[GLint]
    fieldArrays*: seq[bool]
    uniforms*: Table[string, GLint]
    samplerUnits*: Table[string, int]
    samplers*: seq[tuple[location: GLint, target: GLenum, image: GpuImage]]
    attributes*: Table[string, GLint]
    defaultInputs*: VertexInputs
    otherInputs*: seq[tuple[layout: VertexLayout, inputs: VertexInputs]]
    values*: Table[GLint, UniformValue]
    dirtyUniforms*: seq[GLint]
    samplersInitialized*: bool
  TargetState* = object
    read*, draw*: GLint
    viewport*: array[4, GLint]
    target*: RenderTarget
  RendererState* = ref object
    window*: Window
    target*, frameTarget*, defaultDrawable*: RenderTarget
    viewport*: IVec2
    stack*: seq[TargetState]
    stencilOverride*: DrawState
    hasStencilOverride*, active*: bool

var gpuRenderer* = RendererState()
