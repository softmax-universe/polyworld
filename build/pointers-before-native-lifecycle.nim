import
  windy,
  polyworld/[displays, rtscameras]

var cursorEdgeScrolling = FullscreenEdgeScroll

proc cursorConfinementAllowed*(
    focused, fullscreen, closing: bool,
    mode: EdgeScrollMode
): bool =
  ## Keeps the visible pointer confined whenever edge scrolling is enabled.
  focused and not closing and
    rtsEdgePanAllowed(fullscreen, true, false, mode)

when defined(macosx) and not defined(emscripten):
  import windy/platforms/macos/macdefs

  const
    CursorEdgeInset = 8.0
      ## Native points kept clear of resize grips and macOS edge gestures.
    PresentationAutoReveal = (1'u shl 0) or (1'u shl 2) or (1'u shl 11)
      ## Dock, menu bar, and toolbar options that reveal on screen-edge hover.
    PresentationHiddenBars = (1'u shl 1) or (1'u shl 3)
      ## HideDock and HideMenuBar keep both bars unavailable on edge hover.
    PresentationFullscreen = 1'u shl 10
    PresentationAutoHideToolbar = 1'u shl 11

  objc:
    proc setMouseConfinementRect(self: NSWindow, x: NSRect)
      ## Confines the visible cursor using AppKit's window-relative rectangle.
    proc presentationOptions(self: NSApplication): NSApplicationPresentationOptions
      ## Reads the application's requested presentation flags.
    proc isOnActiveSpace(self: NSWindow): bool
      ## Checks whether the native window belongs to the current desktop Space.

  var
    confinedWindow: NSWindow
    confinedBounds: NSRect
    presentationActive: bool
    previousPresentation, appliedPresentation: NSApplicationPresentationOptions

  proc fullscreenPresentation(
      options: NSApplicationPresentationOptions
  ): NSApplicationPresentationOptions =
    ## Disables edge reveal while preserving fullscreen and app switching.
    (options and not PresentationAutoReveal) or PresentationHiddenBars

  proc availablePresentation(
      options: NSApplicationPresentationOptions
  ): NSApplicationPresentationOptions =
    ## Removes fullscreen-only flags after the native window leaves fullscreen.
    result = options
    if confinedWindow.int == 0 or not confinedWindow.isVisible or
      not confinedWindow.isOnActiveSpace or
      (confinedWindow.styleMask and NSWindowStyleMaskFullScreen) == 0:
        result = result and not (
          PresentationFullscreen or PresentationAutoHideToolbar
        )

  proc releaseFullscreenPresentation() =
    ## Restores our override unless AppKit has already changed display modes.
    if presentationActive:
      if NSApp.presentationOptions() == appliedPresentation:
        NSApp.setPresentationOptions(availablePresentation(previousPresentation))
      presentationActive = false

  proc updateFullscreenPresentation(fullscreen: bool) =
    ## Suppresses macOS edge overlays only during confined fullscreen play.
    if not fullscreen:
      releaseFullscreenPresentation()
      return
    let current = NSApp.presentationOptions()
    if not presentationActive:
      previousPresentation = current
      presentationActive = true
    appliedPresentation = availablePresentation(fullscreenPresentation(current))
    if current != appliedPresentation:
      NSApp.setPresentationOptions(appliedPresentation)

  proc cursorConfinementBounds(view: NSView): NSRect =
    ## Keeps edge scrolling inside the content and away from native controls.
    let
      bounds = view.bounds
      inset = min(CursorEdgeInset,
        min(bounds.size.width, bounds.size.height) / 4)
    result = NSMakeRect(
      bounds.origin.x + inset,
      bounds.origin.y + inset,
      max(bounds.size.width - 2 * inset, 0),
      max(bounds.size.height - 2 * inset, 0)
    )
    result.origin = view.convertPoint(result.origin, NSView(0))

proc releaseCursorConfinement*() =
  ## Restores normal pointer movement when GotA loses focus or closes.
  when defined(macosx) and not defined(emscripten):
    releaseFullscreenPresentation()
    if confinedWindow.int != 0:
      confinedWindow.setMouseConfinementRect(NSRect())
      confinedWindow.ID.release()
      confinedWindow = NSWindow(0)
      confinedBounds = NSRect()

proc updateCursorConfinement*(window: Window) =
  ## Refreshes confinement using the current setting, including focus changes.
  when defined(macosx) and not defined(emscripten):
    if not cursorConfinementAllowed(
      window.focused,
      window.isFullscreen,
      window.closeRequested,
      cursorEdgeScrolling
    ):
      releaseCursorConfinement()
      return
    let native = window.nativeWindow
    if native.int == 0:
      releaseCursorConfinement()
      return
    if native.int != confinedWindow.int:
      releaseCursorConfinement()
      confinedWindow = native
      confinedWindow.ID.retain()
    updateFullscreenPresentation(window.isFullscreen)
    let bounds = cursorConfinementBounds(native.contentView)
    if bounds != confinedBounds:
      native.setMouseConfinementRect(bounds)
      confinedBounds = bounds

proc updateCursorConfinement*(window: Window, mode: EdgeScrollMode) =
  ## Remembers the preference so focus callbacks restore the same confinement.
  cursorEdgeScrolling = mode
  window.updateCursorConfinement()
