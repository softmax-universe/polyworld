import std/os

type
  CourtyardMaterial* = object
    ## Live stone material controls (the tuning panel edits these).
    normalStrength*: float32  ## 0 leaves the flat geometric normals.
    lampIntensity*: float32   ## Brightness of the courtyard lanterns.
    slopeBroad*: float32      ## Weight of the fractured rock-face map.
    scaleBroad*: float32      ## World units one tile covers.


proc defaultCourtyardMaterial*(): CourtyardMaterial =
  ## CAC_STONE_NORMALS=0 flattens the stone for comparison.
  CourtyardMaterial(
    normalStrength: if getEnv("CAC_STONE_NORMALS") == "0": 0 else: 0.7,
    lampIntensity: 4.5,
    slopeBroad: 1.25,
    scaleBroad: 6.0
  )
