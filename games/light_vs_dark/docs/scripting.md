# Bassy gameplay commands

Each script controls one player. Commands use the same ownership, resource,
terrain, diplomacy, and queue validators as human orders, and accepted commands
use the same replay path. Existing function names and argument counts remain
valid.

## Gameplay parity audit

| Human action | Script access |
|---|---|
| Move or attack-move | `moveUnit(id, x, y)`, `attackMove(id, x, y)` |
| Shift-queue movement or combat | `queueMove(id, x, y)`, `queueAttackMove(id, x, y)`, `queueAttack(id, target)` |
| Attack a target | `attackUnit(id, target)` |
| Harvest or deliver carried resources | `harvest(peon, target, isTree)`, `deposit(peon, depot)` |
| Queue harvesting or delivery | `queueHarvest(peon, target, isTree)`, `queueDeposit(peon, depot)` |
| Place, resume, or queue construction | `build(peon, kind, x, y)`, `queueBuild(peon, kind, x, y)` |
| Queue training | `train(building, unitKind)` already appends production |
| Ground, gold, or wood rally | `setRally(building, x, y)` already handles all three |
| Research the next upgrade tier | `research(building, researchKind)` |
| Curved formation movement, attack formation, or queued formation | `lineStart`, `lineAddUnit`, `lineAddPoint`, `lineMove` |
| Stop or cancel work | `cancel(id)` |
| Find idle workers | `nearestOwnIdle(0, x, y)` |
| Diplomacy and player communication | Existing diplomacy, `sendChat`, and mailbox functions |

Selection boxes, control groups, camera movement, menus, settings, and visual
previews are UI conveniences. Scripts work with entity IDs and query their own
orders directly; they do not need to move the human cursor or change selection.

## Orders and queues

Single-entity commands return `1` when accepted and `0` when refused. On a
networked client, `1` means submitted; the relay tick decides gameplay success.
A refused command preserves the current order and resources. IDs, kinds,
indices, building positions, and rally tiles require integers. `moveUnit`,
`attackMove`, their queued equivalents, and line points accept fractional tile coordinates;
integers name tile centers.

Ordinary unit commands replace the current assignment and its pending orders.
The `queue*` variants append to the same FIFO used by Shift-click, with at most
32 pending orders per unit. Appending beyond capacity is refused. A queued
harvesting successor waits until the current worker has deposited its load.

`harvest` and `queueHarvest` take a mine entity ID with `isTree = 0`, or a flat
tree tile index with `isTree = 1`. `deposit` and `queueDeposit` take a depot entity
ID. Town halls accept gold and wood; lumber mills accept wood only.

Queued buildings remain plans until activated. Resources are charged at that
point. Plans wait for resources or temporary unit occupancy, but permanently
invalid plans are skipped. They obey the same mine clearance, placement, and
technology rules as ordinary buildings. `build` can resume an existing owned
unfinished site at the same kind and origin.

`train` has a separate five-slot production queue, including the unit currently
training. `cancel(unit)` stops it and clears its pending orders. For buildings,
`cancel` cancels construction, active research, or the last queued trainee, as
applicable. It follows the same refund rules as the human command.

For example, with valid owned IDs and free building sites:

```basic
accepted = moveUnit(peon, 20, 20)
accepted = queueBuild(peon, 1, 24, 20)
accepted = queueBuild(peon, 3, 28, 20)
accepted = queueHarvest(peon, treeIndex, 1)
```

Do not resubmit this sequence every decision. Keep a script variable recording
that it was issued, or inspect the unit's queue before changing it.

## Resource rallies and research

Set a town hall's rally to a tile within a gold mine's footprint or to a standing
tree. Newly trained peons start gathering that resource. Wood rallies remember
the original tile and use nearby trees after it is depleted. Clicking cleared
ground replaces the assignment with a move rally. Non-peon units follow an
ordinary movement rally.

```basic
accepted = setRally(hall, treeIndex mod mapSize, treeIndex \ mapSize)
accepted = train(hall, 0)
accepted = train(hall, 0)
```

Research kinds are `0` Keenflight Arrows, `1` Tempered Edges, `2` Runed Plating,
and `3` Windrunner Training. `research(building, kind)` starts the next tier;
`canResearch(building, kind)` checks availability, and `researchLevel(kind)`
reads this player's completed tier.

## Placement and own-state queries

`canPlace(kind, x, y)` remains a strict footprint check. Use
`canPlaceFor(peon, kind, x, y)` for the same builder occupancy exception as the
human preview. `canQueueBuild(peon, kind, x, y)` additionally checks queue
capacity and overlapping friendly plans without requiring payment yet.
`canBuild(kind)` checks current affordability and technology;
`canTrain(building, unitKind)` checks production readiness.

| Query | Meaning |
|---|---|
| `queuedOrderCount(unit)` | Pending FIFO length, excluding the active order |
| `queuedOrderKind(unit, slot)` | Pending action kind; zero-based slot |
| `queuedOrderFirst/Second/Third(unit, slot)` | The action payload described below |
| `queuedOrderX/Y(unit, slot)` | Destination coordinates for point orders, including movement fractions |
| `carriedGold/Wood(unit)` | Current cargo, separated by resource |
| `trainingCount(building)` | Production slots, including active training |
| `trainingKind(building, slot)` | Unit kind in a zero-based production slot |
| `trainingTicks(building)` | Remaining ticks for the active trainee |
| `rallyKind(building)` | `0` move, `1` gold, `2` wood; `-1` if unset |
| `rallyX/Y(building)` | Rally tile |
| `researchKind(building)` | Active research category |
| `researchTicks(building)` | Remaining research ticks |

These queries only expose the caller's entities. Missing, foreign, or invalid
subjects return `0` for counts, ticks, cargo, and `queuedOrderKind`; kinds,
coordinates, and payload fields otherwise return `-1` when unavailable.
Observation readers (`obs*`) refer to the stable decision snapshot. Own-state
queries describe current applied state. Local commands can be inspected
immediately; network submissions appear after their authoritative relay tick.

| Queued action kind | First | Second | Third |
|---|---|---|---|
| `1` move, `8` attack-move | Destination tile X | Destination tile Y | Unused |
| `2` attack | Target entity ID | Unused | Unused |
| `3` harvest | Mine ID or tree tile index | `0` mine, `1` tree | Unused |
| `4` build | Building kind | Origin X | Origin Y |
| `11` deposit | Depot ID | Unused | Unused |

Use `queuedOrderX/Y` for movement coordinates to preserve fractional offsets.
The integer payload fields are useful when inspecting other command kinds.

## Line formations

`lineStart()` clears the script's staged group and stroke. `lineAddUnit(id)` adds
an eligible owned unit, and `lineAddPoint(x, y)` adds a stroke point. Staging is
bounded to 100 units and 2,048 points. `lineMove(attack, append)` plans with the
same row layout and reachable destinations as human right-drag, then submits
ordinary movement commands. Short lines gain more rows so the whole group fits.

`lineMove` returns the number of accepted unit commands. Use `attack = 1` for an
attack formation and `append = 1` to queue it. Peons use ordinary movement even
in an attack formation. It consumes the staged gesture, including on refusal;
start a new gesture before issuing another formation. The staging functions
return `1` on success and `0` on refusal. An invalid or excess stroke point
discards the gesture. Staging does not issue gameplay orders.

Planning costs 100,000 host work units, plus 400 per staged unit and one per map
tile. All eligible units must receive a planned destination before commands are
submitted; individual commands can still be refused, for example by full queues.

```basic
accepted = lineStart()
accepted = lineAddUnit(firstSoldier)
accepted = lineAddUnit(secondSoldier)
accepted = lineAddPoint(20, 20)
accepted = lineAddPoint(24, 21)
issued = lineMove(1, 1)
```
