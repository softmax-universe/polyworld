import
  std/os,
  pixie, silky, silky/testwindow, vmath,
  polyworld/gameuis,
  ../[common, maps, minimaps, resources, selections, sim, ui]

when not defined(silkyTesting):
  {.error: "Run this test with -d:silkyTesting.".}

proc frame(
  harness: var TestHarness,
  chat: var ChatUi,
  pending = false,
  available = true,
  world = World(),
  messages: seq[Message] = @[],
  failure = ""
): string =
  ## Runs the real UI handlers through Silky's window-compatible harness.
  harness.sk.uiScale = chat.scale
  harness.beginFrame()
  result = drawUi(
    harness.sk, harness.window, world, chat, messages,
    pending, available, failure
  )
  harness.endFrame()
  harness.window.syncInput(chat)
  harness.window.resetInputState()

block input:
  var
    harness = newTestHarness(SilkyAtlas(), 1280, 800)
    chat = initChatUi()
  harness.window.installInput(addr chat)
  discard frame(harness, chat)
  doAssert harness.window.runeInputEnabled
  harness.window.typeText("é🙂")
  doAssert chat.input == "é🙂", "Committed Unicode text reaches Monster."
  harness.window.pressButton(KeyBackspace)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyBackspace)
  doAssert chat.input == "é", "Backspace removes one complete codepoint."
  harness.window.typeText("\xff")
  doAssert chat.input == "é", "Malformed UTF-8 cannot corrupt the input."

  chat.restoreInput("Walk to village")
  harness.window.pressButton(KeyLeft)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyLeft)
  harness.window.typeText("!")
  doAssert chat.input == "Walk to villag!e", "Editing honors the caret."

  chat.restoreInput("")
  setClipboardString("Gather berries")
  harness.window.pressButton(KeyLeftSuper)
  harness.window.pressButton(KeyV)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyV)
  harness.window.releaseButton(KeyLeftSuper)
  doAssert chat.input == "Gather berries", "Paste inserts exactly once."

  harness.window.pressButton(KeyEscape)
  discard frame(harness, chat)
  harness.window.releaseButton(KeyEscape)
  doAssert not chat.typing and not harness.window.runeInputEnabled
  harness.window.typeText("ignored")
  doAssert chat.input == "Gather berries"
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat) == "", "Enter first restores chat focus."
  harness.window.releaseButton(KeyEnter)
  doAssert chat.typing and harness.window.runeInputEnabled

  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat, pending = true) == ""
  harness.window.releaseButton(KeyEnter)
  doAssert chat.input == "Gather berries", "Pending requests retain a draft."
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat) == "Gather berries"
  harness.window.releaseButton(KeyEnter)
  doAssert chat.input.len == 0 and chat.typing
  chat.restoreInput("Try again")
  harness.window.typeText(".")
  doAssert chat.input == "Try again.", "A failed send restores the caret."

echo "Monster chat focus, Unicode editing, clipboard, and retry tests passed."

proc movePointer(window: Window, point: Vec2) =
  ## Positions the harness pointer using a calculated framebuffer location.
  window.moveMouse(point.x.int, point.y.int)

proc hasTextIn(node: SemanticNode, text: string, panel: GameUiPanel): bool =
  ## Finds a live label within a particular resource slot or status region.
  if node.isNil:
    return false
  if node.text == text and panel.contains(
    vec2(node.rect.x + node.rect.w / 2, node.rect.y + node.rect.h / 2)):
      return true
  for child in node.children:
    if child.hasTextIn(text, panel):
      return true

block scaledInput:
  var
    harness = newTestHarness(SilkyAtlas(), 2560, 1600)
    chat = initChatUi()
  chat.scale = 2
  harness.window.installInput(addr chat)
  discard frame(harness, chat)
  chat.restoreInput("Walk to the village")
  let boxes = chatLayout(harness.window.size.vec2 / chat.scale)
  harness.window.movePointer((boxes.send.origin + boxes.send.size / 2) * 2)
  doAssert chat.mouseOverUi(harness.window),
    "The scaled chat panel blocks camera gestures."
  harness.window.pressButton(MouseLeft)
  doAssert frame(harness, chat) == "Walk to the village",
    "The scaled Send button receives clicks at framebuffer coordinates."
  harness.window.releaseButton(MouseLeft)
  harness.window.moveMouse(40, 40)
  doAssert not chat.mouseOverUi(harness.window),
    "World gestures remain available outside scaled panels."

echo "Monster scaled layout and click tests passed."

block panelLayout:
  let image = readImage(currentSourcePath().parentDir.parentDir /
    "assets" / "hud" / "woodland-frame.png")
  for framebuffer in [vec2(1440, 900), vec2(1280, 800), vec2(1040, 800),
      vec2(960, 720), vec2(640, 480), vec2(2560, 1600), vec2(640, 900)]:
    let
      size = framebuffer / chatScale(framebuffer)
      boxes = chatLayout(size)
    for panel in [boxes.panel, boxes.stats, boxes.minimap,
        boxes.history, boxes.input, boxes.send, boxes.scrollbar,
        boxes.portrait, boxes.name, boxes.primaryLabel, boxes.primaryMeter,
        boxes.carrying, boxes.utility]:
      doAssert panel.inside(size),
        "Live controls remain visible while the lower decorative rim is clipped."
    doAssert not boxes.panel.overlaps(boxes.stats),
      "The conversation stays clear of the bottom-right creature stats."
    doAssert not boxes.minimap.overlaps(boxes.panel),
      "The bottom-left map stays clear of the conversation."
    doAssert not boxes.minimap.overlaps(boxes.stats)
    doAssert abs(boxes.frame.size.x / boxes.frame.size.y -
      image.width.float32 / image.height.float32) < 0.001,
      "The joined frame retains its original proportions."
    doAssert boxes.history.size.x > boxes.minimap.size.x * 2,
      "Conversation remains the dominant HUD area."
    doAssert boxes.input.size.x >= 200 and boxes.history.size.y > 0
    for panel in [boxes.minimap, boxes.history, boxes.input, boxes.send,
        boxes.portrait, boxes.primaryMeter]:
      let
        center = panel.origin + panel.size / 2
        source = (center - boxes.frame.origin) / boxes.frame.size *
          vec2(image.width.float32, image.height.float32)
      doAssert image[source.x.int, source.y.int].a <= 8,
        "Live widget centers align with actual transparent artwork openings."
  var
    harness = newTestHarness(SilkyAtlas(), 1280, 800)
    chat = initChatUi()
  discard frame(harness, chat)
  for label in ["VILLAGES", "View", "World overview", "Find my creature"]:
    doAssert harness.findByText(label) == nil,
      "The old village and camera panels have been removed."
  let boxes = chatLayout(harness.window.size.vec2)
  harness.window.movePointer(boxes.stats.origin + vec2(20))
  doAssert chat.mouseOverUi(harness.window)
  harness.window.movePointer(boxes.minimap.origin + vec2(20))
  doAssert chat.mouseOverUi(harness.window)
  harness.window.movePointer(boxes.frame.origin +
    boxes.frame.size * vec2(0.5'f, 0.85'f))
  doAssert chat.mouseOverUi(harness.window),
    "The decorative frame also reserves its pointer events."
  harness.window.moveMouse(1100, 80)
  doAssert not chat.mouseOverUi(harness.window),
    "The old top-right stats area is free for world gestures."

echo "Monster woodland artwork alignment and responsive layout tests passed."

block creatureStats:
  var
    harness = newTestHarness(SilkyAtlas(), 1440, 900)
    chat = initChatUi()
    world = World(creature: Creature(health: 82, energy: 76))
  world.creature.cargo[BerriesResource] = 6
  discard frame(harness, chat, world = world)
  let boxes = chatLayout(harness.window.size.vec2)
  doAssert harness.findByText("Health 82%").hasTextIn("Health 82%",
    boxes.primaryLabel)
  doAssert harness.findByText("Energy 76%").hasTextIn("Energy 76%",
    boxes.utility), "Energy belongs below the fixed health bar."
  doAssert harness.findByText("Carrying 6/6") != nil
  let berries = harness.findByText(BerriesResource.resourceName())
  doAssert berries != nil
  doAssert berries.hasTextIn("6", boxes.stats),
    "The resource icon displays its actual carried amount."
  for kind in GrainResource .. StoneResource:
    doAssert harness.findByText(kind.resourceName()) == nil,
      "Empty resources have neither an icon nor an empty inventory slot."
  doAssert harness.findByText("0") == nil
  world.creature.cargo[BerriesResource] = 0
  world.creature.cargo[FishResource] = 2
  world.creature.cargo[StoneResource] = 4
  world.creature.energy = 41
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Energy 41%") != nil
  doAssert harness.findByText(BerriesResource.resourceName()) == nil
  doAssert harness.findByText(FishResource.resourceName()).hasTextIn("2",
    boxes.stats)
  doAssert harness.findByText(FishResource.resourceName()).rect == berries.rect,
    "Present items pack together instead of leaving holes for empty resources."
  doAssert harness.findByText(StoneResource.resourceName()).hasTextIn("4",
    boxes.stats),
    "Resource quantities update with the live inventory each frame."
  world.creature.cargo = default(Inventory)
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Empty hands") != nil
  for kind in ResourceKind:
    doAssert harness.findByText(kind.resourceName()) == nil
  for kind in ResourceKind:
    world.creature.cargo[kind] = 1
  discard frame(harness, chat, world = world)
  for kind in ResourceKind:
    let item = harness.findByText(kind.resourceName())
    doAssert item != nil
  harness.window.movePointer(boxes.utility.origin + vec2(20))
  harness.window.scrollDelta.y = 200'f / ScrollSpeed.float32
  discard frame(harness, chat, world = world)
  doAssert chat.utilityFrame.scrollPos.y > 0
  let lastItem = harness.findByText(StoneResource.resourceName())
  doAssert lastItem.hasTextIn("1", boxes.utility)
  doAssert boxes.utility.contains(vec2(lastItem.rect.x, lastItem.rect.y))
  doAssert boxes.utility.contains(vec2(lastItem.rect.x + lastItem.rect.w,
    lastItem.rect.y + lastItem.rect.h))
  doAssert harness.findByText("Health 82%").hasTextIn("Health 82%",
    boxes.primaryLabel), "Moss's health remains visible while inventory scrolls."

echo "Monster live creature energy and inventory tests passed."

block inspection:
  var
    harness = newTestHarness(SilkyAtlas(), 1440, 900)
    chat = initChatUi()
    world = newWorld(generateMap())
  chat.restoreInput("Bring fish to Ada")
  let
    person = world.villagerIndex("ada")
    house = world.householdIndex("miller_hut")
    source = world.sourceIndex("fish")
    boxes = chatLayout(harness.window.size.vec2)
  world.villagers[person].health = 65
  world.villagers[person].hunger = 73
  world.villagers[person].sleepiness = 84
  world.villagers[person].cargo = default(Inventory)
  world.villagers[person].cargo[FishResource] = 2
  doAssert chat.select(world, world.selectionById("ada"))
  discard frame(harness, chat, world = world)
  for label in ["Ada", "Health 65%", "Hunger 73%", "Sleepiness 84%",
      "Wary / 2 carried", "Fear 35%", "Trust 0%"]:
    doAssert harness.findByText(label) != nil, label
  harness.window.movePointer(boxes.utility.origin + vec2(20))
  harness.window.scrollDelta.y = 2000'f / ScrollSpeed.float32
  discard frame(harness, chat, world = world)
  doAssert harness.findByText(FishResource.resourceName()).hasTextIn("2",
    boxes.stats)
  doAssert harness.findByText("Energy 100%") == nil
  doAssert chat.input == "Bring fish to Ada" and chat.typing
  doAssert world.actions.len == 0 and not world.active,
    "Inspecting a villager must not order either them or Moss around."
  let selected = chat.selection
  doAssert not chat.select(world, Selection(kind: NoSelection))
  doAssert chat.selection == selected,
    "An empty-ground click keeps the current inspected entity."

  world.villagers[person].trust = 80
  world.villagers[person].fearLevel = 90
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Terrified / 2 carried") != nil,
    "Immediate danger overrides a resident's trust in the profile."
  world.villagers[person].fearLevel = 0
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Allied / 2 carried") != nil
  doAssert harness.findByText("Trust 80%") != nil

  world.villagers[person].health = 0
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Health 0%") != nil
  doAssert harness.findByText(FishResource.resourceName()).hasTextIn("2",
    boxes.stats), "A dead resident's remaining cargo stays inspectable."

  world.households[house].integrity = 38
  world.households[house].fuel = 19
  world.households[house].stock = default(Inventory)
  world.households[house].stock[StoneResource] = 4
  doAssert chat.select(world, world.selectionById("miller_hut"))
  discard frame(harness, chat, world = world)
  for label in ["Miller's hut", "Health 38%", "Warmth 19%"]:
    doAssert harness.findByText(label) != nil, label
  doAssert harness.findByText("Health 38%").hasTextIn("Health 38%",
    boxes.primaryLabel)
  doAssert harness.findByText(StoneResource.resourceName()).hasTextIn("4",
    boxes.stats)
  doAssert harness.findByText("Hunger 73%") == nil
  world.households[house].integrity = 0
  world.households[house].stock = default(Inventory)
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Ruins") != nil
  doAssert harness.findByText("Warmth 19%") == nil

  world.sources[source].amount = 7
  doAssert chat.select(world, world.selectionById("fish"))
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Willow fishing bank") != nil
  doAssert harness.findByText("Available 7/18") != nil
  doAssert harness.findByText("Health 100%") == nil,
    "A resource pile shows its available amount rather than health."
  doAssert harness.findByText(FishResource.resourceName()).hasTextIn("7",
    boxes.stats)
  world.sources[source].amount = 0
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Available 0/18") != nil
  doAssert harness.findByText(FishResource.resourceName()) == nil
  doAssert harness.findByText("No supplies") != nil
  world.sources[source].destroyed = true
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Destroyed") != nil

  world.villages[0].stock = default(Inventory)
  world.villages[0].stock[HardwoodResource] = 5
  world.villages[0].health = 57
  doAssert chat.select(world, world.selectionById("hall"))
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Willow") != nil
  doAssert harness.findByText("Village hall") != nil
  doAssert harness.findByText("Health 57%").hasTextIn("Health 57%",
    boxes.primaryLabel)
  doAssert harness.findByText("Storage 5/4096").hasTextIn("Storage 5/4096",
    boxes.utility), "Hall storage stays below its fixed health bar."
  doAssert harness.findByText(HardwoodResource.resourceName()).hasTextIn("5",
    boxes.stats)
  world.villages[0].health = 0
  world.villages[0].stock = default(Inventory)
  discard frame(harness, chat, world = world)
  doAssert harness.findByText("Ruins") != nil
  doAssert harness.findByText("Storage 0/4096") == nil

  chat.selection = Selection(kind: VillagerSelection, id: "missing")
  discard frame(harness, chat, world = world)
  doAssert chat.selection.kind == MossSelection
  doAssert harness.findByText("Moss") != nil
  doAssert chat.input == "Bring fish to Ada" and chat.typing

echo "Monster selected villagers, homes, stashes, and halls passed."

block minimapNavigation:
  for scale in [1'f, 2'f]:
    var
      harness = newTestHarness(SilkyAtlas(), (1280 * scale).int,
        (800 * scale).int)
      chat = initChatUi()
      world = World(creature: Creature(position: vec2(-32, 24)))
      target = vec3(0)
      following = true
    chat.scale = scale
    chat.restoreInput("Bring fish home")
    world.villagers.add Villager(id: "ada")
    doAssert chat.select(world, world.selectionById("ada"))
    let
      panel = chatLayout(harness.window.size.vec2 / scale).minimap
      area = panel.minimapArea()
      destination = area.origin + area.size * vec2(0.75'f, 0.25'f)
    harness.window.movePointer(destination * scale)
    harness.window.pressButton(MouseLeft)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert chat.minimapPanning and not following
    doAssert abs(target.x - 32) < 1 and abs(target.z + 32) < 1,
      "Scaled minimap clicks place the camera at their world destination."
    doAssert chat.input == "Bring fish home" and chat.typing
    doAssert world.actions.len == 0,
      "Minimap navigation never gives Moss a direct order."
    harness.window.resetInputState()
    harness.window.movePointer((area.origin + area.size + vec2(30)) * scale)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert target == vec3(MapHalf, 0, MapHalf),
      "An active drag continues outside the map and clamps to its bounds."
    doAssert chat.mouseOverUi(harness.window),
      "Captured minimap drags block world camera gestures."
    harness.window.releaseButton(MouseLeft)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert not chat.minimapPanning
    harness.window.resetInputState()
    harness.window.movePointer(
      minimapPosition(world.creature.position, panel) * scale)
    harness.window.pressButton(MouseLeft)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert chat.focusRequested and not chat.minimapPanning,
      "Clicking Moss's icon requests following instead of starting a drag."
    doAssert chat.selection.kind == MossSelection,
      "Moss's minimap portrait restores his profile after inspecting a villager."
    doAssert chat.input == "Bring fish home" and chat.typing
    harness.window.resetInputState()
    harness.window.movePointer(destination * scale)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert not chat.minimapPanning,
      "Dragging after a creature-icon click cannot start terrain panning."
    harness.window.releaseButton(MouseLeft)
    harness.window.resetInputState()
    chat.focusRequested = false
    harness.window.moveMouse(800, 400)
    harness.window.pressButton(MouseLeft)
    chat.updateMinimapCamera(harness.window, world, target, following)
    harness.window.resetInputState()
    harness.window.movePointer(destination * scale)
    chat.updateMinimapCamera(harness.window, world, target, following)
    doAssert not chat.minimapPanning and not chat.focusRequested,
      "A drag begun outside the map cannot be captured by entering it."

echo "Monster minimap click, drag, and creature-follow tests passed."

block utilityScrolling:
  for scale in [1'f, 2'f]:
    var
      harness = newTestHarness(SilkyAtlas(), (1280 * scale).int,
        (800 * scale).int)
      chat = initChatUi()
      world = newWorld(generateMap())
      messages: seq[Message]
    let person = world.villagerIndex("ada")
    world.villagers[person].hunger = 73
    world.villagers[person].sleepiness = 84
    for kind in ResourceKind:
      world.villagers[person].cargo[kind] = 1
    for i in 0 ..< 40:
      messages.add Message(role: EventMessage, text: "Finished action " & $i)
    chat.scale = scale
    chat.restoreInput("Bring berries to Willow")
    doAssert chat.select(world, world.selectionById("ada"))
    discard frame(harness, chat, world = world, messages = messages)
    let
      boxes = chatLayout(harness.window.size.vec2 / scale)
      hunger = harness.findByText("Hunger 73%")
      sleepiness = harness.findByText("Sleepiness 84%")
      fear = harness.findByText("Fear 35%")
      trust = harness.findByText("Trust 0%")
      firstItem = harness.findByText(BerriesResource.resourceName())
      health = harness.findByText("Health 100%")
    doAssert hunger != nil and sleepiness != nil and firstItem != nil
    doAssert hunger.rect.y + hunger.rect.h <= sleepiness.rect.y
    doAssert sleepiness.rect.y + sleepiness.rect.h <= fear.rect.y
    doAssert fear.rect.y + fear.rect.h <= trust.rect.y
    doAssert trust.rect.y + trust.rect.h <= firstItem.rect.y,
      "Carried items follow the stacked needs rather than overlapping them."
    doAssert chat.utilityFrame.scrollPos.y == 0,
      "A selected resident opens at the first stat."

    harness.window.movePointer((boxes.utility.origin + vec2(20)) * scale)
    harness.window.scrollDelta.y = 200'f / ScrollSpeed.float32
    discard frame(harness, chat, world = world, messages = messages)
    let utilityScroll = chat.utilityFrame.scrollPos.y
    doAssert utilityScroll > 0,
      "More carried items remain reachable below the resident's needs."
    doAssert chat.scroll == 0,
      "Scrolling the utility panel cannot move the conversation."
    doAssert harness.findByText("Health 100%").rect == health.rect,
      "The portrait and primary health meter remain fixed while scrolling."
    let lastItem = harness.findByText(StoneResource.resourceName())
    doAssert lastItem != nil
    doAssert boxes.utility.contains(vec2(lastItem.rect.x, lastItem.rect.y))
    doAssert boxes.utility.contains(vec2(lastItem.rect.x + lastItem.rect.w,
      lastItem.rect.y + lastItem.rect.h)),
      "Scrolling to the bottom reveals the complete final item."

    harness.window.moveMouse(40, 40)
    harness.window.scrollDelta.y = 200'f / ScrollSpeed.float32
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y == utilityScroll,
      "Wheel gestures over the world cannot scroll the inspected inventory."
    harness.window.movePointer((boxes.history.origin + vec2(30)) * scale)
    harness.window.scrollDelta.y = -200'f / ScrollSpeed.float32
    discard frame(harness, chat, world = world, messages = messages)
    let historyScroll = chat.scroll
    doAssert historyScroll > 0
    doAssert chat.utilityFrame.scrollPos.y == utilityScroll,
      "The conversation and utility panel keep independent scroll positions."
    doAssert chat.select(world, world.selectionById("ada"))
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y == utilityScroll,
      "Inspecting the same resident again preserves the scroll position."

    chat.utilityFrame.scrollPos.y = 0
    let thumbTop = vec2(
      boxes.utility.origin.x + boxes.utility.size.x - 6,
      boxes.utility.origin.y + 8
    )
    harness.window.movePointer(thumbTop * scale)
    discard frame(harness, chat, world = world, messages = messages)
    harness.window.pressButton(MouseLeft)
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollingY,
      "The utility scrollbar accepts a pointer press at each UI scale."
    harness.window.movePointer(vec2(thumbTop.x,
      boxes.utility.origin.y + boxes.utility.size.y - 16) * scale)
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y > 0
    doAssert chat.scroll == historyScroll
    harness.window.moveMouse(40, 40)
    doAssert chat.mouseOverUi(harness.window),
      "Dragging the utility scrollbar captures gestures outside the HUD."
    discard frame(harness, chat, world = world, messages = messages)
    harness.window.releaseButton(MouseLeft)
    discard frame(harness, chat, world = world, messages = messages)
    doAssert not chat.utilityFrame.scrollingY
    doAssert not chat.mouseOverUi(harness.window)

    harness.window.movePointer((boxes.utility.origin + vec2(20)) * scale)
    harness.window.scrollDelta.y = 200'f / ScrollSpeed.float32
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y > 0
    world.villagers[person].cargo = default(Inventory)
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y < utilityScroll,
      "Giving away cargo clamps the utility offset to the remaining stats."
    doAssert harness.findByText("Empty hands") != nil

    for kind in ResourceKind:
      world.villagers[person].cargo[kind] = 1
    harness.window.scrollDelta.y = 200'f / ScrollSpeed.float32
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.utilityFrame.scrollPos.y > 0
    doAssert chat.select(world, world.selectionById("clara"))
    doAssert chat.utilityFrame.scrollPos.y == 0,
      "Switching residents starts the new inspection at its first stat."
    discard frame(harness, chat, world = world, messages = messages)
    doAssert chat.input == "Bring berries to Willow" and chat.typing,
      "Inspecting stats preserves the conversation draft and keyboard focus."
    doAssert world.actions.len == 0 and not world.active

echo "Monster independent utility scrolling and stacked stats tests passed."

block conversationScrolling:
  for scale in [1'f, 2'f]:
    var
      harness = newTestHarness(SilkyAtlas(), (1280 * scale).int,
        (800 * scale).int)
      chat = initChatUi()
      messages: seq[Message]
    chat.scale = scale
    chat.restoreInput("Bring berries to Willow")
    for i in 0 ..< 40:
      messages.add Message(role: EventMessage, text: "Finished action " & $i)
    discard frame(harness, chat, messages = messages)
    doAssert chat.scroll == 0, "A new conversation begins at its newest line."
    let boxes = chatLayout(harness.window.size.vec2 / scale)
    harness.window.movePointer((boxes.history.origin + vec2(30)) * scale)
    harness.window.scrollDelta.y = -200'f / ScrollSpeed.float32
    discard frame(harness, chat, messages = messages)
    doAssert chat.scroll > 0,
      "Scrolling over the conversation reveals older messages."
    let wheelScroll = chat.scroll
    harness.window.moveMouse(40, 40)
    harness.window.scrollDelta.y = -200'f / ScrollSpeed.float32
    discard frame(harness, chat, messages = messages)
    doAssert chat.scroll == wheelScroll,
      "Wheel input over the world cannot scroll the conversation."

    chat.scroll = 0
    let thumbBottom = vec2(
      boxes.scrollbar.origin.x + boxes.scrollbar.size.x - 6,
      boxes.history.origin.y + boxes.history.size.y - 16
    )
    harness.window.movePointer(thumbBottom * scale)
    discard frame(harness, chat, messages = messages)
    harness.window.pressButton(MouseLeft)
    discard frame(harness, chat, messages = messages)
    doAssert chat.historyFrame.scrollingY,
      "The visible Silky scrollbar thumb accepts a scaled pointer press."
    harness.window.movePointer(vec2(thumbBottom.x,
      boxes.history.origin.y + 12) * scale)
    discard frame(harness, chat, messages = messages)
    doAssert chat.scroll > wheelScroll,
      "Dragging the thumb upward moves back through the transcript."
    harness.window.moveMouse(40, 40)
    doAssert chat.mouseOverUi(harness.window),
      "An active scrollbar drag keeps camera gestures captured outside HUD."
    discard frame(harness, chat, messages = messages)
    harness.window.releaseButton(MouseLeft)
    discard frame(harness, chat, messages = messages)
    doAssert not chat.historyFrame.scrollingY
    doAssert not chat.mouseOverUi(harness.window),
      "Releasing the scrollbar returns outside pointer input to the world."
    doAssert chat.input == "Bring berries to Willow" and chat.typing,
      "Reading the history preserves the user's draft and keyboard focus."

echo "Monster Silky history wheel and thumb-drag tests passed."

block interruptPending:
  var
    harness = newTestHarness(SilkyAtlas(), 1280, 800)
    chat = initChatUi()
  chat.restoreInput("Stop")
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat, pending = true, available = false) == "Stop",
    "Stop reaches the game immediately even while inference is unavailable."
  harness.window.releaseButton(KeyEnter)
  chat.restoreInput("Stop attacking")
  let send = chatLayout(harness.window.size.vec2).send
  harness.window.movePointer(send.origin + send.size / 2)
  harness.window.pressButton(MouseLeft)
  doAssert frame(harness, chat, pending = true) == "Stop attacking",
    "The Send button remains available for an immediate stop."
  harness.window.releaseButton(MouseLeft)
  chat.restoreInput("Attack Ada")
  harness.window.pressButton(KeyEnter)
  doAssert frame(harness, chat, pending = true) == ""
  doAssert chat.input == "Attack Ada",
    "Normal attack requests still wait for the pending model reply."

echo "Monster stop controls passed."
