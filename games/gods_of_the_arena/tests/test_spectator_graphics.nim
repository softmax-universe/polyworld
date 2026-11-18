## Structural guard for the rendered route; packet/simulation behavior is tested
## against the real relay in test_spectator. Browser QA exercises these controls.
import std/strutils
let graphics = readFile("games/gods_of_the_arena/graphics.nim")
let ui = readFile("games/gods_of_the_arena/ui.nim")
doAssert "spectatorStream.receive()" in graphics
doAssert "spectatorStream.advance()" in graphics
doAssert "transport.streamed = network.isSpectator" in graphics
doAssert "if network != nil and not network.isSpectator:" in graphics
doAssert "transportAvailable()" in ui
# Locate the HUD branch without requiring drawUi to be its first statement.
# Reward text and other HUD layers may be drawn before the main UI.
let drawAt = graphics.find("            drawUi(")
doAssert drawAt >= 0, "Expected the rendered match HUD"
let
  mainStart = graphics.rfind("          if matchMenu == HiddenMatchMenu:", last = drawAt)
  mainEnd = graphics.find("          if matchMenu != HiddenMatchMenu:", drawAt)
doAssert mainStart >= 0 and mainEnd > drawAt, "Expected separate HUD and menu branches"
let main = graphics[mainStart ..< mainEnd]
doAssert "menuButton" notin main, "No main-screen leave/save buttons"
doAssert "network.client.status" notin main, "Status belongs in Esc, not over minimap"
echo "Spectator graphics routing and uncluttered HUD passed"
