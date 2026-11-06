## Presentation-only woodcutting pose decisions.
import content, sim

proc woodAxeVisible*(unit: Unit): bool =
  ## Keep the tool for the complete wood assignment, including delivery.
  unit != nil and unit.kind == PeonUnit and unit.hp > 0 and
    unit.state in {UnitToTree, UnitChopping, UnitToDropWood, UnitDepositWood}

proc woodChopping*(unit: Unit): bool =
  unit.woodAxeVisible and unit.state == UnitChopping

proc woodAnimationClip*(unit: Unit, fallback: string): string =
  ## The worker's ordinary attack slot remains Interact for combat/building.
  if unit.woodChopping: "Sword_Attack" else: fallback

proc woodAnimationTime*(unit: Unit, fallback, alpha: float32): float32 =
  ## Restart each swing session without changing authoritative state.
  if unit.woodChopping:
    (float32(clamp(ChopTicks - unit.stateTicks, 0, ChopTicks)) +
      clamp(alpha, 0'f, 1'f)) / float32(TickRate)
  else:
    fallback
