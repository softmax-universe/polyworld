## Native confinement preserves the system cursor across window transitions.
import
  std/[macros, os],
  vmath,
  polyworld/rtscameras,
  ../cameras
include polyworld/pointers

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
  objc:
    proc delegate(self: NSWindow): ID
      ## Checks that cursor setup preserves the original native delegate.
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
    proc firstResponder(self: NSWindow): ID
      ## Checks that style changes retain the game view as the input target.
    proc hasShadow(self: NSWindow): bool
      ## Checks that desktop fullscreen restores the window's shadow state.
    proc hidesOnDeactivate(self: NSWindow): bool
      ## Checks the AppKit visibility policy used for Cmd-Tab restoration.
    proc canBecomeMainWindow(self: NSWindow): bool
      ## Checks which borderless windows can receive application main status.
    proc acceptsMouseMovedEvents(self: NSWindow): bool
      ## Reads native motion delivery independently of synthetic view events.
    proc setAcceptsMouseMovedEvents(self: NSWindow, x: bool)
      ## Seeds a distinct windowed motion policy for restoration checks.
    proc mouseConfinementRect(self: NSWindow): NSRect
      ## Reads the actual native restriction without moving the system cursor.
    proc contentLayoutRect(self: NSWindow): NSRect
      ## Reads expected content geometry independently of the confinement helper.
    proc setBoundsSize(self: NSView, x: NSSize)
      ## Exercises view scaling without changing the display or visible window.
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
    settled: bool = true

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
    updateNativeConfinement(
      window.nativeWindow, window.focused, window.fullscreen,
      window.closeRequested, cursorEdgeScrolling,
      settled = window.settled
    )

  proc updateCursorConfinement(window: TestWindow, mode: EdgeScrollMode) =
    ## Applies the same retained preference as the public window entry point.
    cursorEdgeScrolling = mode
    window.updateCursorConfinement()

  proc clickCursorConfinement(window: TestWindow, button = MouseLeft) =
    ## Sends a physical click through the production native latch decision.
    updateNativeConfinement(
      window.nativeWindow, window.focused, window.fullscreen,
      window.closeRequested, cursorEdgeScrolling,
      clicked = cursorConfinementClick(button), settled = window.settled
    )

  proc rtsPointerInside(window: TestWindow): bool =
    ## Preserves Windy's exact native boundary containment in the camera test.
    window.window.mouseInside

  macro testCameraPan(): untyped =
    ## Runs the production camera pan with only OS focus made deterministic.
    let source = parseStmt(readFile(
      currentSourcePath().parentDir.parentDir.parentDir.parentDir /
        "src/polyworld/rtscameras.nim"
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
    let
      plainClass = object_getClass(plain.nativeWindow.ID)
      plainDelegate = plain.nativeWindow.delegate()
    installPointerHooks(plain)
    doAssert plain.nativeWindow.delegate().int == plainDelegate.int
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

    plain.fullscreen = true
    doAssert plain.fullscreen and not window.fullscreen,
      "Other Windy windows must retain their own fullscreen lifecycle"
    doAssert not plain.visible and not window.visible
    plain.fullscreen = false
    doAssert not plain.fullscreen
    echo "PASS native window classes, KVO observers and unchanged delegates"

  proc testConfinementLifecycle() =
    ## Requires fresh clicks after focus, preference, resize and close changes.
    let window = newWindow(
      "GotA confinement lifecycle", ivec2(800, 600), visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    installPointerHooks(window)
    let
      native = window.nativeWindow
      originalMask = native.styleMask
      originalFrame = native.frame
      originalBounds = window.nativeView.bounds
    doAssert native.isMovable
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    doAssert native.mouseConfinementRect() == NSRect(),
      "Startup and preference application must leave the cursor free"
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)
    doAssert not window.mouseCaptured,
      "Confinement must preserve absolute pointer input for edge scrolling"
    doAssert not native.isMovable,
      "Captured windowed play must disable native dragging"
    doAssert native.firstResponder().int == window.nativeView.int,
      "Resize locking must retain the game view as the native input target"
    doAssert native.styleMask ==
      (originalMask and not NSWindowStyleMaskResizable)
    doAssert native.frame == originalFrame and
      window.nativeView.bounds == originalBounds,
      "Locking controls must preserve the geometry checked before capture"

    state.focused = false
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Switching apps must immediately release the native cursor restriction"
    doAssert native.isMovable and native.styleMask == originalMask
    doAssert native.firstResponder().int == window.nativeView.int
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Unfocused input must not grant a future capture"
    state.focused = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Refocusing must wait for a new click"
    state.clickCursorConfinement(MouseRight)
    doAssert native.mouseConfinementRect() != NSRect()

    let beforeResize = native.mouseConfinementRect()
    window.size = ivec2(1200, 900)
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "A resized window must release rather than replace its clip"
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()
    state.clickCursorConfinement(MouseMiddle)
    doAssert native.mouseConfinementRect() != beforeResize
    doAssert native.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)

    state.updateCursorConfinement(NoEdgeScroll)
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()
    doAssert native.isMovable and native.styleMask == originalMask
    state.focused = false
    state.updateCursorConfinement()
    state.focused = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()

    state.updateCursorConfinement(FullscreenEdgeScroll)
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()
    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Enabling the current mode must not reuse an earlier rejected click"
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() != NSRect()
    state.fullscreen = false
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()

    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.clickCursorConfinement()
    state.closeRequested = true
    state.updateCursorConfinement()
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Closing must release confinement and reject further capture"
    doAssert confinedWindow.int == 0 and confinedBounds == NSRect()
    doAssert native.isMovable and native.styleMask == originalMask
    doAssert not controlsLocked
    releaseCursorConfinement()

    native.setMovable(false)
    native.setStyleMask(originalMask and not NSWindowStyleMaskResizable)
    state.closeRequested = false
    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.clickCursorConfinement()
    state.updateCursorConfinement(NoEdgeScroll)
    doAssert not native.isMovable
    doAssert (native.styleMask and NSWindowStyleMaskResizable) == 0,
      "Release must not enable controls that were disabled before capture"
    echo "PASS click latch, focus/refocus, resize, preferences and close"

  proc testDesktopFullscreen() =
    ## Checks real borderless transitions while leaving the window hidden.
    let window = newWindow(
      "GotA desktop fullscreen",
      ivec2(800, 600),
      visible = false
    )
    defer:
      releaseCursorConfinement()
      window.setFullscreen(false)
      window.close()
    installPointerHooks(window)
    window.nativeWindow.setAcceptsMouseMovedEvents(false)
    let
      native = window.nativeWindow
      originalMask = native.styleMask
      originalFrame = native.frame
      originalLevel = native.level
      originalShadow = native.hasShadow
      originalHides = native.hidesOnDeactivate
      originalMouseMoved = native.acceptsMouseMovedEvents
      originalClass = object_getClass(native.ID)
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.clickCursorConfinement()
    doAssert controlsLocked
    window.configureWindow(Fullscreen, CurrentResolution)
    window.updateWindowSettings()
    doAssert window.isFullscreen and window.windowMode == Fullscreen
    doAssert window.desktopFullscreen and not window.fullscreen,
      "Desktop fullscreen must not enter an AppKit fullscreen Space"
    doAssert not window.desktopFullscreenChanging
    doAssert not window.visible,
      "Changing the display mode must not show an intentionally hidden window"
    doAssert not controlsLocked,
      "The original controls must be restored before saving windowed state"
    doAssert native.hidesOnDeactivate and not native.hasShadow,
      "Desktop fullscreen must hide on app switching and remove the shadow"
    doAssert native.canBecomeMainWindow,
      "The fullscreen game must remain eligible for native main-window input"
    doAssert native.acceptsMouseMovedEvents,
      "Desktop fullscreen must deliver pointer movement without held buttons"
    doAssert (native.styleMask and (NSWindowStyleMaskTitled or
      NSWindowStyleMaskResizable or NSWindowStyleMaskFullScreen)) == 0
    doAssert native.frame == native.screen.frame
    doAssert native.firstResponder().int == window.nativeView.int
    doAssert object_getClass(native.ID).int == originalClass.int
    state.fullscreen = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Fullscreen completion must wait for a fresh click"
    state.clickCursorConfinement()
    doAssert native.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)
    doAssert not controlsLocked and not window.mouseCaptured

    window.configureWindow(Windowed, CurrentResolution)
    window.updateWindowSettings()
    doAssert not window.isFullscreen and window.windowMode == Windowed
    doAssert native.styleMask == originalMask and native.frame == originalFrame,
      "Leaving fullscreen must restore the unlocked windowed snapshot"
    doAssert native.level == originalLevel and native.isMovable
    doAssert native.hasShadow == originalShadow
    doAssert native.hidesOnDeactivate == originalHides,
      "Leaving desktop fullscreen must restore the original visibility policy"
    doAssert native.acceptsMouseMovedEvents == originalMouseMoved,
      "Leaving desktop fullscreen must restore the original motion policy"
    doAssert native.firstResponder().int == window.nativeView.int
    state.fullscreen = false
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()
    doAssert not controlsLocked,
      "Windowed completion must not re-lock resize controls before a click"
    state.clickCursorConfinement()
    doAssert controlsLocked
    doAssert (native.styleMask and NSWindowStyleMaskResizable) == 0
    state.updateCursorConfinement(NoEdgeScroll)
    doAssert native.styleMask == originalMask and native.isMovable
    echo "PASS desktop fullscreen lifecycle, input target and control restoration"

  proc testMainWindowOwnership() =
    ## Leaves unrelated borderless windows on AppKit's original eligibility.
    let window = newWindow(
      "Unrelated borderless window",
      ivec2(400, 300),
      visible = false
    )
    defer: window.close()
    window.style = Undecorated
    let mainEligible = window.nativeWindow.canBecomeMainWindow
    installPointerHooks(window)
    doAssert window.nativeWindow.canBecomeMainWindow == mainEligible,
      "Pointer hooks must preserve Windy's borderless main-window eligibility"
    echo "PASS unrelated borderless main-window eligibility"

  proc testControlOwners() =
    ## Restores each window's saved controls when confinement changes owners.
    let
      first = newWindow("GotA first controls", ivec2(800, 600), visible = false)
      second = newWindow("GotA next controls", ivec2(800, 600), visible = false)
      firstNative = first.nativeWindow
      secondNative = second.nativeWindow
      firstMask = firstNative.styleMask
      secondMask = secondNative.styleMask and not NSWindowStyleMaskResizable
    defer:
      releaseCursorConfinement()
      first.close()
      second.close()
    secondNative.setMovable(false)
    secondNative.setStyleMask(secondMask)
    updateNativeConfinement(firstNative, true, false, false,
      AlwaysEdgeScroll, clicked = true)
    doAssert controlsWindow.int == firstNative.int
    updateNativeConfinement(secondNative, true, false, false,
      AlwaysEdgeScroll, clicked = true)
    doAssert firstNative.isMovable and firstNative.styleMask == firstMask,
      "Changing owners must restore the original window's controls"
    doAssert controlsWindow.int == secondNative.int
    releaseCursorConfinement()
    doAssert not controlsLocked and controlsWindow.int == 0
    doAssert not secondNative.isMovable and secondNative.styleMask == secondMask,
      "The new owner must restore its own saved control permissions"
    echo "PASS control restoration retains the correct native owner"

  proc testMethodImplementation(cls: Class, selector: SEL): IMP
      {.cdecl, importc: "class_getMethodImplementation", dynlib: "libobjc.dylib".}
    ## Saves the native setter while recording the test window's updates.

  proc replaceTestMethod(
      cls: Class, selector: SEL, implementation: IMP, encoding: cstring
  ): IMP {.cdecl, importc: "class_replaceMethod", dynlib: "libobjc.dylib".}
    ## Installs a temporary spy without replacing any window instance's class.

  var
    observedConfinementWindow: NSWindow
    originalConfinementSetter: IMP
    confinementWrites: seq[NSRect]

  proc observeConfinement(
      self: ID, cmd: SEL, bounds: NSRect
  ) {.cdecl.} =
    ## Records clear-and-reapply ordering while forwarding the real native call.
    if self.int == observedConfinementWindow.int:
      confinementWrites.add bounds
    cast[proc(self: ID, cmd: SEL, bounds: NSRect) {.cdecl.}](
      originalConfinementSetter
    )(self, cmd, bounds)

  proc testClickLatch() =
    ## Leaves startup and rejected clicks inert until a stable physical click.
    const Encoding = "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"
    let window = newWindow(
      "GotA click latch", ivec2(800, 600), visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    installPointerHooks(window)
    let
      native = window.nativeWindow
      cls = object_getClass(native.ID)
      selector = s("setMouseConfinementRect:")
    observedConfinementWindow = native
    originalConfinementSetter = testMethodImplementation(cls, selector)
    discard replaceTestMethod(
      cls, selector, cast[IMP](observeConfinement), Encoding
    )
    defer:
      discard replaceTestMethod(
        cls, selector, originalConfinementSetter, Encoding
      )
      observedConfinementWindow = NSWindow(0)
    confinementWrites.setLen(0)
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    for frame in 0 ..< 20:
      state.updateCursorConfinement()
    for button in [KeySpace, KeyEnter, DoubleClick, TripleClick, QuadrupleClick]:
      state.clickCursorConfinement(button)
    doAssert confinementWrites.len == 0 and not controlsLocked,
      "Startup, frames, keys and click notifications must not create a clip"

    state.settled = false
    state.clickCursorConfinement()
    state.settled = true
    for frame in 0 ..< 20:
      state.updateCursorConfinement()
    pollEvents()
    doAssert confinementWrites.len == 0,
      "A click during resize must not schedule capture after the resize ends"
    state.clickCursorConfinement(MouseButton4)
    doAssert native.mouseConfinementRect() ==
      cursorConfinementBounds(window.nativeView)
    doAssert confinementWrites.len > 0
    let writes = confinementWrites.len
    for frame in 0 ..< 20:
      state.updateCursorConfinement()
    doAssert confinementWrites.len == writes,
      "Passive frames must retain the existing clip without reapplying it"

    state.settled = false
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect()
    state.settled = true
    state.updateCursorConfinement()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Leaving a native transition must keep confinement unlatched"
    state.clickCursorConfinement(MouseButton5)
    doAssert native.mouseConfinementRect() != NSRect()
    releaseCursorConfinement()
    state.updateCursorConfinement()
    pollEvents()
    doAssert native.mouseConfinementRect() == NSRect(),
      "Explicit release must not leave any deferred capture request behind"
    doAssert not window.visible
    echo "PASS physical click latch, stable geometry and no deferred capture"

  proc testConfinementGeometry() =
    ## Keeps window-point bounds distinct from Retina pixels and native position.
    const Encoding = "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"
    let window = newWindow(
      "GotA Retina confinement geometry", ivec2(1920, 1080), visible = false
    )
    defer:
      releaseCursorConfinement()
      window.close()
    let
      native = window.nativeWindow
      view = native.contentView
      cls = object_getClass(native.ID)
      selector = s("setMouseConfinementRect:")
    observedConfinementWindow = native
    originalConfinementSetter = testMethodImplementation(cls, selector)
    discard replaceTestMethod(
      cls, selector, cast[IMP](observeConfinement), Encoding
    )
    defer:
      discard replaceTestMethod(
        cls, selector, originalConfinementSetter, Encoding
      )
      observedConfinementWindow = NSWindow(0)
    var state = TestWindow(window: window, focused: true)
    state.updateCursorConfinement(AlwaysEdgeScroll)
    state.clickCursorConfinement()
    let
      initialPoints = native.contentLayoutRect
      initialBacking = view.convertRectToBacking(view.bounds)
      scale = window.contentScale.float64
    doAssert confinedBounds == initialPoints,
      "Native confinement must cover the content in window points"
    doAssert initialPoints.size.width * scale == initialBacking.size.width
    doAssert initialPoints.size.height * scale == initialBacking.size.height
    doAssert initialBacking.size.width == window.size.x.float64
    doAssert initialBacking.size.height == window.size.y.float64
    doAssert not native.confinementGeometryChanged()

    confinementWrites.setLen(0)
    let frame = native.frame
    native.setFrameOrigin(NSMakePoint(frame.origin.x + 19, frame.origin.y + 23))
    doAssert cursorConfinementBounds(view) == initialPoints,
      "Moving the window must preserve its window-relative point rectangle"
    doAssert native.confinementGeometryChanged(),
      "Native window movement must invalidate a same-sized confinement cache"
    state.updateCursorConfinement()
    doAssert confinementWrites == @[NSRect()],
      "Movement must release AppKit's stale restriction without recapturing"
    state.clickCursorConfinement()
    doAssert confinementWrites[^1] == initialPoints
    doAssert not native.confinementGeometryChanged()

    confinementWrites.setLen(0)
    window.size = ivec2(2560, 1440)
    state.updateCursorConfinement()
    let resizedPoints = native.contentLayoutRect
    doAssert confinementWrites == @[NSRect()],
      "Growing the window must clear the old clip and await a new click"
    state.clickCursorConfinement()
    doAssert confinementWrites[^1] == resizedPoints
    doAssert resizedPoints.size.width * scale == window.size.x.float64
    doAssert resizedPoints.size.height * scale == window.size.y.float64

    if scale != 1:
      # Simulate cached geometry from a one-pixel-per-point display.
      confinedBacking = confinedBounds
      doAssert native.confinementGeometryChanged(),
        "A backing-scale change must invalidate otherwise identical point bounds"
      confinementWrites.setLen(0)
      state.updateCursorConfinement()
      doAssert confinementWrites == @[NSRect()]
      state.clickCursorConfinement()
      doAssert confinementWrites[^1] == resizedPoints
      doAssert not native.confinementGeometryChanged()

    let originalBounds = view.bounds
    view.setBoundsSize(NSMakeSize(
      originalBounds.size.width / 2,
      originalBounds.size.height / 2
    ))
    doAssert cursorConfinementBounds(view) == resizedPoints,
      "The complete view rectangle must be converted, including its size"
    view.setBoundsSize(originalBounds.size)
    echo "PASS window-point bounds, Retina backing, movement and reset ordering"

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

  proc testCommittedWindowGeometry() =
    ## Rejects stale server geometry before confinement reaches the full display.
    let
      fullscreen = NSMakeRect(0, 0, 1512, 982)
      expected = windowServerFrame(fullscreen, 982)
      serverFrames = [
        NSMakeRect(276, 207, 960, 568),
        NSMakeRect(138, 103, 1236, 775),
        NSMakeRect(0, 0, 1512, 982)
      ]
    doAssert expected == fullscreen
    for i, frame in serverFrames:
      doAssert confinementFramesMatch(expected, frame) ==
        (i == serverFrames.high),
        "Capture must wait until the server reaches the final window frame"
    doAssert not confinementFramesMatch(expected,
      NSMakeRect(0, 0, 3024, 1964)),
      "WindowServer geometry uses points, independently of Retina pixels"
    doAssert not confinementFramesMatch(expected,
      NSMakeRect(10, 0, 1512, 982)),
      "A matching size at the old position must not pass the readiness check"
    doAssert confinementFramesMatch(expected,
      NSMakeRect(0.5, -0.5, 1512.5, 981.5)),
      "Native coordinate rounding must not leave confinement pending forever"
    doAssert not confinementFramesMatch(expected,
      NSMakeRect(0, 0, 1510, 982))

    doAssert windowServerFrame(NSMakeRect(1512, -300, 1920, 1080), 982) ==
      NSMakeRect(1512, 202, 1920, 1080),
      "Secondary displays must use the primary display's vertical origin"
    doAssert windowServerFrame(NSMakeRect(-1600, 982, 1600, 900), 982) ==
      NSMakeRect(-1600, -900, 1600, 900),
      "Displays above and left of the primary must retain negative coordinates"

    let window = newWindow(
      "GotA uncommitted native geometry", ivec2(800, 600), visible = false
    )
    defer: window.close()
    doAssert not nativeWindowGeometryCommitted(window.nativeWindow),
      "An offscreen window must not be considered ready for cursor confinement"
    doAssert not window.visible
    echo "PASS committed server geometry, Retina points and secondary displays"

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
      state.clickCursorConfinement()
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
  testConfinementLifecycle()
  testDesktopFullscreen()
  testMainWindowOwnership()
  testControlOwners()
  testClickLatch()
  testConfinementGeometry()
  testCommittedWindowGeometry()
  testConfinement()
else:
  echo "Native cursor confinement test requires macOS."
