import std/unittest
import ../orderfeedback
import polyworld/clickmarks
suite "LvD compact order markers":
  test "both semantic markers halve geometry without changing lifetime":
    let shared = clickMarkSettings()
    for attack in [false, true]:
      let mark = orderMarkSettings(attack)
      check mark.radius == shared.radius * 0.5'f32
      check mark.height == shared.height * 0.5'f32
      check mark.duration == shared.duration
      check mark.expandStart == shared.expandStart
      check mark.expandEnd == shared.expandEnd
