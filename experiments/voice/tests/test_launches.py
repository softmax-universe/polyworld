"""Checks the macOS app launch without connecting or recording audio.

Run with: python3 experiments/voice/tests/test_launches.py
Two short-lived Voice Lab windows will open. Screenshots and completion files
are temporary; the compiled test executable stays in the ignored build folder.
"""

import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


def runCommand(arguments, directory, environment, timeout):
    """Runs one process with bounded execution and captured diagnostics."""
    return subprocess.run(
        arguments,
        cwd=directory,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        check=False,
    )


def main():
    """Verifies clean launch, argument forwarding, and child failure reporting."""
    if sys.platform != "darwin":
        print("Skipping macOS launcher checks on this platform.")
        return

    experimentDir = Path(__file__).resolve().parents[1]
    repositoryDir = experimentDir.parent.parent
    buildDir = experimentDir / "build"
    buildDir.mkdir(exist_ok=True)
    executable = buildDir / "test_voice"
    environment = os.environ.copy()
    for name in (
        "OPENAI_API_KEY",
        "POLYWORLD_VOICE_APPLICATION",
        "POLYWORLD_VOICE_COMPLETION",
    ):
        environment.pop(name, None)

    print("Building the actual Voice Lab entry point.", flush=True)
    compilation = runCommand(
        [
            environment.get("NIM", "nim"),
            "c",
            f"--out:{executable}",
            str(experimentDir / "voice.nim"),
        ],
        repositoryDir,
        environment,
        timeout=180,
    )
    assert compilation.returncode == 0, compilation.stdout

    with tempfile.TemporaryDirectory(prefix="voice-launch-test-") as directory:
        temporaryDir = Path(directory)
        environment["TMPDIR"] = str(temporaryDir) + os.sep
        screenshot = temporaryDir / "preview with spaces.png"
        print("Checking clean app exit and forwarded screenshot path.", flush=True)
        preview = runCommand(
            [
                str(executable),
                "--demo",
                "--frames=3",
                f"--screenshot={screenshot}",
            ],
            repositoryDir,
            environment,
            timeout=60,
        )
        assert preview.returncode == 0, preview.stdout
        assert "Opening Voice Lab" in preview.stdout, preview.stdout
        assert screenshot.is_file(), "The launched app did not save its frame."
        png = screenshot.read_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n", "Screenshot is not a PNG."
        assert png[12:16] == b"IHDR", "Screenshot has no PNG image header."
        width, height = struct.unpack(">II", png[16:24])
        assert width > 0 and height > 0, "Screenshot is empty."
        assert not list(temporaryDir.glob("voice-exit-*.txt")), (
            "The launcher left its completion file after a clean exit."
        )

        invalidScreenshot = temporaryDir / "existing-directory.png"
        invalidScreenshot.mkdir()
        print("Checking that a child failure reaches the terminal.", flush=True)
        failure = runCommand(
            [
                str(executable),
                "--demo",
                "--frames=3",
                f"--screenshot={invalidScreenshot}",
            ],
            repositoryDir,
            environment,
            timeout=60,
        )
        assert failure.returncode != 0, failure.stdout
        assert "exited unexpectedly" in failure.stdout, failure.stdout
        assert invalidScreenshot.is_dir()
        assert not list(temporaryDir.glob("voice-exit-*.txt")), (
            "The launcher left its completion file after a child failure."
        )

    print("macOS launcher checks passed.")


if __name__ == "__main__":
    main()
