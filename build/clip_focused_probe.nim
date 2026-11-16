## Exercises real desktop fullscreen edges and Cmd-Tab without game assets.
import
  std/[monotimes, os, strformat, times],
  opengl, vmath
include ../games/gods_of_the_arena/pointers

when defined(macosx) and not defined(emscripten):
  const LogPath = currentSourcePath().parentDir / "gota-focused-clip.log"

  objc:
    proc presentationOptions(
      self: NSApplication
    ): NSApplicationPresentationOptions
      ## Reads the application's requested system presentation options.
    proc currentSystemPresentationOptions(
      self: NSApplication
    ): NSApplicationPresentationOptions
      ## Reads the presentation flags actually in effect for the desktop.
    proc mouseConfinementRect(self: NSWindow): NSRect
      ## Reads the restriction applied to the native system cursor.
    proc firstResponder(self: NSWindow): ID
      ## Reads the content view receiving keyboard input.
    proc keyWindow(self: NSApplication): NSWindow
      ## Distinguishes app activation from this window having keyboard focus.

    proc contentLayoutRect(self: NSWindow): NSRect
      ## Reads the native content layout area independently of view bounds.
    proc visibleRect(self: NSView): NSRect
      ## Reads the visible view rectangle independently of its requested bounds.
    proc updateTrackingAreas(self: NSView)
      ## Refreshes AppKit's native pointer tracking regions for this probe.
    proc updateWindows(self: NSApplication)
      ## Services native window updates before the diagnostic capture reset.
    proc setFrame(self: NSWindow, x: NSRect, display: bool, animate: bool)
      ## Explicitly disables animation while testing frame synchronization.

  proc runFullscreenCheck() =
    ## Leaves time for sustained edge hover, F11 switching and Cmd-Tab recovery.
    createDir(LogPath.parentDir)
    let
      log = open(LogPath, fmWrite)
      window = newWindow("Gota fullscreen cursor check", ivec2(1920, 1080))
      started = getMonoTime()
      deadline = started + initDuration(seconds = 180)
    defer:
      window.updateCursorConfinement(NoEdgeScroll)
      window.setFullscreen(false)
      releaseCursorConfinement()
      window.close()
      log.writeLine("Closed fullscreen check")
      log.close()
    window.makeContextCurrent()
    loadExtensions()
    var
      mouseEvents = 0
      lastState: string
      nextLog = started

    proc recordState(force = false) =
      ## Records focus changes immediately and pointer progress every second.
      let
        native = window.nativeWindow
        state = &"fullscreen={window.isFullscreen}" &
          &" nativeFullscreen={window.fullscreen} focused={window.focused}" &
          &" active={NSApp.isActive} key={NSApp.keyWindow().int}" &
          &" window={native.int} minimized={native.isMiniaturized}" &
          &" class={object_getClass(native.ID)} frame={native.frame}" &
          &" mask={native.styleMask} level={native.level}" &
          &" firstResponder={native.firstResponder().int}" &
          &" view={native.contentView.int}" &
          &" viewFrame={native.contentView.frame}" &
          &" bounds={native.contentView.bounds}" &
          &" visibleRect={native.contentView.visibleRect()}" &
          &" layout={native.contentLayoutRect}" &
          &" pixels={window.size} scale={window.contentScale}" &
          &" backing={native.contentView.convertRectToBacking(native.contentView.bounds)}" &
          &" requested={NSApp.presentationOptions()}" &
          &" effective={NSApp.currentSystemPresentationOptions()}" &
          &" confined={native.mouseConfinementRect()}"
        now = getMonoTime()
      if force or state != lastState or now >= nextLog:
        let elapsed = (now - started).inMilliseconds
        log.writeLine(
          &"ms={elapsed} {state} mouse={window.mousePos}" &
          &" nativeMouse={native.mouseLocationOutsideOfEventStream}" &
          &" inside={window.mouseInside} moves={mouseEvents}"
        )
        log.flushFile()
        lastState = state
        nextLog = now + initDuration(seconds = 1)

    window.onMouseMove = proc() =
      ## Counts movement delivered through Windy's native mouse-event path.
      inc mouseEvents
    window.onFocusChange = proc() =
      ## Exercises the same release and restoration callback as the game.
      window.updateCursorConfinement()
      recordState(true)
    window.onButtonPress = proc(button: Button) =
      ## Toggles fullscreen with F11 and closes the test with Escape.
      if button == KeyF11:
        log.writeLine("ACTION F11 fullscreen toggle")
        window.setFullscreen(not window.isFullscreen)
        recordState(true)
      elif button in {KeyF5, KeyF6, KeyF7}:
        log.writeLine("ACTION ", button)
        let native = window.nativeWindow
        releaseCursorConfinement()
        if button == KeyF6:
          native.contentView.updateTrackingAreas()
          NSApp.updateWindows()
        elif button == KeyF7:
          native.setFrame(native.frame, true, false)
          NSApp.updateWindows()
        updateNativeConfinement(native, window.focused and NSApp.isActive,
          window.isFullscreen, window.closeRequested, AlwaysEdgeScroll)
        recordState(true)
      elif button == KeyEscape:
        window.closeRequested = true
    window.onFrame = proc() =
      ## Keeps the native pointer live while drawing a simple test background.
      window.updateCursorConfinement(AlwaysEdgeScroll)
      glViewport(0, 0, window.size.x, window.size.y)
      glClearColor(0.06, 0.16, 0.24, 1)
      glClear(GL_COLOR_BUFFER_BIT)
      window.swapBuffers()
      recordState()

    window.updateCursorConfinement(AlwaysEdgeScroll)
    window.prepareDesktopFullscreen()
    recordState(true)
    echo "READY pid=", getCurrentProcessId(), " log=", LogPath
    echo "F11 fullscreen; F5 reset; F6 tracking/update; F7 nonanimated frame; Escape."
    while not window.closeRequested and getMonoTime() < deadline:
      window.updateWindowSettings()
      pollEvents()
      sleep(8)
    if getMonoTime() >= deadline:
      echo "Fullscreen check reached its 180-second timeout."

  runFullscreenCheck()
else:
  echo "Desktop fullscreen pointer check requires macOS."
