# Player mailboxes

Each player has one inbox with 100 message slots. A message is an integer ID
and a string, limited to 1024 bytes. Sending to a full inbox does nothing;
unread messages remain until the player pulls them.

The BASIC host passes the sender’s roster slot, the destination, and the
message bytes to the game’s `sendChat`.
The [BASIC mailbox example](../examples/mailboxes/chat.bas) uses these routing
rules:

| Game | Global (`-2`) | Team (`-1`) | DM (player ID) |
| --- | --- | --- | --- |
| Gods of the Arena | Everyone. | Heroes on the sender's red/blue team. | One player. |
| Light vs Dark | Everyone. | Unsupported. | One player. |
| Call to Adventure | Players within 16 tiles on the same level. | Unsupported. | Unsupported. |

Broadcasts include the sender. CTA uses its existing Chebyshev tile distance:
the difference along each tile axis must be at most 16. Range and level are
checked when sending; moving afterward does not remove queued messages.
Each game selects recipients before writing to their inboxes.

In a local game, `sendChat` returns the number of inboxes that accepted a copy. Empty or
oversized messages and unsupported or invalid destinations return zero.
A broadcast can reach some players even when another player's inbox is full.

`pullMailbox$()` consumes the oldest message, or returns an empty string if
there is none. `mailboxId()` identifies the last message pulled: `-2` for
global, `-1` for team, or the sender's player ID for a DM. An empty pull sets
that ID to `-3`. There is no separate sender, channel name, or timestamp.

`mailboxCount()` counts unread messages, `mailboxSelf()` returns the caller's
roster ID, and `mailboxPlayers()` gives the roster size. Addresses run from
0 through `mailboxPlayers() - 1` in all three games. CTA has four party
slots. GotA uses the hero roster and LvD uses the configured player count.

```basic
sendChat(-2, "Hello everyone.")
' GotA only:
sendChat(-1, "Meet at the checkpoint.")
' GotA and Light vs Dark:
sendChat(0, "A direct message to player zero.")
message$ = pullMailbox$()
while message$ <> ""
  print mailboxId(), message$
  message$ = pullMailbox$()
wend
```

Local delivery follows script execution order. A later player can read a message
in the same tick. Players can send and pull multiple times per decision,
within their normal BASIC instruction and string limits. Inboxes persist
across decisions and are replaced when policies are loaded for a new run.
Recorded matches store chat in the same ordered command stream as gameplay
actions. Replay playback consumes those commands without rerunning the bots.

## From submission to inbox

- **GotA** resolves the hero entity to a roster slot. Local policy chat goes
  through `deliverChat` to `deliverPolicyChat`. In multiplayer, `sendChat`
  returns 1 when it queues a submission. Each client receives the submission in an
  authoritative tick packet. The game decodes category 1, checks hero/seat
  ownership and destination, and applies an `ActionPolicyChat` with the sender
  hero, target and text. Human chat uses category 2 and its own transcript.
  See the [packet layout](../games/gods_of_the_arena/packets.md).
- **LvD** uses the player slot directly. Local sends call `deliverChat`.
  Multiplayer queues a submission and returns 1 on acceptance. The client
  decodes the packet’s chat payload (tag 0, player, target, byte-counted text),
  checks ownership and destination, then applies nonempty chat at the packet
  tick. The public HUD reads broadcast actions from the transcript. Reading
  the HUD leaves BASIC inboxes untouched.
- **CTA** converts the hero ID to its party slot and selects nearby players
  with room in their inboxes. When recording, it saves the accepted recipient
  mask, target and text before pushing the broadcast to those same slots.

In each host, `pullMailbox$()` uses Bassy’s public string API to copy the front
message into the calling player’s runtime before popping the entry. The pop updates
`mailboxId()`. An inbox can fill between network submission and delivery.

## Local contract check

With the dependencies from `nimby.lock` available to `config.nims`, run this
from the repository root in a POSIX shell. Set `POLYWORLD_DEPS` if the pinned
dependencies live outside the checkout’s parent directory. This checks FIFO
wraparound, exercises all three BASIC hosts for 300 decisions, measures inbox
allocations, and checks LvD authoritative packet delivery and replay. The
tests run serially with one compiler worker.

```sh
(
  scratch=$(mktemp -d) || exit 1
  trap 'rm -rf "$scratch"' EXIT
  for test in tests/test_mailboxes.nim tests/test_mailbox_allocations.nim \
      games/light_vs_dark/tests/test_replay_chat.nim; do
    nim c -r -d:headless -d:nimAllocStats --parallelBuild:1 \
      --nimcache:"$scratch/cache" -o:"$scratch/check" "$test" || exit 1
  done
)
```
