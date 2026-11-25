import opengl

type
  WorldBarTexture* = GLuint
  WorldBarGpu = object
    program: GLuint
    vertexArray: GLuint
    vertexBuffer: GLuint
    whiteTexture: GLuint
