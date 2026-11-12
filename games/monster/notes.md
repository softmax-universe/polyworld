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
editor or click Find my creature to resume following Moss. Left-clicking the
world never gives the creature an order.

Try this sequence:

1. `Walk to the village.`
2. `Remember: when helping people, gather wild berries. Leave their farm alone.`
3. `Bring the villagers some food.`
4. `Go home and rest.`

The model returns a short reply, physical actions, and any new lasting lessons.
The simulation validates the actions and reports their actual results back to
the conversation. Moss can move, gather, give, eat, rest, dance, stop, and wait.
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

Six villagers share three homes: Ada and Ben at Miller's hut, Clara and Dara
at Weaver's hut, and Eli and Finn at Mason's hut. They walk to supplies, bring
them home, eat, refuel their hearths, and repair damage. They rest when their
needs are met. Their names, current work, household needs, and supplies are
visible in the world and side panels.

Try `Bring fish to Ada`, `Bring pine wood to Weaver's hut`, or
`Take stone and oak to Mason's hut so they can repair it`. Ask Moss about
the village to get an account of the current needs. There is no combat yet.

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
choose new work from their saved needs and supplies. Existing food-only
saves migrate automatically; conversation and lessons are preserved.

Validation:

```sh
nim check games/monster/monster.nim
nim r games/monster/tests/tests.nim
nim r -d:silkyTesting games/monster/tests/test_ui.nim
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
