## Player shop presentation over the shared simulation purchase rules.

import
  std/[algorithm, strutils],
  pixie, silky, vmath, windy,
  polyworld/[inputs, chrome, gameuis, stackpanels],
  content, controls, layouts, sim, game, shopinteractions

const
  Gold = rgbx(247, 215, 135, 255)
  Muted = rgbx(163, 175, 192, 255)
  White = rgbx(241, 244, 250, 255)

var
  waitingItem = NoItem
  receiptSerial = 0
  feedback = "Click an item to buy it."

type ShopSortMode* = enum
  ShopSortName, ShopSortPrice, ShopSortType

const
  CloseTarget = 10
  SortNameTarget = 11
  SellTarget = 14
  CatalogTarget = 100

var
  gestures: ShopGestureState
  sortMode = ShopSortName
  sellSlot = -1
  sellItem = NoItem
  sellCount = 0'i32
  sellPanel: GameUiPanel
  sessionWorld: World
  sessionHero = 0'i32
  sessionSize: Vec2
  gestureInventory: array[InventorySlots, Item]
  gestureCounts: array[InventorySlots, int32]

proc resetShopUi*() =
  ## Retire captures and context targets on match/ownership/resize changes.
  gestures.resetShopGesture()
  sellSlot = -1
  sellItem = NoItem
  waitingItem = NoItem
  receiptSerial = purchaseReceipt.serial
  feedback = "Click an item to buy. Drag inventory to move or swap."
  sessionWorld = nil
  sessionHero = 0

proc closeShop*() =
  shopOpen = false
  resetShopUi()

proc consumeShopEscape*(): bool =
  ## First Esc dismisses context/drag; next Esc closes the shop.
  if sellSlot >= 0 or gestures.draggingShopSlot() >= 0:
    sellSlot = -1
    gestures.resetShopGesture()
    return true
  if shopOpen:
    closeShop()
    return true

proc sortedShopItems*(mode: ShopSortMode): seq[Item] =
  result = @ShopItems
  result.sort(proc(a, b: Item): int =
    case mode
    of ShopSortName: result = cmp(a.itemSpec.name, b.itemSpec.name)
    of ShopSortPrice: result = cmp(a.itemSpec.cost, b.itemSpec.cost)
    of ShopSortType: result = cmp(a.itemSpec.kind, b.itemSpec.kind)
    if result == 0: result = cmp(a.itemSpec.name, b.itemSpec.name)
    if result == 0: result = cmp(a.ord, b.ord))

proc shopInventoryPanels*(size: Vec2): array[InventorySlots, GameUiPanel] =
  ## Own geometry: no coupling to the normal HUD inventory or its controls.
  var footer = shopPanels(size).footer.stack(LeftToRight)
  var inventory = footer.takeColumn(6 * 80, 32).stack(LeftToRight)
  for slot in 0..<InventorySlots:
    result[slot] = inventory.take(vec2(72), 8)

proc shopSortPanels(size: Vec2): array[3, GameUiPanel] =
  let heading = shopPanels(size).heading
  for i in 0..2:
    result[i] = GameUiPanel(origin: heading.origin +
      vec2(84 + i.float32 * 100, 44), size: vec2(96, 26))

proc shopOwned(world: World, hero: Hero): bool =
  ## No alive-only gate: authority handles death/keep and item restrictions.
  run != nil and run.world == world and hero != nil and
    not run.replayMode and not run.historyPlayback and
    options.playerSlot > 0 and options.playerSlot <= world.heroes.len and
    world.heroes[options.playerSlot - 1] == hero and
    world.phase != Drafting and not world.gameOver

proc drawItemCount*(sk: Silky, well: GameUiPanel, count: int32) =
  ## Keeps stack counts legible without covering the icon or cooldown.
  let corner = well.origin + vec2(well.size.x - 25, 2)
  sk.drawRect(corner, vec2(23, 20), rgbx(0, 0, 0, 210))
  sk.drawLabel($count, corner, vec2(23, 20), Gold, "Bold", CenterAlign)

proc itemDescription(item: Item): string =
  ## Summarizes actual item effects without duplicating balance numbers.
  let spec = item.itemSpec
  var lines: seq[string]
  if item in [BattleAxe, SunsteelLongsword]:
    lines.add("Melee heroes only")
  elif item in [RuneCrossbow, RangerBow]:
    lines.add("Ranged heroes only")
  if spec.heal > 0:
    lines.add("Heal " & $spec.heal & " health")
  if spec.restore > 0:
    lines.add("Restore " & $spec.restore & " mana")
  if spec.recoveryTicks > 0:
    lines[0].add(" / " & $(spec.recoveryTicks div TickRate) & "s")
    lines.add("Damage interrupts")
  if spec.cooldownTicks > 0 and spec.channelTicks == 0:
    lines.add($(spec.cooldownTicks div TickRate) & "s cooldown")
  if spec.strike > 0:
    lines.add($spec.strike & " damage to target")
  if spec.channelTicks > 0:
    lines.add("Near allied tower")
    lines.add($(spec.channelTicks div TickRate) & "s channel / " &
      $(spec.cooldownTicks div TickRate) & "s CD")
  if spec.maxHp > 0:
    lines.add("+" & $spec.maxHp & " max health")
  if spec.maxMana > 0:
    lines.add("+" & $spec.maxMana & " max mana")
  if spec.damage > 0:
    lines.add("+" & $spec.damage & " basic damage")
    lines.add("Passive: any slot")
  if spec.movePerTick > 0:
    lines.add("+" & formatFloat(
      spec.movePerTick.float / WorldScale.float * TickRate.float,
      ffDecimal, 2
    ) & " movement / sec")
  lines.join("\n")

proc drawShop*(sk: Silky, window: Window, world: World, hero: Hero,
    size: Vec2, playing: bool) =
  ## Draws the full catalog and acknowledges purchases after their tick.
  if hero == nil or world == nil:
    resetShopUi()
    return
  let owned = shopOwned(world, hero)
  if sessionWorld != world or sessionHero != hero.id or sessionSize != size:
    resetShopUi()
    sessionWorld = world
    sessionHero = hero.id
    sessionSize = size
  if not owned or gestureInventory != hero.inventory or
      gestureCounts != hero.itemCounts:
    gestures.resetShopGesture()
    sellSlot = -1
  gestureInventory = hero.inventory
  gestureCounts = hero.itemCounts
  if purchaseReceipt.serial != receiptSerial:
    receiptSerial = purchaseReceipt.serial
    if purchaseReceipt.heroId == hero.id and waitingItem != NoItem:
      feedback =
        if purchaseReceipt.accepted:
          "Bought " & waitingItem.itemSpec.name & "."
        else:
          "Purchase failed: " & world.purchaseReason(
            hero.id, waitingItem.ord.int32
          )
      waitingItem = NoItem
  sk.drawRect(vec2(0), size, rgbx(5, 10, 18, 245))
  let layout = shopPanels(size)
  sk.drawPanel(layout.panel)
  var heading = layout.heading.stack(RightToLeft)
  let
    close = heading.takeColumn(140, 28)
    wallet = heading.takeColumn(220, 28)
    title = heading.takeRest()
  sk.drawTab(close, hovered = sk.hovered(close))
  sk.drawLabel("CLOSE  Esc", close.origin, close.size, White, "Bold",
    CenterAlign)
  let
    slots = shopInventoryPanels(size)
    sorts = shopSortPanels(size)
    catalog = sortedShopItems(sortMode)
  var target = -1
  for i, panel in slots:
    if panel.contains(sk.mousePos): target = i
  for i, panel in sorts:
    if panel.contains(sk.mousePos): target = SortNameTarget + i
  for i, panel in layout.cards:
    if panel.contains(sk.mousePos): target = CatalogTarget + i
  if close.contains(sk.mousePos): target = CloseTarget
  let hadPopup = sellSlot >= 0
  if hadPopup:
    target = if sellPanel.contains(sk.mousePos): SellTarget else: -1
    if (window.buttonPressed[MouseLeft] or window.buttonPressed[MouseRight]) and
        target != SellTarget:
      sellSlot = -1
      gestures.resetShopGesture()
  var occupied: array[InventorySlots, bool]
  for i in 0..<InventorySlots: occupied[i] = hero.inventory[i] != NoItem
  let gesture = gestures.updateShopGesture(ShopPointerFrame(
    target: target, x: sk.mousePos.x, y: sk.mousePos.y,
    leftPressed: window.buttonPressed[MouseLeft],
    leftReleased: window.buttonReleased[MouseLeft],
    leftDown: window.buttonDown[MouseLeft],
    rightPressed: window.buttonPressed[MouseRight],
    rightReleased: window.buttonReleased[MouseRight],
    rightDown: window.buttonDown[MouseRight]), occupied,
    owned and not (hadPopup and sellSlot < 0))
  sk.mouseConsumed = true
  case gesture.kind
  of ShopContextGesture:
    sellSlot = gesture.source
    sellItem = hero.inventory[sellSlot]
    sellCount = hero.itemCounts[sellSlot]
    sellPanel = GameUiPanel(origin: vec2(
      clamp(sk.mousePos.x, 8.0'f, max(8.0'f, size.x - 288)),
      clamp(sk.mousePos.y - 88, 8.0'f, max(8.0'f, size.y - 96))),
      size: vec2(280, 88))
  of ShopSwapGesture:
    if world.swapItemsReason(hero.id, gesture.source.int32,
        gesture.target.int32).len == 0:
      queueSwapItems(hero.id, gesture.source.int32, gesture.target.int32)
      feedback = "Inventory move queued."
  of ShopClickGesture:
    if gesture.target == CloseTarget:
      closeShop()
      return
    elif gesture.target in SortNameTarget..SortNameTarget + 2:
      sortMode = ShopSortMode(gesture.target - SortNameTarget)
    elif gesture.target == SellTarget and sellSlot >= 0:
      if hero.inventory[sellSlot] == sellItem and
          hero.itemCounts[sellSlot] == sellCount and
          world.sellReason(hero.id, sellSlot.int32).len == 0:
        queueSellItem(hero.id, sellSlot.int32)
        feedback = "Sale queued."
      sellSlot = -1
    elif gesture.target >= CatalogTarget and waitingItem == NoItem:
      let index = gesture.target - CatalogTarget
      if index < catalog.len:
        let item = catalog[index]
        if world.purchaseReason(hero.id, item.ord.int32).len == 0:
          queueBuyItem(hero.id, item.ord.int32)
          waitingItem = item
          receiptSerial = purchaseReceipt.serial
          feedback = "Buying " & item.itemSpec.name & "..."
  of ShopNoGesture: discard
  sk.drawSprite("gold", wallet.origin + vec2(0, 16), vec2(32))
  sk.drawLabel($hero.gold & " gold", wallet.origin + vec2(44, 0),
    wallet.size - vec2(44, 0), Gold, "Bold")
  sk.drawSprite("shop", title.origin + vec2(0, 4), vec2(64))
  sk.drawLabel("ITEM SHOP", title.origin + vec2(84, 0),
    vec2(title.size.x - 84, 40), White, "H1")
  for i, panel in sorts:
    sk.drawTab(panel, hovered = sortMode.ord == i or sk.hovered(panel))
    sk.drawLabel(["Name", "Price", "Type"][i], panel.origin, panel.size,
      sk.theme.defaultTextColor, "Small", CenterAlign)
  for index, item in catalog:
    let
      spec = item.itemSpec
      card = layout.cards[index]
      reason = world.purchaseReason(hero.id, item.ord.int32)
      enabled = reason.len == 0 and waitingItem == NoItem
      hovered = sk.hovered(card)
    sk.drawTab(card, hovered = hovered and enabled)
    let
      padding = if layout.compact: 8.0'f else: 12.0'f
      iconSize = if layout.compact: 48.0'f else: 72.0'f
    var rows = card.stack(TopToBottom, vec2(padding))
    let name = rows.takeRow(26, 6)
    sk.drawLabel(spec.name, name.origin, name.size, White, "Bold")
    var body = rows.takeRow(iconSize, 6).stack(LeftToRight)
    let
      icon = body.take(vec2(iconSize), padding)
      description = body.takeRest()
    sk.drawWellImage(
      icon, itemIconKey(item), iconSize = if layout.compact: 32 else: 64
    )
    sk.drawLabel(item.itemDescription, description.origin, description.size,
      Muted)
    let price = rows.takeRest()
    sk.drawSprite("gold", price.origin + vec2(0, 5), vec2(16))
    sk.drawLabel($spec.cost, price.origin + vec2(24, 0), vec2(60, 28), Gold)
    sk.drawLabel(
      if reason.len > 0: reason
      elif waitingItem != NoItem: "Purchase queued"
      elif spec.kind == Consumable: "BUY  /  Consumable"
      else: "BUY  /  Equipment",
      price.origin + vec2(84, 0), vec2(price.size.x - 84, 28),
      if enabled: Gold else: Muted, "Small"
    )
  var footer = layout.footer.stack(LeftToRight)
  var inventory = footer.takeColumn(6 * 80, 32).stack(LeftToRight)
  for slot in 0 ..< InventorySlots:
    let
      well = inventory.take(vec2(72), 8)
      item = hero.inventory[slot]
    sk.drawWellImage(well,
      if item == NoItem: "" else: itemIconKey(item), iconSize = 64)
    if item != NoItem and item.itemSpec.kind == Consumable:
      sk.drawItemCount(well, hero.itemCounts[slot])
    sk.drawLabel(if slot < 2: "ACTION " & $(slot + 1) else: $(slot + 1),
      well.origin + vec2(0, 74), vec2(72, 20),
      if slot < 2: Gold else: Muted, "Small", CenterAlign)
  let status = footer.takeRest()
  sk.drawLabel(
    if waitingItem != NoItem and not playing:
      "Purchase queued. Press Space to resume and complete it."
    else: feedback,
    status.origin, vec2(status.size.x, 32), Gold, "Bold"
  )
  sk.drawLabel("Drag to move or swap. Right-click an owned item to sell.",
    status.origin + vec2(0, 40), vec2(status.size.x, 28), Muted)
  let dragging = gestures.draggingShopSlot()
  if dragging >= 0 and hero.inventory[dragging] != NoItem:
    sk.drawSprite(itemIconKey(hero.inventory[dragging]),
      sk.mousePos - vec2(24), vec2(48))
  if sellSlot >= 0:
    let reason = world.sellReason(hero.id, sellSlot.int32)
    sk.draw9Patch("window.9patch", sk.theme.windowPatch,
      sellPanel.origin, sellPanel.size)
    sk.drawLabel("Sell " & sellItem.itemSpec.name,
      sellPanel.origin + vec2(12, 8), sellPanel.size - vec2(24, 48),
      sk.theme.defaultTextColor, "Bold")
    sk.drawLabel(if reason.len > 0: reason
      else: "Sell  +" & $world.sellPrice(hero.id, sellSlot.int32) & " gold",
      sellPanel.origin + vec2(12, 46), sellPanel.size - vec2(24, 50),
      if reason.len == 0: Gold else: Muted, "Small")
