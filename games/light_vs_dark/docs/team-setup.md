# Teams and diplomacy

The main **Match Settings** panel has team setup directly below **Max ticks**.
**Diplomacy mode** starts unchecked. Every player initially
has a separate fixed team, shown by a numbered color badge.

Change the **Teams** slider to split the roster into that many teams. Players
are shuffled into groups whose sizes differ by at most one. Right-click a
player's team badge to move that player to another team without changing anyone
else. Changing the slider redistributes the entire roster again.

Fixed teammates share vision, cannot attack each other, and win together when
the opposing teams are eliminated. Team relationships cannot change during the
match. A one-team setup runs as a sandbox until its time limit.

Enable **Diplomacy mode** to start neutral and negotiate war, peace, and
alliances during play. Turning it off in setup restores the saved fixed-team
assignments. The command-line equivalent is `--diplomacy`.

In multiplayer, the host edits teams and applies settings before starting.
Team numbers survive empty seats, replay recording, and replay loading.
Players retain separate armies and controls even when they share a team.
