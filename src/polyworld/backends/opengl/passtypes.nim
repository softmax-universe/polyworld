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
  VertexBuffer* = ref object
    handle*: GLuint
    target*: GLenum
    size*: int
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
    textures*: Table[string, GpuImage]
    samplerUnits*: Table[string, int]
    samplerTargets*: Table[string, GLenum]
    attributes*: Table[string, GLint]
    enabledAttributes*: seq[GLuint]
    values*: OrderedTable[GLint, UniformValue]
  TargetState* = object
    read*, draw*: GLint
    viewport*: array[4, GLint]
    target*: RenderTarget
  RendererState* = ref object
    window*: Window
    target*, frameTarget*: RenderTarget
    viewport*: IVec2
    stack*: seq[TargetState]
    stencilOverride*: DrawState
    hasStencilOverride*, active*: bool

var gpuRenderer* = RendererState()
