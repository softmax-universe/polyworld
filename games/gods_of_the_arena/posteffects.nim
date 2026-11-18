## Arena post-processing defaults and live debug controls.

import
  std/strutils,
  silky, vmath, windy,
  polyworld/screenocclusions

const ArenaOcclusion* = ScreenOcclusionSettings(
  enabled: true,
  radius: 1.2,
  intensity: 3.0,
  bias: 0.08,
  tint: vec3(0.10, 0.10, 0.16),
  sharpness: 15.4,
  bodyOcclusion: 0.25
)

proc drawPostProcessing*(sk: Silky, window: Window,
    settings: var ScreenOcclusionSettings) =
  ## Tunes contact shading live inside the shared debug window.
  h1text "Ambient occlusion"
  checkBox "Enabled", settings.enabled
  text "Soft shading where surfaces meet."
  template slider(id, caption: string, value: var float32,
      low, high: float32) =
    text(caption & "  " & formatFloat(value, ffDecimal, 2))
    scrubber(id, value, low, high)
  slider("aoRadius", "Radius", settings.radius, 0.05, 4)
  slider("aoIntensity", "Intensity", settings.intensity, 0, 8)
  slider("aoBias", "Bias", settings.bias, 0, 0.5)
  slider("aoSharpness", "Edge sharpness", settings.sharpness, 0, 60)
  slider("aoBodies", "Character shading", settings.bodyOcclusion, 0, 1)
  h1text "Shadow tint"
  for (channel, name) in [(0, "Red"), (1, "Green"), (2, "Blue")]:
    slider("aoTint" & name, name, settings.tint[channel], 0, 1)
  button "Reset tuning":
    let enabled = settings.enabled
    settings = ArenaOcclusion
    settings.enabled = enabled
  text "Tuning lasts for this match."
  text "Enabled is saved with your display settings."
