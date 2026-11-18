import std/os

const BrowserTransportLibrary = currentSourcePath().parentDir /
  "browsertransport.js"

{.passL: "--js-library " & quoteShell(BrowserTransportLibrary).}

proc browserVoiceOpen*(model, voice, apiKey: cstring): cint {.
    importc: "voice_transport_open", cdecl, raises: [].}
  ## Requests a temporary token and opens a browser WebSocket asynchronously.

proc browserVoiceClose*(handle: cint) {.
    importc: "voice_transport_close", cdecl, raises: [].}
  ## Cancels token requests and releases the socket and its queued events.

proc browserVoiceReady*(handle: cint): bool {.
    importc: "voice_transport_ready", cdecl, raises: [].}
  ## Returns true only while the underlying browser socket accepts writes.

proc browserVoiceSend*(handle: cint, message: cstring): bool {.
    importc: "voice_transport_send", cdecl, raises: [].}
  ## Sends one ordered message within a bounded browser send buffer.

proc browserVoiceNextLength(handle: cint): cint {.
    importc: "voice_transport_next_length", cdecl, raises: [].}
  ## Returns the next server event's UTF-8 size without consuming it.

proc browserVoiceNextInto(handle: cint, output: cstring, capacity: cint) {.
    importc: "voice_transport_next_into", cdecl, raises: [].}
  ## Copies and removes the next server event.

proc browserVoiceErrorLength(handle: cint): cint {.
    importc: "voice_transport_error_length", cdecl, raises: [].}
  ## Returns a transport failure after queued server events have drained.

proc browserVoiceErrorInto(handle: cint, output: cstring, capacity: cint) {.
    importc: "voice_transport_error_into", cdecl, raises: [].}
  ## Copies the retained browser transport failure into caller memory.

proc browserVoiceNext*(handle: cint): string =
  ## Retrieves the next event without retaining a view of WASM memory.
  let size = browserVoiceNextLength(handle).int
  if size > 0:
    result = newString(size)
    browserVoiceNextInto(handle, result.cstring, cint(size + 1))

proc browserVoiceError*(handle: cint): string =
  ## Retrieves the browser failure without exposing credentials.
  let size = browserVoiceErrorLength(handle).int
  if size > 0:
    result = newString(size)
    browserVoiceErrorInto(handle, result.cstring, cint(size + 1))
