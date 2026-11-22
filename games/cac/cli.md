# Command-line options

Cards and Casters uses Polyworld's shared argument parser in both native and
headless builds. Values accept `--flag VALUE`, `--flag=VALUE`, and
`--flag:VALUE`. `--help` lists the options supported by that build.

```sh
./cac --player 2 --bot players/archer.bas --name Ada
./cac --bot players/mage.bas:4 --seed 7 --record output/match.replay
./cac --replay output/match.replay --play false --speed 3
./build/cac-headless --bots players/warrior.bas:3 --ticks 500 --record output/match.replay
```

`--bot PATH[:N]` adds N seats in order, skipping the one-based human slot from
`--player [N]`. `--bots` is an identical alias. A bare `--player` selects slot
1. `--name TEXT` sets the display name; it does not select a slot. When bot
programs are supplied, they must fill every nonhuman seat exactly. If
`--players N` is omitted, the explicit roster determines the seat count.
Without bot arguments, the native menus and direct launch use bundled bots.

The CaC-specific `--deck PATH` runs a bot script's setup to choose the human's
class and deck. It requires `--player`. It replaces the old overloaded
`--human PATH` option and uses a direct launch. The menu provides its own deck
selection, so `--menu` cannot be combined with `--deck`.

`--replay PATH` loads a recording and excludes live bot, human, seed, duration,
and recording-output arguments. `--record PATH` writes the live match to that
exact path on completion or exit. Parent directories are created. Paths are
relative to the launch directory, including when asset setup changes the
working directory. Setting a record destination alone leaves the main menu
open; it applies to the subsequent live match.

`--play BOOL` chooses the initial pause state and `--speed N` selects a positive
integer speed for local gameplay and replay playback. Online clients follow
the authoritative room timing and reject local duration caps. `--server` and
`--room` configure the multiplayer menu and cannot be combined with direct
bot, human, or replay inputs. `--windowSize`, `--vsync`, `--mute`, `--unmute`,
`--screenshot`, and `--frames` use the shared graphical behavior.

One CaC tick is one accepted gameplay action. Native `--ticks N` limits that
count; `--seconds N` and `--minutes N` convert using Polyworld's 24-tick time
scale. The headless runner supports `--headless-tick-rate N` to pace those
actions in wall-clock time; zero runs without pacing. Its `--players N`
validates the supplied roster, and `--classes archer,mage,...` overrides each
seat's selected class and deck with that class's precon.

Unsupported options fail explicitly. CaC bots do not implement the shared LLM
request modes. Headless builds reject graphical controls and menu connection
settings. Browser builds do not offer replay output or local duration caps.
