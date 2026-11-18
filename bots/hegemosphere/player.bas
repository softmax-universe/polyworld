REM Two mines, two refineries and two factories sustain a tank offensive.
strategy = 2
desiredBuilders = 3
REM Only ordinary fog-limited observations and player commands are used.
DIM lastX(8191)
DIM lastY(8191)
DIM waypoint(8191)
DIM lastTarget(8191)
DIM buildOrderKind(8191)
DIM buildOrderX(8191)
DIM buildOrderY(8191)
DIM buildProgressTick(8191)
DIM foeId(63)
DIM foeX(63)
DIM foeY(63)
DIM routeStarted(8191)
DIM engagementSet(8191)
DIM lastRefuelTick(8191)
DIM lastAttackTick(8191)
DIM lastMovementTick(8191)
IF worldTick() MOD 10 <> 0 THEN END
mapWidth = mapSize()
IF initialized = 0 THEN
  initialized = 1
  FOR k = 1 TO typeCount()
    IF strEq(typeName(k), strNew("Research")) THEN researchKind = k
    IF strEq(typeName(k), strNew("Defense Cannon")) THEN cannonKind = k
    IF strEq(typeName(k), strNew("Transport")) THEN transportKind = k
  NEXT k
  PRINT "strategy", strategy, "seat", selfPlayer()
END IF
home = 0
enemy = 0
foeCount = 0
bestThreat = 1000000
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectOwned(id) AND objectKind(id) = centerKind() AND home = 0 THEN
    home = id
    homeX = objectX(id)
    homeY = objectY(id)
  END IF
NEXT i
IF home = 0 THEN END
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectEnemy(id) THEN
    IF foeCount < 64 THEN
      foeId(foeCount) = id
      foeX(foeCount) = objectX(id)
      foeY(foeCount) = objectY(id)
      foeCount = foeCount + 1
    END IF
    dx = objectX(id) - homeX
    dy = objectY(id) - homeY
    IF dx < 0 THEN dx = -dx
    IF dy < 0 THEN dy = -dy
    IF dx > mapWidth \ 2 THEN dx = mapWidth - dx
    IF dy > mapWidth \ 2 THEN dy = mapWidth - dy
    distance = dx + dy
    IF objectKind(id) = centerKind() THEN
      enemyHomeX = objectX(id)
      enemyHomeY = objectY(id)
      foundEnemyHome = 1
    END IF
    IF distance < bestThreat THEN
      enemy = id
      bestThreat = distance
    END IF
  END IF
NEXT i
IF worldTick() MOD 300 = 0 THEN
  PRINT "tick", worldTick(), "iron", objectIron(home), "fuel", objectFuel(home), "mines", ownCount(mineKind()), "refineries", ownCount(refineryKind()), "factories", ownCount(factoryKind()), "tanks", ownCount(tankKind())
  parameters$ = "{""strategy"":" + STR$(strategy) + ",""iron"":" + STR$(objectIron(home)) + ",""fuel"":" + STR$(objectFuel(home)) + ",""tanks"":" + STR$(ownCount(tankKind())) + "}"
  ignored = ANNOTATE(worldTick(), "metric", "economy", parameters$)
END IF
buildSent = 0
combatGroups = (ownCount(tankKind()) + ownCount(scoutKind()) + 11) \ 12
IF combatGroups < 1 THEN combatGroups = 1
combatGroup = (worldTick() \ 10) MOD combatGroups
combatOrdinal = 0
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectOwned(id) THEN
    kind = objectKind(id)
    IF kind = builderKind() THEN CALL recoverBuilder(id)
    IF kind = builderKind() AND objectIdle(id) AND buildSent = 0 THEN CALL construct(id)
    IF kind = factoryKind() AND objectIdle(id) THEN
      product = tankKind()
      IF ownCount(tankKind()) >= 2 AND ownCount(transportKind) = 0 THEN product = transportKind
      IF strategy = 1 AND ownCount(scoutKind()) < 6 THEN product = scoutKind()
      IF objectIron(home) >= typeCost(product) + reserve AND canBuild(id, product, 0, 0) THEN
        ignored = build(id, product, 0, 0)
      END IF
    END IF
    IF kind = researchKind AND objectIdle(id) AND strategy = 3 THEN
      FOR technology = 0 TO researchCount() - 1
        IF researchAvailable(technology) THEN
          ignored = research(id, technology)
          PRINT "research-order", worldTick(), technology, ignored
          EXIT FOR
        END IF
      NEXT technology
    END IF
    IF kind = tankKind() OR kind = scoutKind() THEN
      IF combatOrdinal MOD combatGroups = combatGroup THEN CALL army(id, kind)
      combatOrdinal = combatOrdinal + 1
    END IF
    IF kind = transportKind THEN CALL logistics(id)
    IF kind = centerKind() AND objectIdle(id) AND ownCount(builderKind()) < desiredBuilders AND objectIron(home) > 500 THEN
      ignored = build(id, builderKind(), 0, 0)
    END IF
  END IF
NEXT i
END

SUB construct(builder)
  desired = 0
  resource = -1
  reserve = 0
  IF ownCount(mineKind()) = 0 THEN
    desired = mineKind()
    resource = 0
  ELSEIF ownCount(refineryKind()) = 0 THEN
    desired = refineryKind()
    resource = 1
  ELSEIF ownCount(powerKind()) = 0 THEN
    desired = powerKind()
  ELSEIF ownCount(factoryKind()) = 0 THEN
    desired = factoryKind()
  ELSEIF strategy = 2 AND ownCount(factoryKind()) < 2 THEN
    desired = factoryKind()
  ELSEIF strategy = 2 AND ownCount(mineKind()) < 2 THEN
    desired = mineKind()
    resource = 0
  ELSEIF strategy = 2 AND ownCount(refineryKind()) < 2 THEN
    desired = refineryKind()
    resource = 1
  ELSEIF ownCount(centerKind()) = 1 AND ownCount(tankKind()) >= 5 THEN
    desired = centerKind()
  ELSEIF strategy = 3 AND ownCount(researchKind) = 0 THEN
    desired = researchKind
  ELSEIF strategy = 3 AND typeUnlocked(cannonKind) AND ownCount(cannonKind) < 2 THEN
    desired = cannonKind
  END IF
  IF desired = 0 THEN EXIT SUB
  reserve = typeCost(desired)
  IF objectIron(home) < reserve OR objectFuel(home) < typeFuelCost(desired) THEN EXIT SUB
  IF resource >= 0 THEN
    count = depositCount(resource)
    IF count = 0 THEN EXIT SUB
    FOR attempt = 0 TO 7
      index = depositCursor MOD count
      depositCursor = depositCursor + 1
      x = depositX(resource, index)
      y = depositY(resource, index)
      dx = x - homeX
      dy = y - homeY
      IF dx < 0 THEN dx = -dx
      IF dy < 0 THEN dy = -dy
      IF dx <= 18 AND dy <= 18 AND canBuild(builder, desired, x, y) THEN
        buildSent = build(builder, desired, x, y)
        CALL rememberBuild(builder)
        PRINT "build-order", worldTick(), desired, x, y, buildSent
        EXIT SUB
      END IF
    NEXT attempt
  ELSE
    FOR attempt = 0 TO 7
      width = 9
      IF desired = centerKind() THEN width = 17
      index = siteCursor MOD (width * width)
      siteCursor = siteCursor + 1
      x = homeX + (index MOD width - width \ 2) * 2
      y = homeY + ((index \ width) MOD width - width \ 2) * 2
      dx = x - homeX
      dy = y - homeY
      IF dx < 0 THEN dx = -dx
      IF dy < 0 THEN dy = -dy
      usefulSite = 1
      IF desired = centerKind() AND dx < 12 AND dy < 12 THEN usefulSite = 0
      IF usefulSite AND canBuild(builder, desired, x, y) THEN
        buildSent = build(builder, desired, x, y)
        CALL rememberBuild(builder)
        PRINT "build-order", worldTick(), desired, x, y, buildSent
        EXIT SUB
      END IF
    NEXT attempt
  END IF
END SUB

SUB rememberBuild(builder)
  IF builder > 8191 THEN EXIT SUB
  buildOrderKind(builder) = desired
  buildOrderX(builder) = x
  buildOrderY(builder) = y
  buildProgressTick(builder) = worldTick()
  lastX(builder) = objectX(builder)
  lastY(builder) = objectY(builder)
END SUB

SUB recoverBuilder(builder)
  IF builder > 8191 THEN EXIT SUB
  IF buildOrderKind(builder) = 0 OR objectIdle(builder) THEN EXIT SUB
  IF lastX(builder) <> objectX(builder) OR lastY(builder) <> objectY(builder) THEN
    lastX(builder) = objectX(builder)
    lastY(builder) = objectY(builder)
    buildProgressTick(builder) = worldTick()
  END IF
  IF worldTick() - buildProgressTick(builder) < 150 THEN EXIT SUB
  FOR inspected = 0 TO objectCount() - 1
    foundation = objectId(inspected)
    IF objectOwned(foundation) AND objectKind(foundation) = buildOrderKind(builder) THEN
      IF objectX(foundation) = buildOrderX(builder) AND objectY(foundation) = buildOrderY(builder) THEN EXIT SUB
    END IF
  NEXT inspected
  ignored = cancel(builder)
  PRINT "retry-blocked-builder", worldTick(), builder, ignored
  buildOrderKind(builder) = 0
END SUB

SUB logistics(transport)
  IF transport > 8191 THEN EXIT SUB
  supplyTarget = -1
  FOR supplyIndex = 0 TO objectCount() - 1
    candidate = objectId(supplyIndex)
    IF objectOwned(candidate) AND objectKind(candidate) = centerKind() AND candidate <> home AND objectHp(candidate) > 1 THEN
      supplyTarget = candidate
      EXIT FOR
    END IF
  NEXT supplyIndex
  IF routeStarted(transport) <> supplyTarget THEN
    x = homeX + 16
    y = homeY + 10
    IF x >= mapWidth THEN x = homeX - 16
    IF y >= mapWidth THEN y = homeY - 10
    IF supplyTarget > 0 THEN
      x = objectX(supplyTarget)
      y = objectY(supplyTarget)
    END IF
    ignored = route(transport, homeX, homeY, x, y)
    routeStarted(transport) = supplyTarget
    PRINT "supply-route", worldTick(), transport, x, y, supplyTarget, ignored
  END IF
  dx = objectX(transport) - homeX
  dy = objectY(transport) - homeY
  IF dx < 0 THEN dx = -dx
  IF dy < 0 THEN dy = -dy
  IF dx <= 5 AND dy <= 5 AND objectFuel(transport) < 300 AND objectFuel(home) > 800 THEN
    ignored = transfer(home, transport, 0, 200)
    PRINT "supply-fuel", worldTick(), transport, ignored
  END IF
END SUB

SUB army(unit, unitKind)
  IF unit > 8191 THEN EXIT SUB
  target = 0
  nearest = mapWidth * 2
  unitX = objectX(unit)
  unitY = objectY(unit)
  FOR foe = 0 TO foeCount - 1
    dx = foeX(foe) - unitX
    dy = foeY(foe) - unitY
    IF dx < 0 THEN dx = -dx
    IF dy < 0 THEN dy = -dy
    IF dx > mapWidth \ 2 THEN dx = mapWidth - dx
    IF dy > mapWidth \ 2 THEN dy = mapWidth - dy
    distance = dx
    IF dy > distance THEN distance = dy
    IF distance < nearest THEN
      nearest = distance
      target = foeId(foe)
    END IF
  NEXT foe
  IF engagementSet(unit) = 0 THEN
    ignored = engagement(unit, 2)
    IF ignored THEN engagementSet(unit) = 1
  END IF
  IF objectFuel(unit) < 5 THEN
    IF lastRefuelTick(unit) = 0 OR worldTick() - lastRefuelTick(unit) >= 100 THEN
      ignored = refuel(unit)
      IF ignored THEN lastRefuelTick(unit) = worldTick()
    END IF
  END IF
  IF target > 0 THEN
    IF lastTarget(unit) <> target OR worldTick() - lastAttackTick(unit) >= 100 THEN
      ignored = attack(unit, target)
      IF ignored THEN
        lastTarget(unit) = target
        lastAttackTick(unit) = worldTick()
      END IF
    END IF
    EXIT SUB
  END IF
  stuck = 0
  IF worldTick() - lastMovementTick(unit) >= 150 THEN
    IF lastX(unit) = objectX(unit) AND lastY(unit) = objectY(unit) THEN stuck = 1
    lastX(unit) = objectX(unit)
    lastY(unit) = objectY(unit)
    lastMovementTick(unit) = worldTick()
  END IF
  IF objectIdle(unit) OR stuck THEN
    IF strategy = 3 AND unitKind = tankKind() AND ownCount(tankKind()) < 5 THEN EXIT SUB
    waypoint(unit) = waypoint(unit) + 1
    IF foundEnemyHome AND stuck = 0 THEN
      x = enemyHomeX
      y = enemyHomeY
    ELSEIF waypoint(unit) = 1 THEN
      x = mapWidth - 1 - homeX
      y = mapWidth - 1 - homeY
    ELSE
      x = (waypoint(unit) * 17 + unit * 7 + homeX) MOD mapWidth
      y = (waypoint(unit) * 11 + unit * 13 + homeY) MOD mapWidth
    END IF
    ignored = attackMove(unit, x, y)
    lastTarget(unit) = 0
  END IF
END SUB

