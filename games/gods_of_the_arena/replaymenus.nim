import
  silky, windy,
  polyworld/replaymenus as sharedReplayMenus,
  content, replaylibraries, replays

export sharedReplayMenus except drawReplayBrowser

proc drawReplayBrowser*(
  sk: Silky, window: Window, ui: var ReplayBrowserUi,
  entries: openArray[ReplayEntry], folder: string, message = ""
): ReplayBrowserResult =
  ## Supplies GotA's replay version and clock to the shared desktop browser.
  sharedReplayMenus.drawReplayBrowser(
    sk, window, ui, entries, folder, ReplayGameVersion, TickRate, message
  )

proc drawReplayBrowser*(
  sk: Silky, window: Window, browser: var ReplayBrowserState
): ReplayBrowserResult =
  ## Supplies GotA's replay metadata to the shared library controller.
  sharedReplayMenus.drawReplayBrowser(
    sk, window, browser, ReplayGameVersion, TickRate
  )
