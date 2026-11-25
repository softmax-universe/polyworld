## Backend-independent settings for CaC screen effects.

import std/[os, strutils], vmath

const
  BloomLevels* = 4
  PostLayerControls* {.booldefine: "cacPostLayers".} = false
    ## Compiles the layer views: the window can show any PostLayer.
  PostPanelControls* {.booldefine: "cacPostPanel".} = false
    ## Compiles the tuning window in postpanel.nim.

type
  PostLayer* = enum
    ## What the window shows. Key 1 is the final image, 2..9 then 0 the rest.
    FinalLayer = "final image"
    SceneLayer = "scene before bloom and grading"
    DepthLayer = "depth"
    NormalLayer = "surface normals"
    RawOcclusionLayer = "occlusion, unblurred"
    OcclusionLayer = "occlusion"
    BeforeVfxLayer = "scene before VFX"
    VfxLayer = "light added by VFX"
    BloomSourceLayer = "bloom source"
    BloomLayer = "bloom"

  PostSettings* = object
    enabled*: bool
    occlusion*: bool
    bloom*: bool
    fxaa*: bool
    occlusionRadius*: float32     ## World units the AO looks around a pixel.
    occlusionIntensity*: float32
    occlusionBias*: float32       ## Cosine ignored, hides flat-surface noise.
    occlusionTint*: Vec3          ## Color occlusion fades toward.
    occlusionSharpness*: float32  ## How hard the blur stops at depth edges.
    occlusionNormalDetail*: float32 ## Mapped surface relief the AO reacts to.
    bloomThreshold*: float32      ## Scene brightness that starts to glow.
    bloomVfx*: float32            ## How much of the VFX light glows.
    bloomStrength*: float32
    vignette*: float32
    vignetteStart*: float32       ## Distance from the center it begins.
    vignetteEnd*: float32         ## Distance where it reaches full strength.
    saturation*: float32
    contrast*: float32

proc envFlag(name: string, default = true): bool =
  ## Reads a boolean environment override.
  let value = getEnv(name)
  if value.len == 0: default else: value notin ["0", "false", "off", "no"]

proc envFloat(name: string, default: float32): float32 =
  ## Reads a numeric environment override.
  try: parseFloat(getEnv(name, $default)).float32
  except ValueError: default

proc defaultPostSettings*(): PostSettings =
  ## Builds the shared defaults and environment overrides.
  PostSettings(
    enabled: envFlag("CAC_POSTFX"),
    occlusion: envFlag("CAC_SSAO"),
    bloom: envFlag("CAC_BLOOM"),
    fxaa: envFlag("CAC_FXAA"),
    occlusionRadius: envFloat("CAC_SSAO_RADIUS", 1.501),
    occlusionIntensity: envFloat("CAC_SSAO_INTENSITY", 3.523),
    occlusionBias: envFloat("CAC_SSAO_BIAS", 0.08),
    occlusionTint: vec3(0.10, 0.10, 0.16),
    occlusionSharpness: 40,
    occlusionNormalDetail: 0.45,
    bloomThreshold: 0.922,
    bloomVfx: 1.0,
    bloomStrength: 0.75,
    vignette: 0.32,
    vignetteStart: 0.35,
    vignetteEnd: 1.05,
    saturation: 1.06,
    contrast: 0.12
  )
