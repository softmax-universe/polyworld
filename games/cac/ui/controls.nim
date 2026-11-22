import windy, polyworld/[inputs, menus]

const CacControlProfile* = ControlProfile(
  defaults: DefaultBindings,
  actions: @[
    ControlBinding(action: SelectInput, label: "Select card / target"),
    ControlBinding(action: OrderInput, label: "Cancel targeting"),
    ControlBinding(action: MenuInput, label: "Game menu / cancel")
  ])

proc battlePressed*(window: Window, button: Button): bool =
  ## Reads configurable card-table actions and preserves other key shortcuts.
  case button
  of MouseLeft:
    window.actionPressed(SelectInput)
  of MouseRight:
    window.actionPressed(OrderInput)
  of KeyEscape:
    window.actionPressed(MenuInput)
  else:
    window.buttonPressed[button]

proc menuShortcut*(): string =
  ## Names the configured menu binding in gameplay status text.
  MenuInput.actionLabel()
