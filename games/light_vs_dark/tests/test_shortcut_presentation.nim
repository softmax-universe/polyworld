import std/unittest
import ../[content, shortcuts, shortcutpresentation]
suite "LvD single command-key presentation":
  test "all live labels show one configured key":
    for action in ShortcutAction:
      var bindings = DefaultShortcuts
      check bindings.commandKeyLabel(action) == bindings[action]
      check bindings.shortcutRouteLabel(action) == bindings[action]
      check bindings.setShortcut(action, "7") == ""
      check bindings.commandKeyLabel(action) == "7"
      check decodeShortcuts(encodeShortcuts(bindings)).shortcutRouteLabel(action) == "7"
  test "conflicts leave labels unchanged":
    var bindings = DefaultShortcuts
    check bindings.setShortcut(BuildChurchShortcut, "F").len > 0
    check bindings.commandKeyLabel(BuildChurchShortcut) == "C"
  test "farm and peon hints have no prefixes":
    check DefaultShortcuts.shortcutRouteLabel(FarmBuilding.shortcutAction) == "F"
    check DefaultShortcuts.shortcutRouteLabel(PeonUnit.shortcutAction) == "P"
    check DefaultShortcuts.commandKeyLabel(SummonUnit.shortcutAction) == "E"
