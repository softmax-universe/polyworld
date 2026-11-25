import pixie, common

type ParticleGpu = ref object
  program: MetalProgram
  sightTexture: MetalTexture
