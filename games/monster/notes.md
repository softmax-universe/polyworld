# Monster

A native Polyworld prototype about teaching one creature through conversation.
Moss uses the Light versus Dark Elemental as its temporary appearance.

Run from the Polyworld repository:

```sh
nim r games/monster/monster.nim
```

The conversation opens focused. Type an instruction and press Enter. Escape
switches keyboard focus between conversation and camera. Right-drag or
middle-drag the world to pan, use the wheel to zoom, and press F outside the
editor or click Moss's minimap portrait to resume following him. Left-clicking
the world selects a creature, villager, house, hall, or resource stash for
inspection. It never gives an order.

The chat has two modes: `Text` and `Conversation`. It starts in Text with no
microphone or voice connection. Conversation requires an OpenAI API key.
Select it once, allow microphone access, and speak naturally. Semantic turn
detection decides when you have finished speaking; there is no Talk/Finish
button or recording time limit. You can interrupt Moss while he speaks.
Text mode stops the microphone, voice output, and voice connection. Leaving
the game window pauses listening; returning resumes the selected Conversation
mode. The typed editor remains available in both modes.

Spoken commands use the same conversation, lessons, and validated actions as
typed commands. Moss speaks new replies with the Voice Lab realtime model and
a low, warm, gravelly `cedar` voice. Saved conversations are not read aloud on
startup. The voice model performs Moss's approved dialogue; the existing
creature model still makes plans and learns lessons. Complete spoken turns
keep their order while Moss is thinking; a spoken stop cancels queued orders.
Connection or microphone failures return to Text. Select Conversation again
to reconnect. On macOS, the microphone and speaker share Apple's voice
processing audio engine for echo cancellation during simultaneous playback
and capture. Other platforms currently use the existing Slappy audio path.

Use `--conversation` to start directly in Conversation. `--mute` disables
voice audio and `--unmute` enables it without starting the microphone.
`--no-voice` disables Conversation. `OPENAI_REALTIME_MODEL` and
`OPENAI_REALTIME_VOICE` override
the Voice Lab model and creature voice. Voice uses `OPENAI_API_KEY`, falling
back to `MONSTER_KEY_FILE` or `~/secrets/openai.key`, including one retry for
a rejected environment key. Offline mode, hidden screenshots, and headless
simulation do not open voice connections or microphones. On macOS the normal
Nim command launches a local Monster app so its microphone permission belongs
to the game.

Monster uses Polyworld's common launch options for `--seed N`,
`--windowSize WIDTHxHEIGHT`, `--vsync BOOL`, `--play BOOL`, `--speed N`,
`--mute`, `--unmute`, `--verbose`, `--screenshot PATH`, and `--frames N`.
Valued arguments accept separate, equals, or colon forms. For example,
`--seed 17`, `--seed=17`, and `--seed:17` have the same meaning.
`--play false` starts the simulation paused; Space pauses or resumes it while
the text editor is unfocused. `--speed` changes the graphical simulation rate
while leaving camera and UI movement unchanged. `--verbose` prints world
events to the terminal.
Headless prompt runs reject graphical transport, window, and capture options.

The same value forms apply to `--model`, `--prompt`, `--select`, and
`--save-dir`. Relative save directories resolve from the launch directory.
Monster has no BASIC bot roster or action replay system, so it rejects
unsupported match flags such as `--bot`, `--player`, `--record`, and `--replay`.

Try this sequence:

1. `Walk to the village.`
2. `Remember: when helping people, gather wild berries. Leave their farm alone.`
3. `Bring the villagers some food.`
4. `Go home and rest.`

The model returns a short reply, physical actions, and any new lasting lessons.
The simulation validates the actions and reports their actual results back to
the conversation. Moss can move, gather, give, eat, rest, dance, stop, wait,
and attack a named villager, house, village hall, or resource source.
Moss can carry six supplies at once. Gather wild berries, grain from the
villagers' farm, fish at the stream bank, fallen pine or oak wood, and loose
stone. Gathering at the farm takes food belonging to the villagers. Food and
fallen wood replenish over time, while loose stone is finite.

Deliver to the village hall for communal storage, a particular hut for its
household, or a named villager for personal help. A delivery transfers all of
Moss's cargo. Food feeds people, pine and oak fuel their hearths, and stone
with oak repairs damaged homes. Villagers carry their own supplies and use
the hall when they need something. They choose their own work; conversation
controls only Moss.

Willow's six villagers share three homes: Ada and Ben at Miller's hut, Clara
and Dara at Weaver's hut, and Eli and Finn at Mason's hut. They walk to supplies, bring
them home, eat, refuel their hearths, and repair damage. Residents share slow
harvesting, fishing, woodcutting, and mining jobs, carrying two supplies per
trip. They take short breaks, tend crops, sweep outside their homes, stroll
around the village, and stop to chat with free neighbors. Eating, sleeping,
and fleeing danger take priority. Their names and location names remain visible
in the world. Select a villager to see health, hunger, sleepiness, and carried
items in the utility panel, along with their current activity. A fuller hunger
or sleepiness meter means a stronger need. Eating consumes real food and lowers
hunger; sleeping gradually
lowers sleepiness. Residents whose homes are destroyed sleep at their intact
village hall, or outdoors if both buildings are gone.

The economy targets two meals per resident per five-minute day. Each meal
uses one food and relieves 45 hunger; hunger rises by 90 per day. Residents
eat before bed when needed. Each home aims to keep four food, and each hall
keeps 14 food, 10 firewood, and six stone. These are pooled food and fuel
targets, so nearby grain can replace a distant berry trip and oak can replace
pine. Residents account for supplies already being carried home and prioritize
food when communal supplies run low. Extra gifts remain available in storage.

Gathering two supplies takes six seconds for berries, eight for grain, ten
for fish or pine, and twelve for oak or stone, plus walking and delivery.
Walking speed stays unchanged. Each farm regrows one grain every 30 seconds;
berries, fish, and pine regrow one unit every 60 seconds, and oak every 90.
Across the valley that allows up to 50 food per day against about 36 meals,
leaving room for interruptions and Moss's help without endless stockpiling.
Regrowth stops at each source's capacity; destroyed sources never regrow and
stone remains finite.

The valley shares GotA's five-minute day and changing light, starting at
08:00. Night runs from 18:00 to 06:00. Villagers prefer going home to sleep
at night, while exhausted villagers can also nap during the day. Urgent
hunger and danger can wake them. The clock and their needs persist when
you close and reopen the game.

The valley is 128 by 128 tiles, four times the original area. Willow is your
home village. Bracken lies northwest and Reedbank lies across the stream to
the east. Each neighbor has its own hall, three homes, and six residents.
The north and south fords provide walking routes across the stream.

Villages compete for the same berry patches, fishing banks, fallen wood, and
finite stone deposits. A gatherer who reaches a pile first leaves less for
the next visitor. Once their households are supplied, residents gather
varied reserves for their own hall. Workers account for supplies already being
gathered or carried, and try another job when a source is unavailable. Stocked
halls let people spend more time on maintenance and village life instead of
gathering indefinitely. They use their own village's grain fields and
stores. Select a village hall to inspect its current food, wood, and stone.

You can help any village through Moss. Try `Bring stone from the shared
quarry to Bracken`, `Take fish to Reedbank`, or `Help our village store some
oak before the others collect it`. Villagers remain autonomous, including
when Moss threatens them.

Try `Hit Iris once` to attack a specific villager. Moss walks into reach,
winds up, and lands one strike for 35 damage. Villagers start with 100
health, so three strikes can kill one. The victim and nearby witnesses flee,
and their village becomes alarmed. Injuries, deaths, and lost workers persist
in your save. Supplies carried by a dead villager remain with the body.
There is no automatic healing or respawning yet.

`Kill Ada` queues enough strikes to finish the named villager. `Destroy
Miller's hut` targets the building, while `Smash the fallen pine wood pile`
destroys that resource source in one strike. Destroyed buildings become
selectable ruins, lose their supplies, and stop providing storage or shelter.
Destroyed sources do not regrow. There is no rebuilding or looting yet.

Villagers begin wary and keep their distance from Moss. Delivering real
supplies builds trust and reduces fear among the recipients: a personal gift
helps that person, a household delivery helps its residents, and a hall
delivery helps its village. Witnessed violence sharply increases fear and
damages trust. Frightened residents flee and remember their fear after the
immediate panic ends. Inspect a villager to see their attitude, trust, and fear.

Typing exactly `stop` or `stop attacking` interrupts Moss immediately, even
while a model reply is pending. A canceled reply cannot restart the attack.
Other commands use the normal conversation and action planning loop.

The bottom-left minimap shows the region, settlements, villagers, and Moss.
Click or drag its terrain to navigate the camera. Click Moss's portrait to
select him again and resume following him. Its outlined rectangle shows the
current camera view.
Zoom stays between camera distances 12 and 50 so the creature remains visible.
The bottom-right utility panel keeps health beside the portrait for Moss,
villagers, houses, and halls. Resource sources show their available quantity.
Energy, needs, relationships, storage, and carried items appear below in a
separately scrollable area. Only present items appear, with quantities over
their icons. Selecting an entity gives it a gold silhouette outline and
changes the panel to its live details. Selection leaves the conversation
directed at Moss. Use the wheel or drag each panel's scrollbar to inspect
more stats or read earlier messages. Changing selections returns the utility
panel to its first stat.

Try `Bring fish to Ada`, `Bring pine wood to Weaver's hut`, or
`Take stone and oak to Mason's hut so they can repair it`. Ask Moss about
the village to get an account of the current needs.

When an action fails, Moss receives its actual result and explains the problem
in conversation. Blocked routes and unavailable resources stay in its memory
as internal feedback. The explanation does not start another plan or create a
new lesson. Connection and save errors remain visible as technical problems.

The game uses an existing nonempty API key from the environment first. For
the native OpenAI connection, if no key is set, it reads the raw key from
`~/secrets/openai.key`, or the path supplied by `MONSTER_KEY_FILE`. File
fallback also retries the same instruction once if OpenAI rejects the
environment key with HTTP 401 and the file contains a different key. The
working file key is then used for the rest of the session. File fallback does
not apply to the sidecar or custom non-OpenAI connections.

The model defaults to `gpt-6-sol`. Set `OPENAI_API_KEY` for the native OpenAI
connection, or use the existing Polyworld sidecar with `COWORLD_LLM_ENDPOINT`.
An explicit `--model:ID` selects a model available through that endpoint.
Existing `COGAME_LLM_KEY`, `OPENROUTER_API_KEY`, and `COGAME_LLM_BASE_URL`
configuration is supported by the shared transport. Conversation uses the
Responses API and requires structured JSON output support. `COGAME_LLM=off`
or `--offline` disables model calls and leaves the scene available for viewing.
Credentials stay in memory and are never saved with the creature.

Conversation, lessons, and physical progress save automatically in the user
data directory under `polyworld/monster/<seed>`. Use `--save-dir:PATH` for a
separate creature. `--seed:N` selects a seeded landscape and a separate default
save. Full conversation is retained up to the explicit memory and request
limits. Reaching a limit displays an error. Sleep does not compact memory yet.
Unfinished creature orders stop when a saved game is reopened. Villagers
choose new work from their saved needs and supplies. Earlier food-only and
single-village saves migrate automatically; Willow's progress, conversation,
and lessons are preserved while the neighboring settlements are added.
Older saves initialize newly added health and relationship fields. Health,
fear, trust, and permanent destruction persist in current saves.

Validation:

```sh
nim check games/monster/monster.nim
nim r games/monster/tests/tests.nim
nim r -d:silkyTesting games/monster/tests/test_ui.nim
nim r games/monster/tests/test_selection_render.nim
nim r games/monster/tests/test_voices.nim
nim r games/monster/tests/test_voice_launch.nim
```

Measure production, meals, reserves, hunger, warmth, and work/leisure time
without rendering, external services, or modifying a save:

```sh
nim r games/monster/tests/bench_economy.nim 12 42,7,123
nim r games/monster/tests/bench_economy.nim 60 42
nim r games/monster/tests/bench_economy.nim 12 42,7,123 empty-food
```

The last scenario removes all initial food but keeps sources intact, testing
recovery from a shortage rather than relying on the starting stockpile.

The opt-in `nim r games/monster/tests/manual_voice.nim --live` check sends
synthetic speech through the real voice connection and game planner without
opening a microphone or speaker. It uses a temporary save. The offline
`nim r games/monster/tests/manual_voice_ui.nim` preview captures the voice HUD.

Run one real model instruction and its resulting actions without a window:

```sh
nim r -d:headless games/monster/monster.nim \
  --save-dir:build/monster-smoke --prompt:'Walk to the village.'
```

Capture the rendered game in a hidden window:

```sh
nim r games/monster/monster.nim --screenshot output/monster.png \
  --frames 30 --windowSize 1440x900
```

These shared screenshot flags also accept `=` and `:` separators. The default
capture is the thirtieth rendered frame. It runs muted in a hidden window,
creates the output directory, and exits without saving world or conversation
changes. Ordinary captures do not send model requests.

Add `--prompt:'Walk to the village.'` to request a model instruction and wait
for its resulting actions before capture. In that mode, `--frames N` is the
minimum rendered frame count. `--save-dir:PATH` selects which existing world
and conversation to read; capture still leaves those files unchanged.

The shared `nim r -d:takeScreenshot games/monster/monster.nim` option also
captures in a hidden window, defaulting to `output/monster.png`. Set
`SCREENSHOT_PATH` for another path, or override it with `--screenshot:PATH`.
`-d:headless` runs only the simulation and cannot capture screenshots.
