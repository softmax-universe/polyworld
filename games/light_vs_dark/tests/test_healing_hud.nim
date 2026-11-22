import std/strutils
import ../[content, maps, sim, hudpresentation]

let w = newWorld(generateMap(DefaultSeed), TickRate * 120)
let id = w.spawnUnit(0, ClericUnit, tile2(40, 40))
let cleric = w.units[w.unitIndex(id)]
when declared(manaLabel):
  doAssert cleric.manaLabel == "MANA 100/100"
  cleric.mana = 3
  doAssert cleric.manaLabel == "MANA 3/100"
  cleric.state = UnitDying
  doAssert cleric.manaLabel == ""
  doAssert w.units[0].manaLabel == ""
  doAssert manaLabel(nil) == ""
else:
  doAssert false, "live Cleric mana label missing"
const source = staticRead("../ui.nim")
doAssert source.contains("sk.drawClericMana(selection.cargo, portraitCleric)")
doAssert source.contains("portraitWorker != nil or portraitCleric != nil")
echo "Cleric live HUD mana and integration passed"
