import windy

when defined(macosx) and not defined(emscripten):
  import windy/platforms/macos/macdefs

  const
    FullScreenPrimary = 1'u shl 7
    FullScreenAuxiliary = 1'u shl 8
    FullScreenNone = 1'u shl 9
    MainMenuWindowLevelKey = 8

  objc:
    proc collectionBehavior(self: NSWindow): uint
      ## Reads the window's desktop and native fullscreen participation.
    proc setCollectionBehavior(self: NSWindow, x: uint)
      ## Disables native fullscreen Spaces for the opted-in game window.
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

  proc CGWindowLevelForKey(key: cint): int32 {.cdecl, importc.}
    ## Resolves the system menu window level without hardcoding its value.

  proc class_getMethodImplementation(cls: Class, selector: SEL): IMP
      {.cdecl, importc, dynlib: "libobjc.dylib".}
    ## Preserves the original main-window eligibility for other Windy windows.

  proc class_replaceMethod(
      cls: Class, selector: SEL, implementation: IMP, encoding: cstring
  ): IMP {.cdecl, importc, dynlib: "libobjc.dylib".}
    ## Overrides a method without replacing AppKit's per-instance KVO class.

  type DesktopFullscreen = object
    window: Window
    active, changing: bool
    beforeChange, afterChange: proc()
    frame: NSRect
    style: NSWindowStyleMask
    level: NSWindowLevel
    movable, shadow, hides, mouseMoved: bool
    collection: uint

  var
    desktop: DesktopFullscreen
    originalCanBecomeMain: IMP

  proc canBecomeDesktopMain(self: ID, cmd: SEL): bool {.cdecl.} =
    ## Gives the opted-in borderless window the same main status as GLFW.
    if desktop.window != nil and not desktop.window.closed and
      desktop.window.nativeWindow.int == self.int:
        return true
    cast[proc(self: ID, cmd: SEL): bool {.cdecl.}](
      originalCanBecomeMain
    )(self, cmd)

proc usesDesktopFullscreen*(window: Window): bool =
  ## Reports whether this window opted into monitor-sized borderless fullscreen.
  when defined(macosx) and not defined(emscripten):
    window != nil and window == desktop.window and not window.closed
  else:
    false

proc desktopFullscreen*(window: Window): bool =
  ## Reports the logical mode even when the fullscreen window is minimized.
  when defined(macosx) and not defined(emscripten):
    window.usesDesktopFullscreen and desktop.active
  else:
    false

proc desktopFullscreenChanging*(window: Window): bool =
  ## Guards input and drawing callbacks during synchronous native style changes.
  when defined(macosx) and not defined(emscripten):
    window.usesDesktopFullscreen and desktop.changing
  else:
    false

proc updateDesktopFullscreen*(window: Window) =
  ## Keeps fullscreen above system bars only while the game has focus.
  when defined(macosx) and not defined(emscripten):
    if not window.desktopFullscreen or desktop.changing:
      return
    let native = window.nativeWindow
    if NSApp.isActive and window.focused and not window.closeRequested:
      native.setLevel(CGWindowLevelForKey(MainMenuWindowLevelKey).int + 1)
      let screen = native.screen
      if screen.int != 0 and native.frame != screen.frame:
        # Follow display resolution changes without changing its video mode.
        desktop.changing = true
        native.setFrame(screen.frame, true)
        desktop.changing = false
    else:
      native.setLevel(desktop.level)

proc setDesktopFullscreen*(window: Window, enabled: bool) =
  ## Applies GLFW-style fullscreen and restores the exact original window.
  when defined(macosx) and not defined(emscripten):
    if not window.usesDesktopFullscreen or desktop.changing or
      desktop.active == enabled:
        return
    let native = window.nativeWindow
    if (native.styleMask and NSWindowStyleMaskFullScreen) != 0:
      raise newException(WindyError,
        "Leave native fullscreen before changing desktop fullscreen")
    desktop.changing = true
    defer:
      desktop.changing = false
      if desktop.afterChange != nil:
        desktop.afterChange()
    if desktop.beforeChange != nil:
      desktop.beforeChange()
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
      discard native.makeFirstResponder(native.contentView)
      native.setAcceptsMouseMovedEvents(true)
      if NSApp.isActive and window.focused:
        native.makeMainWindow()
      native.setMovable(false)
      native.setHasShadow(false)
      native.setFrame(screen.frame, true)
      if NSApp.isActive and window.focused:
        native.setLevel(CGWindowLevelForKey(MainMenuWindowLevelKey).int + 1)
    else:
      desktop.active = false
      native.setLevel(desktop.level)
      native.setStyleMask(desktop.style)
      discard native.makeFirstResponder(native.contentView)
      native.setMovable(desktop.movable)
      native.setHasShadow(desktop.shadow)
      native.setHidesOnDeactivate(desktop.hides)
      native.setAcceptsMouseMovedEvents(desktop.mouseMoved)
      native.setFrame(desktop.frame, true)

proc useDesktopFullscreen*(
    window: Window, beforeChange: proc() = nil, afterChange: proc() = nil
) =
  ## Opts one game window into borderless fullscreen with explicit input hooks.
  when defined(macosx) and not defined(emscripten):
    if window.usesDesktopFullscreen:
      return
    if desktop.window != nil and not desktop.window.closed:
      desktop.window.setDesktopFullscreen(false)
      desktop.window.nativeWindow.setCollectionBehavior(desktop.collection)
    desktop = DesktopFullscreen(
      window: window,
      beforeChange: beforeChange,
      afterChange: afterChange,
      collection: window.nativeWindow.collectionBehavior
    )
    if originalCanBecomeMain == nil:
      let
        cls = objc_getClass("WindyWindow")
        selector = s("canBecomeMainWindow")
      originalCanBecomeMain = class_getMethodImplementation(cls, selector)
      discard class_replaceMethod(
        cls, selector, cast[IMP](canBecomeDesktopMain), "c@:"
      )
    window.nativeWindow.setCollectionBehavior(
      (desktop.collection and not (FullScreenPrimary or FullScreenAuxiliary)) or
        FullScreenNone
    )
