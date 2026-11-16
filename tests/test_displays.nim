import
  windy,
  polyworld/displays

when defined(macosx) and not defined(emscripten):
  import windy/platforms/macos/macdefs

  objc:
    proc isMovable(self: NSWindow): bool
      ## Reads the native permission to move the window.
    proc setMovable(self: NSWindow, x: bool)
      ## Supplies a nondefault control state for restoration testing.
    proc hasShadow(self: NSWindow): bool
      ## Reads the window shadow state.
    proc setHasShadow(self: NSWindow, x: bool)
      ## Supplies a nondefault shadow state for restoration testing.
    proc hidesOnDeactivate(self: NSWindow): bool
      ## Reads how the window behaves when another app activates.
    proc setHidesOnDeactivate(self: NSWindow, x: bool)
      ## Sets the initial app-switching behavior for the test window.
    proc acceptsMouseMovedEvents(self: NSWindow): bool
      ## Reads whether continuous native pointer motion is requested.
    proc setAcceptsMouseMovedEvents(self: NSWindow, x: bool)
      ## Supplies a nondefault pointer state for restoration testing.
    proc firstResponder(self: NSWindow): ID
      ## Reads the native view receiving input after a style change.
    proc canBecomeMainWindow(self: NSWindow): bool
      ## Checks that a borderless game can remain the main input window.
    proc windowDidBecomeKey(self: NSWindow, x: NSNotification)
      ## Dispatches the registered focus callback without activating a window.
    proc windowDidResignKey(self: NSWindow, x: NSNotification)
      ## Dispatches the registered focus-loss callback on a hidden window.

  type NativeWindowState = object
    frame: NSRect
    style: NSWindowStyleMask
    level: NSWindowLevel
    movable, shadow, hides, mouseMoved, visible: bool

  proc windowState(window: Window): NativeWindowState =
    ## Snapshots the native properties owned by desktop fullscreen.
    let native = window.nativeWindow
    NativeWindowState(
      frame: native.frame,
      style: native.styleMask,
      level: native.level,
      movable: native.isMovable,
      shadow: native.hasShadow,
      hides: native.hidesOnDeactivate,
      mouseMoved: native.acceptsMouseMovedEvents,
      visible: native.isVisible
    )

  proc checkFullscreen(window: Window) =
    ## Checks the shared fullscreen API against a real hidden native window.
    let native = window.nativeWindow
    doAssert window.isFullscreen and window.desktopFullscreen
    doAssert window.windowMode == Fullscreen
    doAssert not window.fullscreen,
      "Desktop fullscreen must not enter a native fullscreen Space"
    doAssert (native.styleMask and (
      NSWindowStyleMaskTitled or NSWindowStyleMaskClosable or
      NSWindowStyleMaskResizable or NSWindowStyleMaskFullScreen
    )) == 0
    doAssert native.frame == native.screen.frame,
      "Fullscreen must cover the complete display, including the menu area"
    doAssert native.firstResponder().int == native.contentView.int,
      "Changing styles must preserve the content view as input recipient"
    doAssert native.canBecomeMainWindow,
      "The borderless window must be eligible to remain the main window"
    doAssert native.acceptsMouseMovedEvents and native.hidesOnDeactivate
    doAssert not native.isMovable and not native.hasShadow
    doAssert not native.isVisible,
      "Changing a hidden window's mode must not show it or steal focus"
    doAssert not window.mouseCaptured,
      "Display mode changes must preserve normal native pointer input"

  proc testSharedFullscreen() =
    ## Exercises default fullscreen without importing any game pointer module.
    let
      first = newWindow("Shared fullscreen first", ivec2(800, 600),
        visible = false)
      second = newWindow("Shared fullscreen second", ivec2(900, 500),
        visible = false)
      firstNative = first.nativeWindow
      secondNative = second.nativeWindow
      firstClass = object_getClass(firstNative.ID)
      secondClass = object_getClass(secondNative.ID)
    defer:
      first.setFullscreen(false)
      second.setFullscreen(false)
      first.close()
      second.close()
    firstNative.setMovable(false)
    firstNative.setHasShadow(false)
    firstNative.setHidesOnDeactivate(false)
    firstNative.setAcceptsMouseMovedEvents(false)
    firstNative.setLevel(NSFloatingWindowLevel)
    firstNative.setStyleMask(
      firstNative.styleMask and not NSWindowStyleMaskResizable
    )
    let
      firstOriginal = first.windowState()
      secondOriginal = second.windowState()
    doAssert not first.isFullscreen and not second.isFullscreen
    first.setFullscreen(true)
    first.checkFullscreen()
    doAssert second.windowState() == secondOriginal
    doAssert not second.isFullscreen
    doAssert object_getClass(firstNative.ID).int == firstClass.int,
      "Default fullscreen must preserve AppKit's native runtime class"

    var firstFocusChanges, secondFocusChanges: int
    first.onFocusChange = proc() =
      ## Counts Windy's original callback through the shared native wrapper.
      inc firstFocusChanges
    second.onFocusChange = proc() =
      ## Detects accidental focus callback dispatch to another window.
      inc secondFocusChanges
    firstNative.windowDidBecomeKey(NSNotification(0))
    firstNative.windowDidResignKey(NSNotification(0))
    doAssert firstFocusChanges == 2 and secondFocusChanges == 0,
      "Shared fullscreen hooks must preserve Windy's own focus callbacks"
    first.checkFullscreen()

    var beforeChanges, afterChanges: int
    first.setFullscreenCallbacks(
      proc() =
        inc(beforeChanges),
      proc() =
        inc(afterChanges)
    )
    doAssert beforeChanges == 0 and afterChanges == 0
    first.checkFullscreen()
    second.setFullscreen(true)
    second.checkFullscreen()
    first.checkFullscreen()
    doAssert beforeChanges == 0 and afterChanges == 0,
      "Another window's fullscreen changes must not invoke this window's hooks"
    doAssert object_getClass(secondNative.ID).int == secondClass.int

    first.setFullscreen(false)
    doAssert beforeChanges == 1 and afterChanges == 1,
      "Hooks registered after default entry must survive until fullscreen exit"
    doAssert not first.isFullscreen and first.windowMode == Windowed
    doAssert first.windowState() == firstOriginal,
      "Leaving fullscreen must restore every saved native window property"
    doAssert firstNative.firstResponder().int == firstNative.contentView.int
    second.checkFullscreen()
    second.setFullscreen(false)
    doAssert second.windowState() == secondOriginal
    doAssert not second.isFullscreen
    first.setFullscreen(false)
    doAssert beforeChanges == 1 and afterChanges == 1

    first.configureWindow(Fullscreen, CurrentResolution)
    doAssert not first.isFullscreen and first.windowState() == firstOriginal,
      "Configuring fullscreen must defer native style and frame changes"
    doAssert first.windowMode == Fullscreen
    first.updateWindowSettings()
    first.checkFullscreen()
    doAssert second.windowState() == secondOriginal
    first.configureWindow(Windowed, CurrentResolution)
    doAssert first.isFullscreen,
      "Configuring windowed mode must defer restoration until the update"
    first.updateWindowSettings()
    doAssert first.windowState() == firstOriginal,
      "Queued windowed mode must preserve an originally nonresizable style"
    doAssert not first.isFullscreen and first.windowMode == Windowed
    doAssert beforeChanges == 3 and afterChanges == 3

    second.setFullscreen(true)
    let closing = newWindow("Shared fullscreen closing", ivec2(700, 450),
      visible = false)
    closing.setFullscreen(true)
    closing.checkFullscreen()
    closing.close()
    doAssert closing.closed and not closing.desktopFullscreen,
      "Closing fullscreen must end that window's logical fullscreen state"
    secondNative.windowDidBecomeKey(NSNotification(0))
    secondNative.windowDidResignKey(NSNotification(0))
    doAssert secondFocusChanges == 2
    second.checkFullscreen()
    let
      replacement = newWindow("Shared fullscreen replacement", ivec2(700, 450),
        visible = false)
      replacementOriginal = replacement.windowState()
    defer: replacement.close()
    replacement.setFullscreen(true)
    replacement.checkFullscreen()
    replacement.setFullscreen(false)
    doAssert replacement.windowState() == replacementOriginal,
      "New windows must not inherit snapshots from closed fullscreen windows"
    second.setFullscreen(false)
    doAssert second.windowState() == secondOriginal
    echo "PASS shared default fullscreen, independent windows and restoration"

  testSharedFullscreen()
else:
  echo "Native desktop fullscreen tests require macOS."
