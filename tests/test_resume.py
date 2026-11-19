"""Exercise headless replay warm-up, takeover, and recording in every BASIC game."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
EXE = ".exe" if os.name == "nt" else ""
GAMES = (
    ("gota", "gods_of_the_arena/gota.nim", 10, ["--ticks", "1200"]),
    ("cta", "call_to_adventure/cta.nim", 4, ["--ticks", "120"]),
    ("lvd", "light_vs_dark/lvd.nim", 2, ["--ticks", "1200"]),
    ("heartleaf", "heartleaf/heartleaf.nim", 9, ["--days", "1"]),
    ("cac", "cac/src/cac.nim", 2, ["--ticks", "24"]),
)
CAC_SETUP = '''if selectingClass then
  pickClass(1)
  deckCard("Warrior", 40)
  end
end if
'''


def run(arguments, succeeds=True):
    """Run a real CLI and retain its diagnostics when an assertion fails."""
    result = subprocess.run(
        [str(value) for value in arguments], cwd=ROOT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert (result.returncode == 0) == succeeds, result.stdout
    if succeeds:
        for failure in ("BASIC error", "script FAILED", "player_failure"):
            assert failure not in result.stdout, result.stdout
    return result.stdout


def build(source, target):
    """Compile the normal native headless game with an isolated cache."""
    run(["nim", "c", "-d:headless", "-d:bassyNativeStrict", "--hints:off",
         f"--nimcache:{target}-cache", f"--out:{target}", source])


def test_gota_active_takeover(executable, inspector, source, recorded, temporary):
    """Warm real replacement policies, then let both teams play to completion."""
    players = ROOT / "games/gods_of_the_arena/players"
    cutoff = len(recorded["hashes"]) // 2
    heroes = recorded["heroes"]
    seats = len(heroes)
    prefix = [action for action in recorded["actions"] if action["tick"] <= cutoff]
    for replaced in (seats // 2, seats):
        bots = ["--bot", f"{players / 'rusher.bas'}:{replaced}"]
        if replaced < seats:
            bots += ["--bot", f"{players / 'base.bas'}:{seats - replaced}"]
        branch = temporary / f"gota-rusher-{replaced}.replay"
        run([executable, "--replay", source, "--resume-step", cutoff,
             *bots, "--record", branch])
        resumed = json.loads(run([inspector, "gota", branch]))
        assert resumed["hashes"][:cutoff] == recorded["hashes"][:cutoff]
        assert [a for a in resumed["actions"] if a["tick"] <= cutoff] == prefix
        assert resumed["heroes"] == heroes
        assert len(resumed["hashes"]) == len(recorded["hashes"]), "Match ended early"
        assert resumed["hashes"][cutoff:] != recorded["hashes"][cutoff:], \
            "Replacement policies did not change the live world"
        live = [a for a in resumed["actions"] if a["tick"] > cutoff]
        active = {a["heroId"] for a in live}
        moving = {a["heroId"] for a in live if a["kind"] in resumed["movementKinds"]}
        assert {hero["id"] for hero in heroes[:replaced]} <= moving, \
            "Every replacement must move or attack after handoff"
        assert {hero["id"] for hero in heroes[replaced:]} <= active, \
            "The original policies must keep playing after handoff"
        assert min(a["tick"] for a in live) == cutoff + 1
        run([executable, "--replay", branch])
        print(f"  base -> {replaced} rushers: replay through {cutoff}, "
              f"live from {cutoff + 1} through {len(resumed['hashes'])}", flush=True)


started = time.monotonic()
with tempfile.TemporaryDirectory(prefix="polyworld-resume-") as directory:
    temporary = Path(directory)
    inspector = temporary / f"inspect{EXE}"
    build("tests/test_resume_tapes.nim", inspector)
    for name, entry, seats, duration in GAMES:
        print(f"Testing {name} replay handoff", flush=True)
        game_directory = ROOT / "games" / entry.split("/")[0]
        focused = temporary / f"{name}-state{EXE}"
        build(game_directory / "tests/test_resume.nim", focused)
        run([focused])
        executable = temporary / f"{name}{EXE}"
        prebuilt = os.environ.get("POLYWORLD_RESUME_BIN_DIR")
        if prebuilt:
            executable = Path(prebuilt) / f"{name}{EXE}"
        else:
            build(ROOT / "games" / entry, executable)
        original = temporary / f"{name}-original.bas"
        candidate = temporary / f"{name}-candidate.bas"
        original.write_text(
            CAC_SETUP + "endTurn()\n" if name == "cac" else
            (game_directory / "players/base.bas").read_text()
        )
        candidate.write_text(
            CAC_SETUP + "if canPlay(0) then\nplayCard(0)\nelse\nendTurn()\nend if\n"
            if name == "cac" else "stop\n"
        )
        source = temporary / f"{name}-source.replay"
        run([executable, "--bot", f"{original}:{seats}", *duration,
             "--record", source])
        recorded = json.loads(run([inspector, name, source]))
        length = len(recorded["hashes"])
        assert length > 2
        if name == "gota":
            test_gota_active_takeover(executable, inspector, source, recorded,
                                     temporary)
        middle = length // 2
        bots = ["--bot", f"{candidate}:{seats}"]
        for cutoff, mixed in ((0, False), (middle, False), (middle, True),
                              (length, False)):
            selected = (["--bot", candidate, "--bot", f"{original}:{seats - 1}"]
                        if mixed else bots)
            branch = temporary / f"{name}-{cutoff}-{mixed}.replay"
            run([executable, "--replay", source, "--resume-step", cutoff,
                 *selected, "--record", branch])
            resumed = json.loads(run([inspector, name, branch]))
            assert resumed["hashes"][:cutoff] == recorded["hashes"][:cutoff]
            prefix = lambda tape: [a for a in tape["actions"] if a["tick"] <= cutoff]
            assert prefix(resumed) == prefix(recorded)
            if cutoff == middle and not mixed:
                assert resumed["actions"] != recorded["actions"], name
            run([executable, "--replay", branch])
        for cutoff in (-1, length + 1):
            run([executable, "--replay", source, "--resume-step", cutoff,
                 *bots], succeeds=False)
        run([executable, "--replay", source, "--resume-step", middle,
             "--bot", f"{candidate}:{seats - 1}"], succeeds=False)
        run([executable, "--resume-step", middle, *bots], succeeds=False)
        run([executable, "--replay", source, "--resume-step", middle],
            succeeds=False)
        print(f"  verified prefix, takeover, replay, and boundaries ({length} ticks)",
              flush=True)

print(f"All BASIC games passed headless resume tests in {time.monotonic() - started:.1f}s")
