import std/[monotimes, os, times]
import windy
import windy/platforms/macos/macdefs

objc:
  proc presentationOptions(self: NSApplication): NSApplicationPresentationOptions
  proc currentSystemPresentationOptions(self: NSApplication): NSApplicationPresentationOptions

proc frames(seconds: float) =
  let deadline = getMonoTime() + initDuration(milliseconds = int(seconds * 1000))
  while getMonoTime() < deadline:
    pollEvents()
    sleep(10)

proc report(window: Window, label: string) =
  echo label, " fullscreen=", window.fullscreen, " focused=", window.focused,
    " requested=", NSApp.presentationOptions(),
    " system=", NSApp.currentSystemPresentationOptions()

let window = newWindow("GotA fullscreen input check", ivec2(800, 600))
frames(0.3)
report(window, "Windowed")
window.fullscreen = true
frames(1.5)
report(window, "Fullscreen")
let original = NSApp.presentationOptions()
NSApp.setPresentationOptions((original and not (1'u or 4'u or 2048'u)) or 2'u or 8'u)
frames(0.3)
report(window, "Hidden system bars")
window.fullscreen = false
frames(1.5)
report(window, "Exited fullscreen")
NSApp.setPresentationOptions(0)
window.close()
