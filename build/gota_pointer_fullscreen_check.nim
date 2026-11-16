import std/[os, times], windy, vmath, opengl
include ../games/gods_of_the_arena/pointers

objc:
  proc mouseConfinementRect(self: NSWindow): NSRect
    ## Reads the restriction applied to the visible native window.

proc pump(window: Window) =
  ## Advances AppKit's real fullscreen animation and pointer lifecycle.
  pollEvents()
  window.updateCursorConfinement()
  discard NSRunLoop.currentRunLoop.runMode(
    NSDefaultRunLoopMode,
    NSDate.dateWithTimeIntervalSinceNow(0.01)
  )

proc waitForMode(window: Window, fullscreen: bool) =
  ## Fails promptly if the real native transition does not finish.
  let deadline = epochTime() + 12
  while pointerTransition or window.fullscreen != fullscreen:
    window.pump()
    doAssert epochTime() < deadline, "Native fullscreen transition timed out"
  let settle = epochTime() + 0.25
  while epochTime() < settle:
    window.pump()
  doAssert ((window.nativeWindow.styleMask and
    NSWindowStyleMaskFullScreen) != 0) == fullscreen

proc main() =
  ## Exercises real titlebar teardown and rebuilding in every capture mode.
  let window = newWindow("GotA fullscreen regression check", ivec2(800, 600))
  defer:
    releaseCursorConfinement()
    window.close()
  window.makeContextCurrent()
  loadExtensions()
  window.onFrame = proc() =
    glViewport(0, 0, window.size.x, window.size.y)
    glClearColor(0.06, 0.12, 0.20, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    window.swapBuffers()
  window.onFocusChange = proc() =
    window.updateCursorConfinement()
  let focusDeadline = epochTime() + 8
  while not window.focused:
    window.pump()
    doAssert epochTime() < focusDeadline, "Native test window did not focus"
  let originalMask = window.nativeWindow.styleMask
  for mode in [NoEdgeScroll, FullscreenEdgeScroll, AlwaysEdgeScroll]:
    window.updateCursorConfinement(mode)
    echo "Entering fullscreen with ", mode
    window.fullscreen = true
    window.waitForMode(true)
    doAssert window.focused
    doAssert not window.mouseCaptured
    doAssert window.cursorConfined == (mode != NoEdgeScroll)
    if mode != NoEdgeScroll:
      doAssert window.nativeWindow.mouseConfinementRect() ==
        cursorConfinementBounds(window.nativeView)
      doAssert (NSApp.presentationOptions() and PresentationAutoReveal) == 0
    echo "Leaving fullscreen with ", mode
    window.fullscreen = false
    window.waitForMode(false)
    doAssert window.focused
    doAssert window.cursorConfined == (mode == AlwaysEdgeScroll)
    if mode == AlwaysEdgeScroll:
      doAssert not window.nativeWindow.isMovable
      doAssert window.nativeWindow.styleMask ==
        (originalMask and not NSWindowStyleMaskResizable)
    else:
      doAssert window.nativeWindow.isMovable
      doAssert window.nativeWindow.styleMask == originalMask
    echo "PASS native fullscreen round trip: ", mode
  window.updateCursorConfinement(NoEdgeScroll)
  doAssert window.nativeWindow.styleMask == originalMask
  echo "PASS real fullscreen entry/exit, cursor confinement and window controls"

main()
