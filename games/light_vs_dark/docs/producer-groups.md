# Selected producer groups

- Shift-click toggles buildings; drag-box selects owned visible units and buildings.
- Double-clicking a building selects owned buildings of its type whose projected centres are on screen and currently visible. The second release cannot collapse the group.
- The selection grid includes clickable building portraits.
- Units tab and keyboard training use `controls.queueSelectedTrain`. Readiness is the union of selected eligible producers, never unrelated global producers or only the primary portrait.
- Choose the smallest `queueLength + pending` load (queue slot zero is active). Equal loads rotate after the last chosen producer in stable selection order. HUD badges aggregate accepted and pending selected production.
- Reserve gold, wood, food and queue slots before flush and while network commands are in flight. Reservations live outside simulation/hash state and survive transport flush and selection changes. `multiplayer.applyPacket` retires matching reservations only at the authoritative decision callback, including rejected actions.
- Right-click movement rallies all eligible selected producers, including mixed unit/building movement selections. A-right and blueprint placement retain their separate existing routes.

## Native verification

From the integration checkout with `POLYWORLD_DEPS=/Users/me/p`:

- `nim c -r -d:headless games/light_vs_dark/tests/test_group_production.nim`
- `nim c -r -d:headless games/light_vs_dark/tests/test_group_production_network.nim`
- `nim c -f -r games/light_vs_dark/tests/test_attack_input.nim`
- `nim c -f -r games/light_vs_dark/tests/test_build_placement_graphics.nim`
- Compile `test_group_production_ui.nim` here, then execute its output from a directory whose sibling is `polyworld_art` (the existing `/Users/me/p/polyworld` works). This hidden native HUD fixture exercises actual HUD clicks and production keyboard callbacks, not OS event delivery.
- Both headless group tests are imported by `tests/tests.nim`. The network fixture uses the real binary Relay/RoomClient adapter in process, not a running server: eight accepted trains, six rallies, 96 peer-hash ticks and both serialized replay comparisons.

No browser, WASM, server start, or deployment is required by these tests.
