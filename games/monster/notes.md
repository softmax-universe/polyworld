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
Gathering at the farm takes food belonging to the villagers. Gathering at the
berry patch takes wild food. There is no combat or village economy yet.

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
Unfinished physical orders stop when a saved game is reopened.

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
