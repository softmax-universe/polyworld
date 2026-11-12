# Light vs Dark menus and multiplayer

Run `nim c -r games/light_vs_dark/lvd.nim` from the Polyworld root to open the home menu. Explicit `--bot` or `--replay` arguments retain direct match/replay startup; headless builds retain the command-line runner.

## Shared versus game-specific code

- `src/polyworld/homes.nim`: centered home layout, keyboard navigation, atlas packing, and backdrop drawing.
- `src/polyworld/lobbies.nim`: common lobby layout, buttons, panels, fonts, inputs, seat picker, and readiness indicators.
- `src/polyworld/menus.nim`: persisted display/sound/network preferences and configurable control-binding profiles.
- `src/polyworld/connections.nim`, `rooms.nim`, `roomclients.nim`: unchanged universal transport and room protocol.
- `games/light_vs_dark`: independent-player roster, map preview/settings, diplomacy, controls profile, match lifecycle, and game-owned packet/replay payloads.
- GotA retains its teams, draft, arena presets, map previews, and game commands in its own directory.

Menu art lives in the sibling art checkout at `polyworld_art/themes/lvd/menu/`. The background is a real LvD scene capture; the existing LvD logo is reused, with amethyst/gold variants of the original menu buttons.

## Setup

Battle Setup presents compact player cards stacked in two columns, with vertical scrolling for larger rosters and no Previous/Next paging. Add/remove players, choose human or local BASIC/ZIP policies, fill empty slots, and configure the map and diplomacy. A participant controls at most one human player but can own multiple private bot seats.

Multiplayer connects to the **same universal relay as GotA**. Game identity filters room listings; game commands remain opaque to the server. Create a public/private room, assign seats, ready up, then start. Policies stay on their owners' machines. Changing configuration invalidates readiness.

Roster capacity is 64, subject to a combined map/roster budget. Validation uses the generator's actual seeded growth before allocating cells: at most 262,144 map cells and 8,388,608 player×map cells. Large configurations report a validation error rather than exhausting browser memory.

Sound preferences are shared with GotA; actual audio playback remains unimplemented, as indicated in the Sound tab.

## Playing

Default matches are **FFA**: other players are enemies immediately, independent of Light/Dark art or color. Military units automatically acquire visible enemies while idle; attack-move acquires enemies along the route, and explicit attacks chase visible targets into range. Ordinary move does not acquire targets while moving. The explicit `diplomacySettings.neutralStart: true` config option retains neutral-start diplomacy; peace/alliance mechanics are not removed.

Peons are workers, but not noncombatants: explicit attack and attack-move work. Idle peons deliberately do not autoattack. Their attack has only 1 basic damage and no piercing, so armor can reduce it to **zero** (including against a Swordsman); use military units against armored opponents.

Normal human gameplay has no bottom time scrubber; playback controls remain for replays and spectator viewing. Use Esc for the match menu, pause controls, and Return to Home/Lobby—no persistent return button sits on the battlefield. Finished matches automatically display the winner/outcome headline above the Tab-style statistics and history charts.

Select workers, then right-click a tree's visible canopy or trunk to harvest wood. Tree picking uses the rendered tree rather than the empty ground behind its canopy. If another worker blocks the chopping position, workers seek a reachable alternative approach or another explored tree, retaining cargo and queued orders. Opposing peons deterministically yield sideways when there is safe passing space, then resume their original work; they never overlap to force through a one-cell corridor.

The selected portrait worker's cargo reads **WOOD n**, **GOLD n**, or **CARGO: EMPTY**. Available building portraits are full color with a bright gold edge; unavailable ones are strongly faded. Training buttons use the player's faction-color background and show the selected producer's per-type queue count at bottom-right, including active training; zero counts are hidden.

In a network match, F1 opens shared debug tools. The Network tab includes traffic, RTT/jitter/tick graphs, lag/jitter simulation, and live tick-smoothing controls.

Hover over Build or Units buttons for half a second to see their purpose, costs, requirements, timings, and relevant stats. Tooltips stay inside the viewport.

- **Double-click a unit:** select all available owned units of that type; Shift adds them to the selection.
- **S:** stop selected units and clear queued orders (X remains a cancel alias).
- **Right-click:** contextual move, group attack, harvest, or resume an owned unfinished building.
- **Hold A with right-click:** attack-capable selected units target a clicked hostile unit, or attack-move to a world/minimap ground destination.
- **Right-drag a curve:** preview individual formation positions; release to move each selected unit to its position.
- **Hold A with right-drag:** attack-move formation, shown in red instead of green.
- **Shift when issuing/releasing an order:** append it after the current order; ordinary replacement orders clear queued waypoints.
- **Escape:** cancel an armed command or formation drag before opening the match menu.

Construction requires the assigned living owned peon beside or inside that exact site. A new footprint may contain its assigned peon, but not another friendly or enemy unit, terrain obstacle, tree, or building. The inside builder works in place and exits onto free legal perimeter ground on completion or interruption; a completely blocked exit waits rather than pushing the worker into obstacles. Retargeting, stopping, displacement out of range, or losing the worker pauses the old site; right-click its unfinished shell with another worker to resume without paying again.

Per-unit queues hold up to 32 pending orders. Queued harvest hands off after its next resource deposit; invalid future targets are skipped. The current semantics use LvD gameplay version 28 / network protocol 2 / replay format 6, so all multiplayer clients must reload the current build; older gameplay recordings (including version 27) require their matching archived client.

`?server=wss://HOST/ws` chooses the relay without skipping Home. A `room` query additionally opens multiplayer and joins the invitation. Browser pages served over HTTPS require `wss://`.

## Contextual action keys

There are no Build/Units/Upgrades tabs or menu prefixes. Select a peon for build actions, a Town Hall for Peon training, a Barracks for its military units, or research buildings for their upgrades. Mixed selected producers show their combined actions; training chooses the least-loaded eligible producer including pending commands. Unavailable relevant actions remain faded with prerequisite/cost tooltips.

Each action uses one configured key:

| Build | Key | Train | Key |
|---|---|---|---|
| Town Hall | H | Peon | P |
| Farm | F | Swordsman | S |
| Barracks | B | Archer | A |
| Lumber Mill | L | Mage | M |
| Tower | T | Knight | K |
| Stables | U | Catapult | C |
| Church | C | Cleric | H |
| Blacksmith | K | Elemental | E |

Research: **Q** Keenflight Arrows, **W** Tempered Edges, **R** Runed Plating, **V** Windrunner Training. **X** cancels selected owned unfinished sites and refunds their full paid gold/wood; complete buildings are never demolished by this action. **S** remains Stop for unit selection, so Stables uses **U**. With attack-capable units selected, the configured Attack Move modifier outranks Archer on **A**, but affects only right-click/right-drag orders. Left-click and double-click selection are unaffected. Pointer travel below 10 screen pixels is a click; 10 or more is box selection, independent of HUD scale.

Edit keys under **Settings → Controls → Contextual Action Keys**. Each edit captures one key and saves automatically. Worker and producer palettes may reuse keys; overlapping producer actions cannot. Legacy saved pairs migrate to their second key. On same-palette collisions (including worker S versus Stop), catalog order wins and the conflicting action gets its unclaimed default or first free letter/digit; settings explicitly reports the reassignment. **Reset action keys** restores defaults. Held keys never repeat commands, and chat/menu input suppresses gameplay.

Losing the last Town Hall starts a 15-second simulation-tick defeat grace period, shown locally as **No Town Hall — defeat in Ns**. An owned living Town Hall construction site immediately cancels the warning and deadline. Spectators do not see another player's countdown.

Elementals wear a grand laurel crown and their bodies use the owning faction's color.

## Browser build

```sh
PATH=/opt/homebrew/bin:$PATH EM_PYTHON=/opt/homebrew/bin/python3 \
  nim c -d:emscripten games/light_vs_dark/lvd.nim
python3 -m http.server 9914 --bind 127.0.0.1 \
  --directory games/light_vs_dark/emscripten
```

Open `http://127.0.0.1:9914/lvd.html?server=ws%3A%2F%2F127.0.0.1%3A9911%2Fws` when the existing relay listens on 9911. Do not run concurrent builds targeting the same `emscripten` directory. Native parallel builds should use separate `--nimcache` paths.

## Regression checks

```sh
nim r games/light_vs_dark/tests/tests.nim
nim r games/light_vs_dark/tests/test_menu_ui.nim
nim r games/light_vs_dark/tests/test_graphics_lifecycle.nim
nim r games/light_vs_dark/tests/test_startup_camera.nim
nim r games/light_vs_dark/tests/test_menu_assets.nim
nim r games/light_vs_dark/tests/test_roster_cards.nim
nim r games/light_vs_dark/tests/test_gameplay_transport.nim
nim r games/light_vs_dark/tests/test_tooltips.nim
nim r games/light_vs_dark/tests/test_tree_orders.nim
nim r games/light_vs_dark/tests/test_order_queue.nim
nim r games/light_vs_dark/tests/test_order_queue_network.nim
nim r -d:headless games/light_vs_dark/tests/test_builder_placement_network.nim
nim r games/light_vs_dark/tests/test_ffa_combat.nim
nim r games/light_vs_dark/tests/test_two_human_combat.nim
# Optional real-socket check against the existing relay; creates a private QA room:
nim r -d:liveHumanCombat games/light_vs_dark/tests/test_two_human_combat.nim
nim r tests/test_attack_orders.nim
nim r tests/test_line_moves.nim
nim r -d:headless tests/test_worker_build.nim
nim r tests/test_shared_homes.nim
nim r tests/test_shared_lobbies.nim
nim r tests/test_control_profiles.nim
python3 tests/test_web_game_packaging.py
```

Graphics/menu-asset checks need the normal dependencies and art checkout. Browser acceptance should exercise home → setup → local match → exit, settings, relay connection, room creation/join, readiness, and authoritative tick advancement.
