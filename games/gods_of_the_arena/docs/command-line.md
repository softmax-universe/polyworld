# Command-line options

GotA uses the [shared game arguments](../../../docs/command-line.md) for bot
rosters, human slots, replay files, playback, and display settings. All shared
value flags accept separate, equals, and colon forms.

```sh
./gota --bots players/base.bas:10 --record replays/match.replay --seed 7
./gota --player 2 --bot players/base.bas:9 --name Alice
./gota --replay replays/match.replay --play false --speed 3
./gota --server ws://localhost:9911/ws --room ABC123 --name Alice
```

Paths are relative to the directory from which the game was launched. Bot paths
refer to actual files; the examples above assume a launch from the game folder.
`--player` selects a one-based human slot and defaults to slot one. Display names
use `--name`, including names made entirely of digits.

Direct local matches require ten total slots: ten bots, or nine bots and one
human. Explicit bot or human arguments launch the match directly. With no roster
or replay, the menu opens. Explicit `--server` or `--room` opens Multiplayer;
choose human and bot seats there.

`--record PATH` also applies to live matches started from the menus. The explicit
playback and window choices are preserved when entering a match. Saved fullscreen
preferences do not replace an explicit `--windowSize`.

Live multiplayer controllers follow the server clock. `--play` and `--speed`
control local games, file replays, and spectator playback, and do not change the
server's match speed.

`--headless-tick-rate` and `--llm-mode` belong to the headless runner. Graphical
builds reject those options, and headless builds reject graphical controls.

GotA's draft has deadlines and always advances. `--play false` pauses when the
battle begins; it does not stop draft deadlines. Duration flags count battle time,
with drafting separate from that limit. `--seed` controls the match randomness;
the game-specific `--map-seed` changes the arena.
