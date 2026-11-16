import std/[monotimes, times]
import windy
import windy/platforms/macos/macdefs
import ../games/gods_of_the_arena/graphics as traceGraphics

{.compile: "trace_window_info.m".}
proc traceServerBounds(number: cint): cstring {.cdecl, importc.}
  ## Queries public WindowServer geometry without capturing screen contents.

const ClipTracePath = "/Users/me/p/polyworld/build/gota-actual-clip.log"
var
  clipTraceFile = open(ClipTracePath, fmWrite)
  clipTraceStart = getMonoTime()
  originalTraceRect, originalTraceFrame, originalTraceShape: IMP
  lastTraceWindow: NSWindow
  lastTraceCgs: ID
  clipTraceTimer: ID
  clipSnapshotScheduled: bool
  clipMouseAttached, clipStagesStarted: bool
  clipMouseMoves, clipRepairStage: int
  clipLastMouse: IVec2
  clipNextMouseLog: MonoTime

proc class_getMethodImplementation(cls: Class, selector: SEL): IMP
    {.cdecl, importc, dynlib: "libobjc.dylib".}
  ## Reads the real implementation before installing diagnostic observers.
proc class_replaceMethod(cls: Class, selector: SEL, imp: IMP, types: cstring): IMP
    {.cdecl, importc, dynlib: "libobjc.dylib".}
  ## Installs process-local logging while forwarding every native operation.
proc CGRegionGetBoundingBox(region: pointer): NSRect {.cdecl, importc.}
  ## Reads the clipping shape without altering it.

objc:
  proc setMouseConfinementRect(self: NSWindow, x: NSRect)
    ## Reapplies the existing native restriction for staged diagnosis.
  proc convertRect(self: NSView, x: NSRect, toView: NSView): NSRect
    ## Converts content bounds to the native window's point coordinates.
  proc update(self: NSOpenGLContext)
    ## Refreshes the native OpenGL drawable after resize.
  proc updateWindows(self: NSApplication)
    ## Services AppKit's ordinary pending window updates.
  proc updateTrackingAreas(self: NSView)
    ## Rebuilds the normal content-view tracking areas.
  proc windowNumber(self: NSWindow): int
    ## Matches public WindowServer metadata to the native window.
  proc performSelector(self: ID, x: SEL, withObject: ID, afterDelay: float64)
    ## Schedules automatic diagnostic cleanup through the native loop.
  proc size(self: ID): NSSize
    ## Reads the NSCGSWindow cached geometry used by cursor clipping.
  proc eventShape(self: ID): pointer
    ## Reads the low-level mouse event region.
  proc activationShape(self: ID): pointer
    ## Reads the low-level activation region.
  proc opaqueShape(self: ID): pointer
    ## Reads the low-level opaque content region.
  proc resizeEventShape(self: ID): pointer
    ## Reads the low-level resize handles region.
  proc mouseConfinementShape(self: ID): pointer
    ## Reads the NSCGSWindow geometry in window coordinates.
  proc mouseConfinementRect(self: NSWindow): NSRect
    ## Reads the requested high-level rectangle.
  proc respondsToSelector(self: ID, x: SEL): bool
    ## Avoids invoking optional diagnostic selectors on incompatible versions.

proc clipTraceLine(value: string) =
  ## Flushes each state change for live inspection without altering timing loops.
  clipTraceFile.writeLine($((getMonoTime() - clipTraceStart).inMilliseconds) &
    "ms " & value)
  clipTraceFile.flushFile()

proc traceNativeGeometry(native: NSWindow): string =
  ## Captures window and content geometry after the original method returns.
  result = "window=" & $native.int & " frame=" & $native.frame &
    " visible=" & $native.isVisible & " key=" & $native.isKeyWindow &
    " active=" & $NSApp.isActive & " mask=" & $native.styleMask &
    " server=" & $traceServerBounds(native.windowNumber.cint)
  if native.contentView.int != 0:
    result.add " view=" & $native.contentView.bounds & " backing=" &
      $native.contentView.convertRectToBacking(native.contentView.bounds)
  let animatingSelector = s("_frameIsCurrentlyAnimating")
  if native.ID.respondsToSelector(animatingSelector):
    let animating = cast[proc(self: NSWindow, cmd: SEL): bool {.cdecl.}](
      objc_msgSend)(native, animatingSelector)
    result.add " animating=" & $animating

proc attachTraceMouse()
  ## Hooks real game mouse movement after fullscreen confinement first applies.

proc traceConfinementRect(self: ID, cmd: SEL, rect: NSRect) {.cdecl.} =
  ## Logs requested confinement and the resulting native window dimensions.
  if rect.size.width > 0 and rect.size.height > 0:
    attachTraceMouse()
    if lastTraceWindow.int != self.int:
      if lastTraceWindow.int != 0:
        lastTraceWindow.ID.release()
      lastTraceWindow = self.NSWindow
      self.retain()
    if not clipSnapshotScheduled:
      clipSnapshotScheduled = true
      clipTraceTimer.performSelector(s("snapshot:"), ID(0), 1.0)
  clipTraceLine("RECT before requested=" & $rect & " " &
    traceNativeGeometry(self.NSWindow))
  cast[proc(self: ID, cmd: SEL, rect: NSRect) {.cdecl.}](
    originalTraceRect)(self, cmd, rect)
  clipTraceLine("RECT after requested=" & $self.NSWindow.mouseConfinementRect &
    " " & traceNativeGeometry(self.NSWindow))

proc traceNativeFrame(
    self: ID, cmd: SEL, frame: NSRect, display: bool
) {.cdecl.} =
  ## Records the exact frame sent to AppKit and its returned geometry.
  cast[proc(self: ID, cmd: SEL, frame: NSRect, display: bool) {.cdecl.}](
    originalTraceFrame)(self, cmd, frame, display)
  clipTraceLine("FRAME requested=" & $frame & " display=" & $display & " " &
    traceNativeGeometry(self.NSWindow))

proc traceConfinementShape(self: ID, cmd: SEL, shape: pointer) {.cdecl.} =
  ## Records the low-level size used when transforming the requested region.
  if lastTraceCgs.int != self.int:
    if lastTraceCgs.int != 0:
      lastTraceCgs.release()
    lastTraceCgs = self
    self.retain()
  clipTraceLine("SHAPE before cgs=" & $self.int & " size=" & $self.size &
    " requested=" & $CGRegionGetBoundingBox(shape) &
    " event=" & $CGRegionGetBoundingBox(self.eventShape) &
    " activation=" & $CGRegionGetBoundingBox(self.activationShape) &
    " opaque=" & $CGRegionGetBoundingBox(self.opaqueShape) &
    " resize=" & $CGRegionGetBoundingBox(self.resizeEventShape))
  cast[proc(self: ID, cmd: SEL, shape: pointer) {.cdecl.}](
    originalTraceShape)(self, cmd, shape)
  clipTraceLine("SHAPE after cgs=" & $self.int & " size=" & $self.size &
    " stored=" & $CGRegionGetBoundingBox(self.mouseConfinementShape))

proc snapshotClipTrace(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Samples settled geometry after the first native confinement request.
  if lastTraceWindow.int != 0:
    clipTraceLine("SNAPSHOT " & traceNativeGeometry(lastTraceWindow))
  if lastTraceCgs.int != 0:
    clipTraceLine("SNAPSHOT cgs=" & $lastTraceCgs.int &
      " size=" & $lastTraceCgs.size &
      " clip=" & $CGRegionGetBoundingBox(lastTraceCgs.mouseConfinementShape) &
      " event=" & $CGRegionGetBoundingBox(lastTraceCgs.eventShape) &
      " activation=" & $CGRegionGetBoundingBox(lastTraceCgs.activationShape) &
      " opaque=" & $CGRegionGetBoundingBox(lastTraceCgs.opaqueShape))

proc runClipRepair(stage: int) =
  ## Tries one native repair while the same game window remains active.
  let window = traceGraphics.window
  if window == nil or window.closed or not window.focused or not NSApp.isActive:
    clipTraceLine("STAGE " & $stage & " skipped: game does not have focus")
    return
  clipRepairStage = stage
  let native = window.nativeWindow
  clipTraceLine("STAGE " & $stage & " begin " & traceNativeGeometry(native))
  case stage
  of 2:
    NSApp.updateWindows()
    native.contentView.updateTrackingAreas()
  of 3:
    native.contentView.NSOpenGLView.openGLContext.update()
  of 4:
    native.orderOut(ID(0))
    native.makeKeyAndOrderFront(ID(0))
    discard native.makeFirstResponder(native.contentView)
  else:
    discard
  native.setMouseConfinementRect(NSRect())
  native.setMouseConfinementRect(
    native.contentView.convertRect(native.contentView.bounds, NSView(0)))
  clipTraceLine("STAGE " & $stage & " end " & traceNativeGeometry(native))

proc repairClipOnce(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Retries confinement after four seconds of physical movement.
  runClipRepair(1)

proc repairClipUpdates(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Refreshes native window and tracking state after eight seconds.
  runClipRepair(2)

proc repairClipContext(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Refreshes the OpenGL drawable after twelve seconds.
  runClipRepair(3)

proc repairClipOrder(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Tests reordering the same focused window after sixteen seconds.
  runClipRepair(4)

proc attachTraceMouse() =
  ## Logs real cursor events and starts stages only after the pointer moves.
  let window = traceGraphics.window
  if clipMouseAttached or window == nil or window.closed:
    return
  clipMouseAttached = true
  clipLastMouse = window.mousePos
  clipNextMouseLog = getMonoTime()
  let originalMouseMove = window.onMouseMove
  window.onMouseMove = proc() =
    ## Preserves game input and observes movement without synthesizing events.
    if originalMouseMove != nil:
      originalMouseMove()
    let now = getMonoTime()
    inc clipMouseMoves
    if not clipStagesStarted and clipMouseMoves >= 2 and
      window.mousePos != clipLastMouse and window.focused and NSApp.isActive:
        clipStagesStarted = true
        clipTraceLine("PHYSICAL movement started; repair stages in4/8/12/16sec")
        clipTraceTimer.performSelector(s("repairOnce:"), ID(0), 4.0)
        clipTraceTimer.performSelector(s("repairUpdates:"), ID(0), 8.0)
        clipTraceTimer.performSelector(s("repairContext:"), ID(0), 12.0)
        clipTraceTimer.performSelector(s("repairOrder:"), ID(0), 16.0)
    clipLastMouse = window.mousePos
    if now >= clipNextMouseLog:
      clipTraceLine("MOVE stage=" & $clipRepairStage &
        " events=" & $clipMouseMoves & " mouse=" & $window.mousePos &
        " native=" & $window.nativeWindow.mouseLocationOutsideOfEventStream &
        " size=" & $window.size & " key=" & $window.focused &
        " active=" & $NSApp.isActive)
      clipNextMouseLog = now + initDuration(milliseconds = 100)
  clipTraceLine("Attached physical mouse observer")

proc finishClipTrace(self: ID, cmd: SEL, unused: ID) {.cdecl.} =
  ## Ends only this temporary diagnostic process without changing preferences.
  snapshotClipTrace(self, cmd, unused)
  clipTraceLine("Automatic trace timeout")
  clipTraceFile.close()
  quit(0)

proc installClipTrace() =
  ## Adds temporary native logging before the actual Gota entry point starts.
  let
    windowClass = objc_getClass("NSWindow")
    cgsClass = objc_getClass("NSCGSWindow")
  originalTraceRect = class_getMethodImplementation(windowClass,
    s("setMouseConfinementRect:"))
  originalTraceFrame = class_getMethodImplementation(windowClass,
    s("setFrame:display:"))
  originalTraceShape = class_getMethodImplementation(cgsClass,
    s("setMouseConfinementShape:"))
  discard class_replaceMethod(windowClass, s("setMouseConfinementRect:"),
    cast[IMP](traceConfinementRect), "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
  discard class_replaceMethod(windowClass, s("setFrame:display:"),
    cast[IMP](traceNativeFrame), "v@:{CGRect={CGPoint=dd}{CGSize=dd}}B")
  discard class_replaceMethod(cgsClass, s("setMouseConfinementShape:"),
    cast[IMP](traceConfinementShape), "v@:^v")
  clipTraceLine("Installed actual Gota confinement trace")
  var timerClass: Class
  addClass "GotaClipTraceTimer", "NSObject", timerClass:
    addMethod "finish:", finishClipTrace
    addMethod "snapshot:", snapshotClipTrace
    addMethod "repairOnce:", repairClipOnce
    addMethod "repairUpdates:", repairClipUpdates
    addMethod "repairContext:", repairClipContext
    addMethod "repairOrder:", repairClipOrder
  clipTraceTimer = timerClass.new()
  clipTraceTimer.performSelector(s("finish:"), ID(0), 90.0)

installClipTrace()
include ../games/gods_of_the_arena/gota
