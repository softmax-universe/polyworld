import std/unittest
import windy
import polyworld/inputs
import ../games/light_vs_dark/lobbies

suite "LvD Stop binding migration":
  test "S stops and X is free for fixed cancel":
    check LvdControlProfile.defaults[StopInput] == [KeyS, ButtonUnknown]
    check LvdControlProfile.defaults[PanInput] == [MouseMiddle, ButtonUnknown]
    check LvdControlProfile.defaults[ShadingInput] == [KeyF5, ButtonUnknown]

  test "exact old defaults upgrade independently and idempotently":
    var bindings = LvdControlProfile.defaults
    bindings[StopInput] = [KeyX, ButtonUnknown]
    bindings[PanInput] = [MouseMiddle, KeyS]
    bindings[CameraInput] = [KeyJ, KeyK]
    bindings.migrateLvdBindings()
    check bindings[StopInput] == [KeyS, ButtonUnknown]
    check bindings[PanInput] == [MouseMiddle, ButtonUnknown]
    check bindings[CameraInput] == [KeyJ, KeyK]
    let once = bindings
    bindings.migrateLvdBindings()
    check bindings == once

  test "custom stop and pan bindings survive migration":
    var bindings = LvdControlProfile.defaults
    bindings[StopInput] = [KeyH, KeyJ]
    bindings[PanInput] = [KeyS, KeyK]
    let custom = bindings
    bindings.migrateLvdBindings()
    check bindings == custom

  test "previous S and X defaults migrate and X cannot remain a global action":
    var bindings = LvdControlProfile.defaults
    bindings[StopInput] = [KeyS, KeyX]
    bindings[CameraInput] = [KeyX, KeyK]
    bindings[ShadingInput] = [KeyT, ButtonUnknown]
    bindings.migrateLvdBindings()
    check bindings[StopInput] == [KeyS, ButtonUnknown]
    check bindings[CameraInput] == [ButtonUnknown, KeyK]
    check bindings[ShadingInput] == [KeyF5, ButtonUnknown]
    for action in InputAction:
      check KeyX notin bindings[action]
