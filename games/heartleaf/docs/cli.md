# Command-line options

Heartleaf uses the shared Polyworld launch options. Values accept separate,
equals, or colon forms, such as `--replay match.replay`,
`--replay=match.replay`, and `--replay:match.replay`.

```sh
./heartleaf --bot players/base.bas:9 --record saved/week.replay
./heartleaf --player 2 --bots players/base.bas:8
./heartleaf --replay saved/week.replay --play false --speed 4
```

`--bot PATH[:N]` and `--bots PATH[:N]` both add N instances of one program;
repeat either option for a mixed roster. `--player [N]` controls one human
slot, numbered 1 through 9, and defaults to slot 1 when N is omitted. Bots
fill the other slots in order. Human control requires a graphical build.

`--record PATH` saves this match. `--replay PATH` loads a recording and cannot
be combined with bots, a human controller, or another recording destination.
Replay and bot paths resolve from the launch directory. Recording creates
the destination's parent directories.

`--days N` sets the village calendar, from 1 to 28 days, and defaults to 7.
`--ticks N`, `--seconds N`, and `--minutes N` stop execution earlier without
changing that calendar. A partial saved replay keeps its original calendar
setup and plays only its recorded ticks. Duration options configure new
matches and cannot be combined with `--replay`.

`--headless-tick-rate N` paces a headless run in wall-clock ticks per second;
zero runs without pacing. `--verbose` prints progress every 30 simulated
seconds. The fixed villager names cannot be replaced with `--name`.
Heartleaf's BASIC bindings do not provide LLM requests, so `--llm-mode` is
unavailable. Audio flags are accepted for portable launch scripts; Heartleaf
has no audio output.

`--seek-tick N` or `--seek-event day:N:morning|dinner|scorecard` selects a
starting position. Only one seek target can be supplied. Pair it with
`--play false` to inspect that point without advancing further.
