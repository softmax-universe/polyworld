# LvD match clock and local warning

LvD owns its match duration in the game configuration. The relay distributes
that opaque configuration and checks hashes; it does not parse a duration,
track a countdown, or emit announcements.

Every client derives the three-minute warning from its applied simulation tick
and `maximumTicks`. Matches longer than three minutes produce one gold
`Match: 3 minutes remain` line when the displayed clock reaches
`maximumTicks - 180 * TickRate`. Players and spectators use the same path,
including offline games. A lagging client displays the warning only after its
own simulation reaches the threshold. Paused frames and reconnection do not
repeat it.

The warning is presentation state. It does not enter command packets, bot
mailboxes, gameplay hashes, or saved replay chat records. Replay and local
history viewers derive it from the same duration and displayed tick. Rewinding
before the threshold removes it; moving forward restores it in chronological
order with recorded chat. The bounded feed can age it out normally without
reintroducing it on every frame. A new game resets the warning.

Tab statistics show `Time remaining: MM:SS`, ceiling-rounded from nonnegative
`maximumTicks - world.tick`. Both the countdown and warning follow simulation
time, independently of network delivery time and wall-clock playback speed.

Verification:

- `test_match_clock.nim` checks independent client clocks, deduplication,
  replay ordering and seeks, new-game reset, short matches, early completion,
  transcript immutability and feed capacity without a relay.
- `test_match_clock_ui.nim` checks countdown boundaries and layout.
- `test_match_clock_render.nim` renders the production countdown at three
  viewport sizes and the local spectator warning feed.
