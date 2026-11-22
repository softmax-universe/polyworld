## Click-initiated native cursor confinement for shared game windows.

import
  windy,
  polyworld/[displays, rtscameras]

var cursorEdgeScrolling = FullscreenEdgeScroll

proc updateCursorConfinement*(window: Window)
  ## Releases an existing clip when focus, policy or native geometry changes.

proc cursorConfinementClick*(button: Button): bool =
  ## Recognizes physical mouse presses without treating scroll or keys as clicks.
  button in {MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5}

proc cursorConfinementAllowed*(
    focused, fullscreen, closing: bool,
    mode: EdgeScrollMode
): bool =
  ## Allows click-initiated confinement only while edge scrolling is enabled.
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
    proc inLiveResize(self: NSView): bool
      ## Rejects clicks while AppKit is still resizing the content view.
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
    confinedFullscreen: bool
    pointerWindow: Window
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
  ## Clears the click latch and native clip before restoring window controls.
  when defined(macosx) and not defined(emscripten):
    let wasUpdating = updatingPointer
    updatingPointer = true
    defer: updatingPointer = wasUpdating
    let native = confinedWindow
    confinedWindow = NSWindow(0)
    confinedBounds = NSRect()
    confinedFrame = NSRect()
    confinedBacking = NSRect()
    confinedFullscreen = false
    if native.int != 0:
      native.setMouseConfinementRect(NSRect())
    restoreWindowControls()
    if native.int != 0:
      native.ID.release()

when defined(macosx) and not defined(emscripten):
  proc updateNativeConfinement(
      native: NSWindow, focused, fullscreen, closing: bool,
      mode: EdgeScrollMode, clicked = false, settled = true,
      owner: Window = nil
  ) =
    ## Only a settled click creates a clip; passive updates can only release it.
    if updatingPointer:
      return
    updatingPointer = true
    defer: updatingPointer = false
    if controlsLocked and controlsWindow.int != native.int:
      releaseCursorConfinement()
    if not cursorConfinementAllowed(focused, fullscreen, closing, mode) or
      native.int == 0 or not settled:
        releaseCursorConfinement()
        return
    if confinedWindow.int != 0 and
      (native.int != confinedWindow.int or
      fullscreen != confinedFullscreen or native.confinementGeometryChanged()):
        releaseCursorConfinement()
    if not clicked or confinedWindow.int != 0:
      return
    let
      view = native.contentView
      frame = native.frame
      bounds = cursorConfinementBounds(view)
      backing = view.convertRectToBacking(view.bounds)
    if bounds.size.width <= 0 or bounds.size.height <= 0:
      return
    view.ID.retain()
    defer: view.ID.release()
    confinedWindow = native
    native.ID.retain()
    if not fullscreen:
      lockWindowControls()
    if confinedWindow.int != native.int:
      return
    if owner != nil and
      (owner.closed or owner.closeRequested or not owner.focused or
      not NSApp.isActive or owner.desktopFullscreenChanging):
        releaseCursorConfinement()
        return
    if native.contentView.int != view.int or native.frame != frame or
      cursorConfinementBounds(view) != bounds or
      view.convertRectToBacking(view.bounds) != backing:
        # Control changes can resize the window; wait for another real click.
        releaseCursorConfinement()
        return
    confinedBounds = bounds
    confinedFrame = frame
    confinedBacking = backing
    confinedFullscreen = fullscreen
    native.setMouseConfinementRect(NSRect())
    native.setMouseConfinementRect(bounds)

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

  proc refreshCursorConfinement(window: Window) =
    ## Maintains a click latch without ever acquiring confinement from a frame.
    if updatingPointer:
      return
    if window == nil or window.closed or window.desktopFullscreenChanging:
      releaseCursorConfinement()
      return
    installPointerHooks(window)
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
    updateNativeConfinement(native, focused, window.isFullscreen,
      window.closeRequested, cursorEdgeScrolling,
      settled = not native.contentView.inLiveResize, owner = window)

proc cursorConfined*(window: Window): bool =
  ## Includes the full native boundary when deciding whether edge pan is active.
  when defined(macosx) and not defined(emscripten):
    window != nil and not window.closed and not window.closeRequested and
      window.focused and NSApp.isActive and
      not window.desktopFullscreenChanging and
      confinedWindow.int != 0 and
      window.nativeWindow.int == confinedWindow.int
  else:
    false

proc updateCursorConfinement*(window: Window) =
  ## Validates an existing click latch without recapturing after a release.
  when defined(macosx) and not defined(emscripten):
    refreshCursorConfinement(window)

proc captureCursorConfinement*(window: Window, button: Button) =
  ## Confines only on a real click in an active window with committed geometry.
  when defined(macosx) and not defined(emscripten):
    if not button.cursorConfinementClick or updatingPointer or
      window == nil or window.closed:
        return
    window.updateCursorConfinement()
    if window.closed or window.desktopFullscreenChanging:
      return
    let
      native = window.nativeWindow
      focused = window.focused and NSApp.isActive
    if not cursorConfinementAllowed(focused, window.isFullscreen,
        window.closeRequested, cursorEdgeScrolling):
      return
    updateNativeConfinement(
      native, focused, window.isFullscreen, window.closeRequested,
      cursorEdgeScrolling,
      clicked = true,
      settled = not native.contentView.inLiveResize and
        native.nativeWindowGeometryCommitted(),
      owner = window
    )

proc updateCursorConfinement*(window: Window, mode: EdgeScrollMode) =
  ## Remembers policy while leaving acquisition to the next eligible click.
  cursorEdgeScrolling = mode
  window.updateCursorConfinement()
