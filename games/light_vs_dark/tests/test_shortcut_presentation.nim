import std/unittest
import ../[content, shortcuts, shortcutpresentation]
suite "LvD single command-key presentation":
  test "all live labels show one configured key":
    for action in ShortcutAction:
      var bindings = DefaultShortcuts
      check bindings.commandKeyLabel(action) == bindings[action]
      check bindings.shortcutRouteLabel(action) == bindings[action]
      if action == CancelSiteShortcut:
        check bindings.setShortcut(action, "7").len > 0
        check bindings.commandKeyLabel(action) == "X"
      else:
        check bindings.setShortcut(action, "7") == ""
        check bindings.commandKeyLabel(action) == "7"
        check decodeShortcuts(encodeShortcuts(bindings)).shortcutRouteLabel(action) == "7"
  test "conflicts leave labels unchanged":
    var bindings = DefaultShortcuts
    check bindings.setShortcut(BuildChurchShortcut, "F").len > 0
    check bindings.commandKeyLabel(BuildChurchShortcut) == "V"
  test "farm and peon hints have no prefixes":
    check DefaultShortcuts.shortcutRouteLabel(FarmBuilding.shortcutAction) == "W"
    check DefaultShortcuts.shortcutRouteLabel(PeonUnit.shortcutAction) == "Q"
    check DefaultShortcuts.commandKeyLabel(SummonUnit.shortcutAction) == "T"
