import
  silky, windy,
  polyworld/replaymenus as sharedReplayMenus,
  content, replaylibraries, replays

export sharedReplayMenus except drawReplayBrowser

proc drawReplayBrowser*(
  sk: Silky, window: Window, ui: var ReplayBrowserUi,
  entries: openArray[ReplayEntry], folder: string, message = ""
): ReplayBrowserResult =
  ## Supplies LvD's replay version and clock to the shared desktop browser.
  sharedReplayMenus.drawReplayBrowser(
    sk, window, ui, entries, folder, ReplayGameVersion, TickRate, message
  )
