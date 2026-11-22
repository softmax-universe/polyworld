import std/[os, strformat]
import windy, opengl
include ../games/gods_of_the_arena/pointers

const LogPath = "/Users/me/p/polyworld/build/gota-pointer-probe.log"

objc:
  proc currentSystemPresentationOptions(self: NSApplication): NSApplicationPresentationOptions
  proc mouseConfinementRect(self: NSWindow): NSRect

proc main() =
  let window = newWindow("GotA fullscreen pointer check", ivec2(1000, 700))
  defer:
    releaseCursorConfinement()
    window.close()
  window.makeContextCurrent()
  loadExtensions()
  var frames = 0
  writeFile(LogPath, "Starting pointer check\n")
  window.onFocusChange = proc() =
    window.updateCursorConfinement()
  window.onButtonPress = proc(button: Button) =
    if button == KeyF11:
      window.fullscreen = not window.fullscreen
    elif button == KeyEscape:
      window.closeRequested = true
  window.onFrame = proc() =
    window.updateCursorConfinement(AlwaysEdgeScroll)
    glViewport(0, 0, window.size.x, window.size.y)
    glClearColor(0.05, 0.18, 0.28, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    window.swapBuffers()
    inc frames
    if frames mod 30 == 0:
      let log = open(LogPath, fmAppend)
      log.writeLine(&"fullscreen={window.fullscreen} focused={window.focused} size={window.size} mouse={window.mousePos} inside={window.mouseInside} options={NSApp.presentationOptions()} effective={NSApp.currentSystemPresentationOptions()} movable={window.nativeWindow.isMovable} mask={window.nativeWindow.styleMask} transition={pointerTransition} confined={window.nativeWindow.mouseConfinementRect()}")
      log.close()
  while not window.closeRequested:
    pollEvents()
    sleep(16)

main()
