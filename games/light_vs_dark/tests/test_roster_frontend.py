"""Exercise frontend enablement expressions with Nim, without opening a window.

The expressions are read from the production button calls, not copied into a
parallel model. This guards the wiring from the frontend to its state helper.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
FRONTEND = ROOT / "games/light_vs_dark/frontend.nim"


def expression_after(source, marker):
    tail = source.split(marker, 1)[1]
    return tail.split("):", 1)[0].strip()


class FrontendRosterTests(unittest.TestCase):
    def test_roster_has_no_pager(self):
        source = FRONTEND.read_text()
        roster = source.split("of SingleMenu, LobbyMenu:", 1)[1].split("if online:\n            let info", 1)[0]
        self.assertNotIn('lobbyButton("Previous"', roster)
        self.assertNotIn('lobbyButton("Next"', roster)
        self.assertNotIn("rosterFirst", source)
        self.assertNotIn("RosterPageSize", source)

    def test_local_drafts_and_online_slot_permissions(self):
        source = FRONTEND.read_text()
        seat = expression_after(source, "name, controller, human, empty,\n")
        seat = seat.split(", config.seed", 1)[0]
        fill = expression_after(source, 'fill + vec2(444, 0), 198, "cross",\n')
        scratch = Path(tempfile.gettempdir()) / "polyworld-relay-refactor"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            path = Path(directory) / "roster_gate.nim"
            path.write_text("import games/light_vs_dark/rosterstate\n")
            with path.open("a") as output:
                output.write("var online = false\nlet editable = true\n"
                             "var mine = true\nvar empty = true\nvar owner = true\n"
                             "let modal = false\nlet emptyCount = 1\n"
                             "var roster = RosterState(dirty: true, pendingPayload: \"old\")\n")
                output.write(f'doAssert ({seat}), "local seats are blocked by online draft state"\n')
                output.write(f'doAssert ({fill}), "local Fill is blocked by online draft state"\n')
                output.write("online = true\nroster = RosterState()\n"
                             "mine = false\nempty = false\nowner = true\n")
                output.write(f'doAssert ({seat}), "host cannot manage another controller slot"\n')
                output.write("owner = false\n")
                output.write(f'doAssert not ({seat}), "guest can overwrite another controller slot"\n')
                output.write("mine = true\n")
                output.write(f'doAssert ({seat}), "guest cannot manage their own slot"\n')
                output.write("mine = false\nempty = true\n")
                output.write(f'doAssert ({seat}), "guest cannot claim an empty slot"\n')
            dependencies = []
            dependency_root = Path(os.environ.get("POLYWORLD_DEPS", ROOT.parent))
            for line in (ROOT / "nimby.lock").read_text().splitlines():
                fields = line.split()
                if not fields:
                    continue
                name = fields[0]
                dependency = dependency_root / name
                dependency = dependency / "src" if (dependency / "src").is_dir() else dependency
                dependencies.append(f"--path:{os.environ.get(name.upper() + '_PATH', dependency)}")
            run = subprocess.run(
                ["nim", "r", "--hints:off", "-d:headless", f"--path:{ROOT}",
                 f"--path:{ROOT / 'src'}", *dependencies,
                 f"--nimcache:{directory}/cache", f"-o:{directory}/probe", str(path)],
                cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(run.returncode, 0, run.stdout)


if __name__ == "__main__":
    unittest.main()
