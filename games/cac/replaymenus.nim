import
  silky, windy,
  polyworld/replaymenus as sharedReplayMenus,
  core/replays, replaylibraries

export sharedReplayMenus except drawReplayBrowser

proc drawReplayBrowser*(
  sk: Silky, window: Window, ui: var ReplayBrowserUi,
  entries: openArray[ReplayEntry], folder: string, message = ""
): ReplayBrowserResult =
  ## Shows CaC recordings by accepted action count rather than elapsed time.
  sharedReplayMenus.drawReplayBrowser(
    sk, window, ui, entries, folder, ReplayGameVersion, 1, message,
    lengthDisplay = ReplayActionCount
  )
