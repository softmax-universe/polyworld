import std/strutils
let source = readFile("games/gods_of_the_arena/graphics.nim")
doAssert "drawAimBanner" notin source,
  "Cast mode must not draw an instructional popup over units"
doAssert "proc updateAim" in source
doAssert "armedAbility = -1" in source
echo "Cast previews remain without instructional popup"
