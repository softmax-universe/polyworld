# Game command lines

Polyworld games share one parser for options that have the same meaning.
Run a game's `--help` for its supported options and game-specific setup.
An unsupported option produces an error rather than being silently ignored.

All valued options accept the same three forms:

```sh
./game --replay "replays/my match.replay"
./game --replay="replays/my match.replay"
./game --replay:"replays/my match.replay"
```

Paths are relative to the directory where the game was launched, including
clients that change their working directory to find assets. Quote paths or
names containing spaces. Repeated scalar options use their last value;
`--player` may appear only once and bot options accumulate.

| Option | Shared meaning |
| --- | --- |
| `--record PATH` | Save the current match's replay to this file, creating missing parent directories. |
| `--replay PATH` | Load and play this recording instead of running bots. |
| `--bot PATH[:N]` | Add N instances of a bot program, defaulting to one. Repeat to use different programs. |
| `--bots PATH[:N]` | Identical alias of `--bot`, including repetition and counts. |
| `--player [N]` | Reserve one human-controlled slot, numbered from one. Bare `--player` selects slot one. |
| `--name TEXT` | Set the local human's display name, or the multiplayer identity where supported. |
| `--seed N` | Set the new match's signed 32-bit random seed. |
| `--ticks N` | Set the new match's maximum simulation ticks. |
| `--seconds N`, `--minutes N` | Set the new match's duration using that game's simulation tick rate. |
| `--play [BOOL]` | Start local simulation or replay playback playing or paused; default true. |
| `--speed N` | Use this positive integer local simulation or playback multiplier; default one. |
| `--windowSize WIDTHxHEIGHT` | Set the graphical window dimensions. |
| `--vsync [BOOL]` | Enable or disable display synchronization; default true. |
| `--mute [BOOL]` | Override saved audio settings for this launch; bare `--mute` disables sound. |
| `--unmute [BOOL]` | Enable launch audio; false mutes it. This does not enable microphone input. |
| `--verbose [BOOL]` | Enable diagnostic output; default false. |
| `--headless-tick-rate N` | Pace headless simulation at N ticks per wall-clock second; zero is unlimited. |
| `--llm-mode async\|barrier` | Advance asynchronously or wait for the current batch of bot LLM requests, where supported. |
| `--server URL` | Select the multiplayer relay. |
| `--room CODE` | Select a multiplayer room. `--join CODE` is an identical alias. |
| `--screenshot PATH` | Capture one native rendered frame, save it, and exit. |
| `--benchmark PATH` | Run a hidden native frame-time benchmark and write a JSON report. |
| `--frames N` | Select the screenshot frame or the number of measured benchmark frames. Defaults to 30. |
| `--warmup N` | Render this many frames before starting the benchmark clock. Defaults to 30 and must be positive. |

Booleans accept `true/false`, `on/off`, `yes/no`, and `1/0`. Explicit command-line
choices take precedence over saved window and audio preferences.

## Bots and human slots

An explicit bot roster fills every nonhuman slot exactly. Bot programs expand
in argument order and skip the reserved human slot. There is no implicit cycling
or padding of an explicitly supplied roster. Games can offer bundled bots when
no bot programs are specified, and their fixed or configurable roster sizes
remain game-specific.

For a four-player game, these commands select the same roster:

```sh
./game --player 2 --bot players/base.bas:3
./game --player=2 --bots=players/base.bas:3
./game --player:2 --bot:players/base.bas:3
```

Two different programs can fill the three bot slots:

```sh
./game --player 2 --name "Local player" \
  --bot players/first.bas --bot players/second.bas:2
```

Use `--name` for a display name. `--player Alice` is an error. A headless build
cannot host a human controller.

## Recording and playback

`--record` selects a destination. In a client that opens a menu, the choice
persists into the match started from that menu; the flag alone does not select
a game setup. `--bot`, `--player`, or a game's explicit start option can launch
a configured match directly. Explicit replay files remain separate from optional
automatic desktop replay-library saving.

`--replay` cannot be combined with bots, a human controller, recording, an
explicit seed, or explicit duration flags. A replay carries its original setup;
game-specific seek options control which recorded position to display. Replay
format/version validation is unchanged, with no conversion of older recordings.

Local playback speed does not change simulation rules or a multiplayer server's
tick rate. A live network controller follows the authoritative match clock.
Games report when that prevents a requested pause or playback speed. GotA's
draft remains interactive before its battle simulation starts; `--play=false`
pauses the battle when the draft finishes.

## Game-specific capabilities

GotA, Light vs Dark, Cards and Casters, Call to Adventure, Heartleaf, Crewrift,
Galcon, Pudge Wars, Generals, and Mini Diplomacy use the shared replay and bot
vocabulary where their clients support those capabilities. Monster has no BASIC
roster or action-replay implementation and rejects those options. Its microphone
conversation mode is selected explicitly with `--conversation`.

Map generation, heroes, decks, tutorials, roles, calendar dates, and coaching
controls remain game-specific. Turn-based clients need not support a duration
in seconds. Graphical transport and window flags require a graphical build;
LLM barrier mode requires a client that implements LLM requests.

See [screenshot capture](screenshots.md) for capture behavior and
[testing](testing.md) for the unit-only CI policy. Parser, roster, and path
regressions are unit tests; CI does not open windows or simulate full games.
