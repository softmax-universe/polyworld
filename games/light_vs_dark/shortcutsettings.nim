## LvD single-key editor and platform-neutral Windy configuration storage.
import silky, vmath, windy
import polyworld/[chrome, inputs, menus]
import shortcuts
export shortcuts

const LvdInputActions* = [
  SelectInput, OrderInput, PanInput, CameraInput, PauseInput,
  MenuInput, DebugInput, FullscreenInput, PanLeftInput, PanRightInput,
  PanUpInput, PanDownInput, ShiftInput, ControlInput, ShadingInput,
  TraceInput, ZoomInInput, ZoomOutInput, AttackMoveInput, StopInput
]

type ShortcutEditor* = object
  active*: bool
  action*: ShortcutAction
  draft*: string
  error*: string

var
  currentShortcuts* = DefaultShortcuts
  shortcutEditor: ShortcutEditor
  captureHeld: set[Button]
  shortcutSettingsError*: string

proc maskShortcutBindings*(bindings: InputBindings,
    consumed: set[Button]): InputBindings =
  ## Keep action keys from becoming camera/selection aliases in polling.
  result = bindings
  for action in InputAction:
    for slot in 0 .. 1:
      if result[action][slot] in consumed:
        result[action][slot] = ButtonUnknown

proc shortcutKey*(button: Button): char =
  # Windy does not promise alphabetically contiguous enum ordinals.
  let name = $button
  if name.len == 4 and name[0 .. 2] == "Key" and
      name[3] in {'A'..'Z', '0'..'9'}:
    return name[3]
  if button == KeyEscape: return '\e'

proc shortcutInputConflict*(controls: InputBindings, key: char): string =
  ## Reject keys already used by an active LvD gameplay action.
  for action in LvdInputActions:
    for button in controls[action]:
      if key != '\0' and shortcutKey(button) == key:
        return $key & " is assigned to " & $action & "."

proc validateShortcutInput*(action: InputAction, key: Button): string =
  ## Keep global controls clear of fixed cancel and contextual commands.
  if key == KeyX: return "X is reserved for Cancel."
  let letter = shortcutKey(key)
  if letter == '\0': return
  for shortcut in ShortcutAction:
    if currentShortcuts[shortcut] == $letter:
      return $letter & " is assigned to " & shortcutLabel(shortcut) & "."

proc reconcileShortcutInputs*(bindings: var ShortcutBindings,
    controls: InputBindings): string =
  ## Preserve custom global controls when migrating contextual defaults.
  for action in ShortcutAction:
    if action == CancelSiteShortcut: continue
    let previous = bindings[action]
    if controls.shortcutInputConflict(previous[0]).len == 0: continue
    for key in "QWERFZVTGBHYUIOPJKLNM0123456789":
      if controls.shortcutInputConflict(key).len > 0: continue
      if bindings.setShortcut(action, $key).len == 0:
        result.add shortcutLabel(action) & ": " & previous &
          " conflicts with a control; assigned " & $key & ". "
        break

proc readShortcuts*(app = "Polyworld LvD"): ShortcutBindings =
  decodeShortcuts(getConfig(app, "hotkeys.json"))

proc saveShortcuts*(bindings: ShortcutBindings, app = "Polyworld LvD") =
  setConfig(app, "hotkeys.json", encodeShortcuts(bindings))

proc loadLvdShortcuts*() =
  shortcutSettingsError = ""
  try:
    currentShortcuts = readShortcuts()
    shortcutSettingsError = shortcutMigrationReport
  except CatchableError:
    currentShortcuts = DefaultShortcuts
    shortcutSettingsError = getCurrentExceptionMsg()

proc beginEdit*(editor: var ShortcutEditor, action: ShortcutAction) =
  ## Begin editing only actions whose keys can be reassigned.
  editor = ShortcutEditor(active: action != CancelSiteShortcut, action: action)
  if action == CancelSiteShortcut: editor.error = "X is reserved for Cancel."

proc editKey*(editor: var ShortcutEditor, bindings: var ShortcutBindings,
    key: char, controls = inputBindings): bool =
  ## Commit a complete contextual key only when gameplay controls permit it.
  if not editor.active: return false
  if key == '\e':
    editor.active = false
    editor.draft = ""
    return false
  if key notin {'A'..'Z', '0'..'9'}: return false
  editor.draft = $key
  editor.error = controls.shortcutInputConflict(key)
  if editor.error.len == 0:
    editor.error = bindings.setShortcut(editor.action, editor.draft)
  editor.active = false
  result = editor.error.len == 0

proc endShortcutEditing*() =
  if shortcutEditor.active: bindingCapture = false
  shortcutEditor = ShortcutEditor()
  captureHeld = {}

proc persistCurrent() =
  try:
    currentShortcuts.saveShortcuts()
    shortcutSettingsError = ""
  except CatchableError:
    shortcutSettingsError = getCurrentExceptionMsg()

proc drawShortcutRows(sk: Silky, window: Window, origin: Vec2) =
  if shortcutEditor.active:
    for button in Button:
      if not window.buttonDown[button]: captureHeld.excl button
      let key = shortcutKey(button)
      if key != '\0' and window.buttonPressed[button] and button notin captureHeld:
        captureHeld.incl button
        if shortcutEditor.editKey(currentShortcuts, key): persistCurrent()
        if not shortcutEditor.active:
          bindingCapture = false
          break
  sk.drawLabel("CONTEXTUAL ACTION KEYS", origin, vec2(720, 36),
    sk.theme.defaultTextColor)
  sk.drawLabel("One key per action. Select a worker or producer to see its actions.",
    origin + vec2(0, 36), vec2(720, 36), sk.theme.defaultTextColor)
  let message =
    if shortcutEditor.active: "Type one key for " & shortcutLabel(shortcutEditor.action) & "; Esc cancels."
    elif shortcutSettingsError.len > 0: shortcutSettingsError
    elif shortcutEditor.error.len > 0: shortcutEditor.error
    else: "A/S/D/C are action keys. X always cancels."
  sk.drawLabel(message, origin + vec2(0, 72), vec2(720, 36),
    sk.theme.defaultTextColor)
  for action in ShortcutAction:
    let row = origin + vec2(0, 112 + action.ord.float32 * 38)
    sk.drawLabel(shortcutLabel(action), row, vec2(410, 36), sk.theme.defaultTextColor)
    sk.at = row + vec2(420, 0)
    if action == CancelSiteShortcut:
      sk.drawLabel("X (always Cancel)", sk.at, vec2(280, 36),
        sk.theme.defaultTextColor)
      continue
    let sequence = currentShortcuts[action]
    let label =
      if shortcutEditor.active and shortcutEditor.action == action:
        "Press a key..."
      else: sequence
    button label, not bindingCapture:
      shortcutEditor.beginEdit(action)
      captureHeld = {}
      for held in Button:
        if window.buttonDown[held]: captureHeld.incl held
      bindingCapture = true
  sk.at = origin + vec2(420, 112 + (ShortcutAction.high.ord + 1).float32 * 38)
  button "Reset action keys", not bindingCapture:
    currentShortcuts.resetShortcuts()
    shortcutSettingsError = currentShortcuts.reconcileShortcutInputs(inputBindings)
    shortcutEditor.error = ""
    let report = shortcutSettingsError
    persistCurrent()
    if shortcutSettingsError.len == 0: shortcutSettingsError = report

proc lvdShortcutExtension*(): ControlExtension =
  ## Add LvD shortcut editing and shared-control conflict validation.
  ControlExtension(draw: drawShortcutRows,
    capturing: proc(): bool = shortcutEditor.active,
    validateBinding: validateShortcutInput)
