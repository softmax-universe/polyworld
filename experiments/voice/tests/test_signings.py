"""Checks signing identity selection without keychain or application access."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    """Exercises the shared signing script against isolated tool substitutes."""
    source = Path(__file__).resolve().parents[1] / "sign.sh"
    first = "A" * 40
    second = "B" * 40
    with tempfile.TemporaryDirectory(prefix="voice-signing-test-") as directory:
        root = Path(directory)
        security = root / "security"
        codesign = root / "codesign"
        script = root / "sign.sh"
        arguments = root / "arguments.json"
        security.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$SIGNING_TEST_IDENTITIES\"\n"
            "exit \"${SIGNING_TEST_SECURITY_EXIT:-0}\"\n"
        )
        codesign.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "Path(os.environ['SIGNING_TEST_ARGUMENTS']).write_text(\n"
            "    json.dumps(sys.argv[1:]))\n"
            "sys.exit(int(os.environ.get('SIGNING_TEST_CODESIGN_EXIT', '0')))\n"
        )
        security.chmod(0o755)
        codesign.chmod(0o755)
        script.write_text(
            source.read_text()
            .replace("/usr/bin/security", str(security))
            .replace("/usr/bin/codesign", str(codesign))
        )
        app = str(root / "App with spaces.app")

        def sign(identities, identity=None, securityExit=0, codesignExit=0):
            """Runs only the substitutes and returns captured signing arguments."""
            environment = os.environ.copy()
            environment.pop("VOICE_SIGNING_IDENTITY", None)
            environment.update(
                SIGNING_TEST_IDENTITIES=identities,
                SIGNING_TEST_ARGUMENTS=str(arguments),
                SIGNING_TEST_SECURITY_EXIT=str(securityExit),
                SIGNING_TEST_CODESIGN_EXIT=str(codesignExit),
            )
            if identity is not None:
                environment["VOICE_SIGNING_IDENTITY"] = identity
            arguments.unlink(missing_ok=True)
            result = subprocess.run(
                ["/bin/sh", str(script), app],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            selected = json.loads(arguments.read_text()) if arguments.exists() else None
            return result, selected

        one = f'  1) {first} "Apple Development: Local Developer"\n'
        result, selected = sign(one + "     1 valid identities found\n")
        assert result.returncode == 0, result.stderr
        assert selected == ["--force", "--sign", first, "--timestamp=none", app]

        result, selected = sign(one + f'  2) {first} "Duplicate keychain"\n')
        assert result.returncode == 0, result.stderr
        assert selected[2] == first

        result, selected = sign("     0 valid identities found\n")
        assert result.returncode == 0, result.stderr
        assert selected[2] == "-"
        assert "ad-hoc" in result.stderr

        result, selected = sign(one + f'  2) {second} "Other Developer"\n')
        assert result.returncode != 0
        assert selected is None
        assert "VOICE_SIGNING_IDENTITY" in result.stderr

        explicit = "Apple Development: Example 'quoted' $(not-executed)"
        result, selected = sign("", identity=explicit, securityExit=2)
        assert result.returncode == 0, result.stderr
        assert selected[2] == explicit

        result, selected = sign(one, securityExit=2)
        assert result.returncode == 2
        assert selected is None

        result, selected = sign(one, codesignExit=3)
        assert result.returncode == 3
        assert selected[2] == first

    print("Signing selection checks passed; no keychain or app was accessed.")


if __name__ == "__main__":
    main()
