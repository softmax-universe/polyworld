import opengl

type
  ShapeTexture* = GLuint
  ShapeGpu = object
    program: GLuint
    vertexArray: GLuint
    vertexBuffer: GLuint
    whiteTexture: GLuint
