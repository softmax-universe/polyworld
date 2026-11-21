# Testing

CI runs one bounded unit suite on Linux, macOS, and Windows:

```sh
nim check -d:release tests/unit_tests.nim
nim r -d:release tests/unit_tests.nim
```

Use the pinned dependencies in `nimby.lock`. Each CI job has a five-minute
limit, including setup and compilation. New pushes cancel older runs for the
same branch.

The suite covers command-line and screenshot-option parsing, hashes, random
streams, mailboxes, replay serialization and save recovery, policy packages,
and in-memory room and client state. Screenshot tests check arguments and
capture state only. Tests do not create windows, render images, initialize
audio, start network servers, or simulate full games. The suite intentionally
keeps native command-line semantics, so do not add `-d:headless`.

Full game, integration, rendering, audio, and browser checks remain local and
manual. For the existing combined suite, run:

```sh
nim r -d:release -d:audioTest -d:bassyNativeStrict -d:replayEvents tests/all.nim
```

Run the relevant game's tests or standalone `tests/test_*.nim` and
`tests/manual_*.nim` fixtures locally when changing those systems. Those checks
may need the game's assets and native libraries; they are not CI prerequisites.
