## Exercises real desktop fullscreen edges and Cmd-Tab without game assets.
import
  std/[monotimes, os, strformat, times],
  opengl, vmath
include polyworld/pointers

when defined(macosx) and not defined(emscripten):
  const LogPath = currentSourcePath().parentDir.parentDir.parentDir.parentDir /
    "build/gota-desktop-live.log"

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

  proc runFullscreenCheck() =
    ## Leaves time for sustained edge hover, F11 switching and Cmd-Tab recovery.
    createDir(LogPath.parentDir)
    let
      log = open(LogPath, fmWrite)
      window = newWindow("GotA desktop fullscreen check", ivec2(1000, 700))
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
      ## Exercises the same release and rearm callback as the game.
      window.updateCursorConfinement()
      recordState(true)
    window.onButtonPress = proc(button: Button) =
      ## Captures on click, toggles with F11 and closes with Escape.
      window.captureCursorConfinement(button)
      recordState(true)
      if button == KeyF11:
        window.setFullscreen(not window.isFullscreen)
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
    window.configureWindow(Fullscreen, CurrentResolution)
    window.updateWindowSettings()
    recordState(true)
    echo "READY pid=", getCurrentProcessId(), " log=", LogPath
    echo "Click to confine, then hover and push at all edges."
    echo "Cmd-Tab or F11 releases; click again to confine. Escape closes."
    while not window.closeRequested and getMonoTime() < deadline:
      window.updateWindowSettings()
      pollEvents()
      sleep(8)
    if getMonoTime() >= deadline:
      echo "Fullscreen check reached its 180-second timeout."

  runFullscreenCheck()
else:
  echo "Desktop fullscreen pointer check requires macOS."
