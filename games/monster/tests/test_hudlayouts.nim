import
  vmath,
  ../hudlayouts

echo "Testing automatic Monster HUD scale"
doAssert abs(chatScale(vec2(1440, 900)) - 0.6'f) < 0.001
doAssert chatScale(vec2(640, 480)) < chatScale(vec2(1440, 900))
for size in [vec2(2560, 1600), vec2(3840, 2160), vec2(7680, 4320)]:
  doAssert chatScale(size) == 1.0'f

echo "Monster HUD scale tests passed"
