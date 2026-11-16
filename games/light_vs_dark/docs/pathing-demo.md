# Pathing demo

Run from the repository root:

```sh
nim r games/light_vs_dark/demo_pathing.nim
```

The demo runs 100 friendly units through the production simulation and standard
LvD renderer, including animated models, terrain, buildings, trees, selection,
path overlays, and the playback bar. It opens a 1600 by 1000 window with a camera
framed around the action. The fixtures use a flat map and preset movement orders.
Keys 1–5 switch scenes inside the loaded renderer without a loading splash.
Switching restarts the selected scene and keeps the current pause and speed settings.

| Key | Scenario |
| --- | --- |
| 1 | A compact group spreads into an open-field destination formation. |
| 2 | Two friendly groups move in opposite directions through each other. |
| 3 | Two friendly groups cross at right angles. |
| 4 | A group funnels through a two-tile gap between tree walls. |
| 5 | A group moves around an offset farm and town hall. |

Space pauses, R replays, S changes speed, P toggles the game's path overlay,
and F restores the scenario's camera framing. Scroll to zoom and use the normal
game camera controls to pan. The playback bar also supports seeking and stepping.
Scenarios loop after 1800 ticks. Escape opens the ordinary game menu; returning
home exits the demo. F12 saves the current game frame under
`output/lvd-pathing-demo/`.

Start on a particular scenario with `--scenario=5`; add `--pause` to start paused.
To save a deterministic frame and exit without opening a visible window:

```sh
nim r games/light_vs_dark/demo_pathing.nim --scenario=5 --ticks=400 --capture=output/lvd-pathing.png
```

Capture mode uses a hidden window and an offscreen color/depth framebuffer.

The scenario regression checks all five scenes for deterministic resets, valid
body footprints, visible obstacle data, and every unit reaching its destination:

```sh
nim r games/light_vs_dark/tests/test_pathing_scenarios.nim
```

Check scenario switching, asset reuse, and replay isolation in a hidden window:

```sh
nim r games/light_vs_dark/tests/test_pathing_switch_graphics.nim
```
