# Lane sustain

[`lane_sustain.bas`](lane_sustain.bas) is the shared Aaron / Preston policy
selected by our October 9, 2026 GotA experiments. It is a standalone BASIC
script, published unchanged under the repository's [MIT license](../../../LICENSE).
No model weights, generator, service credentials, or hosted API are required.

The policy prefers Crossbowman when available. It combines lane farming,
health and supply recovery, equipment purchases, portal travel, tower safety,
and objective attacks. Its final lane-positioning change approaches creeps
to a 5.5-tile boundary inside the then-current six-tile attack and XP ranges.
It also stocks poison and uses lethal poison bursts against exposed objectives.
The `@rule` comments mark sections of the generated script; the script itself
contains the complete executable policy.

## Run

Install Nim 2.2.10 or newer and the pinned dependencies as described in the
[repository README](../../../readme.md). From the repository root, run five
copies against five bundled baseline bots:

```sh
nim r -d:headless games/gods_of_the_arena/gota.nim \
  --draft-mode open --seed 42 \
  --bot games/gods_of_the_arena/players/lane_sustain.bas:5 \
  --bot games/gods_of_the_arena/players/base.bas:5
```

The first five slots are red and the next five are blue. Swap the bot arguments
to test the opposite side. Omit `-d:headless` to watch the match with the art
assets installed, or add `--record /tmp/lane-sustain.bin` to save a replay.
The historical evaluations used open draft, which allows duplicate heroes.

Publication compatibility check (November 13, 2026): built the engine at
`3bd5937569439f4a9b8141a0ed19c37b688b4ba7` with its pinned dependencies,
Nim 2.2.10, `-d:headless`, and `-d:bassyNativeStrict`. Both full seed-42 matches
above completed with all ten scripts active, and both recordings replayed
without hash mismatches. These two matches check runtime compatibility only.

## Provenance and historical evaluation

This file was recovered from the registered
`aaron-gota-edge-all-20261009:v1` policy, version
`9c6ad83a-ee90-476f-a0e8-ca90a07c3a48`, and verified against the source hash
recorded when it was deployed. The same source was deployed as
`preston-gota-lane-sustain-20261009:v1`, version
`b3493ea2-ba3b-4dc3-8de4-c1ed19f8d132`.

- Source size: 63,439 bytes.
- SHA-256: `423b2626b99013becc84132905f5524f35ca09408b743ef7f30aa05ef99f906e`.
- Evaluation release: `2026.10.8.1`, replay version 69.

The retained experiment handoff records the following paired comparisons:

| Comparison | Matched pairs | Previous wins | Lane sustain wins | Mean raw XP change |
| --- | ---: | ---: | ---: | ---: |
| Aaron's previous poison-siege policy | 48 | 19 | 23 | +565.69 (+10.7%) |
| Preston's previous H17 policy | 30 | 7 | 12 | +2,041.30 (+64.1%) |
| Larger Preston follow-up | 150 | 40 | 45 | +1,494.53 |

These are historical results against different previous policies, not a
current leaderboard claim or a head-to-head Aaron/Preston comparison. The
larger follow-up reused roster templates with fresh seeds. Aaron's reported
95% interval for the XP gain included zero. Game balance and opponents have
changed since these evaluations; the results do not establish superiority
against today's field. Private research artifacts are not included here.

Verify the unmodified source locally with:

```sh
shasum -a 256 games/gods_of_the_arena/players/lane_sustain.bas
```
