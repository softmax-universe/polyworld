## Shared effect lifetimes and highlight colors.

import vmath
import ../core/core

const
  HoverGold* = vec4(1.0, 0.82, 0.42, 1.0)
  TargetRed* = vec4(1.0, 0.035, 0.065, 1.0)

type
  ActiveVfx* = object
    kind*: VfxKind
    target*: Choice
    position*: Vec3
    elapsed*, duration*: float32
    seed*: int
