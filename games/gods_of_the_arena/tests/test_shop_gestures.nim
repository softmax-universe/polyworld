import ../shopinteractions

var state: ShopGestureState
let occupied = [true, false, true, false, false, false]
# A release without a fresh press must never acquire a control.
doAssert state.updateShopGesture(ShopPointerFrame(target: 0, x: 10,
  leftReleased: true), occupied, true).kind == ShopNoGesture
# Held mouse entering a slot does not capture it either.
doAssert state.updateShopGesture(ShopPointerFrame(target: 0, leftDown: true),
  occupied, true).kind == ShopNoGesture
discard state.updateShopGesture(ShopPointerFrame(target: 0, leftPressed: true,
  leftDown: true), occupied, true)
let moved = state.updateShopGesture(ShopPointerFrame(target: 1, x: 80,
  leftReleased: true), occupied, true)
doAssert moved.kind == ShopSwapGesture and moved.source == 0 and moved.target == 1
doAssert state.updateShopGesture(ShopPointerFrame(target: 1, x: 80,
  leftReleased: true), occupied, true).kind == ShopNoGesture
echo "PASS shop fresh capture and single empty-slot move"
