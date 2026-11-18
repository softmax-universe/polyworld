# Human match chat

Human controllers press **Enter** to open all-chat, **Shift+Enter** to open team-chat, **Enter** to send, or **Esc** to cancel. Backspace removes one UTF-8 codepoint. Empty/whitespace-only messages are ignored. Messages are limited to 1024 UTF-8 bytes; invalid UTF-8, control characters, surrogate/noncharacter values and bidi override/isolate controls are rejected. Canvas text is literal, not HTML.

Chat captures match keyboard input and suppresses polled orders, HUD key aliases, selection, attack/ability activation and camera controls until the closing frame finishes. Silky settings/lobby input retains its own callback focus. The match restores its rune callback on exit.

## Routing

The shared relay has no chat opcode: `SubmitCommand` carries opaque game bytes. GotA network protocol **4** uses category **2** for human chat, with the same game-owned string envelope as category **1** policy mailboxes (`heroId`, scope, length-prefixed UTF-8). Scope is -2 for all, -1 for team. Categories 0 (actions) and 1 (bot mailboxes) retain their existing layouts and behavior.

Only an authoritative TickPacket creates visible messages; no optimistic echo. Relay seat ownership and game hero/seat/type validation prevent spectators, foreign seats and bot-only controllers from speaking as a human. Display names come from the prepared exact human identity, e.g. `mason :)`, not parsed policy names. Human messages never enter policy inboxes. The bounded independent display history retains 100 messages and renders its latest six; team messages are filtered for human viewers, while omniscient spectators may view both teams. As with every opaque command, team text is present in all authoritative packets: this is a display scope, not encryption/private transport.

## Replay chat

GotA replay format **7**, gameplay **83**, preserves chat in a separate event stream alongside hero actions. It records human all-chat and team-chat, policy broadcast/team/direct messages, and authoritative system notices. Events retain their original simulation tick, order, sender, scope or recipient, and exact text. Local policy messages use their decision tick; network messages use the authoritative packet tick.

Replay playback shows human chat and system notices at the current playhead, using the recorded sender names and team display rules. Seeking backward hides later messages; seeking forward restores them without duplicates. Policy messages remain part of the recording without becoming human chat or being consumed by the viewer. The 100-message display limit does not discard the recording's earlier chat. Buffered spectator packet playback also avoids recording a message twice on rewind.

Gameplay replay still applies recorded actions without rerunning private bot VMs. Chat history and consumable policy inboxes remain outside the shared world hash: different controllers and spectators may consume different inboxes. Missing human chat in older recordings therefore did not itself desynchronize ordinary gameplay playback, but those files cannot recover text that was never recorded. Older replay versions require their matching archived client.

## Tests

- `nim c -r games/gods_of_the_arena/tests/tests.nim` includes editing/Unicode bounds, history, binary two-human RoomClient/Relay delivery with exact names/text, default-all and team display filtering, ownership/spectator rejection, policy preservation and source-route integration guards.
- `nim c -r -d:silkyTesting games/gods_of_the_arena/tests/test_human_chat_input.nim` exercises actual callback chaining/restoration, rune activation, consumed typing keys and Silky focused-field coexistence.
- `nim check games/gods_of_the_arena/graphics.nim` checks the integrated renderer.

These tests are native/in-process. Clients must match both gameplay and network protocol versions to join the same room.
