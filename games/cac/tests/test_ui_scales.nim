import
  vmath,
  polyworld/chrome,
  ../ui/heroselect

echo "Testing hero selection automatic and manual scales"
block:
  let
    savedMode = uiScaleMode
    savedPercent = uiScalePercent
    savedReference = uiScaleReference
  defer:
    uiScaleMode = savedMode
    uiScalePercent = savedPercent
    uiScaleReference = savedReference
  uiScaleMode = AutoUiScale
  for density in [1.0'f, 2.0'f, 3.0'f]:
    for size in [vec2(1920, 1080), vec2(3840, 2160), vec2(2160, 3840)]:
      doAssert abs(heroSelectScale(size, density) - 0.72'f) < 0.001
  doAssert heroSelectScale(vec2(960, 600)) < 0.72'f
  uiScaleMode = CustomUiScale
  uiScalePercent = 200
  for size in [vec2(960, 600), vec2(3840, 2160), vec2(2160, 3840)]:
    doAssert abs(heroSelectScale(size) - 1.44'f) < 0.001

echo "Hero selection scale tests passed"
