' Generated from gota_combined_positive_20261006; gota-semantic-policy/1; gota-bassy/combined-positive-20261006
' @rule comments identify regions only; the extractor reads all executable statements.

' @rule R_tower_state
if selfHp <= 0 or drafting = 1 then
tfShotDebtUntil = 0
tfBlocked = 0
end if

' @rule R_portal_state
if selfChannelTicks > 0 then
portalBusy = 1
end if
if selfPortalCooldown > 0 or selfHp <= 0 then
portalBusy = 0
end if

' @rule R_draft
active = 0
if drafting = 1 then
if draftTurnId = selfId then
pick = -1
pickScore = -10000
c = 0
while c < 10
if heroAvailable(c) = 1 then
score = 100
if c = Ranger then
score = 180
end if
if c = Arcanist then
score = 170
end if
if c = Crossbowman then
score = 160
end if
if c = Lich then
score = 150
end if
if c = DruidWarden then
score = 140
end if
if c = DeathKnight then
score = 130
end if
if c = Warlock then
score = 120
end if
if c = Arcanist then
score = score + 300
end if
p = 0
while p < draftPlayerCount()
if draftPlayerTeam(p) = selfTeam then
other = draftedClass(draftPlayerId(p))
if other >= 0 then
if heroRole(other) = heroRole(c) then
score = score - 25
end if
end if
end if
p = p + 1
wend
if score > pickScore then
pickScore = score
pick = c
end if
end if
c = c + 1
wend
if pick >= 0 then
if pick = DeathKnight then
if heroAvailable(Warlock) = 1 then
pick = Warlock
end if
end if
if pick = Warlock and heroAvailable(Berserker) = 1 then
pick = Berserker
end if
if heroAvailable(Crossbowman) = 1 then
pick = Crossbowman
end if
draftHero(pick)
end if
end if
end if
if drafting = 0 then
if selfHp > 0 then
if portalBusy = 0 and selfChannelTicks = 0 and selfStunTicks = 0 then
if worldTick >= nextThink then
nextThink = worldTick + 6
active = 1
end if
end if
end if
end if

' @rule R_recovery_intent
if drafting = 0 and selfHp > 0 and portalBusy = 0 and selfChannelTicks = 0 and selfStunTicks = 0 and canShop() = 0 and selfHp * 100 < selfMaxHp * 30 then
if retreat = 0 then
active = 1
end if
retreat = 1
resumeTarget = 0
end if

' @rule R_base_recovery_intent
if drafting = 0 and selfHp > 0 and portalBusy = 0 and selfChannelTicks = 0 and canShop() = 1 and selfHp * 100 < selfMaxHp * 30 then
if selfTeam = 1 and ordinal = 0 and retreat = 0 then
if selfClass = Ranger or selfClass = Crossbowman then
active = 1
moveTick = worldTick
end if
end if
retreat = 1
resumeTarget = 0
end if

' @rule R_timing
if selfHp <= 0 then
resumeTarget = 0
end if
if drafting = 0 and selfHp > 0 then
if portalBusy = 0 and selfChannelTicks = 0 and selfStunTicks = 0 and selfRootTicks = 0 then
if resumeTarget > 0 then
if retreat = 0 and selfTarget = 0 then
attackTarget(resumeTarget)
end if
resumeTarget = 0
else
if retreat = 0 and selfTarget > 0 and selfAttacksLanded > previousHits then
previousHits = selfAttacksLanded
resumeTarget = selfTarget
walkTo(selfX + 0.25, selfY + 0.25)
active = 0
end if
end if
end if
end if

' @rule R_lifecycle
if drafting = 0 then
if selfHp <= 0 then
initialized = 0
scoutUntil = 0
if selfClass = DemonHunter then
nPullCamp = 0
nPullReady = 0
end if
scoutReady = 0
dhHealUntil = 0
nPullStage = 0
retreat = 0
if selfClass = DruidWarden then
laneUntil = 0
laneHealUntil = 0
end if
buyWait = 25
buyReserve = 200
buyCore = 0
buySlot = 0
while buySlot < 6
buyGear = itemId(buySlot)
if buyGear = 11 or buyGear = 16 or buyGear = 18 or buyGear = 19 then
buyCore = buyCore + 1
end if
buySlot = buySlot + 1
wend
if buyCore = 4 then
buyWait = 5
buyReserve = 100
end if
if selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich then
buyCore = 0
buySlot = 0
while buySlot < 6
buyGear = itemId(buySlot)
if (selfClass = Ranger and buyGear = 15) or (selfClass = Crossbowman and buyGear = 8) or (selfClass <> Ranger and selfClass <> Crossbowman and buyGear = 11) or buyGear = 16 or buyGear = 19 then
buyCore = buyCore + 1
end if
buySlot = buySlot + 1
wend
if buyCore = 3 then
buyWait = 5
buyReserve = 100
end if
end if
if selfClass = DemonHunter then
buyCore = 0
buySlot = 0
while buySlot < 6
buyGear = itemId(buySlot)
if buyGear = 18 or buyGear = 16 or buyGear = 19 then
buyCore = buyCore + 1
end if
buySlot = buySlot + 1
wend
if buyCore = 3 then
buyWait = 5
buyReserve = 100
end if
end if
if selfClass = DemonHunter then
buyWait = 5
buyReserve = 180
buyCore = 0
buySlot = 0
while buySlot < 6
buyGear = itemId(buySlot)
if buyGear = 13 or buyGear = 16 or buyGear = 18 then
buyCore = buyCore + 1
end if
buySlot = buySlot + 1
wend
if buyCore = 3 then
buyReserve = 140
end if
end if
if selfClass = Arcanist or selfClass = DruidWarden or selfClass >= Lich then
buyCore = 0
buySlot = 0
while buySlot < 6
buyGear = itemId(buySlot)
if buyGear = 18 or buyGear = 16 or buyGear = 8 then
buyCore = buyCore + 1
end if
buySlot = buySlot + 1
wend
if buyCore = 3 then
buyWait = 5
buyReserve = 140
end if
dhHealUntil = 0
laneUntil = 0
end if
harvestMob = 0
if worldTick >= 19280 then
buyReserve = 0
buyWait = 2
end if
price = buybackPrice()
if price > 0 and selfRespawnTicks > tickRate * buyWait then
if selfGold >= price + buyReserve then
buyback()
end if
end if
end if
end if
if active = 1 then
if initialized = 0 then
initialized = 1
spawnX = selfX
spawnY = selfY
homeX = selfX
homeY = selfY
enemyX = mapWidth - 1 - selfX
enemyY = mapHeight - 1 - selfY
crossed = 0
previousHp = selfHp
previousHits = selfAttacksLanded
ordinal = 0
p = 0
while p < draftPlayerCount()
if draftPlayerTeam(p) = selfTeam then
if draftPlayerId(p) < selfId then
ordinal = ordinal + 1
end if
end if
p = p + 1
wend
lane = ordinal mod 3
if selfClass = Crossbowman then
lane = 2
if selfTeam = 1 then
lane = 0
end if
laneStored = lane
laneAssigned = 1
laneChanged = 1
end if
if laneDecisionStarted = 0 then
laneDecisionStarted = 1
laneDecisionStart = worldTick
end if
if laneAssigned = 1 then
lane = laneStored
end if
end if
justHit = 0
if selfAttacksLanded > previousHits then
justHit = 1
end if
previousHits = selfAttacksLanded
if selfHp < previousHp then
hurtTick = worldTick
end if
previousHp = selfHp
stopped = 0
upgraded = 0
while upgraded < 4 and abilityPoints() > 0
slot = -1
if canLevelAbility(0) = 1 then
slot = 0
end if
if canLevelAbility(2) = 1 then
slot = 2
end if
if canLevelAbility(1) = 1 then
slot = 1
end if
if canLevelAbility(3) = 1 then
slot = 3
end if
if selfClass = Warlock or selfClass = Lich then
if selfLevel >= 2 and abilityLevel(2) = 0 and canLevelAbility(2) = 1 then
slot = 2
end if
end if
if selfClass = DemonHunter and selfLevel >= 2 and abilityLevel(0) = 0 and canLevelAbility(0) = 1 then
slot = 0
end if
if slot >= 0 then
levelAbility(slot)
end if
upgraded = upgraded + 1
wend
end if
if selfClass = DemonHunter and selfHp <= 0 then
laneUntil = 0
dhHealUntil = 0
end if

' @rule R_observe
if active = 1 then
dhBuy = 96
if selfClass = DemonHunter or selfClass = Berserker or selfClass = Arcanist or selfClass = DruidWarden or selfClass = Warlock or selfClass = Lich then
dhBuy = 64
end if
burstStock = 0
burstCredit = 0
if selfClass = Ranger or selfClass = Crossbowman then
burstCredit = selfAttackDamage
end if
if selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich or selfClass = DemonHunter then
burstScan = 0
while burstScan < 6
if itemId(burstScan) = 4 then
burstStock = itemCount(burstScan)
end if
burstScan = burstScan + 1
wend
end if
nCampId = 0
nCampScore = -1000000
nWaveId = 0
nWaveDistance = 1000000
nWaveCount = 0
nOnUs = 0
nHandoff = 0
laneCount0 = 0
laneCount1 = 0
laneCount2 = 0
laneKnown = 0
ccSlot = -1
ccTarget = 0
ccScore = -1000000
ccRadius = 0
ccDelay = 24
if selfClass = VanguardKnight then
ccSlot = 3
ccRadius = 3
ccDelay = 6
end if
if selfClass = Warlock then
ccSlot = 2
ccRadius = 5
end if
if selfClass = DruidWarden then
ccSlot = 3
ccRadius = 5
end if
if selfClass = Lich then
ccSlot = 2
ccRadius = 6
end if
bestId = 0
bestScore = -1000000
bestDistance = 1000000
threatDistance = 1000000
recallHeroDistance = 1000000
recallCreepDistance = 1000000
dhNeutralDistance = 1000000
homeAnchorDistance = 1000000
towerId = 0
towerHp = 0
towerDistance = 1000000
towerAggro = 0
friendPower = selfLevel + 2
coachHeroId = 0
coachHeroHp = 0
coachHeroDistance = 1000000
coachHeroLevel = 0
coachHeroX = 0
coachHeroY = 0
coachAllies = 0
coachEnemies = 0
coachAssistId = 0
enemyPower = 0
tanks = 0
homeThreat = 0
homeEnemyHeroes = 0
homeDefenders = 0
hitReach = selfAttackRange \ 60000 + 1
forwardScore = 1000000
objects = objectCount()
i = 0
while i < dhBuy and i < objects
idx = i
if i >= 48 then
idx = i + scanOffset
end if
if idx < objects then
hp = objectHp(idx)
if hp > 0 then
id = objectId(idx)
kind = objectKind(idx)
team = objectTeam(idx)
x = objectX(idx)
y = objectY(idx)
dx = x - selfX
dy = y - selfY
distance = dx * dx + dy * dy
if team = selfTeam then
if kind = 3 and distance <= 100 then
nWaveCount = nWaveCount + 1
if nPullStage > 0 and objectTarget(idx) = nPullMob then
nHandoff = 1
end if
if objectTarget(idx) = 0 then
nWaveDx = x - selfX
nWaveDy = y - selfY
if nPullStage > 0 then
nWaveDx = x - nPullCenterX
nWaveDy = y - nPullCenterY
end if
nWaveGap = nWaveDx * nWaveDx + nWaveDy * nWaveDy
if nWaveGap < nWaveDistance then
nWaveDistance = nWaveGap
nWaveId = id
nWaveX = x
nWaveY = y
end if
end if
end if
if laneAssigned = 0 and kind = 2 and id <> selfId and objectAlive(idx) = 1 then
laneAx = x - homeX
laneAy = y - homeY
if laneAx * laneAx + laneAy * laneAy >= 144 then
laneProjection = 0
laneObserved = -1
laneProbe = 0
while laneProbe < 3
lanePx = mapWidth \ 2
lanePy = mapHeight \ 2
if laneProbe = 0 then
lanePx = mapWidth \ 10
lanePy = mapHeight \ 10
end if
if laneProbe = 2 then
lanePx = mapWidth * 9 \ 10
lanePy = mapHeight * 9 \ 10
end if
laneVx = lanePx - homeX
laneVy = lanePy - homeY
laneDot = laneAx * laneVx + laneAy * laneVy
laneNorm = laneVx * laneVx + laneVy * laneVy
if laneDot > 0 and laneNorm > 0 then
laneAlignment = laneDot / laneNorm * laneDot
if laneAlignment > laneProjection then
laneProjection = laneAlignment
laneObserved = laneProbe
end if
end if
laneProbe = laneProbe + 1
wend
if laneObserved = 0 then
laneCount0 = laneCount0 + 1
end if
if laneObserved = 1 then
laneCount1 = laneCount1 + 1
end if
if laneObserved = 2 then
laneCount2 = laneCount2 + 1
end if
if laneObserved >= 0 then
laneKnown = laneKnown + 1
end if
end if
end if
if kind = 1 then
homeX = x
homeY = y
enemyX = mapWidth - 1 - x
enemyY = mapHeight - 1 - y
end if
if kind = 2 and id <> selfId then
hx = x - homeX
hy = y - homeY
if hx * hx + hy * hy < 400 then
homeDefenders = homeDefenders + 1
end if
end if
if kind = 2 and id <> selfId and distance <= 144 then
coachAllies = coachAllies + 1
if objectTarget(idx) > 0 then
coachAssistId = objectTarget(idx)
end if
end if
if kind = 2 and id <> selfId and distance <= 100 then
friendPower = friendPower + objectLevel(idx) + 2
end if
if kind = 3 and distance <= 64 then
tanks = tanks + 1
end if
if kind = 4 then
homeDx = x - spawnX
homeDy = y - spawnY
homeGap = homeDx * homeDx + homeDy * homeDy
if homeGap < homeAnchorDistance then
homeAnchorDistance = homeGap
end if
farmX = mapWidth \ 2
farmY = mapHeight \ 2
if lane = 0 then
farmX = mapWidth \ 10
farmY = mapHeight \ 10
end if
if lane = 2 then
farmX = mapWidth * 9 \ 10
farmY = mapHeight * 9 \ 10
end if
dx = x - farmX
dy = y - farmY
score = dx * dx + dy * dy
if score < forwardScore then
forwardScore = score
forwardX = x
forwardY = y
end if
end if
else
if kind = 6 then
if objectAlive(idx) = 1 then
if selfClass >= Arcanist and selfClass <> DeathKnight and selfClass <> Crossbowman then
if distance < dhNeutralDistance then
dhNeutralDistance = distance
end if
end if
if id = harvestMob then
if objectReturning(idx) <> 0 then
harvestCamp = objectCamp(idx) + 1
harvestUntil = worldTick + tickRate * 150
harvestMob = 0
if selfTarget = id then
walkTo(selfX, selfY)
resumeTarget = 0
end if
end if
end if
if objectReturning(idx) = 0 and (worldTick >= harvestUntil or objectCamp(idx) + 1 <> harvestCamp) then
nCampNumber = objectCamp(idx)
if nPullStage > 0 and nCampNumber = nPullCamp then
nLastSeen = worldTick
if objectTarget(idx) = selfId then
nOnUs = 1
end if
if objectTarget(idx) <> 0 and objectTarget(idx) <> selfId then
nHandoff = 1
end if
end if
if nCampNumber >= 0 and nCampNumber < campCount() and (distance <= 64 or ((selfClass = DemonHunter or selfClass = Berserker or selfClass = Arcanist or selfClass = DruidWarden or selfClass = Warlock or selfClass = Lich) and distance <= 100)) then
nTier = campTier(nCampNumber)
if selfLevel >= 1 + (nTier - 1) * 3 or (selfClass = DemonHunter and selfLevel >= 1 + (nTier - 1) * 2) then
nValue = 1000 - distance * 4 - hp
if id = selfTarget then
nValue = nValue + 100
end if
if nValue > nCampScore then
nCampScore = nValue
nCampId = id
nCampHp = hp
nCampX = x
nCampY = y
nCampDistance = distance
nChosenCamp = nCampNumber
nCampTarget = objectTarget(idx)
end if
end if
end if
end if
end if
end if
if kind = 1 then
enemyX = x
enemyY = y
end if
if ccSlot >= 0 and kind = 2 and objectAlive(idx) = 1 then
if distance <= ccRadius * ccRadius then
ccHeld = objectStunTicks(idx)
if selfClass = Warlock then
if objectSilenceTicks(idx) > ccHeld then
ccHeld = objectSilenceTicks(idx)
end if
end if
if selfClass = Lich or selfClass = DruidWarden then
if objectRootTicks(idx) > ccHeld then
ccHeld = objectRootTicks(idx)
end if
end if
ccFinish = 0
if hp <= abilityDamage(ccSlot) then
ccFinish = 1
end if
ccThreat = 0
if objectTarget(idx) = selfId then
ccThreat = 1
end if
if selfClass = Warlock then
ccMage = objectClass(idx)
if ccMage = Arcanist or ccMage = Warlock or ccMage = Lich or ccMage = DruidWarden then
if objectMana(idx) >= 15 then
ccThreat = 1
end if
end if
end if
if ccHeld <= ccDelay + 6 or ccFinish = 1 then
ccValue = 1000 - distance * 10 - hp
if ccThreat = 1 then
ccValue = ccValue + 1000
end if
if ccFinish = 1 then
ccValue = ccValue + 2000
end if
if ccValue > ccScore then
ccScore = ccValue
ccTarget = id
ccTargetHp = hp
ccTargetThreat = ccThreat
end if
end if
end if
end if
if kind = 2 and distance <= 100 then
coachEnemies = coachEnemies + 1
if distance < coachHeroDistance then
coachHeroId = id
coachHeroHp = hp
coachHeroLevel = objectLevel(idx)
coachHeroDistance = distance
coachHeroX = x
coachHeroY = y
end if
end if
if kind = 2 and distance < recallHeroDistance then
recallHeroDistance = distance
end if
if kind = 3 and distance < recallCreepDistance then
recallCreepDistance = distance
end if
if kind = 2 or kind = 3 then
if distance < threatDistance then
threatDistance = distance
end if
if kind = 2 and distance <= 100 then
enemyPower = enemyPower + objectLevel(idx) + 2
end if
dx = x - homeX
dy = y - homeY
if kind = 2 and dx * dx + dy * dy < 225 then
homeEnemyHeroes = homeEnemyHeroes + 1
end if
if dx * dx + dy * dy < 144 then
homeThreat = homeThreat + 1
end if
end if
if kind = 4 and id = selfTarget then
end if
if kind = 4 and distance < towerDistance then
towerDistance = distance
towerId = id
towerHp = hp
towerX = x
towerY = y
towerTarget = objectTarget(idx)
end if
if kind = 4 and objectTarget(idx) = selfId then
towerAggro = 1
end if
if kind <> 6 and distance <= 324 and objectAlive(idx) = 1 then
score = 1000 - distance * 3
if kind = 3 then
score = score + 200
if hp <= selfAttackDamage and distance <= hitReach * hitReach then
score = score + 650
end if
if objectClass(idx) = 1 then
score = score + 25
end if
end if
if kind = 2 then
score = score + 80
if burstStock > 0 and distance <= hitReach * hitReach then
if hp <= burstStock * 35 + burstCredit then
score = score + 1000
end if
end if
if hp < selfAttackDamage * 4 then
score = score + 300
end if
end if
if kind = 1 then
score = score + 500
end if
if id = selfTarget then
score = score + 70
end if
if score > bestScore then
bestScore = score
bestId = id
bestKind = kind
bestHp = hp
bestX = x
bestY = y
bestDistance = distance
end if
end if
end if
end if
end if
i = i + 1
wend
scanOffset = scanOffset + dhBuy - 48
if scanOffset >= objects - 48 then
scanOffset = 0
end if
if selfClass = DemonHunter and worldTick - hurtTick < tickRate * 2 then
dhHealUntil = 0
laneUntil = 0
end if
if selfClass >= Arcanist and selfClass <> DeathKnight and selfClass <> Crossbowman then
if worldTick - hurtTick < tickRate * 2 then
dhHealUntil = 0
laneUntil = 0
end if
if nCampId > 0 then
if harvestMob <> nCampId or nCampHp < harvestHp or nCampDistance > 16 or selfTarget <> nCampId then
harvestMob = nCampId
harvestHp = nCampHp
harvestTick = worldTick
else
if worldTick - harvestTick >= tickRate * 8 then
harvestCamp = nChosenCamp + 1
harvestUntil = worldTick + tickRate * 150
harvestMob = 0
nCampId = 0
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
resumeTarget = 0
scoutUntil = 0
scoutReady = worldTick
end if
end if
end if
end if
end if

' @rule R_economy
if active = 1 then
if canShop() = 1 and selfClass = Crossbowman and initialized = 1 then
initialized = 2
if selfLevel = 1 and selfDeaths = 0 and worldTick < tickRate * 30 then
buyItem(4)
buyItem(4)
buyItem(4)
buyItem(1)
end if
end if

if selfClass = Arcanist or selfClass = DruidWarden or selfClass >= Lich then
restock = 0
gearCount = 0
healSlot = -1
healCount = 0
poisonSlot = -1
poisonCount = 0
portalCount = 0
s = 0
while s < 6
item = itemId(s)
if item = 18 or item = 16 or item = 8 then
gearCount = gearCount + 1
end if
if item = 1 then
healSlot = s
healCount = itemCount(s)
end if
if item = 4 then
poisonSlot = s
poisonCount = itemCount(s)
end if
if item = 21 then
portalCount = itemCount(s)
end if
s = s + 1
wend
dhBuy = 0
if inOwnSpawn() = 0 and selfSilenceTicks = 0 then
if abilityLevel(0) > 0 and abilityCooldown(0) = 0 and abilityCharges(0) > 0 then
if selfMana >= abilityManaCost(0) and abilityHeal(0) > 0 and selfMaxHp - selfHp >= abilityHeal(0) then
dhBuy = castTarget(0, selfId)
end if
end if
end if
if dhBuy = 0 and healSlot >= 0 and canShop() = 0 and selfMaxHp - selfHp >= 110 then
if itemCooldown(healSlot) = 0 and recallHeroDistance > 100 and recallCreepDistance > 36 then
if dhNeutralDistance > 64 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil and worldTick - hurtTick >= tickRate * 2 then
if useItem(healSlot) = 1 then
dhHealUntil = worldTick + tickRate * 10
laneUntil = 0
healCount = healCount - 1
end if
end if
end if
end if
if canShop() = 1 then
budget = selfGold
dhBuy = 0
while dhBuy < 3
item = 18
score = 180
if dhBuy = 1 then
item = 16
score = 160
end if
if dhBuy = 2 then
item = 8
score = 100
end if
burstBuy = 1
s = 0
while s < 6
if itemId(s) = item then
burstBuy = 0
end if
s = s + 1
wend
if burstBuy = 1 and budget >= score then
if buyItem(item) = 1 then
budget = budget - score
gearCount = gearCount + 1
end if
end if
dhBuy = dhBuy + 1
wend
if selfLevel = 1 and selfDeaths = 0 and worldTick < tickRate * 30 then
while healCount < 2 and budget >= 30
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
while poisonCount < 2 and budget >= 40
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
end if
if gearCount = 3 then
while healCount < 2 and budget >= 30
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
while poisonCount < 2 and budget >= 40
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
dhReserve = (selfDeaths + 1) * 100
while healCount < 4 and budget >= 30 + dhReserve
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
score = 4
if budget >= dhReserve + 500 then
score = 8
end if
while poisonCount < score and budget >= 40 + dhReserve
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
while portalCount < 2 and budget >= 100 + dhReserve
if buyItem(21) = 1 then
portalCount = portalCount + 1
budget = budget - 100
else
budget = 0
end if
wend
end if
else
empty = 0
s = 0
while s < 6
if itemId(s) = 0 then
empty = empty + 1
end if
s = s + 1
wend
if empty > 0 and gearCount < 3 and selfGold >= 500 and recallHeroDistance > 225 and recallCreepDistance > 144 and dhNeutralDistance > 144 and bestDistance > 144 then
restock = 1
retreat = 1
end if
end if
else
if selfClass = DemonHunter then
restock = 0
gearCount = 0
healSlot = -1
healCount = 0
poisonSlot = -1
poisonCount = 0
portalCount = 0
s = 0
while s < 6
item = itemId(s)
if item = 13 or item = 16 or item = 18 then
gearCount = gearCount + 1
end if
if item = 1 then
healSlot = s
healCount = itemCount(s)
end if
if item = 4 then
poisonSlot = s
poisonCount = itemCount(s)
end if
if item = 21 then
portalCount = itemCount(s)
end if
s = s + 1
wend
dhBuy = 0
if inOwnSpawn() = 0 and selfSilenceTicks = 0 then
if abilityLevel(0) > 0 and abilityCooldown(0) = 0 and abilityCharges(0) > 0 then
if selfMana >= abilityManaCost(0) and abilityHeal(0) > 0 and selfMaxHp - selfHp >= abilityHeal(0) then
dhBuy = castTarget(0, selfId)
end if
end if
end if
if dhBuy = 0 and healSlot >= 0 and canShop() = 0 and selfMaxHp - selfHp >= 110 then
if itemCooldown(healSlot) = 0 and recallHeroDistance > 100 and recallCreepDistance > 36 then
if dhNeutralDistance > 64 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil and worldTick - hurtTick >= tickRate * 2 then
if useItem(healSlot) = 1 then
dhHealUntil = worldTick + tickRate * 10
laneUntil = 0
healCount = healCount - 1
end if
end if
end if
end if
if canShop() = 1 then
budget = selfGold
dhBuy = 0
while dhBuy < 3
item = 13
score = 150
if dhBuy = 1 then
item = 16
score = 160
end if
if dhBuy = 2 then
item = 18
score = 180
end if
burstBuy = 1
s = 0
while s < 6
if itemId(s) = item then
burstBuy = 0
end if
s = s + 1
wend
if burstBuy = 1 and budget >= score then
if buyItem(item) = 1 then
budget = budget - score
gearCount = gearCount + 1
end if
end if
dhBuy = dhBuy + 1
wend
if selfLevel = 1 and selfDeaths = 0 and worldTick < tickRate * 30 then
while healCount < 2 and budget >= 30
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
while poisonCount < 2 and budget >= 40
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
end if
if gearCount = 3 then
while healCount < 2 and budget >= 30
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
while poisonCount < 2 and budget >= 40
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
dhReserve = (selfDeaths + 1) * 100
while healCount < 2 and budget >= 30 + dhReserve
if buyItem(1) = 1 then
healCount = healCount + 1
budget = budget - 30
else
budget = 0
end if
wend
score = 4
if budget >= dhReserve + 500 then
score = 8
end if
while poisonCount < score and budget >= 40 + dhReserve
if buyItem(4) = 1 then
poisonCount = poisonCount + 1
budget = budget - 40
else
budget = 0
end if
wend
if portalCount = 0 and budget >= 100 + dhReserve then
buyItem(21)
end if
end if
else
empty = 0
s = 0
while s < 6
if itemId(s) = 0 then
empty = empty + 1
end if
s = s + 1
wend
if empty > 0 and gearCount < 3 and selfGold >= 500 and recallHeroDistance > 225 and recallCreepDistance > 144 and dhNeutralDistance > 144 and bestDistance > 144 then
restock = 1
retreat = 1
end if
end if
else
if selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich then
gearCount = 0
healSlot = -1
healCount = 0
portalCount = 0
poisonSlot = -1
poisonCount = 0
empty = 0
has11 = 0
has16 = 0
has19 = 0
s = 0
while s < 6
item = itemId(s)
if item = 0 then
empty = empty + 1
end if
if (selfClass = Ranger and item = 15) or (selfClass = Crossbowman and item = 8) or (selfClass <> Ranger and selfClass <> Crossbowman and item = 11) then
has11 = 1
gearCount = gearCount + 1
end if
if item = 16 then
has16 = 1
gearCount = gearCount + 1
end if
if item = 19 then
has19 = 1
gearCount = gearCount + 1
end if
if item = 1 then
healSlot = s
healCount = itemCount(s)
end if
if item = 21 then
portalCount = itemCount(s)
end if
if item = 4 then
poisonSlot = s
poisonCount = itemCount(s)
end if
s = s + 1
wend
if healSlot >= 0 and inOwnSpawn() = 0 then
if itemCooldown(healSlot) = 0 and ((selfClass = Ranger and selfHp * 100 <= selfMaxHp * 60) or (selfClass <> Ranger and selfMaxHp - selfHp >= 70)) and threatDistance > 64 then
if worldTick - hurtTick > tickRate then
useItem(healSlot)
end if
end if
end if
if canShop() = 1 then
restock = 0
budget = selfGold
if selfClass = Crossbowman then
burstBuy = 0
while poisonCount < 6 and budget >= 40 and burstBuy < 6
if buyItem(4) = 1 then
budget = budget - 40
if poisonCount = 0 then
empty = empty - 1
end if
poisonCount = poisonCount + 1
else
burstBuy = 6
end if
burstBuy = burstBuy + 1
wend
end if
starterItem = 11
starterCost = 110
if selfClass = Ranger then
starterItem = 15
starterCost = 140
end if
if selfClass = Crossbowman then
starterItem = 8
starterCost = 100
end if
if has11 = 0 and budget >= starterCost and empty > 0 then
if buyItem(starterItem) = 1 then
budget = budget - starterCost
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if has16 = 0 and budget >= 160 and empty > 0 then
if buyItem(16) = 1 then
budget = budget - 160
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if portalCount = 0 and budget >= 100 and empty > 0 then
if buyItem(21) = 1 then
budget = budget - 100
empty = empty - 1
portalCount = 1
end if
end if
if has19 = 0 and budget >= 180 and empty > 0 then
if buyItem(19) = 1 then
budget = budget - 180
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if healCount = 0 and budget >= 30 and empty > 0 then
if buyItem(1) = 1 then
budget = budget - 30
empty = empty - 1
healCount = 1
end if
end if
if healCount = 1 and budget >= 30 then
if buyItem(1) = 1 then
budget = budget - 30
end if
end if
burstReserve = (selfDeaths + 1) * 100 + 100
score = 8
if selfClass = Crossbowman then
burstReserve = 100
score = 24
end if
if gearCount >= 3 and portalCount = 1 and budget >= burstReserve + 100 then
if buyItem(21) = 1 then
budget = budget - 100
end if
end if
burstBuy = 0
while poisonCount < score and budget >= burstReserve + 40 and burstBuy < score
if buyItem(4) = 1 then
budget = budget - 40
poisonCount = poisonCount + 1
else
burstBuy = score
end if
burstBuy = burstBuy + 1
wend
else
if threatDistance > 225 and bestDistance > 144 then
if gearCount < 3 and selfGold >= 500 then
restock = 1
end if
if poisonCount < 2 and selfGold >= (selfDeaths + 1) * 100 + 420 then
restock = 1
end if
end if
end if
if restock = 1 then
retreat = 1
end if
else
gearCount = 0
healSlot = -1
healCount = 0
portalSlot = -1
portalCount = 0
empty = 0
has11 = 0
has16 = 0
has18 = 0
has19 = 0
s = 0
while s < 6
item = itemId(s)
if item = 0 then
empty = empty + 1
end if
if item = 11 then
has11 = 1
gearCount = gearCount + 1
end if
if item = 16 then
has16 = 1
gearCount = gearCount + 1
end if
if item = 18 then
has18 = 1
gearCount = gearCount + 1
end if
if item = 19 then
has19 = 1
gearCount = gearCount + 1
end if
if item = 1 then
healSlot = s
healCount = itemCount(s)
end if
if item = 21 then
portalSlot = s
portalCount = itemCount(s)
end if
s = s + 1
wend
if healSlot >= 0 and inOwnSpawn() = 0 then
if itemCooldown(healSlot) = 0 and selfMaxHp - selfHp >= 70 and threatDistance > 64 then
if worldTick - hurtTick > tickRate then
if selfClass = DruidWarden then
if useItem(healSlot) = 1 then
laneHealUntil = worldTick + tickRate * 10
end if
else
useItem(healSlot)
end if
end if
end if
end if
if canShop() = 1 then
restock = 0
budget = selfGold
if has11 = 0 and budget >= 110 and empty > 0 then
if buyItem(11) = 1 then
budget = budget - 110
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if has16 = 0 and budget >= 160 and empty > 0 then
if buyItem(16) = 1 then
budget = budget - 160
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if portalCount = 0 and budget >= 100 and empty > 0 then
if buyItem(21) = 1 then
budget = budget - 100
empty = empty - 1
end if
end if
if has18 = 0 and budget >= 180 and empty > 0 then
if buyItem(18) = 1 then
budget = budget - 180
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if has19 = 0 and budget >= 180 and empty > 0 then
if buyItem(19) = 1 then
budget = budget - 180
empty = empty - 1
gearCount = gearCount + 1
end if
end if
if gearCount >= 4 and budget >= 100 then
reserveSlot = 0
while reserveSlot < 6
if itemId(reserveSlot) = 21 and itemCount(reserveSlot) = 1 then
if buyItem(21) = 1 then
budget = budget - 100
end if
end if
reserveSlot = reserveSlot + 1
wend
end if
if healCount = 0 and budget >= 30 and empty > 0 then
if buyItem(1) = 1 then
budget = budget - 30
empty = empty - 1
end if
end if
if healCount > 0 and healCount < 2 and budget >= 30 then
buyItem(1)
end if
else
if gearCount < 4 and selfGold >= 500 and threatDistance > 225 then
restock = 1
end if
end if
if restock = 1 then
retreat = 1
end if
end if
end if
if canShop() = 0 and restock = 1 then
shoppingDue = 0
empty = 0
s = 0
while s < 6
if itemId(s) = 0 then
empty = empty + 1
end if
s = s + 1
wend
if empty > 0 then
dhBuy = 0
while dhBuy < 4
item = 11
score = 110
if dhBuy = 1 then
item = 16
score = 160
end if
if dhBuy = 2 then
item = 19
score = 180
end if
if dhBuy = 3 then
item = 18
score = 180
end if
if dhBuy = 0 and selfClass = Ranger then
item = 15
score = 140
end if
if dhBuy = 0 and selfClass = DemonHunter then
item = 18
score = 180
end if
if dhBuy = 3 and (selfClass = DemonHunter or selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich) then
score = 1000000
end if
if selfGold >= score then
burstBuy = 0
s = 0
while s < 6
if itemId(s) = item then
burstBuy = 1
end if
s = s + 1
wend
if burstBuy = 0 then
shoppingDue = 1
end if
end if
dhBuy = dhBuy + 1
wend
end if
if selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich then
if poisonCount < 2 and selfGold >= (selfDeaths + 1) * 100 + 140 then
if empty > 0 or poisonCount > 0 then
shoppingDue = 1
end if
end if
end if
if shoppingDue = 0 then
restock = 0
end if
end if
end if
end if

' @rule R_coach_assess_combat
if active = 1 then
coachConfidence = 0
coachEngaged = 0
if coachHeroId > 0 and coachHeroHp > 0 then
coachConfidence = 50 + (selfHp - coachHeroHp) * 35 \ (selfHp + coachHeroHp)
coachConfidence = coachConfidence + (selfLevel - coachHeroLevel) * 7
coachConfidence = coachConfidence + (selfAttackDamage - 30) / 6
coachConfidence = coachConfidence + coachAllies * 8 - (coachEnemies - 1) * 15
if selfSilenceTicks = 0 and abilityLevel(1) > 0 and abilityCooldown(1) = 0 and selfMana >= abilityManaCost(1) then
coachConfidence = coachConfidence + 4
end if
if coachAssistId = coachHeroId then
coachEngaged = 1
coachConfidence = coachConfidence + 8
end if
if coachConfidence > 100 then
coachConfidence = 100
end if
if coachConfidence < 0 then
coachConfidence = 0
end if
coachCommit = 0
if selfHp * 100 >= selfMaxHp * 55 and coachHeroHp * 4 <= selfHp * 3 and coachConfidence >= 70 then
coachCommit = 1
end if
if coachEngaged = 1 and selfHp * 100 >= selfMaxHp * 50 and coachHeroHp <= selfHp and coachConfidence >= 65 then
coachCommit = 1
end if
if coachCommit = 1 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
if selfHp * 100 >= selfMaxHp * 30 and coachEnemies <= coachAllies + 1 then
retreat = 0
bestId = coachHeroId
bestKind = 2
bestHp = coachHeroHp
bestDistance = coachHeroDistance
bestX = coachHeroX
bestY = coachHeroY
end if
end if
end if
end if

' @rule R_control_hero
if active = 1 then
if selfSilenceTicks = 0 and ccSlot >= 0 and ccTarget > 0 then
if abilityLevel(ccSlot) > 0 and abilityCooldown(ccSlot) = 0 and abilityCharges(ccSlot) > 0 then
ccUseful = 0
if ccTarget = bestId or ccTargetThreat = 1 or ccTargetHp <= abilityDamage(ccSlot) then
ccUseful = 1
end if
if ccUseful = 1 then
ccReserve = 0
if selfHp * 100 < selfMaxHp * 65 then
ccHeal = 0
while ccHeal < 4
if abilityLevel(ccHeal) > 0 and abilityHeal(ccHeal) > 0 and abilityCharges(ccHeal) > 0 then
if abilityCooldown(ccHeal) <= tickRate * 2 and abilityManaCost(ccHeal) > ccReserve then
ccReserve = abilityManaCost(ccHeal)
end if
end if
ccHeal = ccHeal + 1
wend
end if
if selfMana >= abilityManaCost(ccSlot) + ccReserve then
castTarget(ccSlot, ccTarget)
end if
end if
end if
end if
end if

' @rule R_portal_context
if active = 1 then
inBase = canShop()
portalSlot = -1
portalCount = 0
portalReady = 0
s = 0
while s < 6
if itemId(s) = 21 and itemCount(s) > 0 then
portalSlot = s
portalCount = itemCount(s)
if itemCooldown(s) = 0 and selfPortalCooldown = 0 and selfChannelTicks = 0 then
if selfRootTicks = 0 and selfStunTicks = 0 then
portalReady = 1
end if
end if
end if
s = s + 1
wend
end if

' @rule R_choose_lane
if active = 1 then
if laneAssigned = 0 then
laneCurrent = lane
if selfTeam = 1 and ordinal = 0 then
if selfClass = Ranger or selfClass = Crossbowman then
laneCurrent = 1
end if
end if
if worldTick >= laneDecisionStart + tickRate * 12 and worldTick <= laneDecisionStart + tickRate * 35 then
if laneKnown >= 2 and retreat = 0 and selfHp * 2 >= selfMaxHp then
if threatDistance > 100 and bestDistance > 144 then
laneCurrentCount = laneCount1
if laneCurrent = 0 then
laneCurrentCount = laneCount0
end if
if laneCurrent = 2 then
laneCurrentCount = laneCount2
end if
laneChoice = laneCurrent
laneChoiceCount = laneCurrentCount
laneChoiceTravel = 1000000
laneProbe = 0
while laneProbe < 3
laneN = laneCount1
lanePx = mapWidth \ 2
lanePy = mapHeight \ 2
if laneProbe = 0 then
laneN = laneCount0
lanePx = mapWidth \ 10
lanePy = mapHeight \ 10
end if
if laneProbe = 2 then
laneN = laneCount2
lanePx = mapWidth * 9 \ 10
lanePy = mapHeight * 9 \ 10
end if
laneTravel = (selfX - lanePx) * (selfX - lanePx) + (selfY - lanePy) * (selfY - lanePy)
if laneN < laneCurrentCount then
if laneN < laneChoiceCount or (laneN = laneChoiceCount and laneTravel < laneChoiceTravel) then
laneChoice = laneProbe
laneChoiceCount = laneN
laneChoiceTravel = laneTravel
end if
end if
laneProbe = laneProbe + 1
wend
if laneChoice <> laneCurrent then
lane = laneChoice
laneStored = lane
laneAssigned = 1
laneChanged = 1
crossed = 0
moveTick = worldTick
forwardScore = 1000000
end if
end if
end if
end if
if laneAssigned = 0 and worldTick >= laneDecisionStart + tickRate * 35 then
laneAssigned = 1
laneStored = lane
end if
end if
end if

' @rule R_lane_recovery
if active = 1 then
laneAmount = 60
laneCanHeal = 20
if selfClass = Arcanist or selfClass = Lich or selfClass = Warlock then
laneAmount = 80
laneCanHeal = 40
end if
if selfClass = DruidWarden then
laneAmount = 70
laneCanHeal = 30
end if
if selfClass = Arcanist or selfClass = DruidWarden or selfClass >= Lich then
if retreat = 1 and restock = 0 and canShop() = 0 and homeThreat = 0 then
laneSafe = 1
warnings = spellCount()
if warnings > 24 then
laneSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if spellCasterId(w) <> selfId and dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate then
laneSafe = 0
end if
w = w + 1
wend
if laneSafe = 1 and recallHeroDistance > 100 and recallCreepDistance > 36 and dhNeutralDistance > 64 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
if selfHp * 100 >= selfMaxHp * laneAmount and selfMana * 100 >= selfMaxMana * laneCanHeal then
retreat = 0
laneUntil = 0
resumeTarget = 0
moveTick = worldTick
else
if worldTick < dhHealUntil then
if selfHp + (dhHealUntil - worldTick) * 120 \ (tickRate * 10) >= selfMaxHp * laneAmount \ 100 then
if laneUntil = 0 then
laneUntil = worldTick + tickRate * 10
end if
if worldTick < laneUntil then
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
stopped = 1
moveTick = worldTick
resumeTarget = 0
end if
end if
end if
end if
end if
end if
if retreat = 1 and restock = 0 and homeThreat = 0 then
if selfHp * 10 >= selfMaxHp * 8 and selfMana * 10 >= selfMaxMana * 4 and selfMana >= abilityManaCost(1) then
if recallHeroDistance > 100 and recallCreepDistance > 36 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil and worldTick - hurtTick >= tickRate * 2 then
if nCampId = 0 or nCampDistance > 64 then
laneSafe = 1
warnings = spellCount()
if warnings > 24 then
laneSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if spellCasterId(w) <> selfId and dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate then
laneSafe = 0
end if
w = w + 1
wend
if laneSafe = 1 then
retreat = 0
laneUntil = 0
resumeTarget = 0
moveTick = worldTick
end if
end if
end if
end if
end if
else
if selfClass = DemonHunter then
if retreat = 1 and restock = 0 and canShop() = 0 and homeThreat = 0 then
laneSafe = 1
warnings = spellCount()
if warnings > 24 then
laneSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if spellCasterId(w) <> selfId and dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate then
laneSafe = 0
end if
w = w + 1
wend
if laneSafe = 1 and recallHeroDistance > 100 and recallCreepDistance > 36 and dhNeutralDistance > 64 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
if selfHp * 100 >= selfMaxHp * laneAmount and selfMana * 100 >= selfMaxMana * laneCanHeal then
retreat = 0
laneUntil = 0
resumeTarget = 0
moveTick = worldTick
else
if worldTick < dhHealUntil then
if selfHp + (dhHealUntil - worldTick) * 120 \ (tickRate * 10) >= selfMaxHp * laneAmount \ 100 then
if laneUntil = 0 then
laneUntil = worldTick + tickRate * 10
end if
if worldTick < laneUntil then
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
stopped = 1
moveTick = worldTick
resumeTarget = 0
end if
end if
end if
end if
end if
end if
else
if selfClass = DruidWarden then
if worldTick >= tfShotDebtUntil then
if inBase = 1 then
laneUntil = 0
laneHealUntil = 0
end if
if inBase = 0 and retreat = 1 then
shoppingDue = 0
if empty > 0 then
if has11 = 0 and selfGold >= 110 then
shoppingDue = 1
end if
if has16 = 0 and selfGold >= 160 then
shoppingDue = 1
end if
if has18 = 0 and selfGold >= 180 then
shoppingDue = 1
end if
if has19 = 0 and selfGold >= 180 then
shoppingDue = 1
end if
end if
if shoppingDue = 1 then
restock = 1
end if
if restock = 0 then
laneSafe = 0
if recallHeroDistance > 100 and recallCreepDistance > 36 and towerDistance > 100 and towerAggro = 0 then
laneSafe = 1
warnings = spellCount()
if warnings > 24 then
laneSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if spellCasterId(w) <> selfId then
if dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate then
laneSafe = 0
end if
end if
w = w + 1
wend
end if
if laneSafe = 1 then
if selfHp * 100 >= selfMaxHp * laneAmount and selfMana * 100 >= selfMaxMana * laneCanHeal then
retreat = 0
laneUntil = 0
laneHealUntil = 0
resumeTarget = 0
moveTick = worldTick
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
else
laneCanHeal = 0
laneSlot = -1
laneAmount = 0
if worldTick < laneHealUntil then
laneCanHeal = 1
end if
s = 0
while s < 4
if abilityLevel(s) > 0 and abilityHeal(s) > 0 and abilityCharges(s) > 0 then
if selfMana >= abilityManaCost(s) and abilityCooldown(s) <= tickRate * 8 then
laneCanHeal = 1
if abilityCooldown(s) = 0 and abilityHeal(s) > laneAmount then
if selfMaxHp - selfHp >= abilityHeal(s) / 2 then
laneSlot = s
laneAmount = abilityHeal(s)
end if
end if
end if
end if
s = s + 1
wend
if laneCanHeal = 1 then
if laneUntil = 0 then
laneUntil = worldTick + tickRate * 12
end if
if worldTick < laneUntil then
if laneSlot >= 0 and selfSilenceTicks = 0 then
if castTarget(laneSlot, selfId) = 1 then
if laneHealUntil < worldTick + 18 then
laneHealUntil = worldTick + 18
end if
end if
end if
resumeTarget = 0
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
moveTick = worldTick
stopped = 1
end if
end if
end if
end if
end if
end if
end if
end if
end if
if retreat = 1 and restock = 0 and homeThreat = 0 then
if selfHp * 10 >= selfMaxHp * 8 and selfMana * 10 >= selfMaxMana * 4 and selfMana >= abilityManaCost(1) then
if recallHeroDistance > 100 and recallCreepDistance > 36 and towerDistance > 100 and towerAggro = 0 and worldTick >= tfShotDebtUntil and worldTick - hurtTick >= tickRate * 2 then
if nCampId = 0 or nCampDistance > 64 then
laneSafe = 1
warnings = spellCount()
if warnings > 24 then
laneSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if spellCasterId(w) <> selfId and dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate then
laneSafe = 0
end if
w = w + 1
wend
if laneSafe = 1 then
retreat = 0
laneUntil = 0
resumeTarget = 0
moveTick = worldTick
end if
end if
end if
end if
end if
end if
end if

' @rule R_replenish
if active = 1 and inBase = 1 then
if inOwnSpawn() = 1 then
if ((selfClass = DemonHunter and selfHp * 100 >= selfMaxHp * 85 and selfMana * 5 >= selfMaxMana) or (selfClass <> DemonHunter and selfHp * 10 >= selfMaxHp * 8 and selfMana * 10 >= selfMaxMana * 4 and selfMana >= abilityManaCost(1))) then
retreat = 0
else
retreat = 1
stopped = 1
if selfRootTicks = 0 and worldTick >= moveTick then
walkTo(spawnX, spawnY)
moveTick = worldTick + 24
end if
end if
end if
end if

' @rule R_coach_defend
if active = 1 then
if selfClass = VanguardKnight and selfSilenceTicks = 0 then
if abilityLevel(2) > 0 and abilityCooldown(2) = 0 and abilityCharges(2) > 0 then
if selfMana >= abilityManaCost(2) and selfMaxHp - selfHp >= 30 then
if towerAggro = 1 or recallHeroDistance <= 36 or selfHp * 100 < selfMaxHp * 50 then
castTarget(2, selfId)
end if
end if
end if
end if
s = 0
if recallHeroDistance > 64 and towerAggro = 0 and selfMana * 10 < selfMaxMana * 7 and selfMaxMana - selfMana >= 90 then
while s < 6
if itemId(s) = 22 and itemCount(s) > 0 and itemCooldown(s) = 0 then
useItem(s)
end if
s = s + 1
wend
end if
end if

' @rule R_channel_town_scroll
if active = 1 and stopped = 0 and retreat = 1 and inBase = 0 and portalReady = 1 then
if worldTick >= tfShotDebtUntil then
dx = selfX - spawnX
dy = selfY - spawnY
if dx * dx + dy * dy > 256 and homeAnchorDistance <= 400 then
if recallHeroDistance > 100 and recallCreepDistance > 36 and towerDistance > 100 then
if towerAggro = 0 and worldTick - hurtTick >= tickRate then
warningSafe = 1
warnings = spellCount()
if warnings > 24 then
warningSafe = 0
end if
w = 0
while w < warnings and w < 24
dx = spellX(w) - selfX
dy = spellY(w) - selfY
if dx * dx + dy * dy <= 64 and spellImpactTick(w) <= worldTick + tickRate * 3 then
warningSafe = 0
end if
w = w + 1
wend
if warningSafe = 1 then
if useItemAt(portalSlot, spawnX, spawnY) = 1 then
stopped = 1
portalBusy = 1
resumeTarget = 0
end if
end if
end if
end if
end if
end if
end if

' @rule R_walk_to_base
if active = 1 and stopped = 0 and retreat = 1 then
if selfRootTicks = 0 and worldTick >= moveTick then
walkTo(spawnX, spawnY)
moveTick = worldTick + 24
end if
stopped = 1
end if

' @rule R_home_portal
if active = 1 then
if stopped = 0 and retreat = 0 and inBase = 0 and portalReady = 1 and homeAnchorDistance <= 400 then
if ordinal <= 1 and homeEnemyHeroes > 0 and homeDefenders < 2 then
dx = selfX - homeX
dy = selfY - homeY
if dx * dx + dy * dy > 625 and selfHp * 100 >= selfMaxHp * 60 then
if selfPortalCooldown = 0 and threatDistance > 225 and worldTick - hurtTick > tickRate * 2 then
if useItemAt(portalSlot, homeX, homeY) = 1 then
stopped = 1
portalBusy = 1
end if
end if
end if
end if
end if
end if

'' @rule R_poison_objective_finish
if active = 1 and selfClass = Crossbowman and poisonSlot >= 0 then
if itemId(poisonSlot) = 4 then
tfFocus = 0
tfShots = 1000000
tfI = 0
while tfI < objectCount() and tfI < 128
tfKind = objectKind(tfI)
if tfKind = 1 or tfKind = 4 or tfKind = 5 then
if objectTeam(tfI) <> selfTeam and objectAlive(tfI) = 1 and objectHp(tfI) > 0 then
tfDx = objectX(tfI) - selfX
tfDy = objectY(tfI) - selfY
if tfDx * tfDx + tfDy * tfDy <= 100 then
if objectHp(tfI) <= itemCount(poisonSlot) * 35 and objectHp(tfI) < tfShots then
tfShots = objectHp(tfI)
tfFocus = objectId(tfI)
end if
end if
end if
end if
tfI = tfI + 1
wend
if tfFocus > 0 then
if attackTarget(tfFocus) = 1 then
tfUse = (tfShots + 34) \ 35
tfBurstUsed = 0
while tfBurstUsed < tfUse and itemId(poisonSlot) = 4 and itemCount(poisonSlot) > 0
if useItem(poisonSlot) = 1 then
tfBurstUsed = tfBurstUsed + 1
stopped = 1
else
tfUse = 0
end if
wend
end if
end if
end if
end if

' @rule R_glory_close
if active = 1 then
if active = 1 and stopped = 0 and retreat = 0 and selfRootTicks = 0 then
idxd = 0
hp = 0
idx = 0
objects = objectCount()
while idx < objects
kind = objectKind(idx)
if kind > 5 then
idx = objects
else
if objectTeam(idx) <> selfTeam and objectAlive(idx) = 1 then
x = objectX(idx) - selfX
y = objectY(idx) - selfY
if x * x + y * y <= 324 then
score = 0
if kind = 1 then
score = 3
end if
if kind = 4 then
x = objectX(idx) - enemyX
y = objectY(idx) - enemyY
if x * x + y * y <= 144 and (worldTick >= 19280 or objectTarget(idx) <> selfId or selfHp * 2 >= selfMaxHp) then
score = 2
end if
end if
if score > hp or (score = 2 and hp = 2 and objectHp(idx) < tfShots) then
hp = score
idxd = objectId(idx)
            tfShots = objectHp(idx)
end if
end if
end if
idx = idx + 1
end if
wend
if idxd > 0 then
attackTarget(idxd)
stopped = 1
end if
end if
end if

' @rule R_glory_siege
if active = 1 then
if selfClass = DemonHunter and stopped = 0 and retreat = 0 and selfRootTicks = 0 and recallHeroDistance > 8 * 8 and selfHp * 100 >= selfMaxHp * 40 then
id = 0
score = 324
idx = 0
objects = objectCount()
while idx < objects
kind = objectKind(idx)
if kind = 2 or kind = 3 or kind = 6 then
idx = objects
else
if (kind = 4 or kind = 5) and objectTeam(idx) <> selfTeam and objectAlive(idx) = 1 then
x = objectX(idx) - selfX
y = objectY(idx) - selfY
if x * x + y * y <= score then
score = x * x + y * y
id = objectId(idx)
hp = objectX(idx)
distance = objectY(idx)
end if
end if
idx = idx + 1
end if
wend
if id > 0 then
dy = 0
idx = 0
while idx < objects
kind = objectKind(idx)
if kind = 6 then
idx = objects
else
if kind = 3 and objectTeam(idx) = selfTeam then
x = objectX(idx) - hp
y = objectY(idx) - distance
if x * x + y * y <= 36 then
dy = dy + 1
end if
end if
idx = idx + 1
end if
wend
if dy >= 2 then
attackTarget(id)
stopped = 1
end if
end if
end if
end if

' @rule R_glory_group
if active = 1 then
if stopped = 0 and retreat = 0 and selfRootTicks = 0 and worldTick >= 19280 and worldTick >= moveTick then
dx = selfX - enemyX
dy = selfY - enemyY
distance = dx * dx + dy * dy
score = distance
id = 0
idx = 0
objects = objectCount()
while idx < objects
kind = objectKind(idx)
if kind = 3 or kind = 6 then
idx = objects
else
if kind = 2 and objectTeam(idx) = selfTeam and objectId(idx) <> selfId and objectAlive(idx) = 1 then
x = objectX(idx)
y = objectY(idx)
dx = x - enemyX
dy = y - enemyY
if dx * dx + dy * dy < score then
score = dx * dx + dy * dy
id = x
hp = y
end if
end if
idx = idx + 1
end if
wend
if id > 0 and score + 8 * 8 <= distance then
attackMove(id, hp)
moveTick = worldTick + 24
stopped = 1
end if
end if
end if

' @rule R_ari_farm_target
if active = 1 then
if worldTick < 19280 then
if selfClass <> DemonHunter or (homeThreat = 0 and worldTick >= tfShotDebtUntil and (bestId = 0 or (bestKind <> 1 and (bestKind <> 4 or bestHp > selfAttackDamage)))) then
if selfClass <> Berserker or (homeThreat = 0 and worldTick >= tfShotDebtUntil and (bestId = 0 or (bestKind <> 1 and (bestKind <> 4 or bestHp > selfAttackDamage)))) then
if selfClass = DemonHunter or selfClass = Berserker then
nPullStage = 0
if stopped = 0 and retreat = 0 and towerAggro = 0 and selfRootTicks = 0 then
if recallHeroDistance > 100 and recallCreepDistance > 36 and nCampId > 0 then
if (selfClass = DemonHunter and (selfHp * 100 >= selfMaxHp * 60 or (selfHp * 100 >= selfMaxHp * 45 and worldTick < dhHealUntil))) or (selfClass = Berserker and selfHp * 100 >= selfMaxHp * 70) then
bestId = nCampId
bestKind = 6
bestHp = nCampHp
bestX = nCampX
bestY = nCampY
bestDistance = nCampDistance
end if
end if
end if
end if
end if
end if
end if
end if

' @rule R_coach_cover_siege
if active = 1 then
if stopped = 0 and retreat = 0 and selfHp * 2 >= selfMaxHp and recallHeroDistance > 100 and tanks > 0 then
if towerId > 0 and towerTarget > 0 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
tfReach = (selfAttackRange \ 100) / (worldScale \ 100)
if towerDistance <= tfReach * tfReach then
score = 0
idx = 0
objects = objectCount()
while idx < objects and idx < 96 and score = 0
if objectId(idx) = towerTarget and objectKind(idx) = 3 and objectTeam(idx) = selfTeam then
score = 1
end if
idx = idx + 1
wend
if score = 1 then
bestId = towerId
bestKind = 4
bestHp = towerHp
bestX = towerX
bestY = towerY
bestDistance = towerDistance
end if
end if
end if
end if
end if

' @rule R_tower_safety
if active = 1 then
tfThreat = 0
tfThreatGap = 1000000
tfBlockTarget = 0
tfNearTowers = 0
tfBurstUsed = 0
tfI = 0
tfCount = objectCount()
while tfI < tfCount and tfI < 34
tfKind = objectKind(tfI)
if tfKind = 2 then
tfI = 34
else
if tfKind = 4 and objectTeam(tfI) <> selfTeam and objectHp(tfI) > 0 then
tfX = objectX(tfI)
tfY = objectY(tfI)
tfFocus = objectTarget(tfI)
tfDx = selfX - tfX
tfDy = selfY - tfY
if tfDx < 0 then
tfDx = -tfDx
end if
if tfDy < 0 then
tfDy = -tfDy
end if
if tfDx > 0 then
tfDx = tfDx - 1
end if
if tfDy > 0 then
tfDy = tfDy - 1
end if
tfGap = tfDx * tfDx + tfDy * tfDy
if tfGap <= 121 then
tfNearTowers = tfNearTowers + 1
end if
if tfFocus = selfId then
tfShotDebtUntil = worldTick + tickRate * 2
end if
if tfFocus = 0 or tfFocus = selfId then
if tfGap <= 100 and tfGap < tfThreatGap then
tfThreat = 1
tfThreatGap = tfGap
tfThreatX = tfX
tfThreatY = tfY
end if
if bestId > 0 then
tfDx = bestX - tfX
tfDy = bestY - tfY
if tfDx < 0 then
tfDx = -tfDx
end if
if tfDy < 0 then
tfDy = -tfDy
end if
if tfDx > 0 then
tfDx = tfDx - 1
end if
if tfDy > 0 then
tfDy = tfDy - 1
end if
if tfDx * tfDx + tfDy * tfDy <= 100 then
tfReach = (selfAttackRange \ 100) / 600
tfDx = bestX - selfX
tfDy = bestY - selfY
if tfDx < 0 then
tfDx = -tfDx
end if
if tfDy < 0 then
tfDy = -tfDy
end if
tfDx = tfDx + 1
tfDy = tfDy + 1
if bestKind = 4 or tfDx * tfDx + tfDy * tfDy > tfReach * tfReach then
tfBlockTarget = 1
end if
end if
end if
end if
end if
tfI = tfI + 1
end if
wend
if stopped = 0 and bestId > 0 and poisonSlot >= 0 then
if bestKind = 1 or bestKind = 4 or bestKind = 5 then
tfShots = (bestHp + 34) \ 35
tfUse = 0
if bestKind = 1 then
if selfHp * 100 >= selfMaxHp * 65 and enemyPower = 0 then
if bestHp <= itemCount(poisonSlot) * 35 + 2 * selfAttackDamage then
tfUse = tfShots
if tfUse > itemCount(poisonSlot) then
tfUse = itemCount(poisonSlot)
end if
end if
end if
else
if tfShots <= itemCount(poisonSlot) and enemyPower = 0 then
if selfHp > tfNearTowers * 180 + selfMaxHp * 40 \ 100 then
tfUse = tfShots
end if
end if
end if
if tfUse > 0 and tfUse <= 8 then
if attackTarget(bestId) = 1 then
while tfBurstUsed < tfUse and itemId(poisonSlot) = 4 and itemCount(poisonSlot) > 0
if useItem(poisonSlot) = 1 then
tfBurstUsed = tfBurstUsed + 1
else
tfUse = 0
end if
wend
end if
end if
end if
end if
if stopped = 0 and tfThreat = 1 then
tfDx = selfX - tfThreatX
tfDy = selfY - tfThreatY
tfAx = tfDx
tfAy = tfDy
if tfAx < 0 then
tfAx = -tfAx
end if
if tfAy < 0 then
tfAy = -tfAy
end if
tfNorm = tfAx
if tfAy > tfNorm then
tfNorm = tfAy
end if
if tfNorm = 0 then
tfDx = homeX - selfX
tfDy = homeY - selfY
tfNorm = 116
end if
if selfRootTicks = 0 then
walkTo(selfX + tfDx * 4 / tfNorm, selfY + tfDy * 4 / tfNorm)
moveTick = worldTick + 6
end if
resumeTarget = 0
stopped = 1
tfHeal = 0
while tfHeal < 4
if selfSilenceTicks = 0 and abilityLevel(tfHeal) > 0 and abilityCharges(tfHeal) > 0 then
if abilityCooldown(tfHeal) = 0 and abilityHeal(tfHeal) > 0 and selfMana >= abilityManaCost(tfHeal) then
if selfMaxHp - selfHp >= abilityHeal(tfHeal) / 2 then
castTarget(tfHeal, selfId)
end if
end if
end if
tfHeal = tfHeal + 1
wend
end if
if stopped = 0 and tfBlockTarget = 1 then
if selfRootTicks = 0 then
walkTo(selfX, selfY)
end if
resumeTarget = 0
stopped = 1
end if
end if

' @rule R_neutral_farm
if active = 1 then
if worldTick < 19280 then
if selfClass = Arcanist or selfClass = DruidWarden or selfClass = Warlock or selfClass = Lich then
nPullStage = 0
if stopped = 0 and retreat = 0 and restock = 0 and selfRootTicks = 0 then
if homeThreat = 0 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
if selfHp * 100 >= selfMaxHp * 70 and recallHeroDistance > 100 and recallCreepDistance > 36 then
if nCampId > 0 and (bestId = 0 or (bestKind <> 1 and (bestKind <> 4 or bestHp > selfAttackDamage))) then
bestId = nCampId
bestKind = 6
bestHp = nCampHp
bestX = nCampX
bestY = nCampY
bestDistance = nCampDistance
end if
end if
end if
end if
end if
if selfClass <> Arcanist and selfClass <> DruidWarden and selfClass <> Warlock and selfClass <> Lich then
if selfClass <> DemonHunter and selfClass <> Berserker then
if nPullStage > 0 then
if stopped = 1 or retreat = 1 or selfHp * 2 < selfMaxHp or selfRootTicks > 0 then
nPullStage = 0
nPullReady = worldTick + tickRate * 20
end if
end if
if stopped = 0 then
nSafe = 0
if retreat = 0 and towerAggro = 0 and enemyPower = 0 and selfRootTicks = 0 then
if selfHp * 2 >= selfMaxHp and (bestId = 0 or bestKind = 1 or bestKind = 4 or bestKind = 5) then
nSafe = 1
end if
end if
if nPullStage > 0 then
if nSafe = 0 or worldTick >= nPullUntil or worldTick - nLastSeen > tickRate * 2 or nHandoff = 1 then
nPullStage = 0
nPullReady = worldTick + tickRate * 20
end if
end if
if nPullStage = 0 and nSafe = 1 and nCampId > 0 and nWaveId > 0 and nWaveCount >= 2 then
if worldTick >= nPullReady and selfHp * 10 >= selfMaxHp * 7 and nCampTarget = 0 then
nCx = campX(nChosenCamp)
nCy = campY(nChosenCamp)
nDx = nWaveX - nCx
nDy = nWaveY - nCy
nGap = nDx * nDx + nDy * nDy
if nGap >= 16 and nGap <= 81 then
nPullStage = 1
nPullCamp = nChosenCamp
nPullMob = nCampId
nPullX = nCampX
nPullY = nCampY
nPullCenterX = nCx
nPullCenterY = nCy
nPullUntil = worldTick + tickRate * 15
nLastSeen = worldTick
end if
end if
end if
if nPullStage > 0 then
if nWaveId = 0 or nWaveCount < 2 then
nPullStage = 0
nPullReady = worldTick + tickRate * 20
else
if nOnUs = 1 then
nPullStage = 2
end if
nGoalX = nPullX
nGoalY = nPullY
if nPullStage = 2 then
nGoalX = nWaveX
nGoalY = nWaveY
nDx = nGoalX - nPullCenterX
nDy = nGoalY - nPullCenterY
if nDx * nDx >= nDy * nDy then
if nDx >= 0 then
nGoalX = nGoalX + 2
else
nGoalX = nGoalX - 2
end if
else
if nDy >= 0 then
nGoalY = nGoalY + 2
else
nGoalY = nGoalY - 2
end if
end if
end if
nDx = nGoalX - nPullCenterX
nDy = nGoalY - nPullCenterY
if nDx * nDx + nDy * nDy <= 100 then
if walkTo(nGoalX, nGoalY) = 1 then
stopped = 1
else
nPullStage = 0
nPullReady = worldTick + tickRate * 20
end if
else
nPullStage = 0
nPullReady = worldTick + tickRate * 20
end if
end if
end if
if stopped = 0 and nSafe = 1 and nCampId > 0 and selfHp * 10 >= selfMaxHp * 7 then
bestId = nCampId
bestKind = 6
bestHp = nCampHp
bestX = nCampX
bestY = nCampY
bestDistance = nCampDistance
end if
end if
end if
end if
end if
end if

' @rule R_xp_close
if active = 1 then
if stopped = 0 and selfClass = Crossbowman and bestKind = 3 and bestId > 0 then
if bestDistance > 25 and bestDistance <= 64 and enemyPower <= friendPower then
tfFocus = 0
tfI = 0
while tfI < objectCount() and tfI < 128 and tfFocus = 0
if objectId(tfI) = bestId then
tfFocus = tfI + 1
tfX = objectInfo(tfI, 0)
tfY = objectInfo(tfI, 1)
end if
tfI = tfI + 1
wend
tfThreat = 0
if tfFocus > 0 then
tfAx = selfInfo(0)
tfAy = selfInfo(1)
tfDx = tfAx - tfX
tfDy = tfAy - tfY
tfThreatGap = tfDx * tfDx + tfDy * tfDy
tfThreat = 1
end if

if tfThreat = 1 then
' Both basic attack range and nearby-creep XP range are six tiles.
' Approach the 5.5-tile boundary; do not cancel an attack already in range.
if tfThreatGap > 30.25 and tfThreatGap <= 81 and selfRootTicks = 0 then
if selfTarget = 0 or selfAttackCooldown = 0 or justHit = 1 then
tfReach = sqrt(tfThreatGap)
if walkTo(tfX + (tfAx - tfX) * 5.5 / tfReach + mapWidth / 2 - 0.5, tfY + (tfAy - tfY) * 5.5 / tfReach + mapHeight / 2 - 0.5) = 1 then
moveTick = worldTick + 6
stopped = 1
end if
end if
end if
else
if selfRootTicks = 0 then
walkTo((selfX + bestX) / 2, (selfY + bestY) / 2)
moveTick = worldTick + 6
end if
stopped = 1
end if
end if
end if
end if

' @rule R_dh_hero_burst
if active = 1 then
score = 0
if (selfClass = DemonHunter or selfClass = Arcanist or selfClass >= Lich) and selfHp > 0 and selfChannelTicks = 0 and selfSilenceTicks = 0 then
if coachHeroId > 0 and coachHeroHp > 0 and coachHeroDistance <= 36 then
score = 0
slot = 3
while slot >= 1 and score = 0
if slot = 3 or coachHeroDistance <= 25 then
if abilityLevel(slot) > 0 and abilityCharges(slot) > 0 and abilityCooldown(slot) = 0 then
if selfMana >= abilityManaCost(slot) then
score = castTarget(slot, coachHeroId)
end if
end if
end if
slot = slot - 1
wend
end if
end if
ccUseful = score
end if

' @rule R_combat
if active = 1 then
if stopped = 0 and bestId <> 0 then
if justHit = 1 and 1 = 1 then
if selfRootTicks = 0 then
walkTo(selfX + 0.25, selfY + 0.25)
end if
end if
if selfTarget <> bestId or justHit = 1 then
attackTarget(bestId)
end if
if selfClass = Ranger or selfClass = Crossbowman or selfClass = Arcanist or selfClass = Warlock or selfClass = Lich or selfClass = DemonHunter or selfClass = DruidWarden or selfClass = Berserker then
if bestKind = 2 and poisonSlot >= 0 then
burstDamage = 0
if selfClass = Ranger or selfClass = Crossbowman then
if selfTarget = bestId and selfAttackCooldown <= 1 and justHit = 0 then
burstDamage = selfAttackDamage
end if
end if
if selfClass = Crossbowman and tfBlocked = worldTick and p >= bestHp then
idx = 0
while idx < objectCount() and idx < 128
if objectId(idx) = bestId then
dx = objectInfo(idx, 0) - pick
dy = objectInfo(idx, 1) - pickScore
score = dx * c + dy * other
distance = dx * other - dy * c
if dx * dx + dy * dy <= 33.0625 and score > 0 then
if score * score >= 4 * distance * distance then
w = 0
warnings = spellCount()
while w < warnings and w < 128
if spellCasterId(w) = selfId and spellAbility(w) = 26 and spellImpactTick(w) = worldTick then
burstDamage = bestHp
end if
w = w + 1
wend
end if
end if
idx = 128
else
idx = idx + 1
end if
wend
end if
burstShots = (bestHp - burstDamage + 34) \ 35
if burstShots > 0 and burstShots <= itemCount(poisonSlot) then
burstUsed = 0
while burstUsed < burstShots and itemId(poisonSlot) = 4 and itemCount(poisonSlot) > 0
if useItem(poisonSlot) = 0 then
burstUsed = burstShots
else
burstUsed = burstUsed + 1
end if
wend
end if
end if
end if
dhBuy = 0
slot = 0
while slot < 4
if selfSilenceTicks = 0 and (slot <> ccSlot or bestKind <> 2) and abilityLevel(slot) > 0 and abilityCooldown(slot) = 0 then
if abilityCharges(slot) > 0 and selfMana >= abilityManaCost(slot) then
if abilityHeal(slot) > 0 then
if selfMaxHp - selfHp >= abilityHeal(slot) \ 2 then
castTarget(slot, selfId)
end if
else
if selfClass = DemonHunter and slot > 0 and dhBuy = 0 then
if retreat = 0 and homeThreat = 0 and towerAggro = 0 and worldTick >= tfShotDebtUntil then
if recallHeroDistance > 100 and selfHp * 100 >= selfMaxHp * 60 and bestDistance <= 36 then
if selfMana >= abilityManaCost(slot) + 28 and abilityDamage(slot) > 0 and bestHp > selfAttackDamage then
if (bestKind = 6 and (slot = 1 or (slot = 2 and bestHp > selfAttackDamage + abilityDamage(1)) or (slot = 3 and bestHp >= abilityDamage(slot) * 2))) or (bestKind = 3 and slot = 1 and bestHp <= abilityDamage(slot) + selfAttackDamage) then
if slot <> 1 or abilityCharges(1) > 1 or bestHp <= abilityDamage(1) then
dhBuy = castTarget(slot, bestId)
end if
end if
end if
end if
end if
end if
if abilityDamage(slot) > 0 and selfClass <> DemonHunter and ccUseful = 0 then
if bestKind <> 3 or bestHp <= abilityDamage(slot) then
if selfClass = Crossbowman and slot = 2 then
if castTarget(slot, bestId) = 1 then
tfBlocked = 0
idx = 0
while idx < objectCount() and idx < 128
if objectId(idx) = bestId then
pick = selfInfo(0)
pickScore = selfInfo(1)
c = objectInfo(idx, 0) - pick
other = objectInfo(idx, 1) - pickScore
p = abilityDamage(2)
tfBlocked = worldTick + 12
idx = 128
else
idx = idx + 1
end if
wend
end if
else
castTarget(slot, bestId)
end if
end if
end if
end if
end if
end if
slot = slot + 1
wend
stopped = 1
end if
end if

' @rule R_camp_scout
if active = 1 then
if worldTick < 19280 then
if selfClass = DemonHunter or selfClass = Berserker then
if scoutUntil > 0 then
if worldTick >= scoutUntil or nCampId > 0 or (bestId > 0 and bestDistance <= 144) or retreat = 1 or homeThreat > 0 then
scoutUntil = 0
scoutReady = worldTick + tickRate * 12
end if
end if
if stopped = 0 and retreat = 0 and restock = 0 and canShop() = 0 and selfRootTicks = 0 then
if selfTarget = 0 and bestId = 0 and nCampId = 0 and homeThreat = 0 and towerAggro = 0 then
if recallHeroDistance > 100 and recallCreepDistance > 36 and worldTick >= tfShotDebtUntil and selfHp * 100 >= selfMaxHp * 75 then
if scoutUntil = 0 and worldTick >= scoutReady then
nCampScore = 1000000
s = 0
while s < campCount() and s < 32
if (worldTick >= harvestUntil or s + 1 <> harvestCamp) and (selfLevel >= 1 + (campTier(s) - 1) * 3 or (selfClass = DemonHunter and selfLevel >= 1 + (campTier(s) - 1) * 2)) and (selfClass <> DemonHunter or s + 1 <> nPullCamp or worldTick >= nPullReady) then
nCx = campX(s)
nCy = campY(s)
dx = nCx - selfX
dy = nCy - selfY
nGap = dx * dx + dy * dy
if nGap > 16 and (nGap <= 196 or (selfClass = DemonHunter and nGap <= 324)) and nGap < nCampScore then
dx = nCx - homeX
dy = nCy - homeY
score = dx * dx + dy * dy
dx = nCx - (mapWidth - 1 - homeX)
dy = nCy - (mapHeight - 1 - homeY)
if score <= dx * dx + dy * dy then
nCampScore = nGap
scoutCamp = s
scoutUntil = worldTick + tickRate * 8
end if
end if
end if
s = s + 1
wend
if selfClass = DemonHunter and scoutUntil > worldTick then
nPullCamp = scoutCamp + 1
nPullReady = worldTick + tickRate * 60
end if
scoutReady = worldTick + tickRate * 12
end if
if scoutUntil > worldTick then
nCx = campX(scoutCamp)
nCy = campY(scoutCamp)
dx = nCx - selfX
dy = nCy - selfY
if dx * dx + dy * dy <= 16 then
scoutUntil = 0
scoutReady = worldTick + tickRate * 12
else
if worldTick >= moveTick then
if walkTo(nCx, nCy) = 1 then
moveTick = worldTick + 12
stopped = 1
else
scoutUntil = 0
scoutReady = worldTick + tickRate * 12
end if
else
stopped = 1
end if
end if
end if
end if
end if
end if
end if
end if
end if

' @rule R_advance
if active = 1 then
if stopped = 0 then
goalX = mapWidth \ 2
goalY = mapHeight \ 2
if lane = 0 then
goalX = mapWidth \ 10
goalY = mapHeight \ 10
end if
if lane = 2 then
goalX = mapWidth * 9 \ 10
goalY = mapHeight * 9 \ 10
end if
if selfTeam = 1 and ordinal = 0 and laneChanged = 0 then
if selfClass = Ranger or selfClass = Crossbowman then
goalX = mapWidth \ 2
goalY = mapHeight \ 2
end if
end if
dx = selfX - goalX
dy = selfY - goalY
if dx * dx + dy * dy <= 64 then
crossed = 1
end if
if crossed = 1 then
goalX = enemyX
goalY = enemyY
end if
dx = selfX - homeX
dy = selfY - homeY
if homeThreat > 0 and dx * dx + dy * dy < 400 then
goalX = homeX
goalY = homeY
end if
if inBase = 1 and portalReady = 1 and (portalCount >= 2 or (selfClass = DemonHunter and gearCount = 3 and portalCount = 1 and selfHp * 10 >= selfMaxHp * 8 and selfMana * 10 >= selfMaxMana * 4)) then
if retreat = 0 and threatDistance > 144 and forwardScore < 1000000 then
dx = selfX - forwardX
dy = selfY - forwardY
if dx * dx + dy * dy > 400 then
if useItemAt(portalSlot, forwardX, forwardY) = 1 then
stopped = 1
portalBusy = 1
end if
end if
end if
end if
if stopped = 0 and selfRootTicks = 0 and worldTick >= moveTick then
attackMove(goalX, goalY)
moveTick = worldTick + 24
end if
end if
end if
