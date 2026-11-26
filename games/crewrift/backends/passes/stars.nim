## rendering for the shared procedural night sky.

import
  vmath,
  polyworld/nightskies,
  polyworld/backends/passes/common

type StarField* = object
  program: ShaderProgram

proc initStarField*(): StarField =
  ## Compiles the shared Shady night sky for the active graphics device.
  result.program = newProgram(NightSkyVertexSource, NightSkyFragmentSource)

proc close*(field: var StarField) =
  ## Releases the star field pipeline while the shared device is alive.
  destroy(field.program)
  field = StarField()

proc draw*(
  field: StarField,
  viewProjection: Mat4,
  eye: Vec3,
  time: float32
) =
  ## Draws the procedural stars at the far plane without writing depth.
  field.program.setUniform("inverseViewProjection", viewProjection.inverse)
  field.program.setUniform("cameraEye", eye)
  field.program.setUniform("time", time)
  field.program.setUniform("skyBrightness", 1.0'f)
  draw(field.program, nil, 3, DrawState(
    depthTest: true,
    depthWrite: false,
    depthCompare: LessEqual
  ))
