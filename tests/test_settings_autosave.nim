## Preference edits persist through the real settings panel without leaving it.
import
  std/[importutils, monotimes],
  opengl, windy/internal,
  polyworld/viewers
include ../src/polyworld/menus

privateAccess(Window)

proc testSettingsAutosave() =
  ## Uses an isolated settings namespace and a hidden native window.
  let
    app = "Polyworld instant settings test " & $getCurrentProcessId() &
      "-" & $getMonoTime().ticks
    directory = getConfigHome(app)
    window = newWindow("Instant settings", ivec2(1000, 800), visible = false)
  doAssert not dirExists(directory)
  defer:
    bindingCapture = false
    window.close()
    if dirExists(directory):
      removeDir(directory)
  window.makeContextCurrent()
  loadExtensions()
  let builder = newHudAtlas(2048)
  builder.addDefaultFonts()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.applyThemePatches()
  var preferences = Preferences(name: "Original", server: "ws://original/ws")
  preferences.savePreferences(app)

  proc frame(pressed: set[Button] = {}) =
    ## Draws one settings frame without activating the navigation button.
    window.state.perFrame = PerFrame(buttonPressed: pressed)
    window.state.buttonDown = {}
    sk.beginUi(window, window.size)
    sk.mousePos = vec2(950, 750)
    doAssert not sk.settingsPanel(window, preferences, app, vec2(50, 50))
    sk.endUi()

  settingsTab = ControlsSettings
  captureAction = CameraInput
  captureSlot = 0
  bindingCapture = true
  frame({KeyJ})
  doAssert not bindingCapture
  doAssert inputBindings[CameraInput][0] == KeyJ
  doAssert readPreferences(app).bindings[CameraInput][0] == KeyJ,
    "A changed binding must persist before leaving Settings"
  let saved = getConfig(app, "settings.json")
  bindingCapture = true
  frame({KeyEscape})
  doAssert not bindingCapture
  doAssert getConfig(app, "settings.json") == saved

  settingsTab = NetworkingSettings
  frame()
  for (id, value) in [("displayName", "New player"),
      ("preferredServer", "wss://example.test/ws")]:
    let field = textBoxStates[id]
    field.focus(sk, window, id)
    field.selector = 0
    field.cursor = field.runes.len
    doAssert window.onTextInput != nil
    window.onTextInput(value)
    frame()
    let loaded = readPreferences(app)
    if id == "displayName":
      doAssert preferences.name == value and loaded.name == value
    else:
      doAssert preferences.server == value and loaded.server == value
  doAssert readPreferences(app).bindings[CameraInput][0] == KeyJ
  echo "Settings edits persist immediately; cancelled binding capture is inert"

testSettingsAutosave()
