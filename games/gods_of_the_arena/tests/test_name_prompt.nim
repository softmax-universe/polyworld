## Execute production frontend AST routes without graphics, browser or sockets.
import std/[macros, os, strutils, unittest]
import vmath, jsony
import polyworld/[menus, roomclients, rooms]
import ../[content, joiningseats, lobbies, playernames, settings]

macro needsName(): untyped =
  let tree = parseStmt(readFile(currentSourcePath().parentDir.parentDir / "frontend.nim"))
  proc find(node: NimNode): NimNode =
    if node.kind == nnkIdentDefs and node[0].eqIdent("needsPlayerName"):
      return node[^1]
    for child in node:
      result = find(child)
      if result != nil: return
  result = find(tree)
  doAssert result != nil

macro frontendRoute(route: static[string]): untyped =
  let target = route
  let
    source = if target == "preferenceLoader": "settings.nim" else: "frontend.nim"
    tree = parseStmt(readFile(currentSourcePath().parentDir.parentDir / source))
  proc find(node: NimNode): NimNode =
    if target == "preferenceLoader" and node.kind == nnkProcDef and
        (node[0].eqIdent("readGotaPreferences") or
        (node[0].kind == nnkPostfix and
          node[0][1].eqIdent("readGotaPreferences"))):
      result = copyNimTree(node)
      if result[0].kind == nnkPostfix:
        result[0] = result[0][1]
      return
    if target == "readPreferences" and node.kind == nnkAsgn and
        node[0].eqIdent("preferences") and
        ("readPreferences" in node[1].repr or "readGotaPreferences" in node[1].repr):
      return node[1]
    if target == "connect" and node.kind == nnkIfStmt and
        "connectRequested" in node[0][0].repr:
      return node
    if target == "prompt" and node.kind == nnkIfStmt and
        "editingPlayer" in node[0][0].repr:
      return node[0][0]
    if target == "startup" and node.kind == nnkStmtList:
      for i, child in node:
        if child.kind == nnkLetSection and child[0][0].eqIdent("inviteServer"):
          result = newStmtList()
          for j in i ..< node.len:
            if node[j].kind == nnkWhileStmt: break
            result.add node[j]
          return
    if target == "multiplayer" and node.kind == nnkOfBranch and
        node[0].eqIdent("GotaPlayMultiplayer"):
      return node[^1]
    if target == "roomDraft" and node.kind == nnkCall and
        node[0].repr == "roomName.refreshGameName":
      return node
    if target == "createRoom" and node.kind == nnkIfStmt and
        "\"Create Room\"" in node[0][0].repr:
      return node[0][^1]
    if target == "candidate" and node.kind == nnkLetSection:
      for child in node:
        if child.kind == nnkIdentDefs and child[0].eqIdent("valid"):
          return node
    if target == "humanLabel" and node.kind == nnkVarSection:
      for child in node:
        if child.kind == nnkIdentDefs and child[0].eqIdent("name") and
            "Add player" in child[^1].repr:
          return child[^1]
    if target == "confirm" and node.kind == nnkTryStmt and
        "updated.savePreferences" in node.repr:
      return node[0]
    if target == "cancel" and node.kind == nnkIfStmt and
        "Cancel" in node[0][0].repr:
      return node[0][^1]
    if target == "localStart" and node.kind == nnkIfStmt and
        "emptyCount < HeroClassCount" in node[0][0].repr:
      return node[0][^1]
    for child in node:
      result = find(child)
      if result != nil: return
  result = find(tree)
  doAssert result != nil, "Missing production route: " & route

type TestConnection = ref object
  client: RoomClient
var socketCalls: int
var savedPreferences: Preferences
proc close(connection: TestConnection) = discard
proc reconnectAfter(connection: TestConnection, delay: float64) = discard
proc connecting(connection: TestConnection): bool = false
proc serverUrl(server: string): string = server
proc savePreferences(preferences: Preferences, app: string) =
  savedPreferences = preferences
proc gotaIdentity(): int = 0
proc connect(server, name: string, identity: int): TestConnection =
  inc socketCalls
  TestConnection(client: RoomClient(connected: true, name: name))
const AppName = "test"

proc tryConnect(name: string): tuple[sockets: int, pending: bool] =
  var
    preferences = Preferences(name: name)
    connectRequested = true
    connection: TestConnection
    prepared: TestConnection
    matchName, viewedPayload, error: string
    preparedRevision, viewedRevision = 0'u32
    configPending = false
    multiplayerHuman = -1
    joiningSeat: JoiningSeat
    networkPolicies: array[HeroClassCount, LocalPolicy]
  socketCalls = 0
  frontendRoute("connect")
  (socketCalls, connectRequested)

suite "GotA name prompt production routes":
  test "fresh preferences and legacy placeholder require a name":
    var preferences = Preferences()
    check needsName()
    for name in ["", " ", "Player", " player ", "pLaYeR", "\tPLAYER\n"]:
      preferences.name = name
      check needsName()

  test "saved opaque names do not prompt":
    var preferences = Preferences()
    for name in ["mason :)", "  spaced name  ", "Zoë 雪 🙂", "Player two", "abc123"]:
      preferences.name = name
      check not needsName()

  test "direct connect opens no socket for missing or legacy names":
    for name in ["", " ", "Player", " player ", "pLaYeR", "bad\nname", repeat("x", 65)]:
      let attempt = tryConnect(name)
      check attempt.sockets == 0
      check attempt.pending
    let attempt = tryConnect("  mason :)  ")
    check attempt.sockets == 1
    check not attempt.pending

  test "name edit cannot submit the legacy placeholder or sanitize controls":
    let window = (size: ivec2(1000, 700),)
    let sk = (uiScale: 1'f,)
    for playerName in ["Player", " player ", "\nAlice", "Alice\t", repeat("x", 65)]:
      frontendRoute("candidate")
      check not valid
    for playerName in ["  opaque name  ", "Zoë 雪 🙂", "Player two"]:
      frontendRoute("candidate")
      check valid
      check name == playerName

  test "local human launch waits for name while bots-only launch does not":
    let config = "{}"
    proc toJson(config: string): string = config
    proc parseConfig(bytes: string): bool = true
    for humanSeat in [-1, 0]:
      var preferences = Preferences()
      var launchLocal, editingPlayer, localLaunchRequested: bool
      frontendRoute("localStart")
      if humanSeat >= 0:
        check not launchLocal
        check editingPlayer
        check localLaunchRequested
      else:
        check launchLocal
        check not editingPlayer

  test "confirm persists exact name and resumes pending local launch":
    var
      preferences = Preferences()
      updated = Preferences(name: "  mason :)  ")
      editingPlayer = true
      localLaunchRequested = true
      launchLocal = false
      connection: TestConnection
      error: string
    let name = updated.name
    frontendRoute("confirm")
    check preferences.name == name
    check savedPreferences.name == name
    check not needsName()
    check not editingPlayer
    check launchLocal
    check not localLaunchRequested

  test "first name confirmation reaches the room creation message":
    for chosen in ["mason :)", "  Zoë 雪 🙂  ", repeat("é", 32)]:
      var
        preferences = Preferences()
        updated = Preferences(name: chosen)
        editingPlayer = true
        localLaunchRequested, launchLocal: bool
        connection: TestConnection
        roomName, roomNameDefault, error: string
        joiningSeat: JoiningSeat
        lobbyUi = (scroll: 12,)
      let
        name = chosen
        publicRoom = true
        config = (maxTicks: 24,)
      frontendRoute("confirm")
      check preferences.name == chosen
      check not needsName()
      connection = connect("test", preferences.name, gotaIdentity())
      frontendRoute("createRoom")
      check connection.client.outgoing.len == 1
      let sent = decode(connection.client.outgoing[0])
      check sent.kind == CreateRoom
      check sent.name == chosen & "'s game"
      check lobbyUi.scroll == 0

  test "renaming refreshes automatic drafts and preserves custom titles":
    for custom in [false, true]:
      var
        preferences = Preferences(name: "Original")
        updated = Preferences(name: "  Current 雪  ")
        editingPlayer = true
        localLaunchRequested, launchLocal: bool
        connection = connect("test", preferences.name, gotaIdentity())
        roomName, roomNameDefault, error: string
        joiningSeat: JoiningSeat
        lobbyUi = (scroll: 12,)
      let
        name = updated.name
        publicRoom = false
        config = (maxTicks: 24,)
        customTitle = "Friends' 雪 match"
      frontendRoute("roomDraft")
      check roomName == "Original's game"
      if custom:
        roomName = customTitle
      frontendRoute("confirm")
      check connection.client.name == name
      frontendRoute("createRoom")
      check connection.client.outgoing.len == 1
      let sent = decode(connection.client.outgoing[0])
      check sent.kind == CreateRoom
      check sent.name == (if custom: customTitle else: name & "'s game")

  test "settings name updates refresh the displayed automatic draft":
    var
      preferences = Preferences(name: "Original")
      roomName, roomNameDefault: string
    frontendRoute("roomDraft")
    preferences.name = "Current"
    frontendRoute("roomDraft")
    check roomName == "Current's game"
    roomName = ""
    preferences.name = "Newest"
    frontendRoute("roomDraft")
    check roomName == ""

  test "cancel retires pending local launch":
    var
      page = SingleMenu
      editingPlayer = true
      localLaunchRequested = true
      connectRequested = false
      playerName, error: string
    let needsPlayerName = true
    frontendRoute("cancel")
    check page == SingleMenu
    check not editingPlayer
    check not localLaunchRequested

  test "unnamed local human label is an action not a generated name":
    let
      empty = false
      human = true
      online = false
      seat = (name: "",)
      localPolicies = [LocalPolicy()]
      i = 0
    for name in ["", "Player", " player "]:
      let preferences = Preferences(name: name)
      check frontendRoute("humanLabel") == "Choose name"
    let preferences = Preferences(name: "mason :)")
    check frontendRoute("humanLabel") == preferences.name

  test "Multiplayer prompts fresh identity before any connection and edit always opens":
    var
      preferences = Preferences()
      page = HomeMenu
      connectRequested = false
      connection: TestConnection
      lobbyUi = (scroll: 0, selectedSeat: -1)
      editingPlayer = false
    frontendRoute("multiplayer")
    let needsPlayerName = needsName()
    check frontendRoute("prompt")
    check page == MultiplayerMenu
    check tryConnect(preferences.name).sockets == 0
    preferences.name = "mason :)"
    block:
      let needsPlayerName = needsName()
      check not frontendRoute("prompt")
      editingPlayer = true
      check frontendRoute("prompt")

  test "eligibility rejects every ASCII control and byte overflow":
    for value in 0 .. 31:
      check not eligiblePlayerName("before" & $char(value) & "after")
    check not eligiblePlayerName("before\x7fafter")
    check not eligiblePlayerName(repeat("x", 65))
    check not eligiblePlayerName(repeat("é", 33))
    check eligiblePlayerName(repeat("x", 64))
    check eligiblePlayerName(repeat("é", 32))

  test "stored overlong identity must not become a valid truncated name":
    var storage = ""
    proc getConfig(app, file: string): string = storage
    proc readPreferences(app: string): Preferences =
      result = if storage.len == 0: Preferences() else: storage.fromJson(Preferences)
      if result.name.len > 64: result.name.setLen(64)
    frontendRoute("preferenceLoader")
    check not eligiblePlayerName(frontendRoute("readPreferences").name)
    storage = "{}"
    check not eligiblePlayerName(frontendRoute("readPreferences").name)
    for original in [repeat("x", 65), "Player", "  mason :)  "]:
      storage = Preferences(name: original).toJson()
      let loaded = frontendRoute("readPreferences")
      check loaded.name == original
      check eligiblePlayerName(loaded.name) == (original == "  mason :)  ")

  test "URL server-only keeps the main menu and invite or explicit server enters multiplayer":
    for invite in ["", "ABC123"]:
      for serverAddress in ["", "ws://direct/ws"]:
        var
          preferences = Preferences()
          page = HomeMenu
          connectRequested = false
        proc inviteParameter(key: string): string = "wss://url/ws"
        frontendRoute("startup")
        check preferences.server == (if serverAddress.len > 0: serverAddress else: "wss://url/ws")
        check (page == MultiplayerMenu) == (invite.len > 0 or serverAddress.len > 0)
        check connectRequested == (invite.len > 0 or serverAddress.len > 0)
        if connectRequested:
          check tryConnect(preferences.name).sockets == 0
