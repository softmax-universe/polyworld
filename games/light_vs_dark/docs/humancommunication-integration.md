# LvD human chat/diplomacy — integration status

## Implemented

`humancommunication.nim`, `ui.nim`, and `graphics.nim` are wired. Native callback,
HUD/render and real binary in-process relay regressions pass. Final full-suite,
WASM build and two-browser acceptance remain separate parent-owned gates; no
server deployment or commit was performed for this integration.

### Graphics lifecycle and input

- Match entry resets communication, shortcut masks and callbacks. Deferred match
  teardown clears communication, `hudNetwork`, frame/key/release/rune/focus
  callbacks and native rune capture, including exceptional/early-return exits.
- Enter opens/sends and Escape cancels through the production button callback,
  before contextual action keys, pause/menu, fullscreen and chrome hotkeys.
  Entry cancels gestures, build placement and armed attack. Repeated Enter is
  quarantined until release; release forwarding is unconditional.
- The rune callback forwards Unicode to communication only with the match menu
  hidden. Enter requests native rune capture immediately. The frame restores it
  **after all Silky UI passes**, since an unfocused Silky text field otherwise
  disables rune input at `endUi`. Settings retain Silky's ordinary text routing.
- Camera/minimap/Ctrl+A polling and world selection/order polling are gated by
  communication capture and window focus. HUD drawing stays active. Closing
  events remain blocked through input and rendering; `finishHumanCommunicationFrame`
  runs only afterward. Typed keys remain quarantined until release.
- Focus loss cancels typing/pan/selection/formation and clears held-key masks,
  but keeps conversation history. Communication buttons use real left-button
  presses, never keyboard-select aliases. Held Tab cannot engage the stats
  director while communication owns input.

### Authority and diplomacy

- `advanceRenderedMatch` calls `observeHumanCommunication` immediately after each
  successful `network.applyPacket`, including every catch-up packet. It never
  observes optimistic submissions or merely received future packets.
- Chat uses `game.sendChat(sender, -2, text)`. Broadcast mailbox IDs are **-2**,
  not sender IDs; attribution uses the recorded player ID and config name.
  The observer follows the authoritative transcript, retains at most 100
  lines, and never drains bot or human mailboxes. Display continues even when
  unread bot mailboxes reach their independent cap.
- Local successful chat appears immediately; network chat appears only after
  authoritative application. Unicode input is bounded to 1024 bytes and
  Backspace removes a whole scalar. Empty messages are not sent.
- Diplomacy shows actual relationships, incoming/outgoing offers and deadlines.
  Actions use `game.applyDiplomacy`; availability is validated on detached
  relations, including exact offer ID, sender/recipient, cooldown and defeat.
  FFA starts AtWar. Peace and alliance require recipient acceptance; the
  sender's resend cooldown remains after peace. Ending an alliance retains
  vision through its warning interval. The panel pages through all opponents.
- Replay tapes store chat text, sender, recipient and authoritative delivery
  tick, including script messages and direct messages. Public broadcasts appear
  in playback; direct messages stay out of the public HUD. Rewinding rebuilds
  the feed at the displayed tick without consuming bot mailboxes.
- Playback applies recorded commands without rerunning bots. Chat-triggered
  bot actions therefore retain the same simulation hashes. The transcript is
  separate from gameplay commands and supports messages sent at tick zero.

## Native verification

Run from `/Users/me/p/polyworld`, with distinct scratch outputs/caches:

```
nim check --hints:off games/light_vs_dark/graphics.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-authority-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-authority games/light_vs_dark/tests/test_human_communication.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-ui-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-ui games/light_vs_dark/tests/test_human_communication_ui.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-graphics-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-graphics games/light_vs_dark/tests/test_human_communication_graphics.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-diplomacy-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-diplomacy games/light_vs_dark/tests/test_diplomacy.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-feedback-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-feedback games/light_vs_dark/tests/test_order_feedback.nim
nim c -r --hints:off --nimcache:/Users/me/.hermes/cache/scratch/lvd-comm-ffa-cache --out:/Users/me/.hermes/cache/scratch/lvd-comm-ffa games/light_vs_dark/tests/test_ffa_combat.nim
```

All commands above passed during integration (graphics has existing unused
`os`/`strutils` import warnings outside screenshot builds).

- `test_human_communication` is registered in the art-free game suite. It runs
  real two-human Create/Join/Claim/Ready/Start and binary relay exchanges,
  both-direction Unicode/name chat, bot-inbox preservation, bounded feed, no
  optimistic mutation, matching peer hashes and diplomacy/vision transitions.
- `test_human_communication_ui` executes the UI key/rune hooks and quarantine.
- **`test_human_communication_graphics` is intentionally NOT in the art-free
  suite.** It creates a real Windy GL window and art-backed Silky HUD, compiles
  and invokes the actual production callback/routine AST (not string-presence
  assertions), and verifies Enter/runes/send/repeat/Escape, Stop/build/attack/
  pause suppression, camera/Ctrl+A polling, post-Silky rune restoration, native
  focus loss, select-alias suppression and panel Offer/Decline/Accept from both
  player perspectives. It first failed on missing Enter routing; its expanded
  HUD test also caught and regressed typed select aliases clicking Diplomacy.
- Existing diplomacy tests pass combat cessation/shared vision; default-FFA
  combat still damages/kills. All eight order-feedback GPU cases pass, retaining
  green Move and red Attack/AttackMove markers and formation previews.

## Remaining acceptance / limitations

The native fixture is not a complete `runGraphics` match-loop replay, nor proof
of OS text event generation, browser input, final glyph coverage, network HUD
rendering across two browser clients, or return-to-menu/second-match lifecycle.
The parent owns full-suite/build/browser verification after this handoff. Unicode
is transported exactly; the raster font may not cover every entered glyph.
Old replay files cannot recover chat that was never recorded. The updated
transcript uses replay format 8 and game version 49.
