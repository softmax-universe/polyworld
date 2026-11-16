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
them home, eat, refuel their hearths, and repair damage. They rest when their
needs are met. Their names and the valley's location names remain visible
in the world. Select a villager to see health, hunger, sleepiness, and carried
items in the utility panel. A fuller hunger or sleepiness meter means a
stronger need. Eating consumes real food and lowers hunger; sleeping gradually
lowers sleepiness. Residents whose homes are destroyed sleep at their intact
village hall, or outdoors if both buildings are gone.

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
reserves for their own hall. They use their own village's grain fields and
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
```

Run one real model instruction and its resulting actions without a window:

```sh
nim r -d:headless games/monster/monster.nim \
  --save-dir:build/monster-smoke --prompt:'Walk to the village.'
```

Capture the rendered game in a hidden window:

```sh
nim r games/monster/monster.nim --screenshot:output/monster.png
```

Add `--prompt:'Walk to the village.'` to wait for the model and resulting
actions before capture. `--frames:N` sets the minimum rendered frame count.
Use `--save-dir:build/monster-capture` to keep capture progress separate.

The shared `nim r -d:takeScreenshot games/monster/monster.nim` option also
captures in a hidden window, defaulting to `output/monster.png`. Set
`SCREENSHOT_PATH` for another path, or override it with `--screenshot:PATH`.
`-d:headless` runs only the simulation and cannot capture screenshots.
