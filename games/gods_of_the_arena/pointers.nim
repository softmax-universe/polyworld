import
  windy,
  polyworld/[displays, rtscameras]

var cursorEdgeScrolling = FullscreenEdgeScroll

proc updateCursorConfinement*(window: Window)
  ## Refreshes native confinement after focus and fullscreen changes.

proc cursorConfinementAllowed*(
    focused, fullscreen, closing: bool,
    mode: EdgeScrollMode
): bool =
  ## Keeps the visible pointer confined whenever edge scrolling is enabled.
  focused and not closing and
    rtsEdgePanAllowed(fullscreen, true, false, mode)

when defined(macosx) and not defined(emscripten):
  import windy/platforms/macos/macdefs

  const WindowListIncludingWindow = 1'u32 shl 3

  objc:
    proc setMouseConfinementRect(self: NSWindow, x: NSRect)
      ## Confines the visible cursor using AppKit's window-relative rectangle.
    proc convertRect(self: NSView, x: NSRect, toView: NSView): NSRect
      ## Converts the complete view rectangle into window points.
    proc performSelector(self: ID, x: SEL, withObject: ID, afterDelay: float64)
      ## Defers confinement until AppKit services its next event-loop turn.
    proc windowNumber(self: NSWindow): int
      ## Identifies only this application's window in WindowServer metadata.
    proc objectForKey(self: NSDictionary, x: ID): ID
      ## Reads one value from the native window metadata dictionary.
    proc boolValue(self: ID): bool
      ## Reads whether WindowServer has placed the window onscreen.
    proc isMovable(self: NSWindow): bool
      ## Reads whether native window dragging is enabled.
    proc setMovable(self: NSWindow, x: bool)
      ## Enables or disables native window dragging.

  proc CGWindowListCopyWindowInfo(options, window: uint32): pointer
      {.cdecl, importc.}
    ## Copies server metadata for the specified window without capturing pixels.
  proc CGRectMakeWithDictionaryRepresentation(
      dictionary: pointer, rect: ptr NSRect
  ): uint8 {.cdecl, importc.}
    ## Decodes the server's rectangle in screen points.
  proc CFRelease(value: pointer) {.cdecl, importc.}
    ## Releases copied Core Foundation metadata.

  var
    kCGWindowBounds {.importc.}: pointer
    kCGWindowIsOnscreen {.importc.}: pointer
    confinedWindow: NSWindow
    confinedBounds, confinedFrame, confinedBacking: NSRect
    pointerWindow: Window
    deferredWindow: Window
    confinementUpdater: ID
    confinementScheduled: bool
    updatingPointer: bool
    controlsLocked, previousMovable, previousResizable: bool
    controlsWindow: NSWindow

  proc cursorConfinementBounds(view: NSView): NSRect =
    ## Uses window points, independently of the Retina framebuffer dimensions.
    view.convertRect(view.bounds, NSView(0))

  proc confinementGeometryChanged(native: NSWindow): bool =
    ## Detects native geometry changes even when point bounds stay identical.
    native.int != confinedWindow.int or
      cursorConfinementBounds(native.contentView) != confinedBounds or
      native.frame != confinedFrame or
      native.contentView.convertRectToBacking(native.contentView.bounds) !=
        confinedBacking

  proc windowServerFrame(frame: NSRect, desktopTop: float64): NSRect =
    ## Converts AppKit's bottom-left screen points to WindowServer screen points.
    NSMakeRect(frame.origin.x,
      desktopTop - frame.origin.y - frame.size.height,
      frame.size.width, frame.size.height)

  proc confinementFramesMatch(expected, actual: NSRect): bool =
    ## Allows server rounding while rejecting an old or intermediate window size.
    expected.size.width > 0 and expected.size.height > 0 and
      actual.size.width > 0 and actual.size.height > 0 and
      abs(expected.origin.x - actual.origin.x) <= 1 and
      abs(expected.origin.y - actual.origin.y) <= 1 and
      abs(expected.size.width - actual.size.width) <= 1 and
      abs(expected.size.height - actual.size.height) <= 1

  proc nativeWindowGeometryCommitted(native: NSWindow): bool =
    ## Waits for actual server geometry instead of AppKit's eagerly updated frame.
    if not native.isVisible:
      return false
    let screens = NSScreen.screens
    if screens.count == 0:
      return false
    let
      primary = screens.objectAtIndex(0).NSScreen.frame
      expected = windowServerFrame(native.frame,
        primary.origin.y + primary.size.height)
      info = CGWindowListCopyWindowInfo(WindowListIncludingWindow,
        native.windowNumber.uint32)
    if info == nil:
      return false
    defer: CFRelease(info)
    let windows = cast[NSArray](info)
    if windows.count != 1:
      return false
    let metadata = windows.objectAtIndex(0).NSDictionary
    if not metadata.objectForKey(cast[ID](kCGWindowIsOnscreen)).boolValue:
      return false
    let bounds = metadata.objectForKey(cast[ID](kCGWindowBounds))
    var actual: NSRect
    if bounds.int == 0 or
      CGRectMakeWithDictionaryRepresentation(cast[pointer](bounds),
        addr actual) == 0:
        return false
    confinementFramesMatch(expected, actual)

  proc restoreWindowControls() =
    ## Restores only the controls owned by confinement in settled windowed mode.
    if not controlsLocked or controlsWindow.int == 0:
      return
    if (controlsWindow.styleMask and NSWindowStyleMaskFullScreen) != 0:
      return
    let native = controlsWindow
    controlsLocked = false
    controlsWindow = NSWindow(0)
    native.setMovable(previousMovable)
    let mask = native.styleMask
    native.setStyleMask(
      if previousResizable: mask or NSWindowStyleMaskResizable
      else: mask and not NSWindowStyleMaskResizable
    )
    discard native.makeFirstResponder(native.contentView)
    native.ID.release()

  proc lockWindowControls() =
    ## Removes native drag and resize handles only in settled windowed mode.
    if confinedWindow.int == 0 or
      (confinedWindow.styleMask and NSWindowStyleMaskFullScreen) != 0:
        return
    if not controlsLocked:
      controlsWindow = confinedWindow
      controlsWindow.ID.retain()
      previousMovable = confinedWindow.isMovable
      previousResizable =
        (confinedWindow.styleMask and NSWindowStyleMaskResizable) != 0
      controlsLocked = true
    if controlsWindow.int != confinedWindow.int:
      return
    confinedWindow.setMovable(false)
    let mask = confinedWindow.styleMask
    if (mask and NSWindowStyleMaskResizable) != 0:
      confinedWindow.setStyleMask(mask and not NSWindowStyleMaskResizable)
      discard confinedWindow.makeFirstResponder(confinedWindow.contentView)

proc releaseCursorConfinement*() =
  ## Restores normal pointer movement when GotA loses focus or closes.
  when defined(macosx) and not defined(emscripten):
    let wasUpdating = updatingPointer
    updatingPointer = true
    defer: updatingPointer = wasUpdating
    deferredWindow = nil
    restoreWindowControls()
    if confinedWindow.int != 0:
      confinedWindow.setMouseConfinementRect(NSRect())
      confinedWindow.ID.release()
      confinedWindow = NSWindow(0)
      confinedBounds = NSRect()
      confinedFrame = NSRect()
      confinedBacking = NSRect()

when defined(macosx) and not defined(emscripten):
  proc updateNativeConfinement(
      native: NSWindow, focused, fullscreen, closing: bool,
      mode: EdgeScrollMode
  ) =
    ## Applies one native capture state without changing relative mouse input.
    if updatingPointer:
      return
    updatingPointer = true
    defer: updatingPointer = false
    if controlsLocked and controlsWindow.int != native.int:
      restoreWindowControls()
    if not cursorConfinementAllowed(focused, fullscreen, closing, mode) or
      native.int == 0:
        releaseCursorConfinement()
        return
    if native.int != confinedWindow.int:
      releaseCursorConfinement()
      confinedWindow = native
      confinedWindow.ID.retain()
    if not fullscreen:
      lockWindowControls()
    if native.confinementGeometryChanged():
      # AppKit can retain the pre-resize clip despite reporting the new rect.
      native.setMouseConfinementRect(NSRect())
      confinedBounds = cursorConfinementBounds(native.contentView)
      confinedFrame = native.frame
      confinedBacking =
        native.contentView.convertRectToBacking(native.contentView.bounds)
      native.setMouseConfinementRect(confinedBounds)

  proc refreshCursorConfinement(window: Window, afterEvents: bool)
    ## Rechecks capture policy and native geometry after deferred work.

  proc applyDeferredConfinement(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
    ## Applies only the latest request after the native resize has been serviced.
    let window = deferredWindow
    deferredWindow = nil
    confinementScheduled = false
    if window != nil and not window.closed:
      refreshCursorConfinement(window, true)

  proc deferCursorConfinement(window: Window) =
    ## Coalesces geometry changes without pumping events inside game callbacks.
    if deferredWindow == window:
      return
    releaseCursorConfinement()
    deferredWindow = window
    if confinementUpdater.int == 0:
      var cls: Class
      addClass "GotaConfinementUpdater", "NSObject", cls:
        addMethod "applyConfinement:", applyDeferredConfinement
      confinementUpdater = cls.new()
    if not confinementScheduled:
      confinementScheduled = true
      confinementUpdater.performSelector(s("applyConfinement:"), ID(0), 0)

  proc installPointerHooks(window: Window) =
    ## Connects cursor capture to the shared fullscreen lifecycle.
    if pointerWindow == window:
      return
    releaseCursorConfinement()
    window.setFullscreenCallbacks(
      proc() =
        releaseCursorConfinement(),
      proc() =
        window.updateCursorConfinement()
    )
    pointerWindow = window

  proc refreshCursorConfinement(window: Window, afterEvents: bool) =
    ## Waits for AppKit before rebuilding confinement after native resizes.
    if updatingPointer or window.closed or window.desktopFullscreenChanging:
      return
    installPointerHooks(window)
    let previousFrame = window.nativeWindow.frame
    updatingPointer = true
    try:
      window.updateDesktopFullscreen()
    finally:
      updatingPointer = false
    if window.closed:
      releaseCursorConfinement()
      return
    let
      native = window.nativeWindow
      focused = window.focused and NSApp.isActive
    if not cursorConfinementAllowed(focused, window.isFullscreen,
        window.closeRequested, cursorEdgeScrolling):
      releaseCursorConfinement()
      return
    if native.confinementGeometryChanged() and
      (not afterEvents or native.frame != previousFrame):
        deferCursorConfinement(window)
        return
    if native.confinementGeometryChanged() and
      not native.nativeWindowGeometryCommitted():
        # Retry on the next game frame, letting AppKit commit this run-loop turn.
        # Requeuing a zero-delay selector here can prevent that commit entirely.
        return
    updateNativeConfinement(native, focused, window.isFullscreen,
      window.closeRequested, cursorEdgeScrolling)

proc cursorConfined*(window: Window): bool =
  ## Includes the full native boundary when deciding whether edge pan is active.
  when defined(macosx) and not defined(emscripten):
    window.focused and NSApp.isActive and
      not window.desktopFullscreenChanging and
      confinedWindow.int != 0 and
      window.nativeWindow.int == confinedWindow.int
  else:
    false

proc updateCursorConfinement*(window: Window) =
  ## Refreshes confinement using the current setting, including focus changes.
  when defined(macosx) and not defined(emscripten):
    refreshCursorConfinement(window, false)

proc updateCursorConfinement*(window: Window, mode: EdgeScrollMode) =
  ## Remembers the preference so focus callbacks restore the same confinement.
  cursorEdgeScrolling = mode
  window.updateCursorConfinement()
