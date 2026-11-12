import
  silky, silky/testwindow, vmath,
  ../[common, ui]

when not defined(silkyTesting):
  {.error: "Run this test with -d:silkyTesting.".}

proc frame(
  harness: var TestHarness,
  chat: var ChatUi,
  pending = false,
  available = true
): string =
  ## Runs the real UI handlers through Silky's window-compatible harness.
  harness.sk.uiScale = chat.scale
  harness.beginFrame()
  result = drawUi(
    harness.sk, harness.window, World(), chat, [],
    pending, available, ""
  )
  harness.endFrame()
  harness.window.syncInput(chat)
  harness.window.resetInputState()

block input:
  var
    harness = newTestHarness(SilkyAtlas(), 1280, 800)
    chat = initChatUi()
  harness.window.installInput(addr chat)
  discard frame(harness, chat)
  doAssert harness.window.runeInputEnabled
  harness.window.typeText("é🙂")
  doAssert chat.input == "é🙂", "Committed Unicode text reaches Monster."
  harness.window.pressButton(KeyBackspace)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyBackspace)
  doAssert chat.input == "é", "Backspace removes one complete codepoint."
  harness.window.typeText("\xff")
  doAssert chat.input == "é", "Malformed UTF-8 cannot corrupt the input."

  chat.restoreInput("Walk to village")
  harness.window.pressButton(KeyLeft)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyLeft)
  harness.window.typeText("!")
  doAssert chat.input == "Walk to villag!e", "Editing honors the caret."

  chat.restoreInput("")
  setClipboardString("Gather berries")
  harness.window.pressButton(KeyLeftSuper)
  harness.window.pressButton(KeyV)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyV)
  harness.window.releaseButton(KeyLeftSuper)
  doAssert chat.input == "Gather berries", "Paste inserts exactly once."

  harness.window.pressButton(KeyEscape)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyEscape)
  doAssert not chat.typing and not harness.window.runeInputEnabled
  harness.window.typeText("ignored")
  doAssert chat.input == "Gather berries"
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat) == "", "Enter first restores chat focus."
  harness.window.releaseButton(KeyEnter)
  doAssert chat.typing and harness.window.runeInputEnabled

  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat, pending = true) == ""
  harness.window.releaseButton(KeyEnter)
  doAssert chat.input == "Gather berries", "Pending requests retain a draft."
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat) == "Gather berries"
  harness.window.releaseButton(KeyEnter)
  doAssert chat.input.len == 0 and chat.typing
  chat.restoreInput("Try again")
  harness.window.typeText(".")
  doAssert chat.input == "Try again.", "A failed send restores the caret."

echo "Monster chat focus, Unicode editing, clipboard, and retry tests passed."

block scaledInput:
  var
    harness = newTestHarness(SilkyAtlas(), 2560, 1600)
    chat = initChatUi()
  chat.scale = 2
  harness.window.installInput(addr chat)
  discard frame(harness, chat)
  chat.restoreInput("Walk to the village")
  harness.window.moveMouse(2560 - 250, 346)
  doAssert chat.mouseOverUi(harness.window),
    "The scaled creature-focus button blocks camera gestures."
  harness.window.pressButton(MouseLeft)
  discard frame(harness, chat)
  harness.window.releaseButton(MouseLeft)
  doAssert chat.focusRequested, "The scaled camera button receives clicks."
  chat.focusRequested = false
  harness.window.moveMouse(1926, 1472)
  doAssert chat.mouseOverUi(harness.window),
    "The scaled chat panel blocks camera gestures."
  harness.window.pressButton(MouseLeft)
  doAssert frame(harness, chat) == "Walk to the village",
    "The scaled Send button receives clicks at framebuffer coordinates."
  harness.window.releaseButton(MouseLeft)
  harness.window.moveMouse(40, 900)
  doAssert not chat.mouseOverUi(harness.window),
    "World gestures remain available outside scaled panels."

echo "Monster scaled layout and click tests passed."

block resourcePanels:
  var
    harness = newTestHarness(SilkyAtlas(), 1280, 800)
    chat = initChatUi()
  harness.window.moveMouse(40, 250)
  doAssert chat.mouseOverUi(harness.window),
    "The resource panel blocks camera gestures behind its text."
  harness.window.moveMouse(1100, 80)
  doAssert chat.mouseOverUi(harness.window),
    "The creature inventory blocks camera gestures behind its text."
  harness.window.size = ivec2(640, 480)
  harness.window.moveMouse(40, 200)
  doAssert not chat.mouseOverUi(harness.window),
    "Narrow layouts leave world space clear of the ancillary village panel."
  discard frame(harness, chat)

echo "Monster resource panel layout tests passed."
