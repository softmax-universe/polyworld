## Single-key contextual actions, independent of window/rendering code.
import std/[json, strutils]
import content, controls, sim

type
  ShortcutAction* = enum
    BuildTownHallShortcut, BuildFarmShortcut, BuildBarracksShortcut,
    BuildLumberMillShortcut, BuildTowerShortcut, BuildStablesShortcut,
    BuildChurchShortcut, BuildBlacksmithShortcut,
    TrainPeonShortcut, TrainSoldierShortcut, TrainArcherShortcut,
    TrainMageShortcut, TrainKnightShortcut, TrainCatapultShortcut,
    TrainClericShortcut, TrainSummonShortcut,
    ResearchArrowsShortcut, ResearchEdgesShortcut, ResearchPlatingShortcut,
    ResearchWindrunnerShortcut, CancelSiteShortcut
  ShortcutBindings* = array[ShortcutAction, string]
  ShortcutActions* = set[ShortcutAction]
  ShortcutState* = object
    held: set[char]
    consumedKeys: set[char]
  ShortcutMatch* = object
    consumed*: bool
    action*: int

const
  DefaultShortcuts*: ShortcutBindings = [
    "Q", "W", "E", "R", "F", "Z", "V", "T",
    "Q", "W", "E", "R", "F", "Z", "V", "T", "G", "B", "H", "Y", "X"
  ]
  LegacyShortcuts: ShortcutBindings = [
    "H", "F", "B", "L", "T", "U", "C", "K",
    "P", "S", "A", "M", "K", "C", "H", "E", "Q", "W", "R", "V", "X"
  ]
  ReservedShortcutKeys* = "ASDCX"
const ShortcutLabels*: array[ShortcutAction, string] = [
  "Build Town Hall", "Build Farm", "Build Barracks", "Build Lumber Mill",
  "Build Tower", "Build Stables", "Build Church", "Build Blacksmith",
  "Train Peon", "Train Swordsman", "Train Archer", "Train Mage",
  "Train Knight", "Train Catapult", "Train Cleric", "Train Elemental",
  "Research Keenflight Arrows", "Research Tempered Edges",
  "Research Runed Plating", "Research Windrunner Training", "Cancel construction"
]
var shortcutMigrationReport*: string

proc shortcutLabel*(action: ShortcutAction): string =
  ## Returns the human-readable name of a contextual command.
  ShortcutLabels[action]

proc sharesContext(a, b: ShortcutAction): bool =
  ## Worker builds and producer actions are separate palettes. All producers
  ## can coexist in a mixed selection, so their keys must remain distinct.
  (a <= BuildBlacksmithShortcut) == (b <= BuildBlacksmithShortcut)

proc normalizeKey(text: string): string =
  ## Normalizes a single letter or digit without accepting modifiers.
  result = text.strip.toUpperAscii
  if result.len != 1 or result[0] notin {'A'..'Z', '0'..'9'}:
    raise newException(ValueError, "Use one letter or digit.")

proc shortcutKeyError(action: ShortcutAction, key: string): string =
  ## Keeps global action keys and the fixed cancel key out of other commands.
  if action == CancelSiteShortcut:
    if key != "X":
      return "X is always Cancel and cannot be reassigned."
  elif key[0] in ReservedShortcutKeys:
    return key & " is reserved for a game action; X is always Cancel."

proc setShortcut*(bindings: var ShortcutBindings, action: ShortcutAction,
    text: string): string =
  ## Assigns a valid command key without displacing another command.
  var key: string
  try: key = normalizeKey(text)
  except ValueError: return getCurrentExceptionMsg()
  result = shortcutKeyError(action, key)
  if result.len > 0:
    return
  for other in ShortcutAction:
    if other != action and action.sharesContext(other) and bindings[other] == key:
      return "Already assigned to " & shortcutLabel(other) & " in this palette."
  bindings[action] = key

proc resetShortcuts*(bindings: var ShortcutBindings) =
  ## Restores the left-hand command layout.
  bindings = DefaultShortcuts

proc encodeShortcuts*(bindings: ShortcutBindings): string =
  ## Saves the current single-key layout and its migration version.
  var root = newJObject()
  root["version"] = %3
  var rows = newJObject()
  for action in ShortcutAction: rows[$action] = %bindings[action]
  root["bindings"] = rows
  $root

proc decodeShortcuts*(bytes: string): ShortcutBindings =
  ## Migrates older defaults while preserving valid custom assignments.
  result = DefaultShortcuts
  shortcutMigrationReport = ""
  if bytes.len == 0: return
  try:
    let root = parseJson(bytes)
    if root.kind != JObject or root["version"].getInt notin [1, 2, 3] or
        root["bindings"].kind != JObject:
      raise newException(ValueError, "Unsupported shortcut settings format.")
    let
      version = root["version"].getInt
      migrating = version < 3
    var
      custom: ShortcutActions
      defaultsUpdated = false
    for action in ShortcutAction:
      if root["bindings"].hasKey($action):
        var value = root["bindings"][$action].getStr
        if version == 1:
          value = value.splitWhitespace.join("").toUpperAscii
          if value.len != 2 or value[0] notin {'A'..'Z', '0'..'9'}:
            raise newException(ValueError, "Invalid legacy shortcut: " & value)
          value = $value[1]
        value = normalizeKey(value)
        if migrating and value == LegacyShortcuts[action]:
          if value != DefaultShortcuts[action]:
            defaultsUpdated = true
        else:
          result[action] = value
          custom.incl action
    if defaultsUpdated:
      shortcutMigrationReport = "Updated default commands to the left-hand layout. "
    # Preserve custom keys before assigning migrated defaults. Repairs avoid
    # both accepted keys and keys still needed by later commands.
    var order: seq[ShortcutAction]
    for action in ShortcutAction:
      if action in custom: order.add action
    for action in ShortcutAction:
      if action notin custom: order.add action
    var accepted: ShortcutActions
    for action in order:
      var conflict = shortcutKeyError(action, result[action]).len > 0
      for other in accepted:
        if action.sharesContext(other) and result[action] == result[other]: conflict = true
      if conflict:
        if not migrating:
          raise newException(ValueError,
            "Reserved or duplicate shortcut: " & result[action])
        let previous = result[action]
        var candidates = @[DefaultShortcuts[action]]
        if action != CancelSiteShortcut:
          for c in "QWERFZVTGBHYUIOPJKLNM0123456789": candidates.add $c
        for candidate in candidates:
          var used = shortcutKeyError(action, candidate).len > 0
          if action != CancelSiteShortcut:
            for other in ShortcutAction:
              if action != other and action.sharesContext(other) and
                  result[other] == candidate:
                used = true
          if not used:
            result[action] = candidate
            break
        shortcutMigrationReport.add shortcutLabel(action) & ": " & previous &
          " conflicted; assigned " & result[action] & ". "
      accepted.incl action
  except CatchableError:
    raise newException(ValueError, "Cannot read shortcuts: " & getCurrentExceptionMsg())

proc contextualActions*(world: World, player: int32,
    selected: openArray[int32]): ShortcutActions =
  ## Availability is deliberately separate: unavailable relevant actions remain
  ## visible, while unrelated producers never appear as disabled commands.
  if world == nil or player < 0 or player >= world.players.len: return
  for id in selected:
    let index = world.unitIndex(id)
    if index >= 0:
      let u = world.units[index]
      if u.owner == player and u.hp > 0 and u.kind == PeonUnit and
          u.state notin {UnitDying, UnitInMine}:
        return {BuildTownHallShortcut .. BuildBlacksmithShortcut}
  for id in selected:
    let index = world.buildingIndex(id)
    if index < 0: continue
    let b = world.buildings[index]
    if b.owner != player or b.hp <= 0 or b.state == BuildingDying: continue
    if b.state == BuildingUnderConstruction:
      result.incl CancelSiteShortcut
      continue
    for kind in UnitKind:
      if unitOf(player, kind).trainedAt == b.kind:
        result.incl ShortcutAction(TrainPeonShortcut.ord + kind.ord)
    for kind in ResearchKind:
      if researchBuilding(kind) == b.kind:
        result.incl ShortcutAction(ResearchArrowsShortcut.ord + kind.ord)

proc selectedResearchProducer*(world: World, player: int32,
    selected: openArray[int32], kind: ResearchKind): int32 =
  ## Prefer a usable selected producer; retain a disabled card if all are busy.
  result = NoEntity
  for id in selected:
    let index = world.buildingIndex(id)
    if index < 0: continue
    let b = world.buildings[index]
    if b.owner != player or b.hp <= 0 or b.kind != researchBuilding(kind): continue
    if world.canResearch(player, id, kind): return id
    if result == NoEntity: result = id

proc performShortcut*(world: World, player: int32,
    selected: openArray[int32], action: ShortcutAction): bool =
  if action notin world.contextualActions(player, selected): return false
  if action <= BuildBlacksmithShortcut:
    let kind = BuildingKind(action.ord)
    if not world.canBuild(player, kind): return false
    pendingBuild = kind.ord.int32
    attackMoveArmed = false
    return true
  elif action <= TrainSummonShortcut:
    return world.queueSelectedTrain(player, selected,
      UnitKind(action.ord - TrainPeonShortcut.ord))
  elif action == CancelSiteShortcut:
    for id in selected:
      let index = world.buildingIndex(id)
      if index >= 0:
        let b = world.buildings[index]
        if b.owner == player and b.hp > 0 and b.state == BuildingUnderConstruction:
          queueCancel(player, id)
          result = true
  else:
    let kind = ResearchKind(action.ord - ResearchArrowsShortcut.ord)
    let id = world.selectedResearchProducer(player, selected, kind)
    if id != NoEntity and world.canResearch(player, id, kind):
      queueResearch(player, id, kind)
      return true

proc cancelShortcut*(state: var ShortcutState) =
  ## No persistent menu state. Held-key suppression ends only at release.
  discard

proc resetShortcut*(state: var ShortcutState) = state = ShortcutState()
proc releaseShortcut*(state: var ShortcutState, key: char) =
  state.held.excl key.toUpperAscii
  state.consumedKeys.excl key.toUpperAscii

proc pressShortcut*(state: var ShortcutState, bindings: ShortcutBindings,
    key: char, now: float64, gameplay = true, modified = false,
    actions: ShortcutActions = {ShortcutAction.low .. ShortcutAction.high}): ShortcutMatch =
  result.action = -1
  let key = key.toUpperAscii
  if not gameplay or modified:
    state.held.incl key
    return
  if key in state.held:
    result.consumed = key in state.consumedKeys
    return
  state.held.incl key
  for action in actions:
    if bindings[action] == $key:
      result.action = action.ord
      result.consumed = true
      state.consumedKeys.incl key
      return
