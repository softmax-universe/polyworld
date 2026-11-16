' Gameplay 75: Q main, W secondary, E defensive, R ultimate.
' Retain the learned actor's ability identities; translate host slots.
dim engineAbilitySlot(3)
engineAbilitySlot(0) = 2
engineAbilitySlot(1) = 0
engineAbilitySlot(2) = 1
engineAbilitySlot(3) = 3
sub chooseHero()
  if draftTurnId <> selfId then
    exit sub
  end if
  if heroAvailable(6) then
    draftHero(6)
    exit sub
  end if
  bestClass = -1
  bestDraftScore = -2147483647
  candidateClass = 0
  while candidateClass < 10
    if heroAvailable(candidateClass) then
      candidateRole = heroRole(candidateClass)
      draftScore = 100
      draftPlayer = 0
      while draftPlayer < draftPlayerCount()
        if draftPlayerTeam(draftPlayer) = selfTeam then
          pickedClass = draftedClass(draftPlayerId(draftPlayer))
          if pickedClass >= 0 then
            if heroRole(pickedClass) = candidateRole then
              draftScore = draftScore - 100
            end if
          end if
        end if
        draftPlayer = draftPlayer + 1
      wend
      if candidateClass \ 5 = selfTeam then
        draftScore = draftScore + 1
      end if
      if candidateClass = 6 then
        draftScore = draftScore + 25
      end if
      if candidateClass = 1 and heroAvailable(9) then
        draftScore = draftScore + 2
      end if
      if candidateClass = 3 or candidateClass = 5 then
        draftScore = draftScore - 20
      end if
      if draftScore > bestDraftScore then
        bestDraftScore = draftScore
        bestClass = candidateClass
      end if
    end if
    candidateClass = candidateClass + 1
  wend
  draftedAllies = 0
  draftPlayer = 0
  while draftPlayer < draftPlayerCount()
    if draftPlayerTeam(draftPlayer) = selfTeam then
      pickedClass = draftedClass(draftPlayerId(draftPlayer))
      if pickedClass >= 0 then
        draftedAllies = draftedAllies + 1
      end if
    end if
    draftPlayer = draftPlayer + 1
  wend
  if bestClass = 0 then
    if heroAvailable(6) then
      bestClass = 6
    elseif heroAvailable(1) then
      bestClass = 1
    elseif heroAvailable(9) then
      bestClass = 9
    elseif heroAvailable(3) then
      bestClass = 3
    end if
  end if
  if bestClass = 6 and heroAvailable(4) then
    bestClass = 4
  elseif bestClass = 6 and heroAvailable(1) then
    bestClass = 1
  elseif bestClass = 6 and heroAvailable(2) then
    bestClass = 2
  elseif bestClass = 6 and heroAvailable(9) then
    bestClass = 9
  elseif bestClass = 6 and heroAvailable(7) then
    bestClass = 7
  elseif bestClass = 6 and heroAvailable(8) then
    bestClass = 8
  elseif bestClass = 6 and heroAvailable(3) then
    bestClass = 3
  elseif bestClass = 6 and heroAvailable(5) then
    bestClass = 5
  end if
  if bestClass = 8 then
    if heroAvailable(2) then
      bestClass = 2
    end if
  end if
  if bestClass = 1 and heroAvailable(2) then
    bestClass = 2
  end if
  if bestClass = 1 and heroAvailable(8) then
    bestClass = 8
  end if
  if heroAvailable(4) then
    bestClass = 4
  end if
  if bestClass >= 0 then
    draftHero(bestClass)
  end if
end sub

if drafting then
  chooseHero()
  end
end if

if battleStarted = 0 then
  battleStartTick = worldTick
  kiteSpawnX = selfX
  kiteSpawnY = selfY
  battleStarted = 1
end if
battleTick = worldTick - battleStartTick

if selfHp <= 0 then
  buybackCost = buybackPrice()
  if buybackCost > 0 and selfGold >= buybackCost then
    buyback()
  end if
  end
end if

' Preserve an accepted walk-to-cast or casting animation.
if selfInfo(19) then
  end
end if

for upgrade = 1 to 4
  if canLevelAbility(3) then
    levelAbility(3)
  elseif (selfClass = 0 or selfClass = 5) and abilityLevel(2) = 0 and abilityLevel(0) > 0 and canLevelAbility(2) then
    levelAbility(2)
  elseif canLevelAbility(0) then
    levelAbility(0)
  elseif canLevelAbility(1) then
    levelAbility(1)
  elseif canLevelAbility(2) then
    levelAbility(2)
  end if
next upgrade

dim meteorFarmX(7)
dim meteorFarmY(7)
dim f(31)
bestId = 0
primaryIndex = -1
bestDistance = 2147483647
objectiveId = 0
objectiveKind = 0
siegeThreatId = 0
siegeThreatHp = 2147483647
objectiveDistance = 2147483647
heroId = 0
heroDistance = 2147483647
enemyX = selfX
enemyY = selfY
enemyHp = 0
enemyKind = 0
enemyAttackTarget = 0
enemyCamp = 0
enemyReturning = 0
routeOpeningX = 71
routeOpeningY = 12
if selfTeam = 1 then
  routeOpeningX = 45
  routeOpeningY = 104
end if
routeGroupCount = 0
if selfTeam = 0 then
  gateHomeX = 105
  gateHomeY = 10
else
  gateHomeX = 10
  gateHomeY = 105
end if
gateThreatDistance = 2147483647
gateThreatSeen = 0
gateThreatX = gateHomeX
reserveHome = 0
allyCount = 0
allyX = 0
allyY = 0
maxAllyDistance = 0
meteorFarmCount = 0
meteorCollect = 0
if selfClass = 2 and selfChannelTicks = 0 and selfSilenceTicks = 0 and selfStunTicks = 0 then
  if abilityLevel(1) > 0 and abilityCharges(1) > 0 and abilityCooldown(1) = 0 then
    if selfMana >= abilityManaCost(1) * 2 then
      meteorCollect = 1
      meteorLethalDamage = abilityDamage(1)
    end if
  end if
end if
fistFarmReady = 0
fistFarmId = 0
fistFarmHp = 2147483647
if selfClass = 9 and selfChannelTicks = 0 and selfSilenceTicks = 0 and selfStunTicks = 0 then
  if abilityLevel(0) > 0 and abilityCharges(0) > 1 and abilityCooldown(0) = 0 then
    if abilityManaCost(0) = 0 then
      fistFarmReady = 1
      fistFarmDamage = abilityDamage(0)
    end if
  end if
end if
index = 0
while index < objectCount()
  if objectAlive(index) then
    if objectTeam(index) = selfTeam and objectKind(index) = 1 then
      reserveHome = 1
      reserveHomeId = objectId(index)
      reserveX = objectX(index)
      reserveY = objectY(index)
    end if
    if objectTeam(index) = selfTeam and objectKind(index) = 2 then
      allyCount = allyCount + 1
      routeDx = objectX(index) - routeOpeningX
      routeDy = objectY(index) - routeOpeningY
      if routeDx * routeDx + routeDy * routeDy <= 16 then
        routeGroupCount = routeGroupCount + 1
      end if
      allyX = allyX + objectX(index)
      allyY = allyY + objectY(index)
      dx = objectX(index) - selfX
      dy = objectY(index) - selfY
      distance = dx * dx + dy * dy
      if distance > maxAllyDistance then
        maxAllyDistance = distance
      end if
    end if
    if objectTeam(index) <> selfTeam then
      if battleTick < 1000 and (objectKind(index) = 2 or objectKind(index) = 3) then
        gateDx = objectX(index) - gateHomeX
        gateDy = objectY(index) - gateHomeY
        gateDistance = gateDx * gateDx + gateDy * gateDy
        if gateDistance < gateThreatDistance then
          gateThreatDistance = gateDistance
          gateThreatSeen = 1
          gateThreatX = objectX(index)
        end if
      end if
      dx = objectX(index) - selfX
      dy = objectY(index) - selfY
      distance = dx * dx + dy * dy
      if meteorCollect and meteorFarmCount < 8 and distance <= 36 then
        if objectKind(index) = 3 then
          if objectHp(index) > 0 and objectHp(index) <= meteorLethalDamage then
            if objectVelX(index) = 0 and objectVelY(index) = 0 then
              meteorFarmX(meteorFarmCount) = objectX(index)
              meteorFarmY(meteorFarmCount) = objectY(index)
              meteorFarmCount = meteorFarmCount + 1
            end if
          end if
        end if
      end if
      if fistFarmReady then
        if distance <= 2.25 and (objectKind(index) = 3 or objectKind(index) = 6) then
          fistHp = objectHp(index)
          if fistHp > 0 and fistHp <= fistFarmDamage and fistHp < fistFarmHp and objectReturning(index) = 0 then
            fistSkip = 0
            if objectId(index) = selfTarget and selfAttackCooldown <= 12 and selfAttackDamage >= fistHp then
              fistSkip = 1
            end if
            if fistSkip = 0 then
              fistFarmId = objectId(index)
              fistFarmHp = fistHp
            end if
          end if
        end if
      end if
      if distance < bestDistance then
        skipResetCamp = 0
        if (selfClass = 3 or selfClass = 8) and objectKind(index) = 6 then
          if battleTick < campAvoidUntil and objectCamp(index) = campAvoidId then
            skipResetCamp = 1
          end if
        end if
        if skipResetCamp = 0 then
          bestDistance = distance
          bestId = objectId(index)
          primaryIndex = index
          enemyX = objectX(index)
          enemyY = objectY(index)
          enemyHp = objectHp(index)
          enemyKind = objectKind(index)
          enemyCamp = objectCamp(index)
          enemyReturning = objectReturning(index)
          enemyAttackTarget = objectTarget(index)
        end if
      end if
      if objectKind(index) = 2 and objectTarget(index) = selfId then
        siegeRange = selfAttackRange \ 1000
        if distance * 3600 <= siegeRange * siegeRange and objectHp(index) < siegeThreatHp then
          siegeThreatId = objectId(index)
          siegeThreatHp = objectHp(index)
        end if
      end if
      if objectKind(index) = 1 or objectKind(index) = 4 then
        if distance < objectiveDistance then
          objectiveDistance = distance
          objectiveId = objectId(index)
          objectiveKind = objectKind(index)
        end if
      end if
      if objectKind(index) = 2 and distance < heroDistance then
        heroDistance = distance
        heroId = objectId(index)
        ringHeroX = objectX(index)
        ringHeroY = objectY(index)
        ringHeroTarget = objectTarget(index)
      end if
    end if
  end if
  index = index + 1
wend
if (selfClass = 8 and selfLevel = 1 or selfClass = 3) and battleTick > 1000 then
  if selfHp * 4 >= selfMaxHp * 3 and enemyKind = 6 and enemyReturning <> 0 and enemyCamp > 0 then
    campAvoidId = enemyCamp
    campAvoidUntil = battleTick + 3600
  end if
end if
if allyCount > 0 then
  allyX = allyX \ allyCount
  allyY = allyY \ allyCount
else
  allyX = selfX
  allyY = selfY
end if
f(0) = selfHp * 100 \ selfMaxHp
f(1) = 0
if selfMaxMana > 0 then
  f(1) = selfMana * 100 \ selfMaxMana
end if
f(2) = maxAllyDistance \ 100
f(3) = selfLevel * 5
f(4) = allyX - selfX
f(5) = allyY - selfY
f(6) = enemyX - selfX
f(7) = enemyY - selfY
f(8) = enemyHp \ 10
f(9) = enemyKind * 25
if selfTeam = 1 then
  f(4) = 0 - f(4)
  f(5) = 0 - f(5)
  f(6) = 0 - f(6)
  f(7) = 0 - f(7)
end if
f(10) = battleTick \ 288
f(11) = abilityCharges(2) * 25
f(12) = abilityCharges(0) * 25
f(13) = abilityCharges(1) * 25
f(14) = abilityCharges(3) * 25
f(15 + selfClass) = 100
f(25) = battleTick \ 16
if battleTick < 1000 and gateThreatSeen = 1 then
  gateEarlyThreatX = gateThreatX
  gateEarlyThreatSeen = 1
end if
f(26) = 0
if gateEarlyThreatSeen = 1 then
  f(26) = gateEarlyThreatX - gateHomeX
  if selfTeam = 1 then
    f(26) = 0 - f(26)
  end if
end if
f(27) = 0
f(28) = 0
f(29) = 0
f(30) = 0
index = 0
while index < 4
  if abilityLevel(engineAbilitySlot(index)) > 0 and abilityCharges(engineAbilitySlot(index)) > 0 and abilityCooldown(engineAbilitySlot(index)) = 0 and selfMana >= abilityManaCost(engineAbilitySlot(index)) then
    f(27 + index) = 100
  end if
  index = index + 1
wend
index = 0
while index < 31
  if f(index) > 100 then
    f(index) = 100
  end if
  if f(index) < -100 then
    f(index) = -100
  end if
  index = index + 1
wend
dim h(16)
neuralActionCountdown = neuralActionCountdown - 1
if neuralActionCountdown <= 0 then
  neuralActionCountdown = 4
h(0) = 18208 + f(0) * (263) + f(1) * (222) + f(2) * (-62) + f(3) * (-8) + f(4) * (156) + f(5) * (176) + f(6) * (-660) + f(7) * (470) + f(8) * (178) + f(9) * (648) + f(10) * (309) + f(11) * (38) + f(12) * (78) + f(13) * (-150) + f(14) * (200) + f(15) * (5) + f(16) * (-491) + f(17) * (183) + f(18) * (-26) + f(19) * (311) + f(20) * (646) + f(21) * (80) + f(22) * (544) + f(23) * (39) + f(24) * (255)
if h(0) < 0 then
  h(0) = 0
end if
h(1) = 18392 + f(0) * (126) + f(1) * (-23) + f(2) * (117) + f(3) * (-25) + f(4) * (585) + f(5) * (-305) + f(6) * (-320) + f(7) * (118) + f(8) * (235) + f(9) * (32) + f(10) * (21) + f(11) * (-234) + f(12) * (656) + f(13) * (93) + f(14) * (602) + f(15) * (414) + f(16) * (439) + f(17) * (243) + f(18) * (243) + f(19) * (-340) + f(20) * (187) + f(21) * (-78) + f(22) * (72) + f(23) * (-522) + f(24) * (315)
if h(1) < 0 then
  h(1) = 0
end if
h(2) = 3752 + f(0) * (-346) + f(1) * (10) + f(2) * (-181) + f(3) * (180) + f(4) * (64) + f(5) * (725) + f(6) * (-25) + f(7) * (71) + f(8) * (104) + f(9) * (-523) + f(10) * (-232) + f(11) * (-80) + f(12) * (-27) + f(13) * (-30) + f(14) * (-313) + f(15) * (-350) + f(16) * (-320) + f(17) * (-11) + f(18) * (493) + f(19) * (-48) + f(20) * (-128) + f(21) * (182) + f(22) * (-73) + f(23) * (-520) + f(24) * (-23)
if h(2) < 0 then
  h(2) = 0
end if
h(3) = 19627 + f(0) * (190) + f(1) * (158) + f(2) * (-294) + f(3) * (61) + f(4) * (-155) + f(5) * (-122) + f(6) * (280) + f(7) * (-28) + f(8) * (-22) + f(9) * (396) + f(10) * (438) + f(11) * (38) + f(12) * (385) + f(13) * (238) + f(14) * (-15) + f(15) * (-727) + f(16) * (119) + f(17) * (363) + f(18) * (-197) + f(19) * (-128) + f(20) * (-135) + f(21) * (-497) + f(22) * (121) + f(23) * (-12) + f(24) * (-15)
if h(3) < 0 then
  h(3) = 0
end if
h(4) = 18521 + f(0) * (431) + f(1) * (-81) + f(2) * (108) + f(3) * (-107) + f(4) * (178) + f(5) * (-317) + f(6) * (-339) + f(7) * (286) + f(8) * (230) + f(9) * (-103) + f(10) * (-293) + f(11) * (-141) + f(12) * (714) + f(13) * (388) + f(14) * (-197) + f(15) * (-213) + f(16) * (109) + f(17) * (384) + f(18) * (214) + f(19) * (562) + f(20) * (195) + f(21) * (323) + f(22) * (25) + f(23) * (668) + f(24) * (-158)
if h(4) < 0 then
  h(4) = 0
end if
h(5) = 18435 + f(0) * (360) + f(1) * (159) + f(2) * (398) + f(3) * (339) + f(4) * (-52) + f(5) * (-357) + f(6) * (-172) + f(7) * (110) + f(8) * (-22) + f(9) * (646) + f(10) * (125) + f(11) * (-453) + f(12) * (-365) + f(13) * (177) + f(14) * (230) + f(15) * (-367) + f(16) * (408) + f(17) * (465) + f(18) * (703) + f(19) * (61) + f(20) * (136) + f(21) * (543) + f(22) * (41) + f(23) * (-54) + f(24) * (54)
if h(5) < 0 then
  h(5) = 0
end if
h(6) = 23325 + f(0) * (122) + f(1) * (-158) + f(2) * (-130) + f(3) * (204) + f(4) * (-64) + f(5) * (-508) + f(6) * (639) + f(7) * (551) + f(8) * (299) + f(9) * (239) + f(10) * (-38) + f(11) * (-406) + f(12) * (-41) + f(13) * (-158) + f(14) * (-309) + f(15) * (353) + f(16) * (131) + f(17) * (-140) + f(18) * (-48) + f(19) * (244) + f(20) * (161) + f(21) * (174) + f(22) * (-9) + f(23) * (91) + f(24) * (715)
if h(6) < 0 then
  h(6) = 0
end if
h(7) = 19286 + f(0) * (-90) + f(1) * (489) + f(2) * (349) + f(3) * (361) + f(4) * (116) + f(5) * (-315) + f(6) * (-91) + f(7) * (-101) + f(8) * (238) + f(9) * (-164) + f(10) * (238) + f(11) * (-133) + f(12) * (125) + f(13) * (458) + f(14) * (371) + f(15) * (3) + f(16) * (30) + f(17) * (203) + f(18) * (-106) + f(19) * (482) + f(20) * (-345) + f(21) * (302) + f(22) * (932) + f(23) * (147) + f(24) * (505)
if h(7) < 0 then
  h(7) = 0
end if
h(8) = 18159 + f(0) * (101) + f(1) * (49) + f(2) * (180) + f(3) * (-178) + f(4) * (-311) + f(5) * (502) + f(6) * (-51) + f(7) * (361) + f(8) * (179) + f(9) * (638) + f(10) * (-61) + f(11) * (240) + f(12) * (314) + f(13) * (248) + f(14) * (-8) + f(15) * (483) + f(16) * (730) + f(17) * (314) + f(18) * (155) + f(19) * (291) + f(20) * (-257) + f(21) * (241) + f(22) * (543) + f(23) * (9) + f(24) * (-66)
if h(8) < 0 then
  h(8) = 0
end if
h(9) = 19073 + f(0) * (411) + f(1) * (470) + f(2) * (170) + f(3) * (61) + f(4) * (50) + f(5) * (-20) + f(6) * (-192) + f(7) * (-211) + f(8) * (60) + f(9) * (68) + f(10) * (-32) + f(11) * (-109) + f(12) * (-126) + f(13) * (-404) + f(14) * (49) + f(15) * (543) + f(16) * (-90) + f(17) * (554) + f(18) * (445) + f(19) * (341) + f(20) * (-324) + f(21) * (-471) + f(22) * (-27) + f(23) * (378) + f(24) * (114)
if h(9) < 0 then
  h(9) = 0
end if
h(10) = 18190 + f(0) * (861) + f(1) * (381) + f(2) * (130) + f(3) * (413) + f(4) * (-252) + f(5) * (152) + f(6) * (159) + f(7) * (421) + f(8) * (-140) + f(9) * (-151) + f(10) * (669) + f(11) * (-70) + f(12) * (515) + f(13) * (338) + f(14) * (102) + f(15) * (453) + f(16) * (-71) + f(17) * (383) + f(18) * (255) + f(19) * (-158) + f(20) * (195) + f(21) * (441) + f(22) * (133) + f(23) * (189) + f(24) * (264)
if h(10) < 0 then
  h(10) = 0
end if
h(11) = 19629 + f(0) * (82) + f(1) * (-702) + f(2) * (275) + f(3) * (91) + f(4) * (-190) + f(5) * (47) + f(6) * (-505) + f(7) * (-288) + f(8) * (-299) + f(9) * (-56) + f(10) * (716) + f(11) * (-16) + f(12) * (78) + f(13) * (18) + f(14) * (95) + f(15) * (6) + f(16) * (302) + f(17) * (-370) + f(18) * (419) + f(19) * (284) + f(20) * (2) + f(21) * (-157) + f(22) * (129) + f(23) * (332) + f(24) * (261)
if h(11) < 0 then
  h(11) = 0
end if
h(12) = 19929 + f(0) * (-187) + f(1) * (342) + f(2) * (-126) + f(3) * (-271) + f(4) * (-109) + f(5) * (-323) + f(6) * (149) + f(7) * (43) + f(8) * (-690) + f(9) * (236) + f(10) * (-95) + f(11) * (383) + f(12) * (276) + f(13) * (62) + f(14) * (485) + f(15) * (215) + f(16) * (-249) + f(17) * (-34) + f(18) * (413) + f(19) * (130) + f(20) * (137) + f(21) * (562) + f(22) * (61) + f(23) * (214) + f(24) * (123)
if h(12) < 0 then
  h(12) = 0
end if
h(13) = 21374 + f(0) * (-49) + f(1) * (121) + f(2) * (69) + f(3) * (190) + f(4) * (856) + f(5) * (44) + f(6) * (-31) + f(7) * (-132) + f(8) * (-120) + f(9) * (458) + f(10) * (407) + f(11) * (-483) + f(12) * (6) + f(13) * (396) + f(14) * (-271) + f(15) * (452) + f(16) * (40) + f(17) * (-47) + f(18) * (-98) + f(19) * (-226) + f(20) * (-24) + f(21) * (342) + f(22) * (192) + f(23) * (508) + f(24) * (-284)
if h(13) < 0 then
  h(13) = 0
end if
h(14) = 18212 + f(0) * (432) + f(1) * (481) + f(2) * (400) + f(3) * (-699) + f(4) * (108) + f(5) * (103) + f(6) * (-31) + f(7) * (-289) + f(8) * (548) + f(9) * (208) + f(10) * (338) + f(11) * (67) + f(12) * (157) + f(13) * (80) + f(14) * (-99) + f(15) * (-136) + f(16) * (179) + f(17) * (-206) + f(18) * (274) + f(19) * (-139) + f(20) * (86) + f(21) * (412) + f(22) * (33) + f(23) * (278) + f(24) * (594)
if h(14) < 0 then
  h(14) = 0
end if
h(15) = 18656 + f(0) * (651) + f(1) * (160) + f(2) * (-271) + f(3) * (341) + f(4) * (228) + f(5) * (-548) + f(6) * (-380) + f(7) * (170) + f(8) * (260) + f(9) * (78) + f(10) * (188) + f(11) * (579) + f(12) * (-65) + f(13) * (58) + f(14) * (-197) + f(15) * (173) + f(16) * (208) + f(17) * (-353) + f(18) * (354) + f(19) * (-48) + f(20) * (-264) + f(21) * (293) + f(22) * (413) + f(23) * (-53) + f(24) * (-198)
if h(15) < 0 then
  h(15) = 0
end if
decision = 0
bestScore = -2147483647
score = 387878561 + h(0) * (-128) + h(1) * (-127) + h(2) * (-9) + h(3) * (-160) + h(4) * (-125) + h(5) * (-151) + h(6) * (-198) + h(7) * (-129) + h(8) * (-126) + h(9) * (-140) + h(10) * (-111) + h(11) * (-199) + h(12) * (-146) + h(13) * (-192) + h(14) * (-125) + h(15) * (-129)
if score > bestScore then
  bestScore = score
  decision = 0
end if
score = 8621915 + h(0) * (113) + h(1) * (102) + h(2) * (10) + h(3) * (106) + h(4) * (96) + h(5) * (110) + h(6) * (83) + h(7) * (86) + h(8) * (101) + h(9) * (96) + h(10) * (95) + h(11) * (62) + h(12) * (124) + h(13) * (115) + h(14) * (101) + h(15) * (103)
if score > bestScore then
  bestScore = score
  decision = 1
end if
score = 9365853 + h(0) * (114) + h(1) * (122) + h(2) * (25) + h(3) * (121) + h(4) * (105) + h(5) * (113) + h(6) * (104) + h(7) * (113) + h(8) * (112) + h(9) * (113) + h(10) * (102) + h(11) * (86) + h(12) * (104) + h(13) * (132) + h(14) * (98) + h(15) * (113)
if score > bestScore then
  bestScore = score
  decision = 2
end if
score = 10032520 + h(0) * (124) + h(1) * (135) + h(2) * (-1) + h(3) * (134) + h(4) * (118) + h(5) * (129) + h(6) * (105) + h(7) * (120) + h(8) * (110) + h(9) * (115) + h(10) * (108) + h(11) * (65) + h(12) * (116) + h(13) * (119) + h(14) * (124) + h(15) * (124)
if score > bestScore then
  bestScore = score
  decision = 3
end if
score = 10514535 + h(0) * (111) + h(1) * (115) + h(2) * (18) + h(3) * (135) + h(4) * (112) + h(5) * (136) + h(6) * (94) + h(7) * (112) + h(8) * (107) + h(9) * (125) + h(10) * (98) + h(11) * (77) + h(12) * (105) + h(13) * (139) + h(14) * (114) + h(15) * (111)
if score > bestScore then
  bestScore = score
  decision = 4
end if
score = 10182099 + h(0) * (118) + h(1) * (123) + h(2) * (-6) + h(3) * (122) + h(4) * (94) + h(5) * (112) + h(6) * (107) + h(7) * (125) + h(8) * (116) + h(9) * (113) + h(10) * (102) + h(11) * (68) + h(12) * (107) + h(13) * (137) + h(14) * (113) + h(15) * (113)
if score > bestScore then
  bestScore = score
  decision = 5
end if
score = 9061429 + h(0) * (102) + h(1) * (104) + h(2) * (17) + h(3) * (120) + h(4) * (107) + h(5) * (107) + h(6) * (99) + h(7) * (105) + h(8) * (107) + h(9) * (108) + h(10) * (94) + h(11) * (94) + h(12) * (107) + h(13) * (134) + h(14) * (96) + h(15) * (112)
if score > bestScore then
  bestScore = score
  decision = 6
end if
score = 10778495 + h(0) * (127) + h(1) * (114) + h(2) * (43) + h(3) * (132) + h(4) * (111) + h(5) * (125) + h(6) * (106) + h(7) * (120) + h(8) * (132) + h(9) * (123) + h(10) * (118) + h(11) * (89) + h(12) * (113) + h(13) * (133) + h(14) * (117) + h(15) * (131)
if score > bestScore then
  bestScore = score
  decision = 7
end if
score = 9785349 + h(0) * (112) + h(1) * (119) + h(2) * (1) + h(3) * (125) + h(4) * (110) + h(5) * (130) + h(6) * (105) + h(7) * (116) + h(8) * (115) + h(9) * (109) + h(10) * (102) + h(11) * (95) + h(12) * (107) + h(13) * (142) + h(14) * (105) + h(15) * (115)
if score > bestScore then
  bestScore = score
  decision = 8
end if
score = 387767339 + h(0) * (-137) + h(1) * (-135) + h(2) * (-16) + h(3) * (-166) + h(4) * (-133) + h(5) * (-152) + h(6) * (-209) + h(7) * (-142) + h(8) * (-122) + h(9) * (-142) + h(10) * (-121) + h(11) * (-185) + h(12) * (-152) + h(13) * (-198) + h(14) * (-139) + h(15) * (-141)
if score > bestScore then
  bestScore = score
  decision = 9
end if
score = 9125238 + h(0) * (115) + h(1) * (113) + h(2) * (36) + h(3) * (104) + h(4) * (98) + h(5) * (120) + h(6) * (76) + h(7) * (94) + h(8) * (107) + h(9) * (122) + h(10) * (97) + h(11) * (66) + h(12) * (133) + h(13) * (122) + h(14) * (107) + h(15) * (112)
if score > bestScore then
  bestScore = score
  decision = 10
end if
score = 9920025 + h(0) * (107) + h(1) * (128) + h(2) * (-22) + h(3) * (122) + h(4) * (105) + h(5) * (128) + h(6) * (116) + h(7) * (113) + h(8) * (113) + h(9) * (109) + h(10) * (99) + h(11) * (103) + h(12) * (97) + h(13) * (152) + h(14) * (108) + h(15) * (119)
if score > bestScore then
  bestScore = score
  decision = 11
end if
score = 9813639 + h(0) * (116) + h(1) * (134) + h(2) * (8) + h(3) * (128) + h(4) * (110) + h(5) * (125) + h(6) * (89) + h(7) * (117) + h(8) * (109) + h(9) * (106) + h(10) * (100) + h(11) * (83) + h(12) * (115) + h(13) * (114) + h(14) * (114) + h(15) * (111)
if score > bestScore then
  bestScore = score
  decision = 12
end if
score = 11515426 + h(0) * (125) + h(1) * (129) + h(2) * (-7) + h(3) * (136) + h(4) * (117) + h(5) * (137) + h(6) * (124) + h(7) * (118) + h(8) * (119) + h(9) * (119) + h(10) * (108) + h(11) * (83) + h(12) * (129) + h(13) * (149) + h(14) * (122) + h(15) * (130)
if score > bestScore then
  bestScore = score
  decision = 13
end if
score = 9815518 + h(0) * (120) + h(1) * (121) + h(2) * (-14) + h(3) * (127) + h(4) * (100) + h(5) * (106) + h(6) * (113) + h(7) * (117) + h(8) * (110) + h(9) * (112) + h(10) * (106) + h(11) * (76) + h(12) * (119) + h(13) * (129) + h(14) * (112) + h(15) * (106)
if score > bestScore then
  bestScore = score
  decision = 14
end if
score = 11022095 + h(0) * (119) + h(1) * (118) + h(2) * (-26) + h(3) * (137) + h(4) * (124) + h(5) * (135) + h(6) * (105) + h(7) * (124) + h(8) * (123) + h(9) * (129) + h(10) * (114) + h(11) * (132) + h(12) * (121) + h(13) * (145) + h(14) * (113) + h(15) * (121)
if score > bestScore then
  bestScore = score
  decision = 15
end if
score = 10193590 + h(0) * (122) + h(1) * (97) + h(2) * (-11) + h(3) * (122) + h(4) * (110) + h(5) * (109) + h(6) * (97) + h(7) * (118) + h(8) * (112) + h(9) * (106) + h(10) * (111) + h(11) * (73) + h(12) * (133) + h(13) * (130) + h(14) * (112) + h(15) * (123)
if score > bestScore then
  bestScore = score
  decision = 16
end if
score = 10897366 + h(0) * (133) + h(1) * (140) + h(2) * (12) + h(3) * (135) + h(4) * (112) + h(5) * (131) + h(6) * (116) + h(7) * (125) + h(8) * (125) + h(9) * (129) + h(10) * (114) + h(11) * (121) + h(12) * (106) + h(13) * (153) + h(14) * (120) + h(15) * (119)
if score > bestScore then
  bestScore = score
  decision = 17
end if
h(0) = 0.0 + f(0) / 100.0 * (0.3408203125) + f(1) / 100.0 * (0.2666015625) + f(2) / 100.0 * (-0.337890625) + f(3) / 100.0 * (0.111328125) + f(4) / 100.0 * (0.2373046875) + f(5) / 100.0 * (-0.3232421875) + f(6) / 100.0 * (-0.048828125) + f(7) / 100.0 * (0.1025390625) + f(8) / 100.0 * (-0.1064453125) + f(9) / 100.0 * (-0.0244140625) + f(10) / 100.0 * (-0.0087890625) + f(11) / 100.0 * (0.01953125) + f(12) / 100.0 * (-0.4619140625) + f(13) / 100.0 * (-0.2294921875) + f(14) / 100.0 * (-0.4375) + f(15) / 100.0 * (0.0224609375) + f(16) / 100.0 * (0.2646484375) + f(17) / 100.0 * (0.23828125) + f(18) / 100.0 * (0.328125) + f(19) / 100.0 * (0.1240234375) + f(20) / 100.0 * (0.3837890625) + f(21) / 100.0 * (0.3642578125) + f(22) / 100.0 * (-0.150390625) + f(23) / 100.0 * (0.072265625) + f(24) / 100.0 * (0.1845703125) + f(25) / 100.0 * (-0.4892578125) + f(26) / 100.0 * (0.25390625) + f(27) / 100.0 * (0.2197265625) + f(28) / 100.0 * (-0.150390625) + f(29) / 100.0 * (-0.150390625) + f(30) / 100.0 * (0.216796875)
if h(0) < 0.0 then
  h(0) = 0.0
end if
h(1) = 0.0 + f(0) / 100.0 * (0.080078125) + f(1) / 100.0 * (0.4130859375) + f(2) / 100.0 * (0.4111328125) + f(3) / 100.0 * (-0.3173828125) + f(4) / 100.0 * (0.0361328125) + f(5) / 100.0 * (-0.2314453125) + f(6) / 100.0 * (0.0732421875) + f(7) / 100.0 * (0.2822265625) + f(8) / 100.0 * (0.416015625) + f(9) / 100.0 * (0.05078125) + f(10) / 100.0 * (0.2509765625) + f(11) / 100.0 * (0.09375) + f(12) / 100.0 * (0.05078125) + f(13) / 100.0 * (0.0732421875) + f(14) / 100.0 * (-0.2958984375) + f(15) / 100.0 * (-0.0068359375) + f(16) / 100.0 * (-0.0615234375) + f(17) / 100.0 * (0.2578125) + f(18) / 100.0 * (-0.1025390625) + f(19) / 100.0 * (-0.3896484375) + f(20) / 100.0 * (0.154296875) + f(21) / 100.0 * (0.3681640625) + f(22) / 100.0 * (0.54296875) + f(23) / 100.0 * (0.4609375) + f(24) / 100.0 * (-0.126953125) + f(25) / 100.0 * (0.208984375) + f(26) / 100.0 * (-0.2353515625) + f(27) / 100.0 * (0.00390625) + f(28) / 100.0 * (-0.068359375) + f(29) / 100.0 * (0.1669921875) + f(30) / 100.0 * (-0.1015625)
if h(1) < 0.0 then
  h(1) = 0.0
end if
h(2) = 0.0 + f(0) / 100.0 * (-0.1181640625) + f(1) / 100.0 * (-0.091796875) + f(2) / 100.0 * (0.1015625) + f(3) / 100.0 * (-0.4326171875) + f(4) / 100.0 * (-0.548828125) + f(5) / 100.0 * (0.4052734375) + f(6) / 100.0 * (-0.0185546875) + f(7) / 100.0 * (-0.267578125) + f(8) / 100.0 * (0.13671875) + f(9) / 100.0 * (-0.0107421875) + f(10) / 100.0 * (0.1181640625) + f(11) / 100.0 * (0.0302734375) + f(12) / 100.0 * (-0.265625) + f(13) / 100.0 * (-0.3876953125) + f(14) / 100.0 * (-0.3134765625) + f(15) / 100.0 * (-0.267578125) + f(16) / 100.0 * (-0.2841796875) + f(17) / 100.0 * (0.0322265625) + f(18) / 100.0 * (0.3203125) + f(19) / 100.0 * (0.0400390625) + f(20) / 100.0 * (0.052734375) + f(21) / 100.0 * (0.1416015625) + f(22) / 100.0 * (-0.16015625) + f(23) / 100.0 * (-0.0283203125) + f(24) / 100.0 * (-0.2177734375) + f(25) / 100.0 * (0.19921875) + f(26) / 100.0 * (0.265625) + f(27) / 100.0 * (-0.044921875) + f(28) / 100.0 * (0.2119140625) + f(29) / 100.0 * (0.255859375) + f(30) / 100.0 * (0.564453125)
if h(2) < 0.0 then
  h(2) = 0.0
end if
h(3) = 0.0 + f(0) / 100.0 * (-0.0302734375) + f(1) / 100.0 * (0.216796875) + f(2) / 100.0 * (-0.1806640625) + f(3) / 100.0 * (-0.2314453125) + f(4) / 100.0 * (0.2333984375) + f(5) / 100.0 * (0.07421875) + f(6) / 100.0 * (0.3095703125) + f(7) / 100.0 * (-0.0107421875) + f(8) / 100.0 * (-0.3125) + f(9) / 100.0 * (-0.0048828125) + f(10) / 100.0 * (-0.291015625) + f(11) / 100.0 * (-0.1728515625) + f(12) / 100.0 * (0.0458984375) + f(13) / 100.0 * (0.0126953125) + f(14) / 100.0 * (-0.265625) + f(15) / 100.0 * (0.5390625) + f(16) / 100.0 * (-0.5107421875) + f(17) / 100.0 * (0.126953125) + f(18) / 100.0 * (-0.27734375) + f(19) / 100.0 * (0.283203125) + f(20) / 100.0 * (-0.140625) + f(21) / 100.0 * (-0.0126953125) + f(22) / 100.0 * (0.0166015625) + f(23) / 100.0 * (0.013671875) + f(24) / 100.0 * (0.3798828125) + f(25) / 100.0 * (0.0224609375) + f(26) / 100.0 * (-0.197265625) + f(27) / 100.0 * (0.2431640625) + f(28) / 100.0 * (0.1474609375) + f(29) / 100.0 * (0.6279296875) + f(30) / 100.0 * (0.140625)
if h(3) < 0.0 then
  h(3) = 0.0
end if
h(4) = 0.0 + f(0) / 100.0 * (0.08203125) + f(1) / 100.0 * (-0.31640625) + f(2) / 100.0 * (-0.0361328125) + f(3) / 100.0 * (0.2373046875) + f(4) / 100.0 * (-0.0615234375) + f(5) / 100.0 * (0.337890625) + f(6) / 100.0 * (0.40234375) + f(7) / 100.0 * (-0.0849609375) + f(8) / 100.0 * (-0.169921875) + f(9) / 100.0 * (-0.28515625) + f(10) / 100.0 * (-0.0263671875) + f(11) / 100.0 * (0.466796875) + f(12) / 100.0 * (0.4970703125) + f(13) / 100.0 * (-0.1943359375) + f(14) / 100.0 * (-0.009765625) + f(15) / 100.0 * (0.048828125) + f(16) / 100.0 * (0.0205078125) + f(17) / 100.0 * (0.259765625) + f(18) / 100.0 * (0.1259765625) + f(19) / 100.0 * (0.251953125) + f(20) / 100.0 * (0.361328125) + f(21) / 100.0 * (0.4951171875) + f(22) / 100.0 * (0.322265625) + f(23) / 100.0 * (-0.2939453125) + f(24) / 100.0 * (-0.1796875) + f(25) / 100.0 * (-0.0185546875) + f(26) / 100.0 * (0.0224609375) + f(27) / 100.0 * (-0.05078125) + f(28) / 100.0 * (-0.2890625) + f(29) / 100.0 * (0.1767578125) + f(30) / 100.0 * (-0.2734375)
if h(4) < 0.0 then
  h(4) = 0.0
end if
h(5) = 0.0 + f(0) / 100.0 * (0.3779296875) + f(1) / 100.0 * (0.2548828125) + f(2) / 100.0 * (0.0068359375) + f(3) / 100.0 * (0.0078125) + f(4) / 100.0 * (-0.2216796875) + f(5) / 100.0 * (-0.1279296875) + f(6) / 100.0 * (0.205078125) + f(7) / 100.0 * (0.19921875) + f(8) / 100.0 * (0.0380859375) + f(9) / 100.0 * (-0.01171875) + f(10) / 100.0 * (0.2607421875) + f(11) / 100.0 * (-0.341796875) + f(12) / 100.0 * (0.5029296875) + f(13) / 100.0 * (0.453125) + f(14) / 100.0 * (0.1484375) + f(15) / 100.0 * (-0.01953125) + f(16) / 100.0 * (0.1220703125) + f(17) / 100.0 * (0.259765625) + f(18) / 100.0 * (0.0947265625) + f(19) / 100.0 * (0.171875) + f(20) / 100.0 * (0.3046875) + f(21) / 100.0 * (-0.3115234375) + f(22) / 100.0 * (0.1689453125) + f(23) / 100.0 * (-0.43359375) + f(24) / 100.0 * (-0.0478515625) + f(25) / 100.0 * (0.013671875) + f(26) / 100.0 * (0.091796875) + f(27) / 100.0 * (0.046875) + f(28) / 100.0 * (0.248046875) + f(29) / 100.0 * (-0.0703125) + f(30) / 100.0 * (0.6044921875)
if h(5) < 0.0 then
  h(5) = 0.0
end if
h(6) = 0.0 + f(0) / 100.0 * (-0.0166015625) + f(1) / 100.0 * (0.1552734375) + f(2) / 100.0 * (0.2294921875) + f(3) / 100.0 * (0.0390625) + f(4) / 100.0 * (-0.0283203125) + f(5) / 100.0 * (-0.0966796875) + f(6) / 100.0 * (-0.072265625) + f(7) / 100.0 * (-0.4052734375) + f(8) / 100.0 * (-0.1318359375) + f(9) / 100.0 * (0.5556640625) + f(10) / 100.0 * (0.244140625) + f(11) / 100.0 * (0.435546875) + f(12) / 100.0 * (0.361328125) + f(13) / 100.0 * (-0.46484375) + f(14) / 100.0 * (0.005859375) + f(15) / 100.0 * (0.45703125) + f(16) / 100.0 * (0.302734375) + f(17) / 100.0 * (0.2802734375) + f(18) / 100.0 * (0.25390625) + f(19) / 100.0 * (-0.095703125) + f(20) / 100.0 * (-0.0654296875) + f(21) / 100.0 * (-0.5078125) + f(22) / 100.0 * (-0.1083984375) + f(23) / 100.0 * (0.16015625) + f(24) / 100.0 * (0.1201171875) + f(25) / 100.0 * (-0.0009765625) + f(26) / 100.0 * (-0.109375) + f(27) / 100.0 * (0.0771484375) + f(28) / 100.0 * (-0.1669921875) + f(29) / 100.0 * (0.0615234375) + f(30) / 100.0 * (0.1162109375)
if h(6) < 0.0 then
  h(6) = 0.0
end if
h(7) = 0.0 + f(0) / 100.0 * (-0.26953125) + f(1) / 100.0 * (0.2802734375) + f(2) / 100.0 * (0.033203125) + f(3) / 100.0 * (-0.185546875) + f(4) / 100.0 * (0.1396484375) + f(5) / 100.0 * (0.046875) + f(6) / 100.0 * (-0.1552734375) + f(7) / 100.0 * (0.6884765625) + f(8) / 100.0 * (-0.16796875) + f(9) / 100.0 * (-0.009765625) + f(10) / 100.0 * (-0.1884765625) + f(11) / 100.0 * (0.3095703125) + f(12) / 100.0 * (0.1279296875) + f(13) / 100.0 * (-0.03125) + f(14) / 100.0 * (-0.05859375) + f(15) / 100.0 * (-0.140625) + f(16) / 100.0 * (0.40234375) + f(17) / 100.0 * (0.0478515625) + f(18) / 100.0 * (-0.044921875) + f(19) / 100.0 * (0.546875) + f(20) / 100.0 * (-0.2412109375) + f(21) / 100.0 * (-0.115234375) + f(22) / 100.0 * (-0.2255859375) + f(23) / 100.0 * (0.1474609375) + f(24) / 100.0 * (-0.5908203125) + f(25) / 100.0 * (-0.123046875) + f(26) / 100.0 * (0.015625) + f(27) / 100.0 * (-0.2138671875) + f(28) / 100.0 * (0.044921875) + f(29) / 100.0 * (0.2529296875) + f(30) / 100.0 * (0.1005859375)
if h(7) < 0.0 then
  h(7) = 0.0
end if
residualAction = 0
bestResidualScore = -32767.0
residualScore = 0.0 + h(0) * (-0.009765625) + h(1) * (0.001953125) + h(2) * (0.015625) + h(3) * (-0.0048828125) + h(4) * (-0.0048828125) + h(5) * (-0.0185546875) + h(6) * (-0.0029296875) + h(7) * (-0.0009765625)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 0
end if
residualScore = 0.0 + h(0) * (0.0068359375) + h(1) * (-0.005859375) + h(2) * (-0.0009765625) + h(3) * (-0.0107421875) + h(4) * (-0.01953125) + h(5) * (0.0087890625) + h(6) * (-0.005859375) + h(7) * (0.0205078125)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 1
end if
residualScore = 0.0 + h(0) * (-0.001953125) + h(1) * (-0.013671875) + h(2) * (0.0029296875) + h(3) * (-0.0068359375) + h(4) * (0.013671875) + h(5) * (0.009765625) + h(6) * (-0.0166015625) + h(7) * (0.0078125)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 2
end if
residualScore = 0.0 + h(0) * (0.00390625) + h(1) * (-0.005859375) + h(2) * (-0.005859375) + h(3) * (0.00390625) + h(4) * (0.0068359375) + h(5) * (-0.01171875) + h(6) * (0.015625) + h(7) * (-0.005859375)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 3
end if
residualScore = 0.0
if residualScore > bestResidualScore and f(27) > 0 then
  bestResidualScore = residualScore
  residualAction = 4
end if
residualScore = 0.0 + h(0) * (0.0126953125) + h(1) * (0.0029296875) + h(2) * (-0.0029296875) + h(3) * (0.0087890625) + h(4) * (0.00390625) + h(6) * (-0.0009765625) + h(7) * (-0.0068359375)
if residualScore > bestResidualScore and f(28) > 0 then
  bestResidualScore = residualScore
  residualAction = 5
end if
residualScore = 0.0 + h(1) * (-0.001953125) + h(2) * (-0.005859375) + h(3) * (-0.0048828125) + h(5) * (0.005859375) + h(6) * (0.0068359375) + h(7) * (0.0166015625)
if residualScore > bestResidualScore and f(29) > 0 then
  bestResidualScore = residualScore
  residualAction = 6
end if
residualScore = 0.0 + h(0) * (0.001953125) + h(2) * (-0.001953125) + h(3) * (-0.0009765625) + h(4) * (-0.0029296875) + h(5) * (-0.001953125) + h(6) * (0.0009765625) + h(7) * (0.005859375)
if residualScore > bestResidualScore and f(30) > 0 then
  bestResidualScore = residualScore
  residualAction = 7
end if
residualScore = 0.0 + h(0) * (-0.009765625) + h(2) * (-0.015625) + h(3) * (0.013671875) + h(4) * (0.0029296875) + h(5) * (0.0146484375) + h(6) * (0.0078125) + h(7) * (-0.0029296875)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 8
end if
residualScore = 0.0 + h(0) * (-0.01171875) + h(1) * (0.009765625) + h(2) * (0.0048828125) + h(3) * (-0.0029296875) + h(4) * (-0.0029296875) + h(5) * (-0.0078125) + h(6) * (-0.0126953125) + h(7) * (-0.0107421875)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 9
end if
residualScore = 0.0009765625 + h(1) * (0.017578125) + h(2) * (-0.015625) + h(3) * (-0.0029296875) + h(4) * (-0.009765625) + h(5) * (0.0048828125) + h(6) * (0.0166015625) + h(7) * (-0.0009765625)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 10
end if
residualScore = 0.0 + h(0) * (-0.0029296875) + h(1) * (-0.0068359375) + h(3) * (-0.00390625) + h(4) * (0.013671875) + h(5) * (-0.0048828125) + h(6) * (0.0029296875) + h(7) * (-0.0078125)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 11
end if
residualScore = 0.0 + h(0) * (0.0068359375) + h(1) * (0.0068359375) + h(2) * (0.009765625) + h(3) * (-0.017578125) + h(4) * (0.0224609375) + h(5) * (0.00390625) + h(6) * (0.001953125) + h(7) * (-0.0087890625)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 12
end if
residualScore = 0.0
if residualScore > bestResidualScore and f(27) > 0 then
  bestResidualScore = residualScore
  residualAction = 13
end if
residualScore = 0.0 + h(0) * (-0.0068359375) + h(1) * (-0.0068359375) + h(2) * (0.0126953125) + h(3) * (-0.0048828125) + h(4) * (-0.0048828125) + h(5) * (0.0048828125) + h(6) * (-0.0029296875) + h(7) * (-0.005859375)
if residualScore > bestResidualScore and f(28) > 0 then
  bestResidualScore = residualScore
  residualAction = 14
end if
residualScore = 0.0 + h(0) * (0.0048828125) + h(1) * (-0.01171875) + h(2) * (-0.0107421875) + h(3) * (0.01171875) + h(5) * (-0.005859375) + h(6) * (0.0078125) + h(7) * (-0.0048828125)
if residualScore > bestResidualScore and f(29) > 0 then
  bestResidualScore = residualScore
  residualAction = 15
end if
residualScore = 0.0 + h(0) * (-0.0009765625) + h(1) * (0.001953125) + h(2) * (-0.0029296875) + h(3) * (-0.0009765625) + h(4) * (-0.001953125) + h(5) * (-0.0048828125) + h(7) * (0.0029296875)
if residualScore > bestResidualScore and f(30) > 0 then
  bestResidualScore = residualScore
  residualAction = 16
end if
residualScore = 0.0 + h(0) * (-0.0009765625) + h(1) * (0.0048828125) + h(2) * (0.001953125) + h(3) * (0.005859375) + h(4) * (-0.0068359375) + h(5) * (-0.0048828125) + h(6) * (-0.017578125) + h(7) * (0.0009765625)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 17
end if
residualScore = 0.0 + h(0) * (0.005859375) + h(1) * (0.0078125) + h(2) * (0.013671875) + h(3) * (0.0185546875) + h(4) * (-0.009765625) + h(5) * (0.0068359375) + h(6) * (0.0009765625) + h(7) * (0.0009765625)
if residualScore > bestResidualScore then
  bestResidualScore = residualScore
  residualAction = 18
end if
if residualAction = 8 then
  residualAction = 0
end if
if residualAction >= 10 and bestId <> 0 then
  residualAction = 0
end if
if residualAction > 0 then
  decision = residualAction - 1
end if
end if
if decision = 18 then
  combatDecision = 8
else
combatDecision = decision
end if
objectiveBuild = 0
if decision >= 9 then
  combatDecision = decision - 9
  objectiveBuild = 1
end if

routeFallback = 0
if combatDecision = 2 or (combatDecision = 8 and bestId = 0) then
  if (objectiveId = 0 or objectiveDistance > 300) and (heroId = 0 or heroDistance > 700) then
    routeFallback = 1
  end if
end if
routeDx = selfX - routeOpeningX
routeDy = selfY - routeOpeningY
if battleTick < 3500 and routeFallback and routeGroupCount >= 3 then
  if routeDx * routeDx + routeDy * routeDy <= 16 then
    groupDeparture = 1
  end if
end if

if combatDecision = 8 then
  if objectiveId <> 0 and objectiveDistance <= 300 then
    attackTarget(objectiveId)
  else
    if heroId <> 0 and heroDistance <= 700 then
      attackTarget(heroId)
    else
      if bestId <> 0 then
        if selfClass <> 9 or enemyKind <> 3 or battleTick >= 7200 or battleTick mod 6 = 0 then
          attackTarget(bestId)
        end if
      else
        if selfTeam = 0 then
          if battleTick < 3500 and groupDeparture = 0 then
            walkTo(71, 12)
          else
            if battleTick < 4500 then
              walkTo(9, 33)
            else
              walkTo(11, 106)
            end if
          end if
        else
          if battleTick < 3500 and groupDeparture = 0 then
            walkTo(45, 104)
          else
            if battleTick < 4500 then
              walkTo(107, 83)
            else
              walkTo(105, 10)
            end if
          end if
        end if
      end if
    end if
  end if
else
  if bestId <> 0 then
    if selfClass <> 9 or enemyKind <> 3 or battleTick >= 7200 or battleTick mod 6 = 0 then
      attackTarget(bestId)
    end if
  else
    walkTo(64, 64)
  end if
end if
if selfClass = 7 and heroId <> 0 and ringHeroTarget = selfId then
  if heroDistance > 25 and heroDistance <= 49 then
    castPoint(3, (selfX + ringHeroX) \ 2, (selfY + ringHeroY) \ 2)
    if selfInfo(19) then
      end
    end if
  end if
end if
hasHeal = 0
hasMana = 0
hasPoison = 0
hasGear = 0
hasBoots = 0
hasDagger = 0
hasSword = 0
hasArmor = 0
hasAxe = 0
hasBook = 0
emptySlot = 0
slot = 0
while slot < 6
  id = itemId(slot)
  if id = 0 then
    emptySlot = 1
  end if
  if id = 1 or id = 2 then
    hasHeal = 1
    if selfHp * 5 < selfMaxHp * 3 and itemCooldown(slot) = 0 then
      useItem(slot)
    end if
  end if
  if id = 3 or id = 22 then
    hasMana = 1
    if objectiveBuild = 0 and selfMana * 5 < selfMaxMana * 2 and itemCooldown(slot) = 0 then
      useItem(slot)
    end if
  end if
  if id = 4 then
    hasPoison = 1
    if objectiveBuild = 0 and bestId <> 0 then
      useItem(slot)
    end if
  end if
  if id >= 5 and id <= 20 then
    hasGear = 1
  end if
  if id = 8 then
    hasBoots = 1
  end if
  if id = 11 then
    hasDagger = 1
  end if
  if id = 13 then
    hasSword = 1
  end if
  if id = 16 then
    hasArmor = 1
  end if
  if id = 18 then
    hasAxe = 1
  end if
  if id = 20 then
    hasBook = 1
  end if
  slot = slot + 1
wend
if canShop() then
if selfClass = 8 and selfLevel = 1 and hasGear = 0 and selfGold >= 140 then
  buyItem(12)
end if
if selfClass = 1 and selfLevel = 1 and hasGear = 0 and selfGold >= 150 then
  buyItem(7)
  buyItem(5)
end if
reserveHealSlot = 0
if selfClass = 2 or selfClass = 7 or selfClass = 8 then
  reserveHealSlot = 1
end if
if reserveHealSlot and hasHeal = 0 and emptySlot <> 0 and selfGold >= 30 then
  buyItem(1)
end if
if reserveHealSlot = 0 and selfHp * 2 < selfMaxHp and hasHeal = 0 then
  if selfGold >= 50 then
    buyItem(2)
  end if
  if selfGold >= 30 then
    buyItem(1)
  end if
end if
if selfClass = 1 and hasDagger <> 0 and hasBoots = 0 and emptySlot <> 0 then
  if selfGold >= 100 then
    buyItem(8)
  end if
end if
if objectiveBuild = 0 then
if selfMaxMana > 0 then
  if selfMana * 2 < selfMaxMana and hasMana = 0 then
    if selfGold >= 45 then
      buyItem(22)
    end if
  end if
end if
if bestId <> 0 and hasPoison = 0 then
  if selfGold >= 40 then
    buyItem(4)
  end if
end if
if emptySlot <> 0 and (reserveHealSlot = 0 or hasHeal <> 0) then
  melee = 0
  ranged = 0
  magic = 0
  if selfClass = 0 or selfClass = 4 or selfClass = 5 or selfClass = 9 then
    melee = 1
  end if
  if selfClass = 1 or selfClass = 6 then
    ranged = 1
  end if
  if selfClass = 2 or selfClass = 3 or selfClass = 7 or selfClass = 8 then
    magic = 1
  end if
  if melee = 1 then
    if hasGear = 0 and selfGold >= 70 then
      buyItem(7)
    end if
    if selfGold >= 80 then
      buyItem(5)
    end if
    if selfGold >= 110 then
      buyItem(11)
    end if
    if selfGold >= 150 then
      buyItem(13)
    end if
    if selfGold >= 180 then
      buyItem(18)
    end if
  end if
  if ranged = 1 then
    if hasGear = 0 then
      if selfClass = 1 and selfGold >= 90 then
        buyItem(6)
      elseif selfGold >= 100 then
        buyItem(8)
      end if
    end if
    if selfGold >= 150 then
      buyItem(14)
    end if
    if selfGold >= 180 then
      buyItem(19)
    end if
  end if
  if magic = 1 then
    if hasGear = 0 and selfGold >= 140 then
      buyItem(12)
    end if
    if selfGold >= 120 then
      buyItem(10)
    end if
    if selfGold >= 170 then
      buyItem(17)
    end if
    if selfGold >= 190 then
      buyItem(20)
    end if
  end if
  if selfGold >= 90 then
    buyItem(6)
  end if
  if selfGold >= 120 then
    buyItem(9)
  end if
end if
else
  if emptySlot <> 0 and (reserveHealSlot = 0 or hasHeal <> 0) then
    if hasDagger = 0 and selfGold >= 110 then
      buyItem(11)
    end if
    if hasSword = 0 and selfGold >= 150 then
      buyItem(13)
    end if
    if hasArmor = 0 and selfGold >= 160 then
      buyItem(16)
    end if
    if hasAxe = 0 and selfGold >= 180 then
      buyItem(18)
    end if
    if hasBook = 0 and selfGold >= 190 then
      buyItem(20)
    end if
  end if
end if
end if
if combatDecision = 1 then
  if selfTeam = 0 then
    walkTo(mapWidth - 10, 10)
  else
    walkTo(10, mapHeight - 10)
  end if
end if
if combatDecision = 2 then
  if objectiveId <> 0 and objectiveDistance <= 300 then
    attackTarget(objectiveId)
  else
    if heroId <> 0 and heroDistance <= 700 then
      attackTarget(heroId)
    else
      if selfTeam = 0 then
        if battleTick < 3500 and groupDeparture = 0 then
          walkTo(71, 12)
        else
          if battleTick < 4500 then
            walkTo(9, 33)
          else
            walkTo(11, 106)
          end if
        end if
      else
        if battleTick < 3500 and groupDeparture = 0 then
          walkTo(45, 104)
        else
          if battleTick < 4500 then
            walkTo(107, 83)
          else
            walkTo(105, 10)
          end if
        end if
      end if
    end if
  end if
end if
primaryWait = 0
if selfClass = 6 and selfTarget = bestId and bestId <> 0 and primaryIndex >= 0 then
  if enemyKind = 3 or enemyKind = 6 then
    if selfStunTicks = 0 and selfChannelTicks = 0 and enemyReturning = 0 then
      if enemyHp <= selfAttackDamage and selfAttackCooldown > 0 and selfAttackCooldown <= 3 then
        if abilityCharges(0) > 0 and abilityCooldown(0) = 0 and selfMana >= abilityManaCost(0) then
          primaryDx = objectInfo(primaryIndex, 0) - selfInfo(0)
          primaryDy = objectInfo(primaryIndex, 1) - selfInfo(1)
          primaryDistance = primaryDx * primaryDx + primaryDy * primaryDy
          primaryRange = selfInfo(15)
          primaryClosing = primaryDx * objectInfo(primaryIndex, 6) + primaryDy * objectInfo(primaryIndex, 7)
          if primaryClosing <= 0 and primaryDistance <= primaryRange * primaryRange then
            if primaryDistance > selfAttackCooldown * selfAttackCooldown then
              primaryWait = 1
            end if
          end if
        end if
      end if
    end if
  end if
end if

if combatDecision >= 3 and combatDecision <= 6 then
  if bestId <> 0 then
    castReach = 1000000
    if selfClass = 4 then
      if combatDecision = 4 then
        castReach = 2.25
      elseif combatDecision = 5 then
        castReach = 4
      elseif combatDecision = 6 then
        castReach = 25
      end if
    end if
    if selfClass = 8 and combatDecision = 4 then
      castReach = 20
    end if
    if bestDistance <= castReach and (combatDecision <> 4 or primaryWait = 0) then
      castTarget(engineAbilitySlot(combatDecision - 3), bestId)
      if selfInfo(19) then
        end
      end if
    end if
  else
    castTarget(engineAbilitySlot(combatDecision - 3), selfId)
    if selfInfo(19) then
      end
    end if
  end if
end if
if combatDecision = 7 then
  walkTo(allyX, allyY)
end if

if decision = 18 and (bestId = 0 or bestDistance > 64) then
  specialistX = mapWidth - 1 - gateHomeX
  specialistY = gateHomeY
  specialistDx = selfX - specialistX
  specialistDy = selfY - specialistY
  if specialistDx * specialistDx + specialistDy * specialistDy <= 64 then
    perimeterStage = 1
  end if
  if perimeterStage <> 0 then
    specialistY = mapHeight - 1 - gateHomeY
  end if
  walkTo(specialistX, specialistY)
end if

if (combatDecision = 2 or combatDecision = 8) and objectiveKind = 4 and objectiveDistance <= 300 and siegeThreatId <> 0 then
  attackTarget(siegeThreatId)
end if


if (selfClass = 8 or (selfClass = 2 and selfLevel >= 2)) and selfHp * 2 >= selfMaxHp and heroDistance > 36 then
  if combatDecision = 2 or combatDecision = 8 then
    if bestId <> 0 and bestDistance <= 16 and enemyReturning = 0 then
      if enemyKind = 3 or enemyKind = 6 then
        attackTarget(bestId)
      end if
    end if
  end if
end if

if reserveHome <> 0 then
  reserveGuards = 0
  reserveGuardCritical = 0
  reserveNearest = 1
  reserveDx = selfX - reserveX
  reserveDy = selfY - reserveY
  reserveDistance = reserveDx * reserveDx + reserveDy * reserveDy
  reserveTarget = 0
  reserveTargetDistance = 401
  reserveDirect = 0
  reserveDirectDistance = 401
  reserveHero = 0
  reserveHeroDistance = 401
  reserveFinish = 0
  reserveIndex = 0
  while reserveIndex < objectCount()
    reserveDx = objectX(reserveIndex) - reserveX
    reserveDy = objectY(reserveIndex) - reserveY
    reserveObjectHome = reserveDx * reserveDx + reserveDy * reserveDy
    if objectTeam(reserveIndex) = selfTeam then
      if objectKind(reserveIndex) = 4 and objectHp(reserveIndex) > 0 and reserveObjectHome <= 100 then
        reserveGuards = reserveGuards + 1
        if objectHp(reserveIndex) <= 780 then
          reserveGuardCritical = 1
        end if
      end if
      if objectKind(reserveIndex) = 2 and objectAlive(reserveIndex) and reserveObjectHome < reserveDistance then
        reserveNearest = 0
      end if
    else
      if objectAlive(reserveIndex) then
        if (objectKind(reserveIndex) = 2 or objectKind(reserveIndex) = 3) and reserveObjectHome < reserveDirectDistance then
          if objectTarget(reserveIndex) = reserveHomeId then
            reserveDirect = objectId(reserveIndex)
            reserveDirectDistance = reserveObjectHome
          end if
        end if
        if objectKind(reserveIndex) = 2 and reserveObjectHome < reserveHeroDistance then
          reserveHero = objectId(reserveIndex)
          reserveHeroDistance = reserveObjectHome
        end if
        if (objectKind(reserveIndex) = 2 or objectKind(reserveIndex) = 3) and reserveObjectHome < reserveTargetDistance then
          reserveTargetDistance = reserveObjectHome
          reserveTarget = objectId(reserveIndex)
        end if
        if objectKind(reserveIndex) = 1 and objectHp(reserveIndex) <= selfAttackDamage then
          reserveDx = objectX(reserveIndex) - selfX
          reserveDy = objectY(reserveIndex) - selfY
          reserveRange = selfAttackRange \ 1000
          if (reserveDx * reserveDx + reserveDy * reserveDy) * 3600 <= reserveRange * reserveRange then
            reserveFinish = 1
          end if
        end if
      end if
    end if
    reserveIndex = reserveIndex + 1
  wend
  if reserveHero <> 0 then
    reserveTarget = reserveHero
  end if
  if reserveDirect <> 0 then
    reserveTarget = reserveDirect
  end if
  if (reserveGuards <= 1 or (reserveGuardCritical <> 0 and reserveDistance <= 900)) and reserveNearest <> 0 and reserveFinish = 0 then
    if reserveDistance <= 400 and reserveTarget <> 0 then
      attackTarget(reserveTarget)
    else
      walkTo(reserveX, reserveY)
    end if
  end if
end if

if recoveryInitialized <> 0 and selfAttacksLanded > recoveryLastHit then
  walkTo(selfX, selfY)
end if
recoveryLastHit = selfAttacksLanded
recoveryInitialized = 1

if selfClass = 8 and selfHp > 0 then
  warlockTowerIndex = 0
  warlockTowerNearest = 122
  while warlockTowerIndex < objectCount()
    if objectKind(warlockTowerIndex) = 4 then
      if objectId(warlockTowerIndex) = warlockTowerId then
        if objectAlive(warlockTowerIndex) = 0 then
          warlockTowerId = 0
        elseif objectTarget(warlockTowerIndex) <> 0 and objectTarget(warlockTowerIndex) <> selfId then
          warlockTowerId = 0
        end if
      end if
      if objectTeam(warlockTowerIndex) <> selfTeam then
        if objectAlive(warlockTowerIndex) then
          if objectTarget(warlockTowerIndex) = selfId then
            warlockTowerDx = objectX(warlockTowerIndex) - selfX
            warlockTowerDy = objectY(warlockTowerIndex) - selfY
            warlockTowerDistance = warlockTowerDx * warlockTowerDx + warlockTowerDy * warlockTowerDy
            if warlockTowerDistance < warlockTowerNearest then
              warlockTowerNearest = warlockTowerDistance
              warlockTowerId = objectId(warlockTowerIndex)
              warlockTowerX = objectX(warlockTowerIndex)
              warlockTowerY = objectY(warlockTowerIndex)
            end if
          end if
        end if
      end if
    end if
    warlockTowerIndex = warlockTowerIndex + 1
  wend
  if warlockTowerId <> 0 then
    warlockTowerDx = selfX - warlockTowerX
    warlockTowerDy = selfY - warlockTowerY
    if warlockTowerDx * warlockTowerDx + warlockTowerDy * warlockTowerDy > 144 then
      warlockTowerId = 0
    else
      walkTo(gateHomeX, gateHomeY)
    end if
  end if
end if

if selfClass = 1 and selfHp > 0 then
  if bestId <> 0 and enemyAttackTarget = selfId then
    if bestDistance <= 25 or (enemyKind = 4 and bestDistance <= 100) then
      walkTo(gateHomeX, gateHomeY)
    end if
  end if
end if

if selfClass = 3 and selfHp > 0 then
  if heroId <> 0 and ringHeroTarget = selfId and heroDistance <= 36 then
    druidHeroRetreatUntil = battleTick + 120
  end if
  if battleTick < druidHeroRetreatUntil then
    walkTo(gateHomeX, gateHomeY)
  end if
end if

if selfClass = 4 and selfLevel <= 2 and selfHp > 0 and selfHp * 2 < selfMaxHp then
  if enemyKind = 6 and bestId <> 0 and enemyAttackTarget = selfId then
    if bestDistance <= 25 then
      walkTo(gateHomeX, gateHomeY)
    end if
  end if
end if

if selfClass <> 0 and selfClass <> 3 and heroId <> 0 and heroDistance <= 36 and selfChannelTicks = 0 and selfSilenceTicks = 0 then
  spellAccepted = 0
  spellSlot = 3
  while spellSlot >= 1 and spellAccepted = 0
    heroCastReach = 36
    if selfClass = 4 then
      if spellSlot = 1 then
        heroCastReach = 2.25
      elseif spellSlot = 2 then
        heroCastReach = 4
      else
        heroCastReach = 25
      end if
    elseif spellSlot <> 3 then
      heroCastReach = 25
    end if
    if heroDistance <= heroCastReach and abilityLevel(engineAbilitySlot(spellSlot)) > 0 then
      if abilityCharges(engineAbilitySlot(spellSlot)) > 0 and abilityCooldown(engineAbilitySlot(spellSlot)) = 0 then
        if selfMana >= abilityManaCost(engineAbilitySlot(spellSlot)) then
          spellAccepted = castTarget(engineAbilitySlot(spellSlot), heroId)
          if selfInfo(19) then
            end
          end if
        end if
      end if
    end if
    spellSlot = spellSlot - 1
  wend
end if

if selfClass = 0 and selfChannelTicks = 0 and selfSilenceTicks = 0 and selfStunTicks = 0 then
  if heroId <> 0 and heroDistance <= 2.25 then
    if abilityLevel(0) > 0 and abilityCharges(0) > 0 and abilityCooldown(0) = 0 then
      if selfMana >= abilityManaCost(0) then
        castTarget(0, heroId)
        if selfInfo(19) then
          end
        end if
      end if
    end if
  end if
end if

if selfClass = 2 and selfHp > 0 and selfChannelTicks = 0 and selfSilenceTicks = 0 and selfStunTicks = 0 then
  if heroDistance > 64 and abilityLevel(1) > 0 and abilityCharges(1) > 0 and abilityCooldown(1) = 0 then
    if selfMana >= abilityManaCost(1) * 2 then
      meteorBestCount = 2
      meteorCenter = 0
      while meteorCenter < meteorFarmCount
        meteorCount = 0
        meteorNeighbor = 0
        while meteorNeighbor < meteorFarmCount
          meteorDx = meteorFarmX(meteorNeighbor) - meteorFarmX(meteorCenter)
          meteorDy = meteorFarmY(meteorNeighbor) - meteorFarmY(meteorCenter)
          if meteorDx * meteorDx + meteorDy * meteorDy <= 2.25 then
            meteorCount = meteorCount + 1
          end if
          meteorNeighbor = meteorNeighbor + 1
        wend
        if meteorCount > meteorBestCount then
          meteorBestCount = meteorCount
          meteorTargetX = meteorFarmX(meteorCenter)
          meteorTargetY = meteorFarmY(meteorCenter)
        end if
        meteorCenter = meteorCenter + 1
      wend
      if meteorBestCount >= 3 then
        castPoint(1, meteorTargetX, meteorTargetY)
        if selfInfo(19) then
          end
        end if
      end if
    end if
  end if
end if


if fistFarmReady and fistFarmId <> 0 and heroDistance > 36 then
  if abilityCharges(0) > 1 and abilityCooldown(0) = 0 then
    castTarget(0, fistFarmId)
    if selfInfo(19) then
      end
    end if
  end if
end if

if selfClass = 3 and selfChannelTicks = 0 and selfSilenceTicks = 0 then
  healMissing = selfMaxHp - selfHp
  healAccepted = 0
  if healMissing * 3 >= selfMaxHp and abilityLevel(0) > 0 then
    if abilityCharges(0) > 0 and abilityCooldown(0) = 0 then
      if selfMana >= abilityManaCost(0) then
        healAccepted = castPoint(0, selfX, selfY)
        if selfInfo(19) then
          end
        end if
      end if
    end if
  end if
  if healAccepted = 0 and healMissing * 2 >= selfMaxHp and abilityLevel(1) > 0 then
    if abilityCharges(1) > 0 and abilityCooldown(1) = 0 then
      if selfMana >= abilityManaCost(1) then
        castPoint(1, selfX, selfY)
        if selfInfo(19) then
          end
        end if
      end if
    end if
  end if
end if

if selfClass = 3 and selfHp > 0 and selfChannelTicks = 0 and selfSilenceTicks = 0 then
  if abilityLevel(3) > 0 and abilityCharges(3) > 0 and abilityCooldown(3) = 0 then
    if selfMana >= abilityManaCost(3) then
      if heroId <> 0 and heroDistance <= 25 then
        castPoint(3, ringHeroX, ringHeroY)
        if selfInfo(19) then
          end
        end if
      elseif bestId <> 0 and bestDistance <= 25 then
        if enemyKind = 3 or enemyKind = 4 then
          castPoint(3, enemyX, enemyY)
          if selfInfo(19) then
            end
          end if
        end if
      end if
    end if
  end if
end if

if selfClass = 4 and enemyKind = 3 and bestId <> 0 then
  if heroId <> 0 and heroDistance <= 16 then
    carryHasCreep = 0
    carryIndex = 0
    while carryIndex < objectCount()
      if objectAlive(carryIndex) and objectTeam(carryIndex) = selfTeam then
        if objectKind(carryIndex) = 2 and objectId(carryIndex) <> selfId then
          if objectClass(carryIndex) = 1 or objectClass(carryIndex) = 6 then
            if objectTarget(carryIndex) = bestId then
              carryDx = objectX(carryIndex) - selfX
              carryDy = objectY(carryIndex) - selfY
              if carryDx * carryDx + carryDy * carryDy <= 64 then
                carryHasCreep = 1
              end if
            end if
          end if
        end if
      end if
      carryIndex = carryIndex + 1
    wend
    if carryHasCreep <> 0 then
      attackTarget(heroId)
    end if
  end if
end if

if selfClass = 0 and selfHp > 0 and selfAttackCooldown <= tickRate \ 2 then
  lastHitId = 0
  lastHitHp = selfAttackDamage + 1
  lastHitRange = selfAttackRange \ 1000
  lastHitIndex = 0
  while lastHitIndex < objectCount()
    if objectTeam(lastHitIndex) <> selfTeam then
      if objectKind(lastHitIndex) = 3 then
        lastHitDx = objectX(lastHitIndex) - selfX
        if lastHitDx * lastHitDx * 3600 <= lastHitRange * lastHitRange then
          lastHitDy = objectY(lastHitIndex) - selfY
          lastHitDistance = lastHitDx * lastHitDx + lastHitDy * lastHitDy
          if lastHitDistance * 3600 <= lastHitRange * lastHitRange then
            if objectAlive(lastHitIndex) then
              lastHitCreepHp = objectHp(lastHitIndex)
              if lastHitCreepHp > 0 and lastHitCreepHp <= selfAttackDamage then
                if lastHitCreepHp < lastHitHp then
                  lastHitId = objectId(lastHitIndex)
                  lastHitHp = lastHitCreepHp
                end if
              end if
            end if
          end if
        end if
      end if
    end if
    lastHitIndex = lastHitIndex + 1
  wend
  if lastHitId <> 0 then
    attackTarget(lastHitId)
  end if
end if

if (selfClass = 0 or selfClass = 5 or selfClass = 9) and selfHp > 0 and selfChannelTicks = 0 and selfSilenceTicks = 0 and selfStunTicks = 0 then
  if abilityLevel(2) > 0 and abilityCharges(2) > 0 and abilityCooldown(2) = 0 then
    if selfMaxHp - selfHp >= abilityHeal(2) then
      castTarget(2, selfId)
      if selfInfo(19) then
        end
      end if
    end if
  end if
end if

if selfClass = 6 and selfHp > 0 then
  crossbowPressureCount = 0
  crossbowPressureX = 0
  crossbowPressureY = 0
  if selfHp * 4 < selfMaxHp then
    crossbowPressureIndex = 0
    while crossbowPressureIndex < objectCount()
      if objectKind(crossbowPressureIndex) = 3 and objectTeam(crossbowPressureIndex) <> selfTeam then
        if objectAlive(crossbowPressureIndex) and objectTarget(crossbowPressureIndex) = selfId then
          crossbowPressureDx = objectX(crossbowPressureIndex) - selfX
          crossbowPressureDy = objectY(crossbowPressureIndex) - selfY
          if crossbowPressureDx * crossbowPressureDx + crossbowPressureDy * crossbowPressureDy <= 25 then
            crossbowPressureCount = crossbowPressureCount + 1
            crossbowPressureX = crossbowPressureX + objectX(crossbowPressureIndex)
            crossbowPressureY = crossbowPressureY + objectY(crossbowPressureIndex)
          end if
        end if
      end if
      crossbowPressureIndex = crossbowPressureIndex + 1
    wend
  end if
  if crossbowPressureCount > 0 then
    crossbowEscapeDx = selfX - crossbowEscapeX
    crossbowEscapeDy = selfY - crossbowEscapeY
    if battleTick >= crossbowEscapeUntil or crossbowEscapeDx * crossbowEscapeDx + crossbowEscapeDy * crossbowEscapeDy <= 4 then
      crossbowPressureDx = selfX * crossbowPressureCount - crossbowPressureX
      crossbowPressureDy = selfY * crossbowPressureCount - crossbowPressureY
      if crossbowPressureDx = 0 and crossbowPressureDy = 0 then
        crossbowPressureDx = gateHomeX - selfX
        crossbowPressureDy = gateHomeY - selfY
      end if
      crossbowEscapeX = selfX
      crossbowEscapeY = selfY
      if crossbowPressureDx > 0 then
        crossbowEscapeX = selfX + 8
      elseif crossbowPressureDx < 0 then
        crossbowEscapeX = selfX - 8
      end if
      if crossbowPressureDy > 0 then
        crossbowEscapeY = selfY + 8
      elseif crossbowPressureDy < 0 then
        crossbowEscapeY = selfY - 8
      end if
      if crossbowEscapeX < 1 then
        crossbowEscapeX = 1
      elseif crossbowEscapeX > mapWidth - 2 then
        crossbowEscapeX = mapWidth - 2
      end if
      if crossbowEscapeY < 1 then
        crossbowEscapeY = 1
      elseif crossbowEscapeY > mapHeight - 2 then
        crossbowEscapeY = mapHeight - 2
      end if
      crossbowEscapeUntil = battleTick + 120
    end if
  end if
  if battleTick < crossbowEscapeUntil then
    walkTo(crossbowEscapeX, crossbowEscapeY)
  end if
end if

' Spend the long post-shot cooldown moving out of melee reach.
if selfAttackRange >= worldScale * 3 and selfAttackCooldown > tickRate \ 2 and selfAttacksLanded > 0 then
  if selfChannelTicks = 0 and selfStunTicks = 0 and selfRootTicks = 0 then
    kiteNearest = 10
    kiteId = 0
    kiteIndex = 0
    while kiteIndex < objectCount()
      if objectKind(kiteIndex) = 2 and objectTeam(kiteIndex) <> selfTeam and objectAlive(kiteIndex) then
        kiteClass = objectClass(kiteIndex)
        if kiteClass = 0 or kiteClass = 4 or kiteClass = 5 or kiteClass = 9 then
          kiteDx = selfX - objectX(kiteIndex)
          kiteDy = selfY - objectY(kiteIndex)
          kiteDistance = kiteDx * kiteDx + kiteDy * kiteDy
          if kiteDistance < kiteNearest then
            kiteNearest = kiteDistance
            kiteId = objectId(kiteIndex)
            kiteX = kiteDx
            kiteY = kiteDy
          end if
        end if
      end if
      kiteIndex = kiteIndex + 1
    wend
    if kiteId <> 0 then
      if kiteX = 0 and kiteY = 0 then
        kiteX = kiteSpawnX - selfX
        kiteY = kiteSpawnY - selfY
      end if
      kiteScale = kiteX
      if kiteScale < 0 then
        kiteScale = -kiteScale
      end if
      kiteYScale = kiteY
      if kiteYScale < 0 then
        kiteYScale = -kiteYScale
      end if
      if kiteYScale > kiteScale then
        kiteScale = kiteYScale
      end if
      if kiteScale > 0 then
        kiteX = selfX + kiteX * 2 \ kiteScale
        kiteY = selfY + kiteY * 2 \ kiteScale
        if kiteX < 0 then
          kiteX = 0
        elseif kiteX >= mapWidth then
          kiteX = mapWidth - 1
        end if
        if kiteY < 0 then
          kiteY = 0
        elseif kiteY >= mapHeight then
          kiteY = mapHeight - 1
        end if
        walkTo(kiteX, kiteY)
      end if
    end if
  end if
end if
