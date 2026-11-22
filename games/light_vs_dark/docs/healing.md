# Cleric automatic healing

Both factions use identical support balance; their existing attacks are unchanged.

| Setting | Default |
|---|---:|
| Starting / maximum mana | 100 |
| Heal | up to 8 HP, capped at missing HP |
| Mana per successful heal | 5 (even for a partial heal) |
| Heal cooldown | 1 second / 24 simulation ticks |
| Mana regeneration | 1 mana per second / 24 simulation ticks |
| Range | 4 tiles, king-move distance |

At each Cleric's authoritative unit update, mana regenerates and the independent
heal timer counts down. A ready Cleric automatically heals the eligible unit with
the lowest current/max HP ratio, breaking ties by lowest entity ID. Ratios use
integer cross-products, never floating point. Clerics resolve in the simulation's
ascending unit-ID order, so a later Cleric sees earlier healing and cannot overheal.

Eligible targets are living, damaged own or allied mobile units, including the
Cleric itself and living Elementals. Catapults are machines and cannot be healed.
Dead units, miners inside mines, enemies, neutral players, buildings, full-health
units and targets outside range are excluded. An ending alliance remains allied
until its diplomatic deadline, matching shared vision. Range uses authoritative
tiles, like combat, and does not add a separate line-of-sight requirement.

Healing is passive support: no chasing, target replacement, animation/order reset,
movement pause, or consuming a Shift successor. Weapon cooldown remains independent.
No valid target means no mana spent and no new cooldown. No mana means no heal;
regeneration can make a Cleric ready again on that tick. Regen progress resets at
full mana; there is no banked fractional mana while full. Death freezes support.

This gives a short-term 8 HP/second ceiling while mana lasts and a long-term
1.6 HP/second mana-limited rate. It is deliberately support, not unlimited repair.

All three per-unit fields (`mana`, `manaRegenTicks`, `healCooldown`) are hashed and
copied by clone/restore. All six tuning constants enter the content fingerprint.
No spell command or network payload is needed: peers and action-only replay apply
healing during the ordinary tick. **The parent integration must bump gameplay
version once alongside siege/reveal; this isolated patch leaves it unchanged.**

The primary selected Cleric has a labeled mana bar (also in multiselect, explicitly
not a group sum). Cleric training tooltips describe effective capped healing,
range, interval, mana cost/cap/regen and eligibility; Church/Temple text is updated.

## Verification

- `test_healing.nim`: actual healing, exact cooldown, exhaustion/recovery, mana cap,
  lowest ratio/ID, alliances, exclusions, self healing/death, clone/restore/hashes.
- `test_healing_network.nim`: real in-process binary relay, two humans' ordinary
  move + Shift submissions without immediate mutation, actual healing, both
  waypoints reached, same-tick peer hashes and serialized replay hashes. The
  fixture deliberately seeds Clerics and injuries before readiness; replay starts
  from that identical cloned fixture, not from an unmodified opening economy.
- `test_healing_hud.nim` and `test_tooltips.nim`: live labels and content/UI routes.
- Native rendering fixture: `test_healing_render.nim` (no browser/server required).
