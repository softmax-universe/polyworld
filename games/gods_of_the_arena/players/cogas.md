# Co-gas champion

[`cogas.bas`](cogas.bas) is the exact standalone BASIC source of **relh v441**,
the strongest co-gas entry on the public Competition leaderboard when checked
on November 13, 2026 at 20:44 UTC: rank 2, score 32.835957618578036. The other
co-gas champion, richard v504, was rank 12 with score 13.44711477958667.
This is a dated leaderboard observation, not a claim of universal superiority.

The policy includes its learned controller and weights, drafting, farming,
shopping, spell handling, and short post-shot retreats from visible melee
heroes. It needs no model download, network service, or co-gas installation.
It uses the legacy BASIC observation interface supported by the game host.

Run from the repository root with the normal Polyworld dependencies installed:

```sh
nim r -d:headless games/gods_of_the_arena/gota.nim \
  --bot games/gods_of_the_arena/players/cogas.bas:5 \
  --bot games/gods_of_the_arena/players/base.bas:5 \
  --seed 20261113 --ticks 28800 --headless-tick-rate 0
nim r games/gods_of_the_arena/tests/test_cogas.nim
```

Reverse the two bot arguments to put co-gas on the other team. The smoke test
checks drafting and all ten hero classes on both teams, including VM instruction
and work budgets. These are compatibility checks, not a competitive evaluation.

Validated against Polyworld `3bd5937569439f4a9b8141a0ed19c37b688b4ba7`
with its pinned dependencies and Nim 2.2.10. The smoke test passed. In two full
matches with seed `20261113`, co-gas beat `base.bas` on both sides (857.92 battle
seconds as Red, 1199.54 as Blue); all ten scripts remained active in each match.
Two reference matchups do not establish general strength on the current engine.

## Provenance and evidence

- Source: `players/users/relh/co-gas/polyworld-basic/gods_of_the_arena_relhalpha_v75_cooldown_kite_20261030.bas`
  in [co-gas commit 45ede9ed40e43470f30c71e338fc5ba2594f46fe](https://github.com/Metta-AI/co-gas/commit/45ede9ed40e43470f30c71e338fc5ba2594f46fe).
- SHA-256: `c1144b978744da8c7d9a43908e35cc51ab552481ee2df9b5dc3725f435946e43`.
  The exported file is byte-for-byte identical, including embedded weights.
- Hosted policy version: `603bdf80-c91f-434c-a0dc-7738dd2e8006` (v441).
- The October 30 promotion review compared four matched setups: the incumbent
  had one win, two losses, and one draw; v441 had three wins and one loss.
  Some retained wins had lower XP and more deaths. These selected fixtures do
  not establish a population win rate.
- The November 13 readback reported Coworld `cow_181358e7-0980-4425-b501-f29a942ca827`,
  version `2026.11.3.2`. Its latest round, 2569, failed on November 4; the
  leaderboard is retained tournament evidence, not a fresh November 13 match.
- Both mandatory Polyworld Buff pages were fetched and reviewed on November 13
  at 20:43 UTC: [heroes](https://softmax-universe.github.io/polyworld-buff/GOTA/heros/)
  and [players](https://softmax-universe.github.io/polyworld-buff/GOTA/players/).
  Their statistics end on October 7 and predate v441. Demon Hunter and
  Crossbowman lead XP/minute in the latest hero snapshot, but those historical
  figures were not used to change this policy or establish its current rank.
- Upstream inspected: `softmax-universe/polyworld` at
  `3bd5937569439f4a9b8141a0ed19c37b688b4ba7`, including its reference players,
  BASIC host, and policy tests. The repository search also found
  `softmax-universe/polyworld-buff`. Existing MIT-licensed reference behavior
  in the champion retains the repository's Softmax attribution in `LICENSE`.

This contribution preserves the deployed strategy; it does not change the
default players or any tournament membership.
