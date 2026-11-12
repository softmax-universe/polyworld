# Attack-move siege and ranged retaliation vision

Gameplay version 35 (old tapes require their archived client).

- Automatic acquisition ranks all currently visible hostile units and buildings together by king-move tile distance. Buildings use their nearest footprint tile. Equal distances use the global entity ID; no unit-category preference remains. Dead, hidden, neutral and allied entities are not candidates.
- Bomber is the display name of `CatapultUnit`. Its existing range 8 stays two tiles beyond Tower range 6. Sight increases from 8 to 10, above Tower sight 9. Combat still stops in range and resumes the original attack-move destination after destruction.
- An actual ranged shot (`rangeTiles > 1`) or Tower shot reveals its firing location to the target owner. Misses also reveal; acquisition, chase and cooldown alone do not. Melee attacks do not reveal.
- `World.rangedReveals` is authoritative, hashed, snapshot-copied state. Each `(sourceId, recipient)` has the last shot origin, full source footprint and an absolute `expiresTick`. Repeated shots replace that entry and refresh it to `world.tick + RangedRevealTicks` (48 ticks / two seconds). Expiration occurs exactly at that tick.
- The source footprint plus a two-tile king-distance border (`RangedRevealRadius`) is currently visible through ordinary `visible`, `unitVisible` and `buildingVisible`. This small local flash patch bypasses occlusion. It shares with the recipient's current vision allies, not unrelated players; alliance changes take effect while the flash remains live. Exploration survives expiration but current sight does not. The patch stays at the shot position, rather than tracking a moving attacker.
- Rendering must use those normal visibility predicates; it must not mutate the world or maintain its own reveal timer. Projectile/effect rendering is a separate integration responsibility.

## Native evidence

`test_siege.nim` exercises real registered buildings, ordinary attack-move, two sequential full-health tower kills without any Bomber HP loss, continued movement, closest/tie/eligibility behavior, near/far/hidden tower shots, every faction's ranged roster, misses, refresh, exact expiration, allied/unrelated vision and snapshot/hash isolation.

`test_siege_network.nim` uses two human control queues and the real in-process binary relay (no socket server). Both accepted commands are authoritative, no input mutates the pre-packet world, both peers agree over 1800 ticks, and both serialized tapes replay every hash from an explicit combat fixture snapshot. It is not a claim that the fixture's custom initial units/buildings are serialized in the normal action-only tape, nor browser/OS-input evidence.

Run from repository root with `POLYWORLD_DEPS=/Users/me/p`, an isolated `--nimcache`, and `nim c -r -d:headless games/light_vs_dark/tests/tests.nim`. No graphics, browser, WASM, server or deployment changes are included here.
