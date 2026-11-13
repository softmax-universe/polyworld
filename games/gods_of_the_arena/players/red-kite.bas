' N92d (2026-10-07): N92c plus a guard-1 target. Locally guard 0 fell in 6 of
' 6 N92c games and guard 1 in none: with guard 0 down, the nearest tower to
' the guard-1 approach is the mid gate tower (19,95), 10 tiles from guard 1
' (16,105), so the siege took the mid gate (seed 3 seat 4: 3,501 -> 555 hp,
' 0 on guard 1). In the guard-1 phase only a tower within 4 tiles of the
' guard-1 footprint is a siege target, and the fogged walk goes by (6,101)
' to (13,107), more than 10 tiles from the mid gate. Parent N92c.
' N92c (2026-10-07): N92b plus a rest trip. Locally (seed 3, Blue seat 7) the
' seat held lane A at 524/885 hp (59 %) with no potion and 4,675 gold unspent
' from tick 18,844 to the end; siege visits open only at 80 % hp and there is
' no natural regeneration, so it never opened one. A calm siege seat (level
' 5+, no potion, below 80 %, no enemy hero seen, unhurt for 2 s) now returns
' home to heal and shop through the normal retreat. Parent N92b.
' N92b (2026-10-07): N92 plus a guard step. When lane A's gate footprint
' (4,86) reads walkable the lane-A hold clamp moves from 150 to 155, 13 tiles
' short of guard 0 (team-relative (9,98), range 10), and to 162 once guard
' 0's footprint (9,99) reads walkable too (guard 1 at (16,105)). Locally N92
' collapsed lane A in 4 of 6 games but held at y ~78, 20 tiles from guard 0,
' outside the 18-tile siege scan, so 0 guards were touched. The living guard's
' footprint is also the fogged siege zone (N91): a probe showed guard 1 never
' enters the object list from the hold 15 tiles away. Parent N92.
' N92 (2026-10-07): N91h with Crossbowman first in the draft (score 4 -> 11,
' as N79 did on B). Local game 68: N91h's Arcanist visits deal ~450 building
' damage each and leave at ~32 % hp, so lane A never falls (enemy buildings
' lost 4.0 per game, same as red-kite:v63); N90's Crossbowman visits deal
' ~840 and leave at ~72 %, and the enemy mid falls in 6 of 6 games
' (Crossbowman level-12 basic damage 163 v 86, hp ~1,290 v ~500). Parent N91h.
' N91h (2026-10-07): N91f plus no retreat scroll within two seconds of
' taking damage. Locally N91f and N91g channelled the scroll in place 10
' tiles from a fogged gate tower (after a closed visit, or after the 25 %
' retreat under it) and the homing shots killed the hero mid-channel
' (seed 3 Red seat 4, ticks 14,097 and 18,667). Parent N91f.
' N91f (2026-10-07): N91d plus a step back toward home whenever a living
' enemy tower is within 11 tiles (range 9 + 2) and no visit is open. Probe
' on N91d's local seed-1 Blue seat 7: a covered level-5 visit closed at
' tick ~5,200 and the hero stood idle 8 tiles from the outer tower (no
' target, no move), 308 -> 29 hp in 120 ticks, then walked to spawn.
' Parent N91d.
' N91d (2026-10-07): N91 without the ranged retreat at 40 % hp (back to
' N89e's 25 %; the siege exit below 35 % still retreats). Locally N91's Blue
' seat 7 trailed N89e from minute 2 (112 v 300 XP), before any siege visit
' can open at level 5; the 40 % retreat is the only N91 hunk active early.
' Parent N91.
' N91 (2026-10-07): B's N90 siege package (N86b danger-gated uncovered and
' footprint tower visits from level 5, 80 % open / 35 % exit, ranged retreat
' at 40 %) on A's N89e backswing-cancel source, on A's own lane A (towers
' (7,46), (7,77), (4,86)) instead of mid. N90 lifted B's building damage
' 1,576 -> 10,465 per game on the diagnostic worlds. Parent N89e.
' N89e (2026-10-07): red-kite:v63 plus the N89d backswing cancel.
' N56c (2026-09-26): N56b with both spell rules gated to the Mage classes
' (Arcanist, Lich) instead of every ranged seat. In the N56b mirrored screen
' (red-kite:v62, xreq_89ef8ba3) the Warlock seat lost 627 creep last-hit XP
' and 364 camp XP per game (basic attack 21 + 5 per level: Moth Hex was its
' last-hit tool) while the Lich gained 663 hero-kill XP with creep last hits
' flat, and the Arcanist (xreq_bd870980) gained 319 hero-kill XP with creep
' last hits flat. Support seats (Warlock, DruidWarden) keep red-kite:v60's
' spell rules unchanged. Parent red-kite:v62 (N56b).
' N56b (2026-09-26): N56 plus the primary ability (slot 1, three charges)
' reserved for enemy heroes on ranged seats: it is never cast at a creep,
' camp mob or building (creep XP is a shared pool, last hits pay nothing;
' relh's Ranger lands 19-29 primary casts per game on heroes and 0 on
' creeps, ours 17-21 and 51-75), so a charge and the 48-tick cooldown are
' free when a finishable hero enters lance range. Parent: N56 (below).
' N56 (2026-09-26): red-kite:v60 plus one spell rule for ranged seats: a
' damaging non-ground ability (the 3-charge primary: Frost Lance 5.5 tiles,
' Ice Spear, Moth Hex; the Lich / Warlock ultimates) is cast at the lowest-hp
' living enemy hero inside its cast range whenever that hero's hp is at or
' below the ability's damage, even while the basic-attack target is a creep.
' tools/finisher_windows.nim on the red-kite:v60 batches: the Arcanist's basic
' attack reaches 5.0 tiles, Frost Lance 5.5 and homes, so the finishable hero
' that escapes the N55 hold at 5.1-5.4 tiles is inside lance range; v60 only
' casts at bestId. No movement, no change to the target scan or the throw.
' Parent red-kite:v60 (N53b).
' N39d (2026-09-26): N39c with the early-hold gate extended to peer-level
' heroes. In the N39c screen (red-kite:v55, xreq_52626798) the adjacent-only
' hold kept the level-2 Berserker out of the first clash (0 hero hits through
' tick 1,800, XP 1,101 at minute 5 vs 780) but the seat then walked past the
' enemy outer tower at level 4 and died at tick 6,318 to the same DeathKnight
' (level 4, full hp, ours 66 %) — the `selfLevel < 3` gate had closed. Now the
' gate (hold four tiles behind the front, plain walk, adjacent-only targets)
' is up while an enemy hero within 12 tiles is alive and either we are below
' level 3 or its level is at least ours, so a melee seat declines every duel
' it does not out-level. Parent red-kite:v55 (N39c).
' N39c (2026-09-26): N39b plus adjacent-only targets under the gate. In the N39b
' screen (red-kite:v54, xreq_f5f69f87) the team-0 Berserker trail was still
' tick-identical to v51: at tick 1,212 the target scan sends the seat five
' tiles into the enemy wave after creep 1090 (N22 last hit / creep attacking
' us), one decision before the DeathKnight enters 8 tiles, and the hero exchange
' then happens inside their wave. Now: the gate uses the 12-tile hero radius
' (enemyPower), and while it holds a melee seat below level 3 targets only
' objects within 2 tiles, so creeps and heroes must come to the hold.
' Parent red-kite:v54 (N39b).
' N39b (2026-09-26): N39 plus a plain walk under the same gate. In the N39 screen
' (red-kite:v53, xreq_abdfd085) the team-0 Berserker trail was tick-identical to
' v51 through the first clash: the attack-move toward the hold acquires the
' enemy creeps within 8 tiles as soon as the waves meet and walks the seat
' into the wave whatever the hold offset. Below level 3 with an enemy hero
' within 8 tiles a melee seat now plain-walks to its four-tile hold and
' fights only what the target scan picks (last hits, creeps and heroes that
' attack it). Parent red-kite:v53 (N39).
' N39 (2026-09-26): keep the level-2 melee seat out of the first clash. Every
' team-0 Berserker game of red-kite:v47-v52 meets the enemy wave at ticks
' 1,262-1,370 two tiles behind its own front beside a DeathKnight, and both
' winning that exchange (v51) and turning the retreat around (v52) still end
' in a 1,900-tick spawn trip. One change on red-kite:v51: while the hero is
' below level 3 and an enemy hero is within 8 tiles, a melee seat holds four
' tiles behind its front instead of two, so the first exchange is against
' creeps that reach it and the enemy hero has to leave its wave to reach us.
' The hit-back term (N38g) stays for contacts that still happen.
' Parent red-kite:v51.
' N38g (2026-09-26): N38f with the term raised to +600 so it also outranks a
' last-hittable creep (+100 kind +400 last hit +40 targeting us +60 current):
' in red-kite:v50 the hero windows fell in the dead half of the 20-tick swing
' (hit at tick 9, decisions every 12) and every landing swing went to a creep
' (duel_events ereq_059f5a68: 3 creep last hits, 0 basic hits on the hero).
' N38f (2026-09-26): N38c plus one target-score term — a melee seat answers an
' enemy hero that is hitting it from within attack range + 1 tile (+150) so it
' outranks the lane creep that is also hitting it (N38c trail ereq_34cb616d:
' at the first clash the level-2 Berserker landed 1 hit on the DeathKnight over
' 259 hero damage taken because the creep scored +100 kind +40 targeting us and
' the hero +60 - 8 x level +40). Ranged seats unchanged. Parent red-kite:v47.
' N38c (2026-09-26): N38b (B's N37d hunks gated to melee seats: plain-walk lane
' order while no enemy is within 18 tiles, never inside the leg-2 tower zone,
' below-level-5 clash guard) plus B's N22 melee last-hit creep targeting, so a
' level-2 melee seat arriving with its first wave does not wade into the enemy
' wave chasing creeps (red-kite:v46 Berserker died at tick 1,377). Parent red-kite:v42.
' N27 Lich draft re-rank (2026-09-25): Lich ranked above Warlock and Berserker
' (live rounds 775-783: league Lich 4,954 XP per seat vs Warlock 3,430 /
' Berserker 3,768; Andre / Ari take Lich as their second class at 7,296 /
' 6,487 while our Warlock / Berserker seats make 4,572 / 4,541). Parent red-kite:v40.
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
      if candidate = Arcanist then
        score = 10
      elseif candidate = DemonHunter then
        score = 9
      elseif candidate = Lich then
        score = 8
      elseif candidate = Warlock then
        ' N157: the support seat drafts Warlock first (N155: James Botts /
        ' khors Warlock seats win 126-17 / 102-19 on v71's rosters).
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
      ' Outermost living own tower of lane A (leg 1, smallest x) is the hold.
      if y < 24 and x < holdTowerX then
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
      ' N157: the support anchor is an ally outside our spawn; keep the
      ' previous anchor while it stays visible there, else the nearest.
      if id <> selfId and (x - spawnX) * (x - spawnX) + (y - spawnY) * (y - spawnY) > 225 then
        if id = lastAnchorId or ((anchorId = 0 or anchorId <> lastAnchorId) and distance < anchorDistance) then
          anchorId = id
          anchorX = x
          anchorY = y
          anchorDistance = distance
        end if
        ' N173b: the same rule restricted to Crossbowman allies.
        if class = Crossbowman and (id = lastAnchorId or ((xbowId = 0 or xbowId <> lastAnchorId) and distance < xbowDistance)) then
          xbowId = id
          xbowX = x
          xbowY = y
          xbowDistance = distance
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
      ' Lane A progress: leg 1 west along y ~ 10 from the gate (86,5) to the
      ' corner (8,8), leg 2 north along x ~ 8 toward the enemy outer tower (8,47).
      progress = -1
      if y >= 20 and x <= 24 then
        progress = 78 + y - 8
      elseif y < 24 then
        progress = 86 - x
      end if
      if progress >= 0 and progress <= laneClamp and progress > frontProgress then
        frontProgress = progress
        frontX = x
        frontY = y
        if y >= 20 and x <= 24 then
          frontY = y - 2
        else
          frontX = x + 2
        end if
      end if
    end if
    exit sub
  end if
  if kind = 1 then
    enemyX = x
    enemyY = y
  end if
  if kind = 2 and distance <= 144 then
    enemyPower = enemyPower + objectLevel(index) + 2
    if objectMana(index) >= 25 and objectSilenceTicks(index) = 0 then
      enemyPower = enemyPower + 2
    end if
  end if
  ' N39 / N39d: a living enemy hero within 12 tiles this scan that we do not
  ' out-level (any hero while below level 3; see header).
  if kind = 2 and distance <= 144 and objectAlive(index) <> 0 then
    if selfLevel < 3 or objectLevel(index) >= selfLevel then
      heroNear = 1
    end if
  end if
  ' N56: lowest-hp living enemy hero inside the primary ability's cast range
  ' (ranged seats), a finisher candidate for spells() whatever bestId is.
  if kind = 2 and objectAlive(index) <> 0 and (selfClass = Arcanist or selfClass = Lich) then
    if distance <= castRange(1) * castRange(1) and hp < finishHp then
      finishId = id
      finishHp = hp
      finishDist = distance
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
  if kind = 4 and distance < siegeDistance and (zoneX <> 16 or (x - zoneX) * (x - zoneX) + (y - zoneY) * (y - zoneY) <= 16) then
    siegeDistance = distance
    siegeIndex = index
    siegeId = id
    siegeHp = hp
    siegeX = x
    siegeY = y
    siegeTarget = target
  end if
  if x < 24 and y > laneClamp - 68 then
    ' Leg 2 within 11 tiles of the nearest living enemy tower (range 9).
    exit sub
  end if
  ' N39c / N39d: with a peer-or-higher enemy hero within 12 tiles on the
  ' previous scan, a melee seat targets only objects within 2 tiles.
  if attackRange < 3 and heroClose and distance > 4 then
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
    ' N122b: a ranged seat attacks an enemy hero inside its attack range ahead
    ' of any lane creep it cannot last-hit (+400 outranks the creep's +100
    ' kind, +40 targeting-us and +60 held target at any range and level;
    ' a last-hittable creep, +400 more, still wins; N122 +200 lost to them).
    ' The leader lands 2.7x our basic hits on heroes in the same 1 v 1 fights.
    if attackRange >= 3 and distance <= attackRange * attackRange then
      score = score + 400
    end if
    ' N38f: a melee seat hit by an enemy hero standing on it answers that
    ' hero instead of the creep that is also hitting it (+150 outranks the
    ' creep's +100 kind +40 targeting-us; a last-hittable creep still wins).
    if attackRange < 3 and target = selfId and distance <= (attackRange + 1) * (attackRange + 1) then
      score = score + 600
    end if
    if hp < selfAttackDamage * 4 then
      score = score + 250
    end if
  elseif kind = 3 then
    if distance <= 9 then
      enemyCreepNear = 1
    end if
    ' N22 (black-kite:v25 hunk, N38c on A): a melee hero walks at a lane creep
    ' only to last-hit it or to answer one attacking it; the hold's attack-move
    ' still engages creeps that reach the hero. With the plain-walk arrival a
    ' level-2 Berserker otherwise wades into the enemy wave chasing creeps
    ' and dies to the hero standing on it (red-kite:v46, tick 1,377).
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
  finishId = 0
  finishHp = 10000
  finishDist = 1000000
  threatDistance = 1000000
  forwardDistance = 1000000
  friendlyPower = 0
  enemyPower = 0
  heroClose = heroNear
  heroNear = 0
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
  xbowId = 0
  xbowDistance = 1000000
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
  ' N81 / N85d / N86b (from N90): a visit opens at 80 % hp from level 5 and
  ' ends below 35 % (retreat); a fogged lane-A tower stays the target while
  ' its footprint stands; an uncovered visit needs no enemy hero or lane
  ' creep within 10 tiles. Heroes keep target priority.
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
        ' N53b: tools/poison_throws.nim on the red-kite:v59 batches: 11-13 of our
        ' 12-16 doses per game land on heroes above 150 hp, doses are held only
        ' 15-27 % of the game and 0.1-0.7 throws finish a hero; Coach's and
        ' BeWellBot's seats hold doses 65-70 % of the game and land 5-8 throws
        ' per game at <= 35 hp (each a 150-XP last hit). Throw only when the
        ' targeted hero is within two doses of death (hp <= 70).
        elseif id = 4 and bestKind = 2 and selfTarget = bestId and bestId <> 0 and bestHp <= 70 then
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
  ' N127 (exchange_split on the 160 n102 tapes): the leader's Crossbowman opens
  ' with a Crimson Dagger (+8 damage) in 80 / 80 games; its level 1-5 basic
  ' hits on heroes do 54 v our 38 and it wins 2.02 v 1.18 kill exchanges.
  ' Buy the Dagger first, in the slot the two Poison Potions used.
  if role = 1 then
    buy(11, 110, 1)
  end if
  buy(8, 100, 1)
  buy(1, 30, 2)
  buy(21, 100, 2)
  buy(22, 45, 2)
  if role = 0 or role = 4 then
    buy(16, 160, 1)
    buy(2, 75, 2)
  elseif role = 1 then
    buy(19, 180, 1)
  else
    buy(20, 190, 1)
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
  ' N53: BeWellBot's Warlock and Coach's Arcanist throw 33-48 Poison Potions
  ' (id 4, 40 gold, 35 damage at once on the current attack target within
  ' basic-attack range, no cooldown) per game for 7.5-12.9 hero kills; our
  ' ranged Mage / Support seats bought none (the Mana Elixir held the slot).
  ' They now keep four doses, bought only from gold above the next buyback
  ' price (N52's unreserved purchase starved buybacks), and throw one every
  ' decision at the enemy hero they are attacking (inventory()).
  if attackRange >= 3 and role <> 1 then
    for poisonUp = 1 to 4
      if budget >= 100 * (selfDeaths + 1) + 40 then
        buy(4, 40, 4)
      end if
    next poisonUp
  end if
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
        elseif damage > 0 and finishId <> 0 and castGround(spellSlot) = 0 and finishHp <= damage and finishDist <= castRange(spellSlot) * castRange(spellSlot) and finishDist >= castMinimum(spellSlot) * castMinimum(spellSlot) then
          ' N56: a targeted damaging ability finishes any enemy hero in its
          ' cast range ahead of the current attack target.
          castId = finishId
        elseif damage > 0 and bestId <> 0 and spellSlot = 1 and bestKind <> 2 and (selfClass = Arcanist or selfClass = Lich) then
          ' N56b: a ranged seat keeps its primary charges for enemy heroes.
          castId = 0
        elseif damage > 0 and bestKind <> 2 and spellSlot <= 2 and selfClass = Warlock then
          ' N157: the Warlock keeps its two heals for allies and enemy heroes.
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
' N89d: a basic hit lands at 45 % of the swing and the swing restarts
' whenever the hero stops fighting for a tick. Every tick, outside the
' think throttle: on the decision after a hit, walk to our own position;
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
    ' N157: Mending Hex and Dread Pact reach 6 tiles (content.nim 360_000).
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

' Lane-A enemy towers (team-relative tiles): outer (7,46) progress 116,
' inner (7,77) 147, gate (4,86) 156. A destroyed tower's footprint tile reads
' walkable once our team has seen it fall. Towers shoot 9 tiles (gate 10) with
' homing shots, so the creep front is clamped 13 tiles short of the nearest
' living tower and the hero stays two tiles behind it.
' N91: zoneX / zoneY = footprint of the nearest living one (siege zone).
laneClamp = 150
zoneX = -100
zoneY = -100
' N92b: with the lane-A gate down step toward the exposed guards.
if terrainWalkableAt(originX + side * 9, originY + side * 99, GroundLayer) then
  laneClamp = 162
  if terrainWalkableAt(originX + side * 16, originY + side * 106, GroundLayer) = 0 then
    zoneX = 16
    zoneY = 106
  end if
else
  laneClamp = 155
  zoneX = 9
  zoneY = 99
end if
if terrainWalkableAt(originX + side * 4, originY + side * 86, GroundLayer) = 0 then
  laneClamp = 143
  zoneX = 4
  zoneY = 86
end if
if terrainWalkableAt(originX + side * 7, originY + side * 77, GroundLayer) = 0 then
  laneClamp = 134
  zoneX = 7
  zoneY = 77
end if
if terrainWalkableAt(originX + side * 7, originY + side * 46, GroundLayer) = 0 then
  laneClamp = 103
  zoneX = 7
  zoneY = 46
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
' N157b: the Warlock is a pure healer like James Botts' seat (73 hero and
' 303 creep damage per game, 2.06 deaths v N157's 4.75): it never takes an
' attack target, finisher or siege, so spells() casts only its heals.
if selfClass = Warlock then
  bestId = 0
  bestKind = 0
  finishId = 0
  sieging = 0
end if
inventory()
spells()
dodgeWarnings()

if selfHp * 4 < selfMaxHp or (bestKind = 6 and selfHp * 10 < selfMaxHp * 4) then
  retreating = 1
end if
if retreating = 0 and sieging = 0 and zoneX >= 0 and attackRange >= 3 and selfLevel >= 5 then
  if owned(1) = 0 and selfHp * 10 < selfMaxHp * 8 and enemyPower = 0 and worldTick - hurtTick > tickRate * 2 then
    retreating = 1
  end if
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
    if dx * dx + dy * dy > 400 and threatDistance > 144 and worldTick - hurtTick > tickRate * 2 then
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

' N91: walk to a fogged siege tower from the homeward side of leg 2.
if sieging and siegeId = 0 then
  if zoneX = 16 then
    ' N92d: reach guard 1 from the west, out of the mid gate tower's range.
    if myY < 101 and (myX - 6) * (myX - 6) + (myY - 101) * (myY - 101) > 9 then
      moveTo(6, 101, 0)
    else
      moveTo(13, 107, 0)
    end if
    end
  end if
  moveTo(zoneX + 1, zoneY - 4, 0)
  end
end if
if sieging and worldTick - siegePrint >= 240 then
  siegePrint = worldTick
  print worldTick; " N81 siege "; siegeId; " hp "; siegeHp; " feet "; siegeFeet; " visits "; siegeVisits; " self "; selfHp; "/"; selfMaxHp; " at "; myX; ","; myY
end if
if sieging = 0 and siegeId <> 0 and siegeDistance <= 121 then
  moveTo(homeX, homeY, 0)
  end
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
' N173b: in minutes 0-4 the Warlock anchors on a Crossbowman ally outside
' our spawn when one is visible (N172: jb's Warlock does 81 % of the time,
' v73's 46 %, and v73's early Crossbowman exposure is on its melee anchor's lane).
if selfClass = Warlock and worldTick < 7200 and xbowId <> 0 then
  anchorId = xbowId
  anchorX = xbowX
  anchorY = xbowY
  anchorDistance = xbowDistance
end if
' N157: the Warlock stays within 3 tiles of its anchor ally; it fights only
' what the target scan picks there and heals the ally from spells().
if selfClass = Warlock and anchorId <> 0 and anchorDistance > 9 then
  if worldTick - anchorPrint >= 240 then
    anchorPrint = worldTick
    print worldTick; " N157 follow "; anchorId; " d2 "; anchorDistance; " at "; myX; ","; myY
  end if
  moveTo(anchorX, anchorY, 0)
  end
end if
if selfClass = Warlock and anchorId <> 0 then
  ' N157c: an idle ranged hero auto-acquires inside its attack range on 8.1
  ' (sim.nim acquireRadius; N157b's idle hold still dealt 600 basic-attack
  ' damage per game), so the healer keeps a walk order, shuttling between
  ' its anchor and a point two tiles behind it on the home side.
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
          ' Keep 14 tiles from every living enemy lane-A tower (9-tile homing shots).
          tripSafe = 1
          if laneClamp <= 103 and (tripX - 7) * (tripX - 7) + (tripY - 46) * (tripY - 46) < 196 then
            tripSafe = 0
          end if
          if laneClamp <= 134 and (tripX - 7) * (tripX - 7) + (tripY - 77) * (tripY - 77) < 196 then
            tripSafe = 0
          end if
          if laneClamp <= 143 and (tripX - 4) * (tripX - 4) + (tripY - 86) * (tripY - 86) < 196 then
            tripSafe = 0
          end if
          ' The route up leg 2 passes the living enemy tower: same filter as targets.
          if tripX < 24 and tripY > laneClamp - 68 then
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

' Farm lane A: two tiles behind the frontmost own creep inside the clamp,
' otherwise beside the outermost living own tower of the lane.
if holdTowerX < 1000 then
  ' Five tiles west of the tower: outside the 12-tile leash of camp (25,20).
  holdX = holdTowerX - 5
  holdY = holdTowerY
else
  holdX = 16
  holdY = 10
end if
goalX = holdX
goalY = holdY
if frontMemory >= 0 then
  goalX = frontMemX
  goalY = frontMemY
  ' N39 / N39d: with a peer-or-higher enemy hero within 12 tiles a melee seat
  ' holds four tiles behind its front instead of two (see header).
  if attackRange < 3 and heroNear then
    if frontMemY >= 20 and frontMemX <= 24 then
      goalY = goalY - 2
    else
      goalX = goalX + 2
    end if
  end if
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
' N38b: only melee seats (attack range < 3 tiles) get the plain-walk order;
' a ranged seat acquires only inside its attack range and is never pulled,
' and on A the plain walk cost the first-pick Arcanist -480 at slot 0
' (red-kite:v45, 24 v 24), so ranged seats keep the v42 attack-move.
engageWalk = 1
if attackRange < 3 then
  engageWalk = 0
  if threatDistance <= 324 then
    engageWalk = 1
  end if
  ' N39b / N39d: with a peer-or-higher enemy hero within 12 tiles, plain-walk
  ' to the four-tile hold so the attack-move cannot pull the seat into the wave.
  if heroNear then
    engageWalk = 0
  end if
  ' N37d: inside the enemy tower zone on leg 2 (the target scan already
  ' skips heroes there) an attack-move re-acquires a hero within 8 tiles at
  ' every decision and chases it under the tower; walk back to the goal.
  if myX < 24 and myY > laneClamp - 68 then
    engageWalk = 0
  end if
end if
if selfClass = Warlock then
  engageWalk = 0
end if
moveTo(goalX, goalY, engageWalk)
