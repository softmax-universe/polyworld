## What the hero sheets show in each equipment slot.
##
## Presentation only: the simulation has no equipment, just two loot slots
## (`Actor.inventory`). A sheet shows the gear each hero's model wears and
## holds (its preset in the chargen library) in the six body slots, and
## puts the loot it carries in the accessory slots. Nothing here is read
## back by the simulation.

import content

type
  EquipSlot* = enum
    ## In the order the sheet lays them out, row by row.
    MainHandSlot, ArmorSlot, OffHandSlot,
    HelmetSlot, GlovesSlot, BootsSlot,
    BeltSlot, AmuletSlot, FirstRingSlot, SecondRingSlot

const
  GearIconDir* = "items/"
    ## Item art in polyworld_art, packed into the HUD atlas as `gear_<name>`.
  ClassGear*: array[HeroClass, array[EquipSlot, string]] = [
    # Vanguard Knight: sword, shield, helmet, plate, belt, boots.
    ["sunsteel_longsword", "knight_armor", "steel_buckler",
      "steel_helmet", "", "river_treads",
      "emberhide_belt", "", "", ""],
    # Arcanist: staff, orb, circlet, violet robe, belt, boots.
    ["amethyst_wand", "starweave_robe", "mirror_of_echoes",
      "topaz_sun_hairpin", "", "river_treads",
      "emberhide_belt", "", "", ""],
    # Ranger: bow, quiver, hood, tunic and cape, belt, boots.
    ["ranger_bow", "moonweave_cloak", "sunburst_bolts",
      "bronze_fox_mask", "", "ranger_boots",
      "emberhide_belt", "", "", ""],
    # Druid Warden: staff, orb, antler crown, bark mantle, belt, boots.
    ["thornwood_staff", "ironbark_pauldrons", "mire_slime_core",
      "whisperwood_idol", "", "ranger_boots",
      "emberhide_belt", "", "", ""]
  ]
    ## Item art closest to each preset's worn and held parts. No preset
    ## wears gloves, an amulet or rings, so those start empty.
  BagRings*: array[InventorySlots, EquipSlot] = [FirstRingSlot, SecondRingSlot]
    ## Each bag slot's own ring, so an item stays put while the other one
    ## comes and goes: the simulation never shifts a bag.

proc gearKey*(name: string): string =
  ## Returns the atlas name of one piece of gear art.
  "gear_" & name

proc wornAtNeck*(kind: LootKind): bool =
  ## True for the carried loot that hangs on a cord rather than a finger.
  kind in {NatureTalismanLoot, BattleHornLoot}

proc gearIcons*(): seq[string] =
  ## Returns every distinct piece of gear art the sheets draw.
  for class in HeroClass:
    for name in ClassGear[class]:
      if name.len > 0 and name notin result:
        result.add name

proc carriedSlots*(
    kinds: array[InventorySlots, int]
): array[InventorySlots, EquipSlot] =
  ## Places each carried loot kind (its ord, or -1 for an empty bag slot):
  ## a talisman or horn on the amulet slot while it is free, anything else
  ## on its bag slot's own ring.
  var neckTaken = false
  for bag, kind in kinds:
    result[bag] = BagRings[bag]
    if kind >= 0 and LootKind(kind).wornAtNeck and not neckTaken:
      result[bag] = AmuletSlot
      neckTaken = true
