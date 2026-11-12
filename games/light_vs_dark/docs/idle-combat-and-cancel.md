# Idle combat and construction cancellation (gameplay 36)

## Idle combat

Uncommanded military already acquired targets in version 35. The regression was
version 34's direct Move latch surviving **successful arrival**, making ordinary
completed moves behave as permanent Hold. Successful Move now clears that latch;
the next tick starts any Shift successor before considering automatic combat.

- Idle non-Peon units acquire current-visible hostile units **or buildings** within
  their own sight radius, then use the existing terrain-safe chase and weapon range.
- First priority for idle defenders: a visible hostile unit actively attacking or
  chasing this unit. This includes retaliation against a nearby shooter after an
  actual hit. Among such threats choose nearest, then lowest entity ID.
- Otherwise choose nearest unit/building together, with global entity ID ties.
  Attack-move retains its version-35 nearest-unit/building selection, not the new
  idle defensive preference.
- Threat classification uses existing authoritative `targetId` and combat state;
  no new damage-history state, per-frame renderer state, or client-local timer.
  `damageEntity`'s `attacker` is a player ID, not an entity ID: it is not misused.
- Active Move and Shift paths are not diverted, including while taking damage.
  A successful final arrival resumes ordinary idle combat. Failed direct moves
  retain their hold latch so a failed explicit destination does not resume chase.
- Explicit `holdPosition` still suppresses idle acquisition. The existing **S/X
  Stop/Cancel** command is **not Hold**: it clears current and queued orders and
  releases the latch, after which military units can acquire again. There is no
  separate player-facing Hold command introduced here.
- Peons do not idle-autoattack. Passive Cleric healing is unchanged. Towers retain
  their fixed-footprint passive firing logic and never acquire movement.
- Death, diplomacy and lost current sight still end combat. Paths remain ordinary
  bounded terrain paths; visible but unreachable enemies do not grant wall passage.

## Cancel an unfinished building

Use the existing `queueCancel(player, buildingId)` control path. It produces
`ActionCancel`; the existing Game/World `applyCancel` validates and records it.
No new UI API or command opcode is needed.

For a living owned unfinished site, cancellation returns **all gold and wood paid
on creation**, even after partial progress. These costs are currently exactly
`BuildingTable[site.kind].gold/wood`; adopting a paused site never charges again.
The site becomes dying, its footprint is released, and all exact interior-builder
associations are retired immediately. An active builder becomes idle without
losing Shift successors; a former builder's replacement assignment is preserved.

An enemy, destroyed or already-cancelled site cannot be cancelled/refunded. A
completed building cannot be demolished/refunded by this route; its existing
training/research cancellation behavior is unchanged. Unit Stop is unchanged.

## Town Hall defeat countdown

A player with no living Town Hall (completed **or unfinished**) receives exactly
15 seconds of simulation ticks before defeat. Losing/cancelling the last hall
sets `Player.hallLossDeadline = world.tick + TownHallDefeatGraceTicks`; accepted
Town Hall construction resets it immediately. A paused unfinished shell counts,
while destroyed/cancelled shells do not. Multiple halls prevent a countdown until
the last disappears. After rebuilding and cancelling again, the full grace starts
over. Army size, Peons, other structures and connection status do not replace halls.

All expiries are processed before winner selection: one nondefeated survivor wins,
simultaneous elimination of everyone draws. Reaching the configured tick cap with
multiple survivors is a draw, not a score victory. Solo sandboxes still run to the
cap rather than winning on their first tick. Scores remain available for rankings.

UI hook: `world.hallDefeatTicksRemaining(player)` is read-only and returns zero
when inactive/invalid/defeated. Show `(ticks + TickRate - 1) div TickRate` seconds for
the local player. The authoritative deadline is hashed and cloned; pause does not
advance it. The warning renderer is owned by the UI integration writer.

## Verification

- `tests/test_idle_combat.nim`: actual unit/building chase and HP loss, completed
  Move, retaliation before a closer building, Shift under fire, nonhostile/hidden/
  outside-own-sight exclusion, explicit hold, Peons, deterministic ties and terrain.
- `tests/test_move_priority.nim`: no active-move diversion, completed-move combat,
  failed-move hold, hash/clone distinction.
- `tests/test_cancel_site.nim`: progressed full refunds, duplicate/enemy/dead/
  complete rejection, footprint/interior release and queued/new worker tasks.
- `tests/test_idle_combat_network.nim`: real in-process binary relay, two human
  control queues, no pre-authority mutation, 482 matching peer observations,
  exact accepted cancellation count, hall rebuild/cancel/exact defeat and both
  serialized fixture replay hash streams.
- `tests/test_hall_defeat.nim`: exact grace boundary, stopped unfinished rebuild,
  cancellation restart, multiple halls, simultaneous draw, hashed clone/restore,
  paused warning readback and score-independent capped draws.
- Full art-free `tests/tests.nim` passes, including siege, healing, economy,
  diplomacy, movement, queues, snapshots and network/replay checks. The healing
  movement fixture uses neutral diplomacy so it tests support and arrivals rather
  than newly restored post-arrival combat with a nearby enemy base.

Gameplay/replay version is 36; prior tapes require the matching archived client.
No browser, server launch, WASM build, commit or deployment was performed.
