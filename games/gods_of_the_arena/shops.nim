## Player shop presentation over the shared simulation purchase rules.

import
  std/monotimes,
  pixie, silky, vmath, windy,
  polyworld/[chrome, gameuis, stackpanels],
  content, controls, layouts, sim, game, shopinteractions, shopcatalog, tooltips

export shopcatalog

const
  Gold = rgbx(247, 215, 135, 255)
  Muted = rgbx(163, 175, 192, 255)
  White = rgbx(241, 244, 250, 255)

var
  waitingItem = NoItem
  receiptSerial = 0
  feedback = "Click an item to buy it."

const
  CloseTarget = 10
  SellTarget = 14
  CatalogTarget = 100

var
  gestures: ShopGestureState
  sortMode = ShopSortGrouped
  shopTooltip: TooltipSession
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
  shopTooltip.clearTooltip()
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

proc shopInventoryPanels*(size: Vec2): array[InventorySlots, GameUiPanel] =
  ## Own geometry: no coupling to the normal HUD inventory or its controls.
  var footer = shopPanels(size).footer.stack(LeftToRight)
  var inventory = footer.takeColumn(6 * 80, 32).stack(LeftToRight)
  for slot in 0..<InventorySlots:
    result[slot] = inventory.take(vec2(72), 8)

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

proc shopTooltipAnchor(session: TooltipSession, size: Vec2): GameUiPanel =
  ## Adapt only placement, never card content or the shared HUD renderer.
  let gutter = shopPanels(size).tooltipGutter
  let height = tooltipPanel(session.current.card, session.current.anchor, size).size.y
  GameUiPanel(origin: gutter.origin + vec2(190, height + 10), size: vec2(0))

proc updateShopTooltip(hero: Hero, size, mouse: Vec2, now: float64) =
  var targets: seq[TooltipTarget]
  let layout = shopPanels(size)
  for i, item in sortedShopItems(sortMode):
    targets.add TooltipTarget(id: "shop:" & $hero.id & ":" & $item.ord,
      card: itemDetails(item), anchor: layout.cards[i])
  let slots = shopInventoryPanels(size)
  for slot, item in hero.inventory:
    if item != NoItem:
      targets.add TooltipTarget(id: "shop-inventory:" & $hero.id & ":" & $slot &
        ":" & $item.ord, card: itemDetails(item), anchor: slots[slot])
  # Resolve anchors in a translated input space, clear of the HUD renderer's
  # naturally above-anchor popup. Only the final gutter panel retains hover;
  # covered catalogue anchors must remain reachable when the session is warm.
  let retained = shopTooltip.tooltipContains(mouse)
  for target in targets.mitems:
    target.anchor.origin.x -= size.x
  var pointer = mouse - vec2(size.x, 0)
  if retained:
    let natural = tooltipPanel(shopTooltip.current.card,
      shopTooltip.current.anchor, size)
    pointer = natural.origin + natural.size / 2
  shopTooltip.updateTooltip(targets, pointer, size, now)
  if shopTooltip.hover.visible:
    shopTooltip.panel = tooltipPanel(shopTooltip.current.card,
      shopTooltip.shopTooltipAnchor(size), size)

proc drawShopTooltip(sk: Silky, size: Vec2) =
  var placed = shopTooltip
  placed.current.anchor = shopTooltip.shopTooltipAnchor(size)
  sk.drawTooltip(placed, size)

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
  sk.drawRect(vec2(0), size, rgbx(5, 10, 18, 180))
  let layout = shopPanels(size)
  sk.drawPanel(layout.panel)
  var heading = layout.heading.stack(RightToLeft)
  let
    close = heading.takeColumn(140, 16)
    wallet = heading.takeColumn(180, 16)
    title = heading.takeRest()
  sk.drawTab(close, hovered = sk.hovered(close))
  sk.drawLabel("CLOSE  Esc", close.origin, close.size, White, "Bold",
    CenterAlign)
  let
    slots = shopInventoryPanels(size)
    catalog = sortedShopItems(sortMode)
  var target = -1
  for i, panel in slots:
    if panel.contains(sk.mousePos): target = i
  for i, panel in layout.cards:
    if panel.contains(sk.mousePos): target = CatalogTarget + i
  if close.contains(sk.mousePos): target = CloseTarget
  if sellSlot < 0 and gestures.draggingShopSlot() < 0:
    updateShopTooltip(hero, size, sk.mousePos,
      getMonoTime().ticks.float64 / 1_000_000_000.0)
  else:
    shopTooltip.clearTooltip()
  if shopTooltip.tooltipContains(sk.mousePos): target = -1
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
    shopTooltip.clearTooltip()
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
  sk.drawSprite("shop", title.origin, vec2(40))
  sk.drawLabel("ITEM SHOP", title.origin + vec2(52, 0),
    vec2(title.size.x - 52, 40), White, "H1")
  for group in ShopGroup:
    let panel = layout.groups[group]
    sk.drawLabel(ShopGroupNames[group], panel.origin, panel.size, Muted, "Small")
  for index, item in catalog:
    let
      spec = item.itemSpec
      card = layout.cards[index]
      enabled = world.purchaseReason(hero.id, item.ord.int32).len == 0 and
        waitingItem == NoItem
    sk.drawTab(card, hovered = card.contains(sk.mousePos) and enabled)
    let icon = GameUiPanel(origin: card.origin + vec2(4, 0), size: vec2(72))
    sk.drawWellImage(icon, itemIconKey(item), iconSize = 72)
    sk.drawSprite("gold", card.origin + vec2(10, 76), vec2(16))
    sk.drawLabel($spec.cost, card.origin + vec2(30, 72), vec2(48, 24),
      if enabled: Gold else: Muted, "Bold")
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
    status.origin, vec2(status.size.x, 44), Gold, "Small"
  )
  sk.drawLabel("Drag to move or swap. Right-click an owned item to sell.",
    status.origin + vec2(0, 48), vec2(status.size.x, 40), Muted)
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

  if sellSlot < 0:
    sk.drawShopTooltip(size)
