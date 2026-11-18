import std/unittest
import silky, vmath, windy
import polyworld/[menus, inputs]
import ../games/light_vs_dark/[lobbies, shortcuts, shortcutsettings]

suite "LvD shortcut settings integration":
  test "settings entry point accepts the shared main menu and match layout":
    static:
      doAssert compiles(block:
        let sk = Silky()
        let window: Window = nil
        var preferences = Preferences()
        discard sk.lvdSettingsPanel(window, preferences, "Polyworld LvD", vec2(0))
      )
  test "button adapter supports letters digits punctuation and Escape":
    check shortcutKey(KeyB) == 'B'
    check shortcutKey(KeyP) == 'P'
    check shortcutKey(Key7) == '7'
    check shortcutKey(KeyEscape) == '\e'
    check shortcutKey(KeyPeriod) == '.'
    check shortcutKey(KeyComma) == ','
    check shortcutKey(MouseLeft) == '\0'
  test "consumed sequence keys cannot trigger polled mouse aliases":
    var bindings = LvdControlProfile.defaults
    when declared(maskShortcutBindings):
      let masked = maskShortcutBindings(bindings, {KeyS, KeyA})
      check masked[PanInput] == [MouseMiddle, ButtonUnknown]
      check masked[AttackMoveInput] == [ButtonUnknown, ButtonUnknown]
      check bindings == LvdControlProfile.defaults
    else:
      check false

  test "native config roundtrip uses isolated app namespace":
    let app = "Polyworld LvD Shortcut Tests"
    var custom = DefaultShortcuts
    check custom.setShortcut(BuildBarracksShortcut, "7") == ""
    check custom.setShortcut(IdlePeonShortcut, ",") == ""
    saveShortcuts(custom, app)
    check readShortcuts(app) == custom
    custom.resetShortcuts()
    saveShortcuts(custom, app)
    check readShortcuts(app) == DefaultShortcuts
  test "single-key editor keeps old assignment on duplicate and commits complete input":
    var editor: ShortcutEditor
    var bindings = DefaultShortcuts
    editor.beginEdit(BuildBarracksShortcut)
    check editor.editKey(bindings, 'T') == false
    check editor.error.len > 0
    check bindings == DefaultShortcuts
    editor.beginEdit(BuildBarracksShortcut)
    check editor.editKey(bindings, '7') == true
    check bindings[BuildBarracksShortcut] == "7"
    editor.beginEdit(TrainPeonShortcut)
    check editor.editKey(bindings, '\e') == false
    check not editor.active
    check bindings[TrainPeonShortcut] == "Q"
    editor.beginEdit(IdlePeonShortcut)
    check editor.editKey(bindings, ',')
    check bindings[IdlePeonShortcut] == ","

  test "defaults never conflict with active game controls":
    for action in ShortcutAction:
      if action != CancelSiteShortcut:
        check LvdControlProfile.defaults.shortcutInputConflict(
          DefaultShortcuts[action][0]) == ""

  test "both editors reject cross-palette control conflicts and fixed X":
    var editor: ShortcutEditor
    var bindings = DefaultShortcuts
    var controls = LvdControlProfile.defaults
    controls[CameraInput] = [KeyJ, ButtonUnknown]
    editor.beginEdit(BuildBarracksShortcut)
    check not editor.editKey(bindings, 'J', controls)
    check editor.error.len > 0
    check bindings == DefaultShortcuts
    editor.beginEdit(CancelSiteShortcut)
    check not editor.active
    check not editor.editKey(bindings, '7', controls)
    check bindings[CancelSiteShortcut] == "X"
    currentShortcuts = DefaultShortcuts
    let extension = lvdShortcutExtension()
    check extension.validateBinding(CameraInput, KeyQ).len > 0
    check extension.validateBinding(CameraInput, KeyX).len > 0
    check extension.validateBinding(CameraInput, KeyPeriod).len > 0
    check extension.validateBinding(CameraInput, KeyJ) == ""
    check extension.validateBinding(CameraInput, ButtonUnknown) == ""

  test "saved custom controls take precedence during shortcut migration":
    var controls = LvdControlProfile.defaults
    controls[CameraInput] = [KeyQ, ButtonUnknown]
    var bindings = DefaultShortcuts
    let report = bindings.reconcileShortcutInputs(controls)
    check report.len > 0
    check controls[CameraInput] == [KeyQ, ButtonUnknown]
    check bindings[BuildTownHallShortcut] != "Q"
    check bindings[TrainPeonShortcut] != "Q"
    for action in ShortcutAction:
      if action != CancelSiteShortcut:
        check controls.shortcutInputConflict(bindings[action][0]) == ""
    check bindings.reconcileShortcutInputs(controls) == ""
    check decodeShortcuts(encodeShortcuts(bindings)) == bindings

  test "custom period control keeps priority over the new idle peon default":
    var controls = LvdControlProfile.defaults
    controls[CameraInput] = [KeyPeriod, ButtonUnknown]
    var bindings = DefaultShortcuts
    check bindings.reconcileShortcutInputs(controls).len > 0
    check bindings[IdlePeonShortcut] != "."
    check controls[CameraInput] == [KeyPeriod, ButtonUnknown]
    check decodeShortcuts(encodeShortcuts(bindings)) == bindings
