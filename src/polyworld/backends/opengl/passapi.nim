## OpenGL and WebGL implementation of the shared scene-pass interface.

import
  shady,
  passtypes, passresources, passprograms, passtargets

export passtypes, passresources, passprograms, passtargets

converter programHandle*(program: ShaderProgram): GLuint =
  ## Exposes a borrowed program name for legacy OpenGL interoperability.
  if program == nil: 0.GLuint else: program.handle

template nativeStage*(fn, stage: untyped): string =
  ## Generates GLSL for the current desktop or browser rendering context.
  when defined(emscripten):
    toShader(fn, glsl3WebGL, stage)
  else:
    toShader(fn, glsl4Desktop, stage)
