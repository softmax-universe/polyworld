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

  const
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
    proc isMovable(self: NSWindow): bool
      ## Reads whether native window dragging is enabled.
    proc setMovable(self: NSWindow, x: bool)
      ## Enables or disables native window dragging.

  proc object_setClass(self: ID, cls: Class): Class
      {.cdecl, importc, dynlib: "libobjc.dylib".}
    ## Adds Gota's delegate hooks without changing the window's storage.

  var
    confinedWindow: NSWindow
    confinedBounds: NSRect
    presentationActive: bool
    previousPresentation, appliedPresentation: NSApplicationPresentationOptions
    pointerWindow: Window
    pointerClass, pointerSuperclass: Class
    pointerTransition, updatingPointer: bool
    controlsLocked, previousMovable, previousResizable: bool
    controlsWindow: NSWindow

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
    appliedPresentation = availablePresentation(
      fullscreenPresentation(current or PresentationFullscreen)
    )
    if current != appliedPresentation:
      NSApp.setPresentationOptions(appliedPresentation)

  proc cursorConfinementBounds(view: NSView): NSRect =
    ## Confines the native cursor to the full content area without an inset.
    result = view.bounds
    result.origin = view.convertPoint(result.origin, NSView(0))

  proc restoreWindowControls() =
    ## Restores only the controls owned by confinement in settled windowed mode.
    if not controlsLocked or controlsWindow.int == 0:
      return
    if pointerTransition or
      (controlsWindow.styleMask and NSWindowStyleMaskFullScreen) != 0:
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
    native.ID.release()

  proc lockWindowControls() =
    ## Removes native drag and resize handles only in settled windowed mode.
    if pointerTransition or confinedWindow.int == 0 or
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

proc releaseCursorConfinement*() =
  ## Restores normal pointer movement when GotA loses focus or closes.
  when defined(macosx) and not defined(emscripten):
    let wasUpdating = updatingPointer
    updatingPointer = true
    defer: updatingPointer = wasUpdating
    releaseFullscreenPresentation()
    restoreWindowControls()
    if confinedWindow.int != 0:
      confinedWindow.setMouseConfinementRect(NSRect())
      confinedWindow.ID.release()
      confinedWindow = NSWindow(0)
      confinedBounds = NSRect()

when defined(macosx) and not defined(emscripten):
  proc updateNativeConfinement(
      native: NSWindow, focused, fullscreen, closing: bool,
      mode: EdgeScrollMode
  ) =
    ## Applies one native capture state without changing relative mouse input.
    if updatingPointer or pointerTransition:
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
    updateFullscreenPresentation(fullscreen)
    let bounds = cursorConfinementBounds(native.contentView)
    if bounds != confinedBounds:
      native.setMouseConfinementRect(bounds)
      confinedBounds = bounds

  proc callWindowSuper(self: ID, cmd: SEL, argument: ID) =
    ## Preserves Windy's window state and callbacks before Gota refreshes input.
    var parent = objc_super(receiver: self, super_class: pointerSuperclass)
    cast[proc(parent: ptr objc_super, cmd: SEL, argument: ID) {.cdecl.}](
      objc_msgSendSuper
    )(parent.addr, cmd, argument)

  proc ownsPointerWindow(self: ID): bool =
    ## Limits the hooks to the live Gota window that installed them.
    pointerWindow != nil and not pointerWindow.closed and
      pointerWindow.nativeWindow.int == self.int

  proc beginPointerTransition() =
    ## Releases resize locking before AppKit starts its fullscreen animation.
    releaseCursorConfinement()
    pointerTransition = true

  proc togglePointerFullscreen(self: ID, cmd: SEL, sender: ID) {.cdecl.} =
    ## Unlocks the window before AppKit checks whether fullscreen is allowed.
    if ownsPointerWindow(self):
      beginPointerTransition()
    callWindowSuper(self, cmd, sender)

  proc pointerWillTransition(
      self: ID, cmd: SEL, notification: NSNotification
  ) {.cdecl.} =
    ## Also handles fullscreen changes initiated by native window controls.
    if ownsPointerWindow(self) and not pointerTransition:
      beginPointerTransition()

  proc pointerDidTransition(
      self: ID, cmd: SEL, notification: NSNotification
  ) {.cdecl.} =
    ## Reapplies confinement even if resize delivered the final bounds earlier.
    callWindowSuper(self, cmd, notification.ID)
    if ownsPointerWindow(self):
      pointerTransition = false
      let wasUpdating = updatingPointer
      updatingPointer = true
      restoreWindowControls()
      updatingPointer = wasUpdating
      confinedBounds = NSRect()
      pointerWindow.updateCursorConfinement()

  proc pointerFailedTransition(
      self: ID, cmd: SEL, native: NSWindow
  ) {.cdecl.} =
    ## Restores capture when AppKit declines a fullscreen transition.
    if ownsPointerWindow(self):
      pointerTransition = false
      cancelWindowTransition()
      let wasUpdating = updatingPointer
      updatingPointer = true
      restoreWindowControls()
      updatingPointer = wasUpdating
      confinedBounds = NSRect()
      pointerWindow.updateCursorConfinement()

  proc pointerFullscreenPresentation(
      self: ID, cmd: SEL, native: NSWindow,
      proposed: NSApplicationPresentationOptions
  ): NSApplicationPresentationOptions {.cdecl.} =
    ## Supplies fullscreen rules through AppKit's per-window delegate hook.
    result = proposed
    if ownsPointerWindow(self) and cursorEdgeScrolling != NoEdgeScroll:
      if not presentationActive:
        previousPresentation = proposed
      appliedPresentation = fullscreenPresentation(proposed)
      presentationActive = true
      result = appliedPresentation

  proc installPointerHooks(window: Window) =
    ## Extends only Gota's native window while retaining Windy's delegate.
    if pointerWindow == window:
      return
    releaseCursorConfinement()
    pointerTransition = false
    pointerWindow = window
    let native = window.nativeWindow
    if pointerClass.int == 0:
      pointerSuperclass = object_getClass(native.ID)
      addClass "GotaPointerWindow", $pointerSuperclass, pointerClass:
        addMethod "toggleFullScreen:", togglePointerFullscreen
        addMethod "windowWillEnterFullScreen:", pointerWillTransition
        addMethod "windowWillExitFullScreen:", pointerWillTransition
        addMethod "windowDidEnterFullScreen:", pointerDidTransition
        addMethod "windowDidExitFullScreen:", pointerDidTransition
        addMethod "windowDidFailToEnterFullScreen:", pointerFailedTransition
        addMethod "windowDidFailToExitFullScreen:", pointerFailedTransition
        addMethod "window:willUseFullScreenPresentationOptions:",
          pointerFullscreenPresentation
    discard object_setClass(native.ID, pointerClass)
    native.setDelegate(ID(0))
    native.setDelegate(native.ID)

proc cursorConfined*(window: Window): bool =
  ## Includes the full native boundary when deciding whether edge pan is active.
  when defined(macosx) and not defined(emscripten):
    window.focused and not pointerTransition and
      confinedWindow.int != 0 and
      window.nativeWindow.int == confinedWindow.int
  else:
    false

proc updateCursorConfinement*(window: Window) =
  ## Refreshes confinement using the current setting, including focus changes.
  when defined(macosx) and not defined(emscripten):
    if updatingPointer or window.closed:
      return
    installPointerHooks(window)
    updateNativeConfinement(window.nativeWindow, window.focused,
      window.isFullscreen, window.closeRequested, cursorEdgeScrolling)

proc updateCursorConfinement*(window: Window, mode: EdgeScrollMode) =
  ## Remembers the preference so focus callbacks restore the same confinement.
  cursorEdgeScrolling = mode
  window.updateCursorConfinement()
