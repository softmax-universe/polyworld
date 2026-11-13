## Execute production frontend gates; no sockets, browser, or game startup.
import std/[macros, strutils, unittest, os, unicode, importutils]
import chroma, opengl, silky, vmath, windy, windy/internal
import polyworld/[chrome, menus, rooms, roomclients, viewers]
import ../[lobbies, homes]
privateAccess(Window)

# Only the transport boundary is replaced. The modal, native textbox, storage,
# connection predicate and direct-invite dispatch below are production AST.
type TestConnection = ref object
  client: RoomClient
  reconnects: int
proc reconnectAfter(connection: TestConnection, delay: float64) =
  inc connection.reconnects
proc presentFrame(window: Window, rate: int) = discard
proc reportReplayFrame(tick, maximum: int) = discard
const framePaceHz = 0

macro identityFrame(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIfStmt and
        node[0][0].repr.startsWith("editingPlayer or"):
      return node
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing production identity modal")

macro inviteDispatch(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIfStmt and node[0][0].repr.startsWith("client.welcomed and"):
      return node
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing production invite dispatch")

macro multiplayerConnected(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIdentDefs and node[0].repr == "connected":
      return node[^1]
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing multiplayer create/join gate")

macro homeMultiplayer(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkOfBranch and node[0].repr == "PlayMultiplayer":
      # Execute the navigation/connection request, omitting roster-only resets.
      result = newStmtList()
      for statement in node[^1]:
        if statement.kind == nnkAsgn and statement[0].repr in ["page", "connectRequested"]:
          result.add statement
      return
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing Home multiplayer route")

proc connecting(connection: TestConnection): bool = false

macro connectionGate(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIfStmt and node[0][0].repr.startsWith("connectRequested and"):
      return node[0][0]
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing frontend connection gate")

macro needsName(): untyped =
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIdentDefs and node[0].repr == "needsPlayerName":
      return node[^1]
    for child in node:
      let found = find(child)
      if found != nil: return found
  result = find(parseStmt(staticRead("../frontend.nim")))
  if result == nil: error("Missing frontend identity prompt gate")

suite "LvD frontend confirmed identity":
  test "absent blank and legacy Player never connect and require a prompt":
    for saved in ["", "   ", "Player", "player", "  pLaYeR  "]:
      let preferences = Preferences(name: saved)
      let connectRequested = true
      let editingPlayer = false
      check not connectionGate()
      check needsName()

  test "saved actual names skip prompting without altering opaque bytes":
    for saved in ["mason :)", "空 白 🙂", "  quotes \"colon: (name)  ",
        "Player One", "Player :)" , "Ω"]:
      let preferences = Preferences(name: saved)
      let connectRequested = true
      let editingPlayer = false
      check connectionGate()
      check not needsName()

  test "an open editor blocks even a pending connection for a saved name":
    let preferences = Preferences(name: "Existing name")
    let connectRequested = true
    let editingPlayer = true
    check not connectionGate()

  test "unconfirmed names never seed a game title":
    for name in ["", " ", "Player", "  PLAYER  "]:
      check defaultGameName(name) == ""

let window = newWindow("LvD identity regression", ivec2(800, 540), visible = false)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
builder.addLobbyFonts()
let sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
# Set LVD_IDENTITY_TEST_DIR to put all real setConfig I/O in isolated scratch.
let configPath = getEnv("LVD_IDENTITY_TEST_DIR", getTempDir()) /
  ("lvd-identity-" & $getCurrentProcessId())
let AppName = relativePath(configPath, getConfigHome(""))
var
  preferences = Preferences()
  page = MultiplayerMenu
  playerName, roomName, error: string
  editingPlayer, connectRequested, joinRequested: bool
  connection: TestConnection
  invite = "Ab12Cd"
  backgroundActions: int

proc frame() =
  let needsPlayerName = needsName()
  identityFrame()
  inc backgroundActions

proc reset(saved = "", editing = false) =
  if dirExists(configPath): removeDir(configPath)
  preferences = Preferences(name: saved)
  page = MultiplayerMenu
  playerName = ""
  roomName = defaultGameName(saved)
  editingPlayer = editing
  connectRequested = true
  joinRequested = true
  connection = nil
  error = ""
  backgroundActions = 0
  window.state.perFrame.buttonPressed = {}
  window.state.buttonDown = {}
  window.state.perFrame.buttonReleased = {}
  frame()
  if "newPlayerName" in textBoxStates:
    let editor = textBoxStates["newPlayerName"]
    editor.setText("")
    editor.focus(sk, window, "newPlayerName")
    editor.cursor = 0
    editor.selector = 0

proc typeName(value: string) =
  for rune in value.runes:
    window.onRune(rune)
    frame()
    doAssert not connectionGate(), "Typing must never release pending connection"

proc enter() =
  window.state.perFrame.buttonPressed = {KeyEnter}
  frame()
  window.state.perFrame.buttonPressed = {}

suite "LvD production native name editor":
  test "fresh storage and stored placeholders prompt on Home multiplayer entry":
    for stored in ["missing", "", "   ", "Player", "  pLaYeR  ", "Saved Ω :)"]:
      reset()
      if stored != "missing":
        Preferences(name: stored).savePreferences(AppName)
      preferences = readPreferences(AppName)
      page = HomeMenu
      connectRequested = false
      backgroundActions = 0
      homeMultiplayer()
      check page == MultiplayerMenu
      check connectRequested
      frame()
      if stored == "Saved Ω :)":
        check backgroundActions == 1
        check connectionGate()
      else:
        check backgroundActions == 0
        check not connectionGate()

  test "create and join remain unavailable with an old welcomed connection":
    reset()
    connection = TestConnection(client: RoomClient(connected: true, welcomed: true))
    for saved in ["", "   ", "Player", " pLaYeR "]:
      preferences.name = saved
      check not multiplayerConnected()
      let client = connection.client
      inviteDispatch()
      check client.outgoing.len == 0
    preferences.name = "Actual Ω"
    check multiplayerConnected()
    editingPlayer = true
    check not multiplayerConnected()

  test "last native input and Enter in one frame save the latest text":
    reset()
    for rune in "mason :)".runes: window.onRune(rune)
    enter()
    check preferences.name == "mason :)"
    check readPreferences(AppName).name == "mason :)"
    check connectionGate()

  test "invalid control and length bounds remain enforced":
    for name in ["line\nbreak", "tab\tname", "delete\x7f", "x".repeat(65), "白".repeat(22)]:
      check not confirmedPlayerName(name)
    check confirmedPlayerName("x".repeat(64))

  test "typing remains modal; explicit confirmation saves exact opaque names":
    for name in ["mason :)", "空 白 🙂", "  quotes \"colon: (name)  ", "Player :)"]:
      reset("Player")
      typeName(name)
      check playerName == name
      check preferences.name == "Player"
      check getConfig(AppName, "settings.json") == ""
      check backgroundActions == 0
      enter()
      check error == ""
      check preferences.name == name
      check readPreferences(AppName).name == name
      check roomName == name & "'s game"
      check connectionGate()
      check backgroundActions == 0 # confirmation frame cannot click through

  test "placeholder confirmation remains blocked":
    for name in ["Player", "  pLaYeR  ", "   "]:
      reset()
      typeName(name)
      enter()
      check preferences.name == ""
      check getConfig(AppName, "settings.json") == ""
      check not connectionGate()
      check backgroundActions == 0

  test "cancel leaves no saved identity and disarms queued invite":
    reset()
    typeName("Draft only")
    window.state.perFrame.buttonPressed = {KeyEscape}
    frame()
    window.state.perFrame.buttonPressed = {}
    check page == HomeMenu
    check not connectRequested
    check not joinRequested
    check getConfig(AppName, "settings.json") == ""
    check backgroundActions == 0

  test "custom room title survives confirmation and later edits":
    reset("Player")
    roomName = "Our custom Ω arena"
    typeName("mason :)")
    enter()
    check roomName == "Our custom Ω arena"

  test "canceling an existing-name edit retains saved identity and custom title":
    reset("Saved Ω", editing = true)
    preferences.savePreferences(AppName)
    roomName = "Custom room"
    typeName("Unsaved draft")
    window.state.perFrame.buttonPressed = {KeyEscape}
    frame()
    window.state.perFrame.buttonPressed = {}
    check page == MultiplayerMenu
    check not editingPlayer
    check preferences.name == "Saved Ω"
    check readPreferences(AppName).name == "Saved Ω"
    check roomName == "Custom room"
    check backgroundActions == 0

  test "storage failure keeps the prompt closed to networking":
    reset()
    typeName("Cannot save yet")
    writeFile(configPath, "block directory creation")
    enter()
    check error.len > 0
    check preferences.name == ""
    check not connectionGate()
    check backgroundActions == 0
    removeFile(configPath)
    enter()
    check preferences.name == "Cannot save yet"
    check error == ""
    check connectionGate()

  test "confirmed invite dispatch waits through editor and sends exact room once":
    reset("Player")
    typeName("空 白 :)")
    enter()
    require connectionGate()
    connection = TestConnection(client: RoomClient(connected: true, welcomed: true))
    let client = connection.client
    editingPlayer = true
    inviteDispatch()
    check client.outgoing.len == 0
    editingPlayer = false
    inviteDispatch()
    require client.outgoing.len == 1
    check decode(client.outgoing[0]).kind == JoinRoom
    check decode(client.outgoing[0]).room == invite
    inviteDispatch()
    check client.outgoing.len == 1

if dirExists(configPath): removeDir(configPath)
window.close()
