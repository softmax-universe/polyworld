import std/os, vmath
include ../games/gods_of_the_arena/pointers

objc:
  proc observationInfo(self: NSWindow): pointer
  proc addObserver(self: NSWindow, x: ID, forKeyPath: NSString, options: uint, context: pointer)
  proc removeObserver(self: NSWindow, x: ID, forKeyPath: NSString, context: pointer)

var observations: int
proc observeTitle(self: ID, cmd: SEL, keyPath: NSString, obj: ID, changes: ID, context: pointer) {.cdecl.} =
  inc observations

var observerClass: Class
addClass "GotaKvoProbeObserver", "NSObject", observerClass:
  addMethod "observeValueForKeyPath:ofObject:change:context:", observeTitle
let
  observer = observerClass.new()
  window = newWindow("KVO hidden probe", ivec2(800, 600), visible = false)
  native = window.nativeWindow
  beforeRegistration = object_getClass(native.ID)
echo "Before registration: ", beforeRegistration, " info=", cast[uint](native.observationInfo())
native.addObserver(observer, @"title", 0, nil)
let beforeHook = object_getClass(native.ID)
echo "Before hook: ", beforeHook, " info=", cast[uint](native.observationInfo())
native.setTitle(@"Before hook title update")
echo "Before hook observations: ", observations
installPointerHooks(window)
echo "After hook: ", object_getClass(native.ID), " info=", cast[uint](native.observationInfo())
native.setTitle(@"After hook title update")
echo "After hook observations: ", observations
if observations != 2:
  echo "REGRESSION: hooking lost title observation; skip unsafe observer removal"
  quit(0)
native.removeObserver(observer, @"title", nil)
echo "Observer removal completed"
releaseCursorConfinement()
window.close()
observer.release()
