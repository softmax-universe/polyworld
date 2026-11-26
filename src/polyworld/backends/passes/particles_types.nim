import pixie, common

type ParticleGpu = ref object
  program: ShaderProgram
  sightTexture: GpuImage
