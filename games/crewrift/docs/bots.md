# Crewrift BASIC bots

Crewrift uses one Bassy BASIC runtime for each bot-controlled player. The
default policy lives in `games/crewrift/players/base.bas` and is embedded in the
executable, so normal startup does not need a separate bot file. It handles
crew assignments, imposter movement, reports, meeting discussion, and voting.

Run these commands from the repository root:

```sh
# Play the first slot with the default BASIC bots.
nim r games/crewrift/crewrift.nim

# Watch an eight-player match with the default BASIC bots.
nim r games/crewrift/crewrift.nim --spectate

# Give two bot slots a custom policy; other bots keep the default policy.
nim r games/crewrift/crewrift.nim --bot my-bot.bas:2

# Run a headless match with eight instances of the same policy.
nim r -d:headless games/crewrift/crewrift.nim --bot my-bot.bas:8

# Record and verify a headless match.
nim r -d:headless games/crewrift/crewrift.nim --record:tmp/crew.json
nim r -d:headless games/crewrift/crewrift.nim --replay:tmp/crew.json
```

`--bot PATH[:N]`, `--bot:PATH[:N]`, and `--bot=PATH[:N]` are equivalent. Repeat
the flag to mix policies. Files fill bot slots in order, skipping the human
slot selected by `--player:N`. The roster size still comes from `--players:N`;
unspecified bot slots use `base.bas`. Crewrift accepts plain BASIC source,
including files without a `.bas` extension. ZIP policy packages are not
supported.

Each bot has independent persistent BASIC globals and arrays. A decision
restarts the program from its first statement while preserving that memory.
Source, memory, instructions, host work, and output are bounded. A compile
error prevents the match from starting. A runtime error stops the affected
bot and reports its error; other players continue.

Bot commands produce the same player inputs and ordered meeting actions used
by human controls and replay playback. The host limits observations to the
calling player's knowledge. Navigation remains a shared game service; policy
decisions live in the BASIC program.

Live matches cache their source after loading it. Seeking backward rebuilds
bot memory from that cached source while applying recorded actions, allowing
the match to continue deterministically. Saved replay playback reads only the
recorded setup and actions: it does not read or compile bot files, and ignores
any supplied bot paths.

## Values available to a decision

Player slots, task IDs, assignment indices, body indices, and chat indices are
zero-based. Coordinates are original map pixels; eight pixels equal one
Polyworld tile. Booleans are `0` or `1`. Unknown or invalid numeric observations
return `-1` unless a function below specifies otherwise; string observations
return an empty string.

| Value | Meaning |
| --- | --- |
| `selfSlot` | Calling player's roster index. |
| `worldTick`, `tickRate` | Simulation tick and ticks per second, including reveal and meeting phases. |
| `phase` | `0` lobby, `1` playing, `2` voting, `3` vote result, `4` game over, `5` role reveal, `6` game info, `7` meeting call. |
| `myX`, `myY`, `myAlive` | Calling player's position and life state. |
| `myRole` | `0` crewmate or `1` imposter. |
| `myKillCooldown` | Remaining kill cooldown in ticks. |
| `playerTotal`, `taskTotal` | Public roster and station counts. |
| `assignmentTotal` | Number of the calling player's assigned tasks. |
| `bodyTotal` | Number of bodies visible in this playing-phase decision. |
| `chatTotal` | Current meeting feed length; zero outside voting. |
| `meetingCaller` | Reporting or button-calling player; `-1` outside voting or when unknown. |
| `meetingKind` | `0` unknown, `1` emergency button, `2` reported body; zero outside voting. |
| `voteTimer`, `voteDuration` | Remaining and configured meeting ticks. |
| `voteFinalize` | Remaining finalization ticks after everyone votes. |
| `myVote` | `-1` before voting, `-2` after skipping, otherwise the chosen player. |
| `myCursor` | Current vote selection; `playerTotal` selects skip. |
| `chatCooldown`, `myLastChatTick` | Required chat interval and last accepted message tick. |
| `killRange`, `reportRange` | Configured interaction distances in pixels. |
| `routeStuck`, `routeLength` | Consecutive stationary playing ticks and number of points in the cached route. |

Use meeting values during `phase = 2`. Both `myVote` and `myCursor` are `-1`
outside voting. Body indices describe only the current visible list; use
`bodyId` when remembering a body across decisions.

## Observations

| Function | Result |
| --- | --- |
| `playerVisible(slot)` | Whether this player's position and life state are observable. Invalid slots return zero. |
| `playerX(slot)`, `playerY(slot)`, `playerAlive(slot)` | Observed coordinates or life state; `-1` when hidden. |
| `playerRole(slot)` | Own role, or an imposter teammate's role; otherwise `-1`. |
| `playerName$(slot)` | Public color name, such as `"red"`; not the bot filename. |
| `assignedTask(index)` | Task ID from the calling player's assignments. |
| `taskX(task)`, `taskY(task)` | A reachable interaction point at a public station. |
| `taskDone(task)` | Completion state for an assigned task; `-1` for other tasks. |
| `atTask(task)` | Whether the player is inside the station's interaction area; zero for invalid tasks. |
| `bodyId(index)` | Stable identity of the visible body's player. |
| `bodyX(index)`, `bodyY(index)` | Visible body's location. |
| `bodyAge(index)` | Ticks since the visible player died. |
| `bodyRoom$(index)` | Room containing a visible body. |
| `ownRoom$()` | Calling player's room, or `"the corridor"`. |
| `meetingBodyName$()`, `meetingBodyRoom$()` | Reported player's color and body location during a body-report meeting. |
| `chatSender(index)` | Roster slot that sent a message in the current meeting feed. |
| `chatText$(index)` | Message text in the current meeting feed. |
| `randomInt(bound)` | Private deterministic random value from zero through `bound - 1`; zero for nonpositive bounds. |

During play, living players see nearby actors through open corridors. Other
players' ghosts are not observable. A ghost can see living actors across the
map. Meetings expose the public roster. Role access remains restricted even
when a player is visible; there is no query for a corpse's killer or another
player's assignments. Each bot uses Polyworld's portable random generator,
seeded independently from the match seed and slot. It does not advance the
simulation's generator.

The meeting feed retains at most six messages. It is a view of the visible
conversation, not an unread-message queue. Direct messages, team messages,
mailboxes, and LLM calls are not part of this host API.

## Commands

Commands queue inputs for the current tick. They do not directly modify the
simulation while a policy runs. A command generally returns `1` when queued
and `0` when refused; gameplay rules still decide the resulting interaction.
All pending commands are discarded if that decision raises a BASIC error.

| Function | Behavior |
| --- | --- |
| `setInput(mask)` | Replaces this tick's complete button state. Accepts integers from `0` through `127`. |
| `pressUse()` | Alternates the use button relative to the previous tick, producing a rising edge when possible. Returns the resulting button state. |
| `holdUse()` | Holds use for this tick, allowing continuous task work. |
| `moveTo(x, y)` | Sets movement buttons toward a walkable map point using a cached route. Call each tick to keep moving. |
| `voteFor(slot)` | Selects a living player and generates a vote button edge during voting. Use `playerTotal` to skip; dead targets, repeated votes, and unavailable rising edges return zero. |
| `sendChat(-2, text$)` | Queues one public meeting message from a living player, respecting cooldown and length. Other destinations are refused. |

The input mask uses `1` up, `2` down, `4` left, `8` right, `16` select,
`32` use/attack, and `64` vent. Add flags to combine buttons. Calling
`setInput(0)` clears them all. `moveTo` changes only movement buttons;
`pressUse` and `holdUse` change only use. The host permits at most one fresh
route search per decision; a request requiring another search returns zero.
Calls that follow the cached route still work. Prefer one movement destination
per decision so the host can retain that route.

Chat accepts at most 320 bytes and removes nonprintable/non-ASCII characters
using the normal game's chat rules. Empty messages are refused. Bot chat,
votes, and movement are recorded in the same ordered action stream as human
commands.

This minimal crewmate policy completes assignments and skips meeting votes:

```basic
if phase = 2 then
  if myAlive <> 0 and myVote = -1 then
    accepted = voteFor(playerTotal)
  end if
  stop
end if

if phase = 1 and myRole = 0 then
  for assignment = 0 to assignmentTotal - 1
    task = assignedTask(assignment)
    if taskDone(task) = 0 then
      if atTask(task) <> 0 then
        accepted = holdUse()
      else
        accepted = moveTo(taskX(task), taskY(task))
      end if
      stop
    end if
  next assignment
end if
```

The bundled `base.bas` adds evidence tracking, reports, imposter behavior,
and three rounds of meeting discussion before voting.

## Runtime limits

Each bot can use 128 KiB of source, 50,000 compiled instructions, 512 globals,
32 arrays with 4,096 total array elements, and 2 MiB of runtime memory.
Persistent strings have a 4 KiB individual limit and 128 KiB combined limit.
A decision receives 50,000 instructions and 100,000 work units, including
host-call costs, and can print at most 4 KiB across 64 events. Navigation calls
cost more than simple observations. These limits apply to both interpreted
and native execution.
