# Play Cards and Casters fast path

**You are the coding agent.** Help your human build a Cards and Casters bot
and improve it with evidence. A bot is one BASIC `.bas` file that the game
runs itself: no container, no network. You build, test and upload; **your
human submits** to the league.

```
copy a reference bot -> build the headless runner -> run matches
    -> make one scoped change -> verify over many seeds -> upload; human submits
```

- Full reference: [`README.md`](README.md): rules, the whole BASIC API and
  a working minimal bot. Where it and this file disagree, the README wins.
- Reference bots: [`players/`](players/). `archer.bas`, `warrior.bas` and
  `mage.bas` play the class precons, `archer_warrior.bas` an Archer deck
  splashing Warrior cards. They play alike; only their decks differ.
- Coworld package: [`coworld/cac`](../../coworld/cac). Coworld and league
  ids: <https://softmax.com/play.md>.

## Minimum game facts

- 2 to 7 heroes: two play a duel, 3 to 7 a free-for-all ring. The last hero
  standing scores 1, everyone else 0. A draw, a timeout or a player failure
  scores 0 for all.
- Each hero has a class (Archer, Warrior or Mage), 20 life and a 40-card
  deck (1 to 4 copies of any base card; level-up cards any number), and
  draws 5.
- Your turn: total energy +1 (no cap), refill, draw 1. Then, in any order,
  play cards you can afford and attack once with each ready minion. Then
  end the turn.
- Another class's card costs 3 more, less 1 for each of that class's
  level-up cards (the 0-cost `Archer`, `Warrior` and `Mage` trinkets) you
  control.
- A hero at 0 life, or drawing from an empty deck, is out.
- Every card: `./cac --cards` (`--cards:warrior`, `--card:NAME`).

## How a bot runs

1. **Setup**, once, while `selectingClass` is 1: `pickClass(c)`, then
   `deckCard(name$, copies)` up to 40 cards, then `END`.
2. **Every decision** runs the script again from the top. It must make
   **exactly one** accepted command, or the match stops and you score 0.
   Commands return 1 if accepted, 0 if refused (nothing changed: try
   another).
3. Answer in this order: `tossCount > 0` → `discardCards("picks")`;
   `triggerTargets > 0` → `resolveTrigger("picks")`; otherwise play a card
   (`playCard…`), `attack(id, c)` or `endTurn()`. The engine never acts for
   you.

BASIC traps: comparisons give -1 or 0, and `AND`, `OR` and `NOT` are
bitwise, so compare host results explicitly: `IF canPlay(i) = 1 AND n > 0`.
`PRINT` writes to your private log.

## Test locally

From `games/cac`:

```sh
nim c -d:headless -o:build/cac-headless src/cac.nim
./build/cac-headless --bot my.bas --bot players/warrior.bas --seed 3
for s in $(seq 1 100); do ./build/cac-headless --bot my.bas --bot players/warrior.bas --seed $s; done | grep -c '^Match winner_0'
```

The first `--bot` is seat 0, so the loop counts your wins out of 100 (who
moves first is random). `--bot PATH:N` fills N seats for a ring game;
`--classes` and `--record PATH` are in the README. A script error or an
illegal deck is printed.

Give these to your human; they open a window:

```sh
nim c src/cac.nim
./cac --human --bot my.bas      # play against the bot
./cac --replay m.replay         # watch a recorded match
```

## Upload

```sh
uv run coworld upload-policy --file my.bas --name NAME
```

Then your human submits it to the league.

## What not to spend time on

- **Reading the engine.** The README documents the whole bot API.
- **Card balance from bot results.** The reference bots play one greedy card
  at a time and never plan combos, so their win rates reflect bot skill,
  not card strength.
- **Beating one opponent.** Check against all three precons and in the
  ring, not only the duel you tuned for.
