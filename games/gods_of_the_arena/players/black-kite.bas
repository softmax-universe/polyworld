' N134 (2026-10-09): N133 / N134 loss census (runs/loss_presence_81, 194 live
' black-kite:v75 games on 2026.10.8.1): our own mid gate falls in 45 of 49
' losses and our seat is dead at 28 of those gates; in those games it dies
' 9.0 times, 82 % of deaths to a hero 2+ levels above it. One change on v75:
' N93a's out-levelled step-back unchanged (step home while a living enemy hero
' within 10 tiles is two or more levels above us and we are not sieging, unless
' our hero target has less than two basic hits of hp). Parent black-kite:v75.
' N110 (2026-10-08): black-kite:v74 with the mid-outer footprint tile
' corrected to (51,73). A terrainWalkableAt probe (N108) reads (51,72)
' walkable from the first tick while (50,73) and (51,73) are not; hosted
' v74 logs show clamp 133 (inner) from tick 242 with the outer alive, so
' the seat followed its creeps past the living outer tower. Parent v74.
' N90 (2026-10-07): N89d's backswing cancel on the N86b siege source; the
' cancel also applies to tower and barracks swings (Beta:v4 cadence 14).
' N86b (2026-10-07): N86's uncovered visits feed because 9 of 19 also take
' enemy hero or creep damage, while 7 of 10 Beta:v4 r4 visits take tower
' damage only. One change on N86: an uncovered visit (no own footman near the
' tower this or last decision) opens and persists only while no living enemy
' hero or lane creep is within 10 tiles of us; covered visits keep N85d rules.
' Parent N86.
' N86 (2026-10-07): N85d / N82 cap near 1.7k building damage per game because
' our footmen rarely stand at a living enemy tower. K1 Beta:v4 (siege_gate a
' mode on k1-lead-r4 g0) opens 6 of 10 visits with 0 own footmen near the
' tower, stays to 7-30 % hp, then walks home and heals; it never steps back
' to drink. One change on N85d: tower visits no longer depend on own-footman
' cover (visible and footprint openers, footprint persistence and the
' uncovered-and-aimed exit); the 35 % retreat and power check stay.
' Parent N85d.
' N85d (2026-10-06): replaying the N85b diagnostic tapes with our seat live
' (tools/replay_script.nim, 0 mismatches) shows 8 visits in 4 games, 5 of them
' ended because the tower left the fogged object list, and in > 99 % of the
' level-5+ off-visit decisions no enemy tower was visible within 18 tiles
' although our footmen stood within 9 tiles of the nearest living mid tower
' in 50-135 of them at >= 80 % hp. One change on N85b: the visit opens and
' persists on that tower's known footprint (cover = own footmen within 9
' tiles of it, seat within 30 tiles), walking to it while it is fogged.
' Parent N85b.
' N85b (2026-10-06): N85 opened visits at level 1-2 (ticks 3,400-8,700) for
' 38-341 damage each, died in 4 of 15 visits and finished 1.25 levels below
' N84b; K1 Beta:v4 makes its first visits at level 4-5. One change on N85: a
' visit opens only from level 5. Parent N85.
' N85 mid siege (2026-10-06): the N84b block (11 live B rosters x 8, staging)
' raised hero damage 2.3k -> 11.2k per game but building damage only 0 -> 354
' and outcomes stayed flat (t -0.45, 97 % timeouts); K1 Beta:v4 wins from the
' same seat with 7.2k building damage. One change on N84b: the N81c covered
' siege gate (80 % hp + own footman within 9 tiles of the nearest enemy tower,
' tower keeps target priority below heroes, exit when uncovered and aimed at
' below 60 % or below 35 %) now runs on the mid towers. Parent N84b.
' N84b (2026-10-06): N84 died 6.0 times per game on the diagnostic worlds
' (N79 2.25), mostly walking home below 25 % hp inside a Lich / Ranger's
' reach (tools/death_story.nim, homeward = 1) or idle at low hp in mid. One
' change on N84: a ranged seat (attack range >= 3) retreats below 40 % hp
' instead of 25 % (Beta:v4 leaves its tower visits at 26-39 %). Parent N84.
' N84 Crossbowman on mid (2026-10-06, game 2026.10.6.1 / replay 68): farm the
' mid lane instead of lane A. tools/kill_chase.nim on K1 (Beta:v4 in B's seat,
' 13 games) v N79 (12 games): Beta has a visible enemy hero inside its attack
' range 11.5 % of alive ticks v our 4.4 % (and within 10 tiles 8.0 % v 3.4 %),
' 140 v 35 hero engagements per game, 12.4k v 2.8k hero damage; once a hero is
' in range both target it ~51 %. Beta plays the mid diagonal and roams; our
' seat sits at the lane-A corner / leg-2 hold. The N74 mid geometry (hold,
' creep front, tower clamp, tower-zone filters, trip safety; enemy mid towers
' (51,72)/(34,85)/(19,95), unchanged on game 68) replaces lane A. Parent N79.
' N79/N80 Crossbowman-first draft (2026-10-06, game 67 rebalance): Crossbowman
' attacks every 30 ticks instead of 126 and DemonHunter lost its speed; live
' rounds 1251-1263 decided picks Crossbowman 34-29 v DemonHunter 25-33. Only
' the Crossbowman draft score changes (4 -> 11). Parent black-kite:v49.
' N41d melee opening kit only (2026-09-26): Steel Helmet + Leather Gauntlets instead
' of Ranger Boots (and no Mana Potions) on melee heroes; no camp route. Parent black-kite:v43.
' N27b Lich draft re-rank on B (2026-09-25): Lich ranked above Warlock and
' Berserker (live rounds 775-783: league Lich 4,954 XP per seat vs Warlock
' 3,430 / Berserker 3,768; B holds Warlock in 31 of 104 live seats at 4,911;
' A's same change = red-kite:v42, +726 score per seat hosted). Parent black-kite:v25.
' N22 melee last-hit targeting (2026-09-25): melee heroes (attack range < 3)
' pick lane creeps as explicit targets only for a last hit or when the creep
' attacks them; the attack-move hold is unchanged. Parent black-kite:v22.
' N5b tower-margin lane farm (2026.9.24.2; N1c with the hold and the target
' filter moved outside the new 9-tile tower range): stay in the team-relative
' lane A (own outer tower 13 tiles from the creep meeting corner), follow own
' creeps two tiles behind the front, never advance past the clamp 13 tiles
' short of the nearest enemy lane-A tower whose 2x2 footprint tile still reads
' unwalkable (seen alive), ignore enemy units on leg 2 closer than 11 tiles to
' that tower, no structure attacks without creep support. Camp mobs pulled
' onto a frail hero send it home. The frontier is remembered across the
' rotating creep scan (decays 3 per decision) so the goal cannot flip between
' scan windows; no spawn trips for mana alone. N3: value-ranked draft.
' N4c: enemy heroes deep on leg 2 count as threats and targets (probe).
' N12: DemonHunter ranked above Arcanist in the draft (league rounds 756-765:
' DemonHunter 8,056 XP per seat vs Arcanist 5,679; the top four policies take
' it with their first pick, our seats never hold it).
' N2c: with nothing in reach, level 7+ and 70 % hp, walk to the nearest tier-3
' camp within 22 tiles (14+ tiles from living enemy lane-A towers, not up leg 2
' past a living tower), clear it with the existing camp rule (40 % floor once
' there), remember cleared camps for 75 s; a trip ends if the hero is displaced
' (death, portal) more than 25 tiles from the camp. Everything else (draft,
' abilities, shop, dodge, retreat, kiting) is the base.
' Every GotA host function has a gameplay use here; calls remain conditional.
' Object indices last only for this decision. IDs may be remembered.
' Read the bot guide for units, LOS restrictions, and action error constants.
' Abilities and items are used only by our explicit policy commands.

dim owned(22)
dim inventorySlot(22)
dim allyIds(9)
dim seenMaxHp(9)
dim castRange(3)
dim castDelay(3)
dim castGround(3)
dim castMinimum(3)
dim hostSlot(3)
' N187 (2026-10-29): release 2026.10.29.1 moved every kit's old slot 0
' (passive / utility) to slot 2 and old slots 1 and 2 to 0 and 1. Policy
' rules keep the old slot numbers; host ability calls translate them.
hostSlot(0) = 2
hostSlot(1) = 0
hostSlot(2) = 1
hostSlot(3) = 3
dim campWait(15)

sub chooseHero()
  if draftTurnId <> selfId then
    exit sub
  end if
  ' N3: value-ranked pick from live per-class XP (rounds 745-748): the
  ' role-diversity rule took VanguardKnight (class 0, first frontline) in
  ' 35 of our 72 live seats at a mean score of 168; Arcanist / DemonHunter
  ' / Warlock / Berserker seats scored 1,300-1,600.
  bestClass = -1
  bestScore = -10000
  for candidate = 0 to 9
    if heroAvailable(candidate) then
      score = 0
      if candidate = DemonHunter then
        score = 10
      elseif candidate = Arcanist then
        score = 9
      elseif candidate = Lich then
        score = 8
      elseif candidate = Warlock then
        ' N158: the support seat drafts Warlock first (red-kite:v73's
        ' pure-healer role, n157cblk t +4.53).
        score = 12
      elseif candidate = Berserker then
        score = 6
      elseif candidate = DruidWarden then
        score = 5
      elseif candidate = Crossbowman then
        score = 11
      elseif candidate = DeathKnight then
        score = 3
      elseif candidate = Ranger then
        score = 2
      elseif candidate = VanguardKnight then
        score = 1
      end if
      if score > bestScore then
        bestScore = score
        bestClass = candidate
      end if
    end if
  next candidate
  if bestClass >= 0 then
    accepted = draftHero(bestClass)
    actionError = lastActionError()
  end if
end sub

sub learnAbilities()
  ' Rank requirements and effects come from the host, not a stat table.
  for upgrade = 1 to 4
    if abilityPoints() = 0 then
      exit sub
    end if
    upgradeSlot = -1
    upgradeScore = -1
    for spellSlot = 0 to 3
      rank = abilityLevel(hostSlot(spellSlot))
      if rank < abilityMaxLevel(hostSlot(spellSlot)) then
        if selfLevel >= abilityRequiredLevel(hostSlot(spellSlot)) then
          if canLevelAbility(hostSlot(spellSlot)) then
            ' Prefer R, W, E, Q whenever the next rank is legal.
            score = spellSlot
            if spellSlot = 1 then
              score = 2
            elseif spellSlot = 2 then
              score = 1
            end if
            if score > upgradeScore then
              upgradeScore = score
              upgradeSlot = spellSlot
            end if
          end if
        end if
      end if
    next spellSlot
    if upgradeSlot < 0 then
      exit sub
    end if
    accepted = levelAbility(hostSlot(upgradeSlot))
    actionError = lastActionError()
  next upgrade
end sub

sub readObject(index)
  id = objectId(index)
  kind = objectKind(index)
  team = objectTeam(index)
  hp = objectHp(index)
  if hp <= 0 then
    exit sub
  end if
  x = originX + side * objectX(index)
  y = originY + side * objectY(index)
  dx = x - myX
  dy = y - myY
  distance = dx * dx + dy * dy
  if kind = 6 then
    ' Camps never distract from lane combat or count as enemy heroes.
    if objectReturning(index) or objectAlive(index) = 0 then
      exit sub
    end if
    if distance <= 36 and objectTarget(index) = selfId then
      campAggro = campAggro + 1
    end if
    camp = objectCamp(index)
    tier = campTier(camp)
    campDx = originX + side * campX(camp) - myX
    campDy = originY + side * campY(camp) - myY
    if campDx * campDx + campDy * campDy > 100 then
      exit sub
    end if
    enoughHealth = selfHp * 10 >= selfMaxHp * 7
    if selfTarget = id or camp = tripCamp then
      enoughHealth = selfHp * 10 >= selfMaxHp * 4
    end if
    if camp >= 0 and camp < campCount() and enoughHealth then
      if selfLevel >= 1 + (tier - 1) * 3 and distance <= 64 then
        score = 100 - distance
        if objectLeader(index) then
          score = score - 10
        end if
        if selfTarget = id then
          score = score + 100
        end if
        if score > campScore then
          campScore = score
          campIndex = index
          campId = id
          campHp = hp
          campXpos = x
          campYpos = y
          campDistance = distance
        end if
      end if
    end if
    exit sub
  end if
  if team = selfTeam then
    if kind = 1 then
      homeX = x
      homeY = y
      enemyX = mapWidth - 1 - x
      enemyY = mapHeight - 1 - y
    elseif kind = 4 then
      ' Protected allied towers still serve as portal anchors.
      dx = x - enemyX
      dy = y - enemyY
      score = dx * dx + dy * dy
      if score < forwardDistance then
        forwardDistance = score
        forwardX = x
        forwardY = y
      end if
      ' Outermost living own mid tower (smallest x - y) is the hold.
      if x + y >= 98 and x + y <= 122 and x > y and x - y < holdTowerX - holdTowerY then
        holdTowerX = x
        holdTowerY = y
      end if
    elseif kind = 2 then
      allyIds(allies) = id
      allies = allies + 1
      class = objectClass(index)
      if hp > seenMaxHp(class) then
        seenMaxHp(class) = hp
      end if
      if distance <= 100 then
        friendlyPower = friendlyPower + objectLevel(index) + 2
      end if
      missing = seenMaxHp(class) - hp
      if distance <= healRange * healRange and missing > healMissing then
        healMissing = missing
        healId = id
      end if
      ' N158: the support anchor is an ally outside our spawn; keep the
      ' previous anchor while it stays visible there, else the nearest.
      if id <> selfId and (x - spawnX) * (x - spawnX) + (y - spawnY) * (y - spawnY) > 225 then
        if id = lastAnchorId or ((anchorId = 0 or anchorId <> lastAnchorId) and distance < anchorDistance) then
          anchorId = id
          anchorX = x
          anchorY = y
          anchorDistance = distance
        end if
      end if
    elseif kind = 3 then
      if distance <= 64 then
        tanks = tanks + 1
      end if
      if (x - zoneX) * (x - zoneX) + (y - zoneY) * (y - zoneY) <= 81 then
        zoneFeet = zoneFeet + 1
      end if
      if siegeId <> 0 and (x - siegeX) * (x - siegeX) + (y - siegeY) * (y - siegeY) <= 81 then
        siegeFeet = siegeFeet + 1
      end if
      ' Mid progress along the diagonal from our gate (95,19) to theirs (19,95).
      progress = -1
      if x + y >= 96 and x + y <= 134 and x >= 14 and y >= 14 and x <= 100 and y <= 100 then
        progress = y - x + 100
      end if
      if progress >= 0 and progress <= laneClamp and progress > frontProgress then
        frontProgress = progress
        frontX = x + 2
        frontY = y - 2
      end if
    end if
    exit sub
  end if
  if kind = 1 then
    enemyX = x
    enemyY = y
  end if
  if kind = 2 and distance <= 100 and objectAlive(index) and objectLevel(index) > strongLevel then
    strongLevel = objectLevel(index)
  end if
  if kind = 2 and distance <= 144 then
    enemyPower = enemyPower + objectLevel(index) + 2
    if objectMana(index) >= 25 and objectSilenceTicks(index) = 0 then
      enemyPower = enemyPower + 2
    end if
  end if
  ' N86b: living enemy heroes and lane creeps within 10 tiles.
  if (kind = 2 or kind = 3) and distance <= 100 and objectAlive(index) then
    siegeDanger = siegeDanger + 1
  end if
  if distance < threatDistance then
    threatDistance = distance
    threatX = x
    threatY = y
  end if
  if distance > 324 or objectAlive(index) = 0 then
    exit sub
  end if
  target = objectTarget(index)
  if kind = 4 and target = selfId then
    towerAggro = 1
  end if
  ' N81: nearest enemy tower within 18 tiles is the siege candidate.
  if kind = 4 and distance < siegeDistance then
    siegeDistance = distance
    siegeIndex = index
    siegeId = id
    siegeHp = hp
    siegeX = x
    siegeY = y
    siegeTarget = target
  end if
  if (x - zoneX) * (x - zoneX) + (y - zoneY) * (y - zoneY) < 121 then
    ' Within 11 tiles of the nearest living enemy mid tower (range 9).
    exit sub
  end if
  score = 1000 - distance * 2
  if kind = 1 then
    score = score + 500
  elseif kind = 2 then
    ' N37c: below level 5 a melee seat inside the enemy wave (an enemy lane
    ' creep within 3 tiles on the previous scan) targets an enemy hero only to
    ' finish it or when that hero attacks us; a level-2 chase through the
    ' first clash dies to creep focus, while pokes outside it are answered.
    if attackRange < 3 and selfLevel < 5 and enemyCreepClose and hp >= selfAttackDamage * 4 and target <> selfId then
      exit sub
    end if
    score = score + 60 - objectLevel(index) * 8
    if hp < selfAttackDamage * 4 then
      score = score + 250
    end if
  elseif kind = 3 then
    if distance <= 9 then
      enemyCreepNear = 1
    end if
    ' N22: a melee hero walks at a lane creep only to last-hit it or to answer
    ' one attacking it; the hold's attack-move still engages creeps that
    ' reach the hero. The shared pool (15 XP within six tiles) pays the same
    ' for standing beside the wave as for wading into it.
    if attackRange < 3 and hp > selfAttackDamage and target <> selfId then
      exit sub
    end if
    score = score + 100
    if hp <= selfAttackDamage and selfAttackCooldown <= tickRate \ 2 then
      score = score + 400
    end if
  elseif kind = 5 then
    score = score + 40
  end if
  if target = selfId then
    score = score + 40
  end if
  if id = selfTarget then
    score = score + 60
  end if
  if id = blockedId and worldTick < blockedUntil then
    exit sub
  end if
  if score > bestScore then
    bestScore = score
    bestIndex = index
    bestId = id
    bestKind = kind
    bestHp = hp
    bestX = x
    bestY = y
    bestDistance = distance
  end if
end sub

sub observe()
  enemyCreepClose = enemyCreepNear
  enemyCreepNear = 0
  campScore = -10000
  campId = 0
  bestScore = -10000
  bestId = 0
  bestDistance = 1000000
  threatDistance = 1000000
  forwardDistance = 1000000
  friendlyPower = 0
  enemyPower = 0
  strongLevel = 0
  allies = 0
  tanks = 0
  towerAggro = 0
  campAggro = 0
  frontProgress = -1
  lastSiegeFeet = siegeFeet
  lastZoneFeet = zoneFeet
  zoneFeet = 0
  siegeFeet = 0
  siegeDanger = 0
  siegeId = 0
  siegeDistance = 1000000
  sieging = 0
  holdTowerX = 1000
  holdTowerY = 0
  healId = selfId
  healMissing = selfMaxHp - selfHp
  seenMaxHp(selfClass) = selfMaxHp
  lastAnchorId = anchorId
  anchorId = 0
  anchorDistance = 1000000
  objects = objectCount()
  ' Buildings and heroes precede creeps. Rotate the large creep tail so a
  ' crowded battlefield cannot exhaust the per-decision VM budget.
  for scan = 0 to 95
    index = scan
    if scan >= 48 then
      index = scan + scanOffset
    end if
    if index < objects then
      readObject(index)
    end if
  next scan
  ' Retain a creep target outside this scan window only after validating
  ' its remembered index against the stable ID in the fresh observation.
  if targetIndex >= 48 and targetIndex < objects and selfTarget <> 0 then
    if targetIndex < 48 + scanOffset or targetIndex >= 96 + scanOffset then
      if objectId(targetIndex) = selfTarget then
        readObject(targetIndex)
      end if
    end if
  end if
  scanOffset = scanOffset + 48
  if scanOffset >= objects - 48 then
    scanOffset = 0
  end if
  ' N81: a visit opens at 80 % hp with cover and ends below 35 % (retreat)
  ' or when no enemy tower is in reach; heroes keep target priority.
  ' N85d: a fogged mid tower stays the visit target while its footprint
  ' stands and our footmen still cover it.
  if siegeOn and siegeId = 0 then
    if zoneX < 0 or (zoneFeet = 0 and lastZoneFeet = 0 and siegeDanger > 0) then
      siegeOn = 0
    end if
  end if
  if siegeOn and siegeId <> 0 and siegeFeet = 0 and lastSiegeFeet = 0 and siegeDanger > 0 then
    siegeOn = 0
  end if
  if siegeOn and selfHp * 20 < selfMaxHp * 7 then
    siegeOn = 0
    retreating = 1
  end if
  if siegeOn = 0 and siegeId <> 0 and attackRange >= 3 and siegeTarget <> selfId and selfLevel >= 5 then
    if selfHp * 10 >= selfMaxHp * 8 and (siegeFeet >= 1 or lastSiegeFeet >= 1 or siegeDanger = 0) then
      if enemyPower <= friendlyPower then
        siegeOn = 1
        siegeVisits = siegeVisits + 1
      end if
    end if
  end if
  ' N85d: our footmen at the nearest living mid tower's footprint open a
  ' visit within 30 tiles even when the tower itself is fogged.
  if siegeOn = 0 and siegeId = 0 and zoneX >= 0 and attackRange >= 3 and selfLevel >= 5 and (zoneFeet >= 1 or siegeDanger = 0) then
    if (myX - zoneX) * (myX - zoneX) + (myY - zoneY) * (myY - zoneY) <= 900 then
      if selfHp * 10 >= selfMaxHp * 8 and enemyPower <= friendlyPower then
        siegeOn = 1
        siegeVisits = siegeVisits + 1
      end if
    end if
  end if
  if siegeOn and (bestId = 0 or bestKind <> 2) then
    sieging = 1
    bestId = siegeId
    bestIndex = siegeIndex
    bestKind = 4
    bestHp = siegeHp
    bestX = siegeX
    bestY = siegeY
    bestDistance = siegeDistance
  end if
  if bestId = 0 and campId <> 0 and towerAggro = 0 and enemyPower = 0 then
    bestId = campId
    bestIndex = campIndex
    bestKind = 6
    bestHp = campHp
    bestX = campXpos
    bestY = campYpos
    bestDistance = campDistance
  end if
  if bestId = 0 then
    exit sub
  end if
  targetIndex = bestIndex
  ' Divide large integer world units before mixing them with Q16.16 values.
  velocityX = (side * objectVelX(bestIndex) \ 100) / (worldScale \ 100)
  velocityY = (side * objectVelY(bestIndex) \ 100) / (worldScale \ 100)
  ' Do not lead a unit whose control lasts through the predicted impact.
  targetHeld = objectStunTicks(bestIndex)
  targetRoot = objectRootTicks(bestIndex)
  if targetRoot > targetHeld then
    targetHeld = targetRoot
  end if
  facingX = (side * objectFacingX(bestIndex) \ 100) / (worldScale \ 100)
  facingY = (side * objectFacingY(bestIndex) \ 100) / (worldScale \ 100)
  aimedAtUs = facingX * (myX - bestX) + facingY * (myY - bestY)
  if bestKind = 2 then
    ' Visible equipment and potion stacks help judge a close duel.
    for inspectSlot = 0 to 5
      gear = objectItemId(bestIndex, inspectSlot)
      quantity = objectItemCount(bestIndex, inspectSlot)
      if quantity > 0 and bestDistance <= 144 then
        if gear >= 5 and gear <= 20 then
          enemyPower = enemyPower + 1
        elseif gear = 1 or gear = 2 then
          enemyPower = enemyPower + 2
        end if
      end if
    next inspectSlot
  end if
end sub

sub buy(id, price, quantity)
  if owned(id) >= quantity or budget < price then
    exit sub
  end if
  if owned(id) = 0 and emptySlots = 0 then
    exit sub
  end if
  accepted = buyItem(id)
  actionError = lastActionError()
  if accepted then
    if owned(id) = 0 then
      emptySlots = emptySlots - 1
    end if
    owned(id) = owned(id) + 1
    budget = budget - price
    for boughtSlot = 0 to 5
      if itemId(boughtSlot) = id then
        inventorySlot(id) = boughtSlot
      end if
    next boughtSlot
  end if
end sub

sub inventory()
  for id = 0 to 22
    owned(id) = 0
    inventorySlot(id) = -1
  next id
  emptySlots = 0
  for itemSlot = 0 to 5
    id = itemId(itemSlot)
    if id = 0 then
      emptySlots = emptySlots + 1
    else
      owned(id) = itemCount(itemSlot)
      inventorySlot(id) = itemSlot
      if itemCooldown(itemSlot) = 0 and inOwnSpawn() = 0 then
        consume = 0
        if id = 1 and selfMaxHp - selfHp >= 60 then
          consume = threatDistance > 100 and worldTick - hurtTick > tickRate
        elseif id = 2 and selfHp * 2 < selfMaxHp then
          consume = 1
        elseif id = 22 and selfMaxMana - selfMana >= 45 then
          consume = threatDistance > 100 and worldTick - hurtTick > tickRate
        elseif id = 3 and selfMana * 3 < selfMaxMana then
          consume = bestId <> 0
        elseif id = 4 and selfTarget = bestId and bestId <> 0 then
          consume = bestDistance <= attackRange * attackRange
        end if
        if consume then
          accepted = useItem(itemSlot)
          actionError = lastActionError()
          if accepted then
            owned(id) = owned(id) - 1
            if owned(id) = 0 then
              emptySlots = emptySlots + 1
              inventorySlot(id) = -1
            end if
          end if
        end if
      end if
    end if
  next itemSlot
  if canShop() = 0 then
    exit sub
  end if
  ' Reserve three slots for recovery and travel, two for useful equipment,
  ' and one for a role-specific burst consumable. Stacks top up on return.
  budget = selfGold
  ' N41d: the leaders' melee opening kit alone (richard / relh DemonHunter seats,
  ' rounds 811-812): Steel Helmet (+50 hp) and Leather Gauntlets (+4 damage)
  ' with the 150 starting gold; no boots or mana potions on melee heroes.
  if attackRange < 3 then
    buy(5, 80, 1)
    buy(7, 70, 1)
  else
    buy(8, 100, 1)
  end if
  buy(1, 30, 2)
  buy(21, 100, 2)
  if attackRange >= 3 then
    buy(22, 45, 2)
  end if
  if role = 0 or role = 4 then
    buy(16, 160, 1)
    buy(2, 75, 2)
  elseif role = 1 then
    buy(19, 180, 1)
    buy(4, 40, 2)
  else
    buy(20, 190, 1)
    buy(3, 90, 2)
  end if
  ' N15: there is no natural regeneration and the hoarded gold (1,500-4,800
  ' unspent at L9+) buys nothing, so top the potion stack up to eight after
  ' the standard kit, keeping the next buyback price in reserve.
  ' A buyback leaves the keep within two or three decisions, so fill the
  ' stack in one decision instead of one potion per decision.
  for topUp = 1 to 6
    if budget >= 100 * (selfDeaths + 1) + 30 then
      buy(1, 30, 8)
    end if
  next topUp
end sub

sub dodgeWarnings()
  dodge = 0
  warnings = spellCount()
  ' Rotate unusually busy spell lists instead of starving later warnings.
  for warning = warningOffset to warningOffset + 11
    if warning < warnings then
      spell = spellAbility(warning)
      caster = spellCasterId(warning)
      hostile = caster <> selfId
      for ally = 0 to allies - 1
        if caster = allyIds(ally) then
          hostile = 0
        end if
      next ally
      ' Recovery effects are harmless, including those with hidden casters.
      if spell = 0 or spell = 2 or spell = 8 or spell = 12 then
        hostile = 0
      end if
      if spell = 13 or spell = 14 or spell = 16 or spell = 20 then
        hostile = 0
      end if
      if spell = 32 or spell = 36 then
        hostile = 0
      end if
      impact = spellImpactTick(warning) - worldTick
      warningX = originX + side * spellX(warning)
      warningY = originY + side * spellY(warning)
      dx = myX - warningX
      dy = myY - warningY
      if hostile and impact > 0 and impact <= tickRate * 3 then
        if dx * dx + dy * dy <= 9 then
          dodge = 1
          dodgeX = myX + 3
          dodgeY = myY + 3
          if dx < 0 then
            dodgeX = myX - 3
          end if
          if dy < 0 then
            dodgeY = myY - 3
          end if
        end if
      end if
    end if
  next warning
  warningOffset = warningOffset + 12
  if warningOffset >= warnings then
    warningOffset = 0
  end if
end sub

sub moveTo(goalX, goalY, marching)
  if selfRootTicks > 0 then
    exit sub
  end if
  if goalX = orderX and goalY = orderY and marching = orderMarch then
    if worldTick - orderTick < tickRate * 2 then
      exit sub
    end if
  end if
  ' Snap the requested destination to an open nearby surface. A* in the
  ' host still owns the complete route and cliff/ramp collision checks.
  routeScore = 1000000
  routeFound = 0
  floorHeight = terrainHeight(selfX, selfY)
  for offsetY = -1 to 1
    for offsetX = -1 to 1
      tileX = goalX + offsetX
      tileY = goalY + offsetY
      worldTileX = originX + side * tileX
      worldTileY = originY + side * tileY
      if tileX >= 0 and tileX < mapWidth then
        if tileY >= 0 and tileY < mapHeight then
          open = terrainWalkable(worldTileX, worldTileY)
          ground = terrainKind(worldTileX, worldTileY)
          height = terrainHeight(worldTileX, worldTileY)
          depth = terrainWaterDepth(worldTileX, worldTileY)
          if open = 0 then
            for layer = 0 to mapLayers - 1
              worldLayer = layer
              if layer = RedFortLayer or layer = BlueFortLayer then
                worldLayer = layer + selfTeam * (RedFortLayer + BlueFortLayer - 2 * layer)
              end if
              if terrainWalkableAt(worldTileX, worldTileY, worldLayer) then
                open = 1
                ground = terrainKindAt(worldTileX, worldTileY, worldLayer)
                height = terrainHeightAt(worldTileX, worldTileY, worldLayer)
                depth = terrainWaterDepthAt(worldTileX, worldTileY, worldLayer)
                exit for
              end if
            next layer
          end if
          if open and ground <> TerrainNone then
            elevation = height - floorHeight
            if elevation < 0 then
              elevation = -elevation
            end if
            score = (offsetX * offsetX + offsetY * offsetY) * 20
            score = score + depth * 2 + elevation
            if ground = TerrainRoad then
              score = score - 5
            end if
            if score < routeScore then
              routeScore = score
              routeX = tileX
              routeY = tileY
              routeFound = 1
            end if
          end if
        end if
      end if
    next offsetX
  next offsetY
  if routeFound = 0 then
    exit sub
  end if
  if marching then
    accepted = attackMove(originX + side * routeX, originY + side * routeY)
  else
    accepted = walkTo(originX + side * routeX, originY + side * routeY)
  end if
  actionError = lastActionError()
  orderTick = worldTick
  if accepted then
    orderX = goalX
    orderY = goalY
    orderMarch = marching
  elseif actionError = ActionNoRoute then
    ' Try the lane center on the next decision rather than retrying a wall.
    crossedMiddle = 0
    blockedId = bestId
    blockedUntil = worldTick + tickRate * 3
  end if
end sub

sub spells()
  if selfSilenceTicks > 0 then
    exit sub
  end if
  for spellSlot = 0 to 3
    charges = abilityCharges(hostSlot(spellSlot))
    recharge = abilityRecharge(hostSlot(spellSlot))
    damage = abilityDamage(hostSlot(spellSlot))
    healing = abilityHeal(hostSlot(spellSlot))
    restore = abilityRestore(hostSlot(spellSlot))
    cost = abilityManaCost(hostSlot(spellSlot))
    if abilityLevel(hostSlot(spellSlot)) > 0 and charges > 0 then
      if abilityCooldown(hostSlot(spellSlot)) = 0 and selfMana >= cost then
        castId = 0
        if healing > 0 and healMissing >= healing \ 2 then
          if (selfClass = DruidWarden or selfClass = Warlock) and spellSlot > 0 then
            castId = healId
          elseif selfClass = VanguardKnight and spellSlot = 2 then
            ' Aegis heals around us, even when only an ally is wounded.
            castId = selfId
          elseif selfMaxHp - selfHp >= healing \ 2 then
            castId = selfId
          end if
        elseif restore > 0 and selfMaxMana - selfMana >= restore then
          castId = selfId
        elseif damage > 0 and bestKind <> 2 and spellSlot <= 2 and selfClass = Warlock then
          ' N158: the Warlock keeps its two heals for allies and enemy heroes.
          castId = 0
        elseif damage > 0 and bestId <> 0 then
          if bestDistance <= castRange(spellSlot) * castRange(spellSlot) then
            if bestDistance >= castMinimum(spellSlot) * castMinimum(spellSlot) then
              ' Save the last recharging charge for valuable targets.
              if bestKind <> 3 or charges > 1 or recharge <= tickRate then
                castId = bestId
              elseif bestHp <= damage then
                castId = bestId
              end if
            end if
          end if
        end if
        if castId <> 0 then
          if castId = bestId and castGround(spellSlot) then
            ' Area spells lead the observed movement, with a bounded lead.
            leadX = velocityX * castDelay(spellSlot)
            leadY = velocityY * castDelay(spellSlot)
            if targetHeld >= castDelay(spellSlot) then
              leadX = 0
              leadY = 0
            end if
            if leadX > 2 then
              leadX = 2
            elseif leadX < -2 then
              leadX = -2
            end if
            if leadY > 2 then
              leadY = 2
            elseif leadY < -2 then
              leadY = -2
            end if
            aimX = bestX + leadX
            aimY = bestY + leadY
            if aimX >= 0 and aimX < mapWidth - 1 then
              if aimY >= 0 and aimY < mapHeight - 1 then
                accepted = castPoint(hostSlot(spellSlot), originX + side * aimX, originY + side * aimY)
                actionError = lastActionError()
                if accepted then
                  exit sub
                end if
              end if
            end if
          end if
          ' Targeted projectiles track their target. Targeted ground rings
          ' offset their center so the enemy is inside the damaging band.
          ' Also fall back here if a led point is outside the map or vision.
          accepted = castTarget(hostSlot(spellSlot), castId)
          actionError = lastActionError()
          if accepted then
            exit sub
          end if
        end if
      end if
    end if
  next spellSlot
end sub

if drafting then
  chooseHero()
  end
end if

' Buy back immediately whenever affordable, including during a long respawn.
if selfHp <= 0 then
  price = buybackPrice()
  if price > 0 and selfGold >= price then
    accepted = buyback()
    actionError = lastActionError()
  end if
  initialized = 0
  end
end if
if selfChannelTicks > 0 or selfStunTicks > 0 then
  end
end if
' N90 = N89d's backswing cancel on N86b: a basic hit lands at 45 % of the
' swing and the swing restarts whenever the hero stops fighting for a tick.
' Every tick, outside the think throttle: on the decision after a hit, walk
' to our own position;
' on the next, attack the same target again, or think at once when the
' hit killed it (Beta:v4 hits every 14 ticks where the full cycle is 30).
if cancelTarget <> 0 then
  accepted = attackTarget(cancelTarget)
  cancelTarget = 0
  if accepted then
    end
  end if
end if
if selfAttacksLanded <> cancelHits then
  cancelHits = selfAttacksLanded
  if walkTo(selfX, selfY) then
    cancelTarget = selfTarget
    if selfTarget = 0 then
      nextThink = worldTick + 1
    end if
    end
  end if
end if
if worldTick < nextThink then
  end
end if
' Use the same team-relative coordinates for every spatial decision.
side = 1 - selfTeam * 2
originX = selfTeam * (mapWidth - 1)
originY = selfTeam * (mapHeight - 1)
myX = originX + side * selfX
myY = originY + side * selfY

nextThink = worldTick + 6
role = heroRole(selfClass)
attackRange = (selfAttackRange \ 100) / (worldScale \ 100)
speed = (selfMoveSpeed \ 100) / (worldScale \ 100)

if initialized = 0 then
  initialized = 1
  spawnX = myX
  spawnY = myY
  homeX = myX
  homeY = myY
  enemyX = mapWidth - 1 - myX
  enemyY = mapHeight - 1 - myY
  previousHp = selfHp
  progressTick = worldTick
  previousX = myX
  previousY = myY
  crossedMiddle = 0
  retreating = 0
  tripCamp = -1
  ' The host exposes effects and costs, but not spell range or cast shape.
  ' These small tables mirror content.nim; all distances are in tiles.
  castRange(0) = 0
  castRange(1) = 1.5
  castRange(2) = 2.5
  castRange(3) = 2
  castDelay(2) = 24
  castDelay(3) = 24
  healRange = 4
  for spellSlot = 0 to 3
    castGround(spellSlot) = spellSlot >= 2
    castMinimum(spellSlot) = 0
  next spellSlot
  if selfClass = VanguardKnight then
    healRange = 7 / 3
    castRange(2) = 7 / 3
    castRange(3) = 11 / 6
    castDelay(2) = 12
    castDelay(3) = 6
  elseif selfClass = Ranger then
    castRange(0) = 7
    castRange(1) = 6
    castRange(2) = 6.5
    castRange(3) = 8
  elseif selfClass = Arcanist then
    castRange(1) = 5.5
    castRange(2) = 6
    castRange(3) = 7
    castDelay(2) = 48
    castDelay(3) = 72
  elseif selfClass = DruidWarden then
    castRange(1) = 4
    castRange(2) = 4
    castRange(3) = 10 / 3
  elseif selfClass = DemonHunter then
    castRange(2) = 2
    castRange(3) = 5
    castDelay(2) = 6
    castGround(3) = 0
  elseif selfClass = DeathKnight then
    castRange(2) = 8 / 3
    castRange(3) = 7 / 3
    castDelay(3) = 12
    castGround(3) = 0
    castMinimum(3) = 2 / 3
  elseif selfClass = Crossbowman then
    castRange(0) = 7
    castRange(1) = 20 / 3
    castRange(2) = 6
    castRange(3) = 7.5
    castDelay(2) = 12
  elseif selfClass = Lich then
    castRange(0) = 6
    castRange(1) = 20 / 3
    castRange(2) = 5
    castRange(3) = 6.5
    castGround(3) = 0
  elseif selfClass = Warlock then
    ' N158: Mending Hex and Dread Pact reach 6 tiles (content.nim 360_000).
    healRange = 6
    castRange(1) = 6
    castRange(2) = 6
    castRange(3) = 5
    castGround(2) = 0
    castGround(3) = 0
  elseif selfClass = Berserker then
    castRange(3) = 13 / 6
    castDelay(2) = 12
    castDelay(3) = 48
  end if
end if

if selfHp < previousHp then
  hurtTick = worldTick
end if
previousHp = selfHp
if selfAttacksLanded <> previousHits or myX <> previousX or myY <> previousY then
  progressTick = worldTick
end if
previousHits = selfAttacksLanded
previousX = myX
previousY = myY
if worldTick - progressTick > tickRate * 6 and selfTarget <> 0 then
  blockedId = selfTarget
  blockedUntil = worldTick + tickRate * 3
  progressTick = worldTick
end if

' Mid enemy towers (team-relative tiles): outer (51,72) progress 121,
' inner (34,85) 151, gate (19,95) 176. A destroyed tower's footprint tile reads
' walkable once our team has seen it fall. Towers shoot 9 tiles (gate 10) with
' homing shots, so the creep front is clamped 13 tiles (18 progress) short of
' the nearest living tower and the hero stays two tiles behind it.
laneClamp = 190
zoneX = -100
zoneY = -100
if terrainWalkableAt(originX + side * 19, originY + side * 95, GroundLayer) = 0 then
  laneClamp = 158
  zoneX = 19
  zoneY = 95
end if
if terrainWalkableAt(originX + side * 34, originY + side * 85, GroundLayer) = 0 then
  laneClamp = 133
  zoneX = 34
  zoneY = 85
end if
if terrainWalkableAt(originX + side * 51, originY + side * 73, GroundLayer) = 0 then
  laneClamp = 103
  zoneX = 51
  zoneY = 73
end if
learnAbilities()
observe()
' Remember the lane frontier across the rotating creep scan windows.
frontMemory = frontMemory - 3
if frontProgress >= frontMemory then
  frontMemory = frontProgress
  frontMemX = frontX
  frontMemY = frontY
end if
if (bestKind = 1 or bestKind = 4 or bestKind = 5) and sieging = 0 then
  if tanks < 3 or selfHp * 10 < selfMaxHp * 6 then
    bestId = 0
    bestKind = 0
  end if
end if
' N158: the Warlock is a pure healer (red-kite:v73): it never takes an
' attack target or siege, so spells() casts only its heals.
if selfClass = Warlock then
  bestId = 0
  bestKind = 0
  sieging = 0
end if
inventory()
spells()
dodgeWarnings()

if selfHp * 4 < selfMaxHp or (attackRange >= 3 and selfHp * 10 < selfMaxHp * 4) or (bestKind = 6 and selfHp * 10 < selfMaxHp * 4) then
  retreating = 1
end if
if inOwnSpawn() then
  if selfHp * 10 < selfMaxHp * 9 or selfMana * 10 < selfMaxMana * 9 then
    moveTo(spawnX, spawnY, 0)
    end
  end if
  retreating = 0
end if

if dodge and selfRootTicks = 0 then
  moveTo(dodgeX, dodgeY, 0)
  end
end if
if retreating then
  ' A safe scroll saves the long return trip; damage and control can punish it.
  if owned(21) > 0 and selfPortalCooldown = 0 and selfRootTicks = 0 then
    dx = myX - homeX
    dy = myY - homeY
    if dx * dx + dy * dy > 400 and threatDistance > 144 then
      accepted = useItemAt(inventorySlot(21), originX + side * spawnX, originY + side * spawnY)
      actionError = lastActionError()
      if accepted then
        end
      end if
    end if
  end if
  moveTo(spawnX, spawnY, 0)
  end
end if

if sieging and siegeId = 0 then
  moveTo(zoneX + 3, zoneY - 3, 0)
  end
end if
if sieging and worldTick - siegePrint >= 240 then
  siegePrint = worldTick
  print worldTick; " N81 siege "; siegeId; " hp "; siegeHp; " feet "; siegeFeet; " visits "; siegeVisits; " self "; selfHp; "/"; selfMaxHp; " at "; myX; ","; myY
end if
if towerAggro and selfHp * 3 < selfMaxHp * 2 and tanks = 0 and sieging = 0 then
  moveTo(homeX, homeY, 0)
  end
end if
if campAggro > 0 and bestKind <> 6 then
  ' Camp mobs pulled by someone else: a frail hero leaves their 12-tile leash.
  if selfMaxHp < 250 or selfHp * 2 < selfMaxHp then
    moveTo(homeX, homeY, 0)
    end
  end if
end if
if enemyPower > friendlyPower + 6 and threatDistance < 64 then
  if selfHp * 4 < selfMaxHp * 3 then
    moveTo(homeX, homeY, 0)
    end
  end if
end if
' N93a: an enemy hero two or more levels above us within 10 tiles wins the
' duel (live rounds 1307-1310: 75 % of black-kite:v74's deaths); step back
' unless our hero target is two hits from death.
if strongLevel >= selfLevel + 2 and sieging = 0 then
  if bestKind <> 2 or bestHp >= selfAttackDamage * 2 then
    moveTo(homeX, homeY, 0)
    end
  end if
end if
' N158: the Warlock stays within 3 tiles of its anchor ally and heals it
' from spells().
if selfClass = Warlock and anchorId <> 0 and anchorDistance > 9 then
  if worldTick - anchorPrint >= 240 then
    anchorPrint = worldTick
    print worldTick; " N158 follow "; anchorId; " d2 "; anchorDistance; " at "; myX; ","; myY
  end if
  moveTo(anchorX, anchorY, 0)
  end
end if
if selfClass = Warlock and anchorId <> 0 then
  ' An idle ranged hero auto-acquires inside its attack range on 8.1, so
  ' the healer keeps a walk order, shuttling between its anchor and a
  ' point two tiles behind it on the home side.
  behindX = anchorX
  behindY = anchorY
  if homeX - anchorX > 2 then
    behindX = anchorX + 2
  elseif homeX - anchorX < -2 then
    behindX = anchorX - 2
  end if
  if homeY - anchorY > 2 then
    behindY = anchorY + 2
  elseif homeY - anchorY < -2 then
    behindY = anchorY - 2
  end if
  if (myX - behindX) * (myX - behindX) + (myY - behindY) * (myY - behindY) <= 1 then
    moveTo(anchorX, anchorY, 0)
  else
    moveTo(behindX, behindY, 0)
  end if
  end
end if

if bestId <> 0 then
  ' Finish a windup before kiting; never cancel every swing with movement.
  if bestKind = 2 and aimedAtUs > 0 and attackRange >= 3 then
    if bestDistance < 4 and selfAttackCooldown > tickRate \ 2 then
      if selfAttacksLanded > 0 and speed > 0 then
        kiteStep = (selfMoveSpeed * tickRate) \ worldScale
        if kiteStep < 1 then
          kiteStep = 1
        elseif kiteStep > 4 then
          kiteStep = 4
        end if
        kiteX = myX + kiteStep
        kiteY = myY + kiteStep
        if bestX >= myX then
          kiteX = myX - kiteStep
        end if
        if bestY >= myY then
          kiteY = myY - kiteStep
        end if
        moveTo(kiteX, kiteY, 0)
        end
      end if
    end if
  end if
  if selfTarget <> bestId then
    accepted = attackTarget(bestId)
    actionError = lastActionError()
    if accepted = 0 then
      blockedId = bestId
      blockedUntil = worldTick + tickRate * 3
    else
      orderTick = 0
    end if
  end if
  end
end if

' N2 camp trip: nothing to attack here (no enemy within 18 tiles, no camp mob
' within 8). Walk to a camp the lane hold leaves out of reach; the camp rule in
' observe() engages it on arrival. A camp with no mob visible from its center
' is cleared or respawning: remember it for 75 s and pick another.
if tripCamp >= 0 then
  tripX = originX + side * campX(tripCamp)
  tripY = originY + side * campY(tripCamp)
  tripDx = tripX - myX
  tripDy = tripY - myY
  tripDone = 0
  if worldTick > tripUntil or retreating or towerAggro then
    tripDone = 1
  end if
  if selfHp * 2 < selfMaxHp or threatDistance <= 144 then
    tripDone = 1
  end if
  ' A death or portal moved the hero: never cross the map for a camp.
  if tripDx * tripDx + tripDy * tripDy > 625 or inOwnSpawn() then
    tripDone = 1
  end if
  if tripDx * tripDx + tripDy * tripDy <= 36 then
    tripIdle = tripIdle + 1
    if tripIdle >= 2 then
      campWait(tripCamp) = worldTick + tickRate * 75
      tripDone = 1
    end if
  end if
  if tripDone then
    tripCamp = -1
    tripCooldown = worldTick + tickRate * 5
  else
    if worldTick - traceTick >= 240 then
      traceTick = worldTick
      print worldTick; " L"; selfLevel; " hp "; selfHp; "/"; selfMaxHp; " at "; myX; ","; myY; " trip "; tripCamp; " to "; tripX; ","; tripY; " idle "; tripIdle
    end if
    moveTo(tripX, tripY, 0)
    end
  end if
end if
if tripCamp < 0 and worldTick >= tripCooldown and retreating = 0 then
  if towerAggro = 0 and campAggro = 0 and selfHp * 10 >= selfMaxHp * 7 and threatDistance > 225 then
    tripScore = -1
    camps = campCount()
    if camps > 15 then
      camps = 15
    end if
    if camps < 1 then
      camps = 1
    end if
    for tripScan = 0 to camps - 1
      tripTier = campTier(tripScan)
      if tripTier = 3 and selfLevel >= 7 and worldTick >= campWait(tripScan) then
        tripX = originX + side * campX(tripScan)
        tripY = originY + side * campY(tripScan)
        tripDx = tripX - myX
        tripDy = tripY - myY
        tripDist = tripDx * tripDx + tripDy * tripDy
        if tripDist <= 484 then
          ' Keep 14 tiles from every living enemy mid tower (9-tile homing shots).
          tripSafe = 1
          if laneClamp <= 103 and (tripX - 51) * (tripX - 51) + (tripY - 72) * (tripY - 72) < 196 then
            tripSafe = 0
          end if
          if laneClamp <= 133 and (tripX - 34) * (tripX - 34) + (tripY - 85) * (tripY - 85) < 196 then
            tripSafe = 0
          end if
          if laneClamp <= 158 and (tripX - 19) * (tripX - 19) + (tripY - 95) * (tripY - 95) < 196 then
            tripSafe = 0
          end if
          if tripSafe and tripTier * 1000 - tripDist > tripScore then
            tripScore = tripTier * 1000 - tripDist
            tripCamp = tripScan
          end if
        end if
      end if
    next tripScan
    if tripCamp >= 0 then
      tripUntil = worldTick + tickRate * 90
      tripIdle = 0
      tripX = originX + side * campX(tripCamp)
      tripY = originY + side * campY(tripCamp)
      moveTo(tripX, tripY, 0)
      end
    end if
  end if
end if

' Farm mid: two tiles behind the frontmost own creep inside the clamp,
' otherwise beside the outermost living own mid tower.
if holdTowerX < 1000 then
  ' Three tiles homeward of the tower, 9 tiles from the tier-1 camp (65,31).
  holdX = holdTowerX + 3
  holdY = holdTowerY - 2
else
  holdX = 70
  holdY = 37
end if
goalX = holdX
goalY = holdY
if frontMemory >= 0 then
  goalX = frontMemX
  goalY = frontMemY
end if
if worldTick - traceTick >= 240 then
  traceTick = worldTick
  print worldTick; " L"; selfLevel; " hp "; selfHp; "/"; selfMaxHp; " at "; myX; ","; myY; " raw "; selfX; ","; selfY; " goal "; goalX; ","; goalY; " front "; frontProgress; "/"; frontMemory; " clamp "; laneClamp; " tanks "; tanks; " best "; bestKind; " ep "; enemyPower; " fp "; friendlyPower; " ca "; campAggro; " trip "; tripCamp; " gold "; selfGold; " pot "; owned(1)
end if
if canShop() and owned(21) > 0 and selfPortalCooldown = 0 then
  dx = myX - holdX
  dy = myY - holdY
  if dx * dx + dy * dy > 400 then
    if threatDistance > 144 then
      accepted = useItemAt(inventorySlot(21), originX + side * holdX, originY + side * holdY)
      actionError = lastActionError()
      if accepted then
        end
      end if
    end if
  end if
end if
' N37: attack-move auto-engages resting camp mobs within 8 tiles (melee
' acquire radius), so the level-1 walk with the first wave past the tier-3
' camp at (25,20) pulls it and costs the first two waves. Plain-walk to the
' goal while no enemy object is within 18 tiles; attack-move near contact.
engageWalk = 0
if threatDistance <= 324 then
  engageWalk = 1
end if
' N37d: within 11 tiles of the nearest living enemy mid tower (the target scan already skips
' heroes there) an attack-move re-acquires a hero within 8 tiles at every
' decision and chases it under the tower; walk back to the clamped goal.
if (myX - zoneX) * (myX - zoneX) + (myY - zoneY) * (myY - zoneY) < 121 then
  engageWalk = 0
end if
if selfClass = Warlock then
  engageWalk = 0
end if
moveTo(goalX, goalY, engageWalk)
