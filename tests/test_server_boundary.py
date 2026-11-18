"""Compile and launch the relay without any game source directories."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    environment = os.environ.copy()
    environment["POLYWORLD_DEPS"] = str(
        Path(environment.get("POLYWORLD_DEPS", root.parent)).resolve()
    )
    with tempfile.TemporaryDirectory(prefix="polyworld-relay-boundary-") as path:
        standalone = Path(path)
        shutil.copytree(root / "src", standalone / "src")
        (standalone / "tools").mkdir()
        for name in ("config.nims", "nimby.lock", "tools/gameserver.nim"):
            shutil.copy2(root / name, standalone / name)
        executable = standalone / ("relay.exe" if os.name == "nt" else "relay")
        subprocess.run(
            [
                "nim", "c", "--hints:off", "--threads:on", "-d:release",
                f"--nimcache:{standalone / 'cache'}", f"--out:{executable}",
                "tools/gameserver.nim",
            ],
            cwd=standalone,
            env=environment,
            check=True,
        )
        result = subprocess.run(
            [str(executable), "--help"], capture_output=True, text=True, check=True
        )
        assert "Usage: gameserver" in result.stdout, result.stdout
        for arguments in (["--port", "0"], ["--port", "65536"], ["--port"]):
            result = subprocess.run(
                [str(executable), *arguments], capture_output=True, timeout=10
            )
            assert result.returncode != 0, arguments
    print("Standalone relay builds and launches without game sources")


if __name__ == "__main__":
    main()
