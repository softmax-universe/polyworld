import windy

when defined(macosx) and not defined(emscripten):
  import windy/platforms/macos/macdefs

  const
    FullScreenPrimary = 1'u shl 7
    FullScreenAuxiliary = 1'u shl 8
    FullScreenNone = 1'u shl 9
    MainMenuWindowLevelKey = 8
    PresentationAutoReveal = (1'u shl 0) or (1'u shl 2) or (1'u shl 11)
    PresentationHiddenBars = (1'u shl 1) or (1'u shl 3)
    PresentationFullscreen = 1'u shl 10
    PresentationAutoHideToolbar = 1'u shl 11

  type
    NSNotificationCenter = distinct NSObject
    DesktopFullscreen = ref object
      window: Window
      active, changing, updating: bool
      beforeChange, afterChange: proc()
      frame: NSRect
      style: NSWindowStyleMask
      level: NSWindowLevel
      movable, shadow, hides, mouseMoved: bool

  objc:
    proc collectionBehavior(self: NSWindow): uint
      ## Reads the window's desktop and native fullscreen participation.
    proc setCollectionBehavior(self: NSWindow, x: uint)
      ## Prevents native fullscreen Spaces from bypassing the shared backend.
    proc isMovable(self: NSWindow): bool
      ## Reads the original permission to move the window.
    proc setMovable(self: NSWindow, x: bool)
      ## Disables dragging while the window covers the display.
    proc hasShadow(self: NSWindow): bool
      ## Reads the shadow state to restore when leaving fullscreen.
    proc setHasShadow(self: NSWindow, x: bool)
      ## Removes the shadow of the monitor-sized borderless window.
    proc hidesOnDeactivate(self: NSWindow): bool
      ## Reads whether AppKit hides the window when another app activates.
    proc setHidesOnDeactivate(self: NSWindow, x: bool)
      ## Lets Cmd-Tab hide and restore fullscreen without minimizing it.
    proc acceptsMouseMovedEvents(self: NSWindow): bool
      ## Reads whether the window requests continuous native pointer motion.
    proc setAcceptsMouseMovedEvents(self: NSWindow, x: bool)
      ## Requests movement even when no mouse button is held.
    proc makeMainWindow(self: NSWindow)
      ## Keeps the borderless game as the application's primary input window.
    proc isOnActiveSpace(self: NSWindow): bool
      ## Checks whether the window belongs to the current desktop Space.
    proc windows(self: NSApplication): NSArray
      ## Finds any remaining native fullscreen window before restoring flags.
    proc presentationOptions(self: NSApplication): NSApplicationPresentationOptions
      ## Reads the app's current requested Dock and menu-bar policy.
    proc defaultCenter(class: typedesc[NSNotificationCenter]): NSNotificationCenter
      ## Returns the process notification center for app activity changes.
    proc addObserver(
      self: NSNotificationCenter, x: ID, selector: SEL,
      name: NSString, object_mangle: ID
    )
      ## Observes app activation and window cleanup independently of game code.

  proc notificationObject(notification: NSNotification): ID =
    ## Reads the native object without using Nim's reserved object keyword.
    cast[proc(self: NSNotification, cmd: SEL): ID {.cdecl.}](objc_msgSend)(
      notification, s("object")
    )

  proc CGWindowLevelForKey(key: cint): int32 {.cdecl, importc.}
    ## Resolves the system menu window level without hardcoding its value.

  proc class_getMethodImplementation(cls: Class, selector: SEL): IMP
      {.cdecl, importc, dynlib: "libobjc.dylib".}
    ## Preserves Windy's original callback implementations before wrapping them.

  proc class_replaceMethod(
      cls: Class, selector: SEL, implementation: IMP, encoding: cstring
  ): IMP {.cdecl, importc, dynlib: "libobjc.dylib".}
    ## Overrides a method without replacing AppKit's per-instance KVO class.

  var
    desktops: seq[DesktopFullscreen]
    originalCanBecomeMain, originalDidBecomeKey, originalDidResignKey: IMP
    fullscreenObserver: ID
    presentationActive: bool
    previousPresentation, appliedPresentation: NSApplicationPresentationOptions

  proc findDesktop(window: Window): DesktopFullscreen =
    ## Locates one live window without registering other Windy windows.
    if window == nil or window.closed:
      return
    for desktop in desktops:
      if desktop.window == window:
        return desktop

  proc findDesktop(native: ID): DesktopFullscreen =
    ## Resolves native focus notifications to their independent window state.
    for desktop in desktops:
      if not desktop.window.closed and
        desktop.window.nativeWindow.int == native.int:
          return desktop

  proc restorablePresentation(
      options: NSApplicationPresentationOptions
  ): NSApplicationPresentationOptions =
    ## Avoids restoring native fullscreen-only flags without a fullscreen Space.
    result = options
    let windows = NSApp.windows
    for i in 0 ..< windows.count.int:
      let native = windows.objectAtIndex(i.uint).NSWindow
      if native.isVisible and native.isOnActiveSpace and
        (native.styleMask and NSWindowStyleMaskFullScreen) != 0:
          return
    result = result and not (
      PresentationFullscreen or PresentationAutoHideToolbar
    )

  proc updateFullscreenPresentation() =
    ## Gives one focused fullscreen window ownership of the app's hidden bars.
    var owner: DesktopFullscreen
    if NSApp.isActive:
      for desktop in desktops:
        let window = desktop.window
        if desktop.active and not desktop.changing and not window.closed and
          not window.closeRequested and window.focused and window.visible and
          window.nativeWindow.isOnActiveSpace:
            owner = desktop
            break
    let current = NSApp.presentationOptions()
    if owner == nil:
      if presentationActive:
        if current == appliedPresentation:
          NSApp.setPresentationOptions(restorablePresentation(previousPresentation))
        presentationActive = false
      return
    if not presentationActive:
      previousPresentation = current
      presentationActive = true
    appliedPresentation = (current and not (
      PresentationAutoReveal or PresentationFullscreen
    )) or PresentationHiddenBars
    if current != appliedPresentation:
      NSApp.setPresentationOptions(appliedPresentation)

proc desktopFullscreen*(window: Window): bool =
  ## Reports the logical fullscreen mode, including while the app is inactive.
  when defined(macosx) and not defined(emscripten):
    let desktop = findDesktop(window)
    desktop != nil and desktop.active
  else:
    false

proc desktopFullscreenChanging*(window: Window): bool =
  ## Guards input and drawing callbacks during synchronous native style changes.
  when defined(macosx) and not defined(emscripten):
    let desktop = findDesktop(window)
    desktop != nil and desktop.changing
  else:
    false

proc updateDesktopFullscreen*(window: Window) =
  ## Refreshes the native level and app presentation without game-specific code.
  when defined(macosx) and not defined(emscripten):
    let desktop = findDesktop(window)
    if desktop != nil and desktop.active:
      if desktop.changing or desktop.updating:
        return
      desktop.updating = true
      defer: desktop.updating = false
      let native = window.nativeWindow
      native.ID.retain()
      defer: native.ID.release()
      if NSApp.isActive and window.focused and not window.closeRequested:
        native.setLevel(CGWindowLevelForKey(MainMenuWindowLevelKey).int + 1)
        if window.closed:
          return
        let screen = native.screen
        if screen.int != 0 and native.frame != screen.frame:
          # Follow display changes without changing the monitor's video mode.
          desktop.changing = true
          try:
            native.setFrame(screen.frame, true)
          finally:
            desktop.changing = false
      else:
        native.setLevel(desktop.level)
    updateFullscreenPresentation()

when defined(macosx) and not defined(emscripten):
  proc updateDesktopWindows() =
    ## Refreshes a stable list even if native callbacks close or create windows.
    var pending: seq[DesktopFullscreen]
    for desktop in desktops:
      pending.add desktop
    for desktop in pending:
      desktop.window.updateDesktopFullscreen()
    updateFullscreenPresentation()

  proc canBecomeDesktopMain(self: ID, cmd: SEL): bool {.cdecl.} =
    ## Gives registered borderless windows the same main status as GLFW.
    if findDesktop(self) != nil:
      return true
    cast[proc(self: ID, cmd: SEL): bool {.cdecl.}](
      originalCanBecomeMain
    )(self, cmd)

  proc desktopDidBecomeKey(
      self: ID, cmd: SEL, notification: NSNotification
  ): ID {.cdecl.} =
    ## Preserves Windy's focus notification before restoring fullscreen policy.
    result = cast[proc(
      self: ID, cmd: SEL, notification: NSNotification
    ): ID {.cdecl.}](originalDidBecomeKey)(self, cmd, notification)
    updateDesktopWindows()

  proc desktopDidResignKey(
      self: ID, cmd: SEL, notification: NSNotification
  ): ID {.cdecl.} =
    ## Preserves game focus callbacks before releasing fullscreen presentation.
    result = cast[proc(
      self: ID, cmd: SEL, notification: NSNotification
    ): ID {.cdecl.}](originalDidResignKey)(self, cmd, notification)
    updateDesktopWindows()

  proc desktopApplicationActivity(
      self: ID, cmd: SEL, notification: NSNotification
  ) {.cdecl.} =
    ## Handles app activation even if no game installs a focus callback.
    updateDesktopWindows()

  proc desktopWindowWillClose(
      self: ID, cmd: SEL, notification: NSNotification
  ) {.cdecl.} =
    ## Removes closed window state and releases its presentation ownership.
    let desktop = findDesktop(notification.notificationObject)
    if desktop == nil:
      return
    desktop.active = false
    for i in 0 ..< desktops.len:
      if desktops[i] == desktop:
        desktops.delete(i)
        break
    updateFullscreenPresentation()

  proc installDesktopHooks() =
    ## Adds shared lifecycle hooks while keeping every native instance intact.
    if originalCanBecomeMain != nil:
      return
    let cls = objc_getClass("WindyWindow")
    doAssert cls.int != 0
    originalCanBecomeMain = class_getMethodImplementation(
      cls, s("canBecomeMainWindow")
    )
    originalDidBecomeKey = class_getMethodImplementation(
      cls, s("windowDidBecomeKey:")
    )
    originalDidResignKey = class_getMethodImplementation(
      cls, s("windowDidResignKey:")
    )
    discard class_replaceMethod(
      cls, s("canBecomeMainWindow"), cast[IMP](canBecomeDesktopMain), "c@:"
    )
    discard class_replaceMethod(
      cls, s("windowDidBecomeKey:"), cast[IMP](desktopDidBecomeKey), "v@:@"
    )
    discard class_replaceMethod(
      cls, s("windowDidResignKey:"), cast[IMP](desktopDidResignKey), "v@:@"
    )
    var observerClass: Class
    addClass "PolyworldFullscreenObserver", "NSObject", observerClass:
      addMethod "applicationActivityChanged:", desktopApplicationActivity
      addMethod "windowWillClose:", desktopWindowWillClose
    fullscreenObserver = observerClass.new()
    let center = NSNotificationCenter.defaultCenter()
    for name in [
      "NSApplicationDidBecomeActiveNotification",
      "NSApplicationDidResignActiveNotification",
      "NSApplicationDidChangeScreenParametersNotification"
    ]:
      center.addObserver(
        fullscreenObserver, s("applicationActivityChanged:"), @name, NSApp.ID
      )
    center.addObserver(
      fullscreenObserver, s("windowWillClose:"),
      @"NSWindowWillCloseNotification", ID(0)
    )

proc prepareDesktopFullscreen*(window: Window) =
  ## Registers the shared macOS fullscreen path before native UI can bypass it.
  when defined(macosx) and not defined(emscripten):
    if window == nil or window.closed or findDesktop(window) != nil:
      return
    installDesktopHooks()
    desktops.add DesktopFullscreen(window: window)
    let native = window.nativeWindow
    native.setCollectionBehavior(
      (native.collectionBehavior and not (
        FullScreenPrimary or FullScreenAuxiliary
      )) or FullScreenNone
    )

proc setFullscreenCallbacks*(
    window: Window, beforeChange: proc() = nil, afterChange: proc() = nil
) =
  ## Registers optional input cleanup without opting into a different backend.
  when defined(macosx) and not defined(emscripten):
    window.prepareDesktopFullscreen()
    let desktop = findDesktop(window)
    if desktop != nil:
      desktop.beforeChange = beforeChange
      desktop.afterChange = afterChange

proc setDesktopFullscreen*(window: Window, enabled: bool) =
  ## Applies GLFW-style fullscreen and restores this window's original state.
  when defined(macosx) and not defined(emscripten):
    window.prepareDesktopFullscreen()
    let desktop = findDesktop(window)
    if desktop == nil or desktop.changing or desktop.active == enabled:
      return
    let native = window.nativeWindow
    if (native.styleMask and NSWindowStyleMaskFullScreen) != 0:
      raise newException(WindyError,
        "Leave native fullscreen before changing desktop fullscreen")
    native.ID.retain()
    defer: native.ID.release()
    desktop.changing = true
    defer:
      desktop.changing = false
      window.updateDesktopFullscreen()
      if desktop.afterChange != nil and not window.closed:
        desktop.afterChange()
    updateFullscreenPresentation()
    if desktop.beforeChange != nil:
      desktop.beforeChange()
    if window.closed:
      return
    if enabled:
      let screen = native.screen
      if screen.int == 0:
        raise newException(WindyError, "Fullscreen window has no display")
      desktop.frame = native.frame
      desktop.style = native.styleMask
      desktop.level = native.level
      desktop.movable = native.isMovable
      desktop.shadow = native.hasShadow
      desktop.hides = native.hidesOnDeactivate
      desktop.mouseMoved = native.acceptsMouseMovedEvents
      desktop.active = true
      native.setHidesOnDeactivate(true)
      native.setStyleMask(NSWindowStyleMaskMiniaturizable)
      if window.closed:
        return
      discard native.makeFirstResponder(native.contentView)
      native.setAcceptsMouseMovedEvents(true)
      if NSApp.isActive and window.focused:
        native.makeMainWindow()
      native.setMovable(false)
      native.setHasShadow(false)
      native.setFrame(screen.frame, true)
    else:
      desktop.active = false
      native.setLevel(desktop.level)
      if window.closed:
        return
      native.setStyleMask(desktop.style)
      if window.closed:
        return
      discard native.makeFirstResponder(native.contentView)
      native.setMovable(desktop.movable)
      native.setHasShadow(desktop.shadow)
      native.setHidesOnDeactivate(desktop.hides)
      native.setAcceptsMouseMovedEvents(desktop.mouseMoved)
      native.setFrame(desktop.frame, true)
