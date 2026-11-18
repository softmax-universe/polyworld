import std/os
include ../games/gods_of_the_arena/pointers

objc:
  proc mouseConfinementRect(self: NSWindow): NSRect
    ## Reads AppKit's requested cursor rectangle without moving the cursor.
  proc contentLayoutRect(self: NSWindow): NSRect
    ## Reads the usable native content layout rectangle.
  proc backingScaleFactor(self: NSWindow): float64
    ## Reads the native pixel density.

proc report(window: Window, label: string) =
  ## Dumps native geometry without showing or focusing the window.
  let native = window.nativeWindow
  echo label, " frame=", native.frame, " view.frame=", native.contentView.frame,
    " view.bounds=", native.contentView.bounds,
    " layout=", native.contentLayoutRect,
    " backing=", native.contentView.convertRectToBacking(native.contentView.bounds),
    " confinement=", native.mouseConfinementRect,
    " size=", window.size, " scale=", native.backingScaleFactor,
    " visible=", window.visible

proc probe(size: IVec2) =
  ## Compares the Gota and live-harness sizes through identical hidden changes.
  let window = newWindow("Hidden Retina geometry", size, visible = false)
  defer:
    releaseCursorConfinement()
    window.setFullscreen(false)
    window.close()
  window.prepareDesktopFullscreen()
  let native = window.nativeWindow
  window.report("initial")
  updateNativeConfinement(native, true, false, false, AlwaysEdgeScroll)
  window.report("confined-windowed")
  window.setFullscreenCallbacks(
    proc() = releaseCursorConfinement(),
    proc() = updateNativeConfinement(native, true, window.isFullscreen,
      false, AlwaysEdgeScroll)
  )
  window.setFullscreen(true)
  window.report("fullscreen-immediate")
  for i in 0 ..< 5:
    pollEvents()
    sleep(10)
  window.report("fullscreen-polled")
  let fullBounds = native.contentView.bounds
  native.setFrame(NSMakeRect(0, 0, 600, 400), true)
  window.report("shrunk-with-confinement")
  native.setFrame(native.screen.frame, true)
  window.report("restored-with-confinement")
  native.setMouseConfinementRect(fullBounds)
  window.report("reapplied-identical-bounds")
  native.setMouseConfinementRect(NSRect())
  native.setMouseConfinementRect(fullBounds)
  window.report("reset-then-reapplied")

probe(ivec2(1920, 1080))
probe(ivec2(1000, 700))
