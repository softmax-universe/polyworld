## Native confinement preserves the system cursor across window transitions.
import
  std/[macros, os],
  vmath,
  polyworld/rtscameras,
  "/Users/me/p/polyworld/games/gods_of_the_arena/cameras"
include kvo_pointers_before

echo "Testing confinement follows the edge-scrolling preference and focus"
for mode in EdgeScrollMode:
  for fullscreen in [false, true]:
    doAssert not cursorConfinementAllowed(false, fullscreen, false, mode)
    doAssert not cursorConfinementAllowed(true, fullscreen, true, mode)
doAssert not cursorConfinementAllowed(true, false, false, NoEdgeScroll)
doAssert not cursorConfinementAllowed(true, true, false, NoEdgeScroll)
doAssert not cursorConfinementAllowed(true, false, false, FullscreenEdgeScroll)
doAssert cursorConfinementAllowed(true, true, false, FullscreenEdgeScroll)
doAssert cursorConfinementAllowed(true, false, false, AlwaysEdgeScroll)
doAssert cursorConfinementAllowed(true, true, false, AlwaysEdgeScroll)

when defined(macosx) and not defined(emscripten):
  echo "Testing fullscreen presentation removes hover reveal without locking apps"
  block:
    const
      Fullscreen = 1'u shl 10
      CursorAssistance = 1'u shl 12
      AutoReveal = 1'u or 4'u or (1'u shl 11)
      AppSwitchAndForceQuit = (1'u shl 5) or (1'u shl 6)
    let flags = fullscreenPresentation(Fullscreen or CursorAssistance or AutoReveal)
    doAssert flags == (Fullscreen or CursorAssistance or 2'u or 8'u)
    doAssert (flags and AutoReveal) == 0,
      "Hidden menu bars cannot retain the conflicting auto-hide toolbar flag"
    doAssert (flags and AppSwitchAndForceQuit) == 0,
      "Fullscreen edge scrolling must retain Cmd-Tab and Force Quit"

  objc:
    proc delegate(self: NSWindow): ID
      ## Reads the delegate installed for fullscreen presentation callbacks.
    proc respondsToSelector(self: ID, x: SEL): bool
      ## Checks that AppKit can discover Gota's optional delegate methods.
    proc addObserver(
      self: NSWindow,
      x: ID,
      forKeyPath: NSString,
      options: uint,
      context: pointer
    )
      ## Registers a real native observer before installing pointer hooks.
    proc removeObserver(
      self: NSWindow,
      x: ID,
      forKeyPath: NSString,
      context: pointer
    )
      ## Verifies that pointer hooks preserve native observer registration.
    proc windowDidEnterFullScreen(self: NSWindow, x: NSNotification)
      ## Dispatches the registered native fullscreen completion callback.
    proc windowDidExitFullScreen(self: NSWindow, x: NSNotification)
      ## Dispatches the registered native windowed completion callback.
    proc window(
      self: NSWindow,
      x: NSWindow,
      willUseFullScreenPresentationOptions: NSApplicationPresentationOptions
    ): NSApplicationPresentationOptions
      ## Invokes the real registered fullscreen presentation selector.
    proc mouseConfinementRect(self: NSWindow): NSRect
      ## Reads the actual native restriction without moving the system cursor.
    proc windowNumber(self: NSWindow): int
      ## Reads the target window for a synthetic local event.
    proc mouseMoved(self: NSView, x: NSEvent)
      ## Delivers a local movement through Windy's native event handler.
    proc mouseEventWithType(
      class: typedesc[NSEvent],
      x: uint,
      location: NSPoint,
      modifierFlags: uint,
      timestamp: float64,
      windowNumber: int,
      context: ID,
      eventNumber: int,
      clickCount: int,
      pressure: float32
    ): NSEvent
      ## Creates a local event without moving the system cursor.

  type TestWindow = object
    window: Window
    focused, fullscreen, closeRequested: bool

  proc isFullscreen(window: TestWindow): bool =
    ## Supplies a display mode without changing the user's desktop.
    window.fullscreen

  proc nativeWindow(window: TestWindow): NSWindow =
    ## Uses a real hidden window for native confinement updates.
    window.window.nativeWindow

  converter nativeTestWindow(window: TestWindow): Window =
    ## Keeps coordinate and keyboard reads on the real hidden native window.
    window.window

  proc updateCursorConfinement(window: TestWindow) =
    ## Tests production native updates with deterministic focus and mode flags.
    updateNativeConfinement(window.nativeWindow, window.focused,
      window.fullscreen, window.closeRequested, cursorEdgeScrolling)

  proc updateCursorConfinement(window: TestWindow, mode: EdgeScrollMode) =
    ## Applies the same retained preference as the public window entry point.
    cursorEdgeScrolling = mode
    window.updateCursorConfinement()

  proc rtsPointerInside(window: TestWindow): bool =
    ## Preserves Windy's exact native boundary containment in the camera test.
    window.window.mouseInside

  macro testCameraPan(): untyped =
    ## Runs the production camera pan with only OS focus made deterministic.
    let source = parseStmt(readFile(
      "/Users/me/p/polyworld/src/polyworld/rtscameras.nim"
    ))
    result = newStmtList()
    for node in source:
      if node.kind != nnkProcDef or
        node[0].repr != "rtsPanDir*" or
        not node[3][1][^2].eqIdent("Window"):
          continue
      let update = copyNimTree(node)
      update[3][1][^2] = ident("TestWindow")
      result.add update
    doAssert result.len == 1

  testCameraPan()

  var titleObservations: int

  proc observeTitle(
      self: ID, cmd: SEL, keyPath: NSString, native: ID,
      changes: ID, context: pointer
  ) {.cdecl.} =
    ## Counts title changes delivered through Foundation's KVO machinery.
    inc titleObservations

  proc testWindowObservers() =
    ## Preserves AppKit's runtime class and KVO through hook installation.
    let plain = newWindow(
      "GotA plain native class",
      ivec2(800, 600),
      visible = false
    )
    defer: plain.close()
    let plainClass = object_getClass(plain.nativeWindow.ID)
    installPointerHooks(plain)
    doAssert object_getClass(plain.nativeWindow.ID).int == plainClass.int,
      "Pointer hooks must not replace the class of an initialized NSWindow"

    var observerClass: Class
    addClass "GotaPointerTestObserver", "NSObject", observerClass:
      addMethod "observeValueForKeyPath:ofObject:change:context:", observeTitle
    let
      observer = observerClass.new()
      window = newWindow(
        "GotA observed native class",
        ivec2(800, 600),
        visible = false
      )
      native = window.nativeWindow
    defer:
      releaseCursorConfinement()
      window.close()
      observer.release()
    native.addObserver(observer, @"title", 0, nil)
    let observedClass = object_getClass(native.ID)
    titleObservations = 0
    native.setTitle(@"Before installing pointer hooks")
    doAssert titleObservations == 1
    installPointerHooks(window)
    doAssert object_getClass(native.ID).int == observedClass.int,
      "Pointer hooks must preserve Foundation's KVO subclass"
    native.setTitle(@"After installing pointer hooks")
    doAssert titleObservations == 2,
      "Existing KVO observers must keep receiving changes after hook installation"
    native.removeObserver(observer, @"title", nil)
    native.setTitle(@"After removing the observer")
    doAssert titleObservations == 2,
      "Removing a preexisting observer must succeed and stop its callbacks"

    pointerTransition = true
    plain.nativeWindow.windowDidEnterFullScreen(NSNotification(0))
    doAssert plain.fullscreen and not window.fullscreen,
      "Other Windy windows must retain their original fullscreen callbacks"
    doAssert pointerTransition,
      "Another window's fullscreen callback must not settle Gota's transition"
    plain.nativeWindow.windowDidExitFullScreen(NSNotification(0))
    doAssert not plain.fullscreen and pointerTransition
    pointerTransition = false
    echo "PASS native window classes, KVO observers and unrelated window callbacks"

  proc testConfinementLifecycle() =
    ## Verifies real native apply/release across focus, settings, and resize.
    let window = newWindow(
      "GotA confinement lifecycle",
      ivec2(800, 600),
      visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    installPointerHooks(window)
    let originalMask = window.nativeWindow.styleMask
    doAssert window.nativeWindow.isMovable
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    doAssert window.nativeWindow.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)
    doAssert not window.mouseCaptured,
      "Confinement must preserve absolute pointer input for edge scrolling"
    doAssert not window.nativeWindow.isMovable,
      "Captured windowed play must disable native dragging"
    doAssert (window.nativeWindow.styleMask and NSWindowStyleMaskResizable) == 0,
      "Captured windowed play must disable native resizing"
    doAssert window.nativeWindow.styleMask ==
      (originalMask and not NSWindowStyleMaskResizable)

    state.focused = false
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect(),
      "Switching apps must immediately release the native cursor restriction"
    doAssert window.nativeWindow.isMovable
    doAssert window.nativeWindow.styleMask == originalMask,
      "Focus loss must restore the window's original resize permission"
    state.focused = true
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() != NSRect(),
      "Refocusing must restore the retained Always preference in windowed mode"

    let beforeResize = window.nativeWindow.mouseConfinementRect()
    window.size = ivec2(1200, 900)
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() != beforeResize
    doAssert window.nativeWindow.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)

    state.updateCursorConfinement(NoEdgeScroll)
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect()
    doAssert window.nativeWindow.isMovable
    doAssert window.nativeWindow.styleMask == originalMask
    state.focused = false
    state.updateCursorConfinement()
    state.focused = true
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect(),
      "Refocusing must not reenable confinement after edge scrolling is Off"

    state.updateCursorConfinement(FullscreenEdgeScroll)
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect()
    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() != NSRect()
    state.fullscreen = false
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect()

    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.closeRequested = true
    state.updateCursorConfinement()
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect(),
      "Closing must release confinement even before focus changes"
    doAssert confinedWindow.int == 0 and confinedBounds == NSRect()
    doAssert window.nativeWindow.isMovable
    doAssert window.nativeWindow.styleMask == originalMask
    doAssert not controlsLocked
    releaseCursorConfinement()

    window.nativeWindow.setMovable(false)
    window.nativeWindow.setStyleMask(
      originalMask and not NSWindowStyleMaskResizable
    )
    state.closeRequested = false
    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.updateCursorConfinement(NoEdgeScroll)
    doAssert not window.nativeWindow.isMovable
    doAssert (window.nativeWindow.styleMask and NSWindowStyleMaskResizable) == 0,
      "Release must not enable controls that were disabled before capture"
    echo "PASS native confinement settings, focus/refocus, resize and close"

  proc testFullscreenPresentation() =
    ## Checks native flags and restoration while only fullscreen owns the bars.
    let window = newWindow(
      "GotA fullscreen presentation",
      ivec2(800, 600),
      visible = false
    )
    let original = NSApp.presentationOptions()
    defer:
      releaseCursorConfinement()
      NSApp.setPresentationOptions(original)
      window.close()
    NSApp.setPresentationOptions(0)
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    doAssert NSApp.presentationOptions() == 0,
      "Windowed confinement must not change the Dock or menu bar"

    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == (2'u or 8'u),
      "Fullscreen must hide both bars instead of revealing them on hover"
    doAssert not window.mouseCaptured
    state.updateCursorConfinement()
    state.focused = false
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == 0,
      "Focus loss must restore the original presentation flags"
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect()
    state.focused = true
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == (2'u or 8'u),
      "Refocusing fullscreen must suppress edge reveal again"

    state.updateCursorConfinement(NoEdgeScroll)
    doAssert NSApp.presentationOptions() == 0
    doAssert not presentationActive
    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.fullscreen = false
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == 0,
      "Returning to windowed Always mode restores the bars but keeps confinement"
    doAssert window.nativeWindow.mouseConfinementRect() != NSRect()

    NSApp.setPresentationOptions(1'u or 4'u)
    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == (2'u or 8'u)
    state.focused = false
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == (1'u or 4'u),
      "Release must restore the actual original flags, not a fixed default"
    state.focused = true
    state.updateCursorConfinement()
    NSApp.setPresentationOptions(0)
    state.fullscreen = false
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == 0,
      "AppKit's fullscreen-exit restoration must not be replaced by stale flags"
    doAssert not presentationActive

    state.fullscreen = true
    state.updateCursorConfinement()
    state.closeRequested = true
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == 0
    doAssert not presentationActive
    doAssert window.nativeWindow.mouseConfinementRect() == NSRect()

    state.closeRequested = false
    state.updateCursorConfinement()
    previousPresentation = 1'u or 4'u or
      PresentationFullscreen or PresentationAutoHideToolbar
    doAssert availablePresentation(previousPresentation) == (1'u or 4'u),
      "A hidden window cannot restore fullscreen or auto-hide toolbar flags"
    state.closeRequested = true
    state.updateCursorConfinement()
    doAssert NSApp.presentationOptions() == (1'u or 4'u),
      "Closing after native fullscreen exit must restore valid presentation flags"
    echo "PASS fullscreen-only bar suppression and native presentation restoration"

  proc testFullscreenHooks() =
    ## Exercises installed delegate callbacks without entering a desktop Space.
    let window = newWindow(
      "GotA fullscreen callbacks",
      ivec2(800, 600),
      visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    installPointerHooks(window)
    let
      native = window.nativeWindow
      originalMask = native.styleMask
      proposed = PresentationFullscreen or 1'u or 4'u
    doAssert native.delegate().int == native.int
    doAssert native.ID.respondsToSelector(
      s("window:willUseFullScreenPresentationOptions:")
    ), "The native delegate must expose Gota's fullscreen rules"
    cursorEdgeScrolling = NoEdgeScroll
    doAssert native.window(native, proposed) == proposed
    cursorEdgeScrolling = FullscreenEdgeScroll
    doAssert native.window(native, proposed) ==
      (PresentationFullscreen or PresentationHiddenBars),
      "The delegate must hide both bars before the fullscreen transition starts"
    discard native.window(native, PresentationFullscreen or PresentationHiddenBars)
    doAssert previousPresentation == proposed,
      "Repeated delegate calls must preserve the original presentation baseline"
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    doAssert controlsLocked
    pointerWillTransition(native.ID, s("windowWillEnterFullScreen:"),
      NSNotification(0))
    doAssert pointerTransition
    doAssert native.mouseConfinementRect() == NSRect()
    doAssert native.isMovable and native.styleMask == originalMask,
      "Window controls must be restored before the fullscreen animation"
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Frame callbacks must not relock a window while AppKit is animating it"
    pointerDidTransition(native.ID, s("windowDidEnterFullScreen:"),
      NSNotification(0))
    doAssert not pointerTransition and window.fullscreen,
      "The Gota delegate must preserve Windy's fullscreen state update"
    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)
    doAssert native.styleMask == originalMask and not controlsLocked

    pointerWillTransition(native.ID, s("windowWillExitFullScreen:"),
      NSNotification(0))
    doAssert pointerTransition
    pointerDidTransition(native.ID, s("windowDidExitFullScreen:"),
      NSNotification(0))
    doAssert not pointerTransition and not window.fullscreen
    state.fullscreen = false
    state.updateCursorConfinement()
    let originalBounds = native.mouseConfinementRect()
    doAssert originalBounds != NSRect() and controlsLocked

    native.setMouseConfinementRect(NSRect())
    window.configureWindow(Fullscreen, CurrentResolution)
    doAssert window.windowMode == Fullscreen,
      "The display mode request must be pending before simulated failure"
    pointerTransition = true
    pointerFailedTransition(native.ID, s("windowDidFailToEnterFullScreen:"), native)
    doAssert not pointerTransition and confinedBounds == NSRect(),
      "Failed transitions must invalidate the cached rectangle"
    doAssert window.windowMode == Windowed,
      "Failed entry must cancel the pending fullscreen display-mode request"
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == originalBounds,
      "Confinement must be reapplied even when the window bounds are unchanged"
    doAssert not window.mouseCaptured,
      "Fullscreen transitions must keep the system cursor in absolute mode"
    echo "PASS native fullscreen delegate, transitions and failed-entry recovery"

  proc testDeferredControlRestoration() =
    ## Retains the control owner when focus changes during an AppKit transition.
    let
      first = newWindow("GotA pending controls", ivec2(800, 600), visible = false)
      second = newWindow("GotA next controls", ivec2(800, 600), visible = false)
      firstNative = first.nativeWindow
      secondNative = second.nativeWindow
      firstMask = firstNative.styleMask
      secondMask = secondNative.styleMask and not NSWindowStyleMaskResizable
    defer:
      pointerTransition = false
      releaseCursorConfinement()
      first.close()
      second.close()
    secondNative.setMovable(false)
    secondNative.setStyleMask(secondMask)
    updateNativeConfinement(firstNative, true, false, false, AlwaysEdgeScroll)
    pointerTransition = true
    releaseCursorConfinement()
    doAssert confinedWindow.int == 0
    doAssert controlsLocked and controlsWindow.int == firstNative.int,
      "Fullscreen must defer resize restoration while retaining its owner"
    updateNativeConfinement(secondNative, true, false, false, AlwaysEdgeScroll)
    doAssert controlsWindow.int == firstNative.int
    doAssert not secondNative.isMovable and secondNative.styleMask == secondMask,
      "Deferred controls from another window must not leak into a new owner"
    pointerTransition = false
    updateNativeConfinement(secondNative, true, false, false, AlwaysEdgeScroll)
    doAssert firstNative.isMovable and firstNative.styleMask == firstMask,
      "Settled windowed state must restore the original owner's controls"
    doAssert controlsWindow.int == secondNative.int
    releaseCursorConfinement()
    doAssert not controlsLocked and controlsWindow.int == 0
    doAssert not secondNative.isMovable and secondNative.styleMask == secondMask,
      "The new owner must restore its own saved control permissions"
    echo "PASS deferred control restoration retains the correct native owner"

  proc movePointer(window: Window, point: NSPoint) =
    ## Exercises Windy's absolute coordinates and containment synchronously.
    autoreleasepool:
      let event = NSEvent.mouseEventWithType(
        5,
        point,
        0,
        0,
        window.nativeWindow.windowNumber(),
        ID(0),
        0,
        0,
        0
      )
      window.nativeView.mouseMoved(event)

  proc testConfinement() =
    ## Checks real native input at every confined edge before and after resize.
    let window = newWindow(
      "GotA pointer boundaries",
      ivec2(800, 600),
      visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    var state = TestWindow(window: window, focused: true)
    for size in [ivec2(800, 600), ivec2(1200, 900)]:
      window.size = size
      state.updateCursorConfinement(AlwaysEdgeScroll)
      let
        view = window.nativeView
        bounds = view.bounds
        rawOrigin = view.convertPoint(bounds.origin, NSView(0))
      window.movePointer(NSMakePoint(
        rawOrigin.x + bounds.size.width,
        rawOrigin.y + bounds.size.height / 2
      ))
      doAssert not window.mouseInside,
        "The exact right boundary reproduces the stopped-scrolling input"
      window.movePointer(NSMakePoint(
        rawOrigin.x + bounds.size.width / 2,
        rawOrigin.y
      ))
      doAssert not window.mouseInside,
        "The exact bottom boundary reproduces the stopped-scrolling input"
      let
        confined = cursorConfinementBounds(view)
        clearances = [
          confined.origin.x - rawOrigin.x,
          confined.origin.y - rawOrigin.y,
          rawOrigin.x + bounds.size.width -
            (confined.origin.x + confined.size.width),
          rawOrigin.y + bounds.size.height -
            (confined.origin.y + confined.size.height)
        ]
      for clearance in clearances:
        doAssert clearance == 0,
          "Confinement must reach the full content area without a visible inset"
      for direction in [
        vec2(-1, 0), vec2(1, 0), vec2(0, -1), vec2(0, 1),
        vec2(-1, -1), vec2(1, -1), vec2(-1, 1), vec2(1, 1)
      ]:
        window.movePointer(NSMakePoint(
          confined.origin.x +
            (direction.x.float64 + 1) / 2 * confined.size.width,
          confined.origin.y +
            (1 - direction.y.float64) / 2 * confined.size.height
        ))
        doAssert window.mousePos.x >= 0 and window.mousePos.y >= 0 and
          window.mousePos.x <= window.size.x and
          window.mousePos.y <= window.size.y,
          "Native edge input must reach the content boundaries on every side"
        var target = vec3(0)
        if not window.mouseInside:
          doAssert state.rtsPanDir(AlwaysEdgeScroll, GotaEdgePanMargin) == vec2(0),
            "Unconfined outside input must still stop edge scrolling"
        for frame in 0 ..< 120:
          let pan = state.rtsPanDir(
            AlwaysEdgeScroll,
            GotaEdgePanMargin,
            pointerConfined = true
          )
          doAssert pan == rtsPanDir(vec2(0), direction)
          doAssert applyRtsPan(target, pan, 1.0'f / 60, 20, 1000)
        doAssert target.x * direction.x >= 0
        doAssert target.z * direction.y >= 0
        doAssert target.length > 30,
          "A stationary edge cursor must pan continuously"
      echo "PASS native confinement edges/corners at ", window.size,
        " scale=", window.contentScale

  testWindowObservers()
else:
  echo "Native cursor confinement test requires macOS."
