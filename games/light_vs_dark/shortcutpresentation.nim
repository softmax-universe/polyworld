## Presentation only: read live bindings, never cache or change input semantics.
import content, shortcuts
import chroma, pixie, silky, vmath
import polyworld/[chrome, gameuis]

proc shortcutAction*(kind: BuildingKind): ShortcutAction =
  doAssert kind <= BuildableHigh
  ShortcutAction(BuildTownHallShortcut.ord + kind.ord)

proc shortcutAction*(kind: UnitKind): ShortcutAction =
  ShortcutAction(TrainPeonShortcut.ord + kind.ord)

proc commandKeyLabel*(bindings: ShortcutBindings, action: ShortcutAction): string =
  let sequence = bindings[action]
  if sequence.len == 1: sequence else: "?"

proc shortcutRouteLabel*(bindings: ShortcutBindings, action: ShortcutAction): string =
  let sequence = bindings[action]
  if sequence.len == 1: sequence else: "Unbound"

proc commandKeyPanel*(slot: GameUiPanel, training: bool): GameUiPanel =
  ## Build costs are at the bottom; training costs at the top and queue at right.
  GameUiPanel(origin: slot.origin + vec2(2, if training: slot.size.y - 20 else: 2),
    size: vec2(22,18))

proc drawCommandKey*(sk: Silky, panel: GameUiPanel, label: string) =
  ## Draw AFTER unavailable veils and cost overlays. Opaque neutral backing
  ## keeps the hint equally readable on every faction and disabled command.
  sk.drawRect(panel.origin, panel.size, rgbx(18,20,25,255))
  sk.drawLabel(label, panel.origin, panel.size, rgbx(245,247,250,255),
    "Bold", CenterAlign)
