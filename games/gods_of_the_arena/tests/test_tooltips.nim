import
  std/strutils,
  ../[content, tooltips]

echo "Hover cards describe only the selected rank."
for ability in Ability:
  for rank in 0'i32 .. ability.abilitySpec.slot.abilityMaxLevel:
    let
      card = abilityDetails(ability, rank)
      spec = ability.abilitySpec(rank)
    doAssert card.title == spec.name
    doAssert card.description.len > 0
    if rank == 0:
      doAssert card.subtitle.startsWith("Not learned")
    else:
      doAssert card.subtitle.startsWith("Rank " & $rank & " /")
    if spec.damage > 0:
      doAssert ("Enemy damage", $spec.damage) in card.rows
    if spec.heal > 0:
      doAssert ("Healing", $spec.heal & " HP") in card.rows

echo "Hero levels and ability upgrades show the actual spell strength."
for ability in Ability:
  let maxRank = ability.abilitySpec.slot.abilityMaxLevel
  for heroLevel in [1, 10, HeroMaxLevel]:
    for rank in 0'i32 .. maxRank:
      let
        card = abilityDetails(ability, rank, heroLevel)
        spec = ability.abilitySpec(rank, heroLevel)
        firstLevel = ability.abilitySpec(rank)
      if spec.damage > 0:
        doAssert ("Enemy damage", $spec.damage) in card.rows
        if heroLevel > 1:
          doAssert spec.damage > firstLevel.damage
      if spec.heal > 0:
        doAssert ("Healing", $spec.heal & " HP") in card.rows
        if heroLevel > 1:
          doAssert spec.heal > firstLevel.heal
      if spec.restore > 0:
        doAssert ("Mana restored", $spec.restore) in card.rows
        if heroLevel > 1:
          doAssert spec.restore > firstLevel.restore
      doAssert ("Mana cost", $firstLevel.manaCost) in card.rows
  let
    current = abilityDetails(ability, 1, 10)
    upgrade = abilityDetails(ability, 2, 10)
    spec = ability.abilitySpec(2, 10)
  doAssert upgrade.subtitle.startsWith("Rank 2 /")
  if spec.damage > 0:
    doAssert ("Enemy damage", $spec.damage) in upgrade.rows
    doAssert ("Enemy damage", $spec.damage) notin current.rows
  if spec.heal > 0:
    doAssert ("Healing", $spec.heal & " HP") in upgrade.rows
    doAssert ("Healing", $spec.heal & " HP") notin current.rows

echo "All inventory items explain their real effects."
for item in HealthPotion .. Item.high:
  let card = itemDetails(item)
  doAssert card.title == item.itemSpec.name
  doAssert card.description.len > 0
  doAssert card.rows.len > 0
  let spec = item.itemSpec
  if spec.healthRegen > 0:
    doAssert ("Health regen", "+" & $spec.healthRegen & " HP/s") in card.rows
    doAssert "stacks with other equipment" in card.description
    doAssert "continues in combat" in card.description
  if spec.manaRegen > 0:
    doAssert ("Mana regen", "+" & $spec.manaRegen & " mana/s") in card.rows
    doAssert "stacks with other equipment" in card.description
    doAssert "continues in combat" in card.description
doAssert "takes damage" in itemDetails(HealthPotion).description
doAssert "current attack target" in itemDetails(PoisonPotion).description
doAssert "Stuns and roots" in itemDetails(PortalScroll).description
doAssert ("Stun", "0.5s") in abilityDetails(FirebrandSword, 4).rows
doAssert ("Healing", "375 HP") in abilityDetails(HealingBloom, 4).rows

for item in [BattleAxe, RuneCrossbow, SunsteelLongsword, RangerBow]:
  let card = itemDetails(item)
  let eligibility = if item in [BattleAxe, SunsteelLongsword]:
    "Melee heroes only" else: "Ranged heroes only"
  doAssert ("Requires", eligibility) in card.rows
  doAssert ("Attack damage", "+" & $item.itemSpec.damage) in card.rows
  doAssert "basic attacks only" in card.description
  doAssert "any inventory slot" in card.description
  doAssert "not increase attack range" in card.description

for item in ArtifactItems:
  let card = itemDetails(item)
  doAssert card.subtitle == "Magical artifact"
  doAssert ("Requires", "Any hero") in card.rows
  doAssert ("Attack damage", "+" & $item.itemSpec.damage) in card.rows
  doAssert "basic attacks only" in card.description
  doAssert "stack with other equipment" in card.description
doAssert "protection still applies" in itemDetails(Worldbreaker).description

# Art-free timing/session regressions run with the ordinary GotA suite.
{.push warning[UnusedImport]: off.}
import test_tooltip_hover, test_tooltip_session, test_tooltip_routes
{.pop.}
