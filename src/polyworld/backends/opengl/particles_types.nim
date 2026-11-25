import std/strutils, opengl

const
  ParticleUniformNames = [
    "uParticleViewProjection",
    "uParticleCameraRight",
    "uParticleCameraUp",
    "uParticleCameraForward",
    "uParticleTime",
    "uParticleStartTime",
    "uParticleTravelTime",
    "uParticleSeed",
    "uParticleEffectKind",
    "uParticleOrigin",
    "uParticleTarget",
    "uParticleSight",
    "uParticleSightOrigin",
    "uParticleSightWidth",
    "uParticleClipSight"
  ]
  ParticleVertexSource =
    when defined(emscripten):
      toShader(gameParticleVertex, glsl3WebGL, shaderVertex)
    else:
      toShader(gameParticleVertex, glsl4Desktop, shaderVertex)
  ParticleFragmentSource =
    when defined(emscripten):
      toShader(gameParticleFragment, glsl3WebGL, shaderFragment)
    else:
      toShader(gameParticleFragment, glsl4Desktop, shaderFragment)

type
  ParticleUniform = enum
    ViewProjectionUniform,
    CameraRightUniform,
    CameraUpUniform,
    CameraForwardUniform,
    TimeUniform,
    StartTimeUniform,
    TravelTimeUniform,
    SeedUniform,
    EffectKindUniform,
    OriginUniform,
    TargetUniform,
    SightUniform,
    SightOriginUniform,
    SightWidthUniform,
    ClipSightUniform

  ParticleProgram = object
    id: GLuint
    locations: array[ParticleUniform, GLint]

  ParticleGpu = object
    program: ParticleProgram
    vertexArray: GLuint
    sightTexture: GLuint
