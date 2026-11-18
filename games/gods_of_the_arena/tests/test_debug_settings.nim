import
  windy,
  polyworld/[chrome, inputs, menus],
  ../settings

echo "Testing GotA debug shortcuts migrate without replacing custom controls"
block:
  var bindings = DefaultBindings
  bindings[AbilityOneInput] = [KeyJ, MouseButton4]
  bindings.migrateGotaBindings()
  doAssert bindings[DebugInput] == [KeyF2, ButtonUnknown]
  doAssert bindings[TraceInput] == [KeyF1, ButtonUnknown]
  doAssert bindings[AbilityOneInput] == [KeyJ, MouseButton4]
  doAssert bindings[WaterPanelInput] == [ButtonUnknown, ButtonUnknown]
  let migrated = bindings
  bindings.migrateGotaBindings()
  doAssert bindings == migrated

block:
  for action in [DebugInput, TraceInput]:
    var bindings = DefaultBindings
    bindings[action] = [KeyF6, KeyF7]
    let custom = bindings
    bindings.migrateGotaBindings()
    doAssert bindings[DebugInput] == custom[DebugInput]
    doAssert bindings[TraceInput] == custom[TraceInput]

echo "Testing GotA control reset keeps F2 and other games retain their defaults"
block:
  var preferences = Preferences()
  preferences.bindings[DebugInput] = [KeyF9, ButtonUnknown]
  preferences.resetBindings(GotaControlProfile)
  doAssert preferences.bindings[DebugInput] == [KeyF2, ButtonUnknown]
  doAssert preferences.bindings[TraceInput] == [KeyF1, ButtonUnknown]
  doAssert DefaultBindings[DebugInput] == [KeyF1, ButtonUnknown]
  doAssert DefaultBindings[TraceInput] == [KeyF2, ButtonUnknown]
  for binding in GotaControlProfile.actions:
    doAssert binding.action != WaterPanelInput

echo "Testing F2 opens and closes GotA debugging without firing during binding capture"
block:
  let
    previousBindings = inputBindings
    previousCustom = customBindingsEnabled
    previousCapture = bindingCapture
    previousOpen = debugMenuOpen
  inputBindings = GotaControlProfile.defaults
  customBindingsEnabled = true
  bindingCapture = false
  debugMenuOpen = false
  doAssert handleChromeKey(KeyF2)
  doAssert debugMenuOpen
  doAssert handleChromeKey(KeyF2)
  doAssert not debugMenuOpen
  bindingCapture = true
  doAssert not handleChromeKey(KeyF2)
  doAssert not debugMenuOpen
  inputBindings = previousBindings
  customBindingsEnabled = previousCustom
  bindingCapture = previousCapture
  debugMenuOpen = previousOpen

echo "GotA debug settings tests passed"
