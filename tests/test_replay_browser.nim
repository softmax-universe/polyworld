import
  std/[os, strutils, tempfiles],
  polyworld/[replaylibraries, replaymenus, tapes]

type BrowserReplay = object
  formatVersion, gameVersion: uint16
  ticks: int

proc inspectBrowserReplay(bytes: string): int =
  ## Decodes a small fixture through the real shared replay container.
  decodeReplayFile("browser_test", 7, bytes, BrowserReplay).ticks

const BrowserLibrary = ReplayLibrary(
  gameFolder: "Replay browser test",
  gamePrefix: "Test",
  format: ReplayLibraryFormat(
    game: "browser_test", gameVersion: 7, tapeVersion: 2,
    maxBytes: DefaultMaxReplayBytes
  ),
  inspect: inspectBrowserReplay
)

proc browserBytes(version = 7'u16): string =
  ## Produces current or obsolete fixtures with matching outer and inner versions.
  encodeReplayFile("browser_test", version,
    BrowserReplay(formatVersion: 2, gameVersion: version, ticks: 42))

proc testReplayBrowser() =
  ## Exercises shared refresh, import, stale-file validation, and error recovery.
  let
    root = createTempDir("polyworld-replay-browser-", "")
    folder = root / "library with spaces"
    source = root / "source.replay"
    bytes = browserBytes()
  defer:
    removeDir(root)
  var browser = initReplayBrowser(BrowserLibrary, directory = folder)
  doAssert not dirExists(folder)
  doAssert browser.refreshRequested
  doAssert browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult()).action == StayReplayBrowser
  doAssert dirExists(folder)
  doAssert not browser.refreshRequested
  doAssert browser.entries.len == 0

  writeFile(source, bytes)
  browser.importBrowserReplay(BrowserLibrary, source)
  let imported = browser.ui.selectedPath
  doAssert imported.parentDir == folder
  doAssert readFile(source) == bytes
  doAssert browser.refreshRequested
  doAssert browser.message == "Replay imported."
  discard browser.updateReplayBrowser(BrowserLibrary, ReplayBrowserResult())
  doAssert browser.entries.len == 1
  doAssert browser.entries[0].ticks == 42
  doAssert browser.entries[0].playable
  doAssert browser.ui.selectedPath == imported
  let chosen = browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: PlayReplay, path: imported))
  doAssert chosen.action == PlayReplay and chosen.path == imported

  browser.importBrowserReplay(BrowserLibrary, "")
  doAssert browser.ui.selectedPath == imported
  doAssert not browser.refreshRequested
  doAssert browser.entries.len == 1

  writeFile(imported, browserBytes(6))
  doAssert browser.entries[0].playable
  doAssert browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: PlayReplay, path: imported)
  ).action == StayReplayBrowser
  doAssert "Game version 6" in browser.message
  discard browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: RefreshReplays))
  doAssert browser.message.len == 0
  doAssert not browser.entries[0].playable
  doAssert browser.entries[0].gameVersion == 6

  let obsolete = root / "obsolete.replay"
  writeFile(obsolete, browserBytes(6))
  browser.importBrowserReplay(BrowserLibrary, obsolete)
  discard browser.updateReplayBrowser(BrowserLibrary, ReplayBrowserResult())
  doAssert browser.entries.len == 2
  for entry in browser.entries:
    doAssert not entry.playable
  doAssert readFile(obsolete) == browserBytes(6)

  removeFile(imported)
  doAssert browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: PlayReplay, path: imported)
  ).action == StayReplayBrowser
  doAssert browser.message.len > 0
  doAssert browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: BackFromReplays)
  ).action == BackFromReplays
  doAssert browser.message.len == 0

  browser.folder = source / "not a directory"
  discard browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: RefreshReplays))
  doAssert browser.message.len > 0
  doAssert not browser.refreshRequested
  doAssert browser.entries.len == 2
  doAssert readFile(source) == bytes
  browser.folder = folder
  discard browser.updateReplayBrowser(BrowserLibrary,
    ReplayBrowserResult(action: RefreshReplays))
  doAssert browser.message.len == 0
  doAssert browser.entries.len == 1

testReplayBrowser()
echo "Shared replay browser imports, refreshes, and playback validation passed."
