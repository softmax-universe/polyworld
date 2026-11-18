REM One army per slot. All actions use ordinary, validated player commands.
DIM depositRank(7)
DIM depositSiteX(7)
DIM depositSiteY(7)
DIM depositAfter(1)
IF worldTick() MOD 20 <> 0 THEN END
mapWidth = mapSize()
depositChecks = 0
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectEnemy(id) THEN
    FOR j = 0 TO objectCount() - 1
      own = objectId(j)
      IF objectOwned(own) AND objectKind(own) = tankKind() THEN
        ignored = attack(own, id)
      END IF
    NEXT j
  END IF
NEXT i
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectOwned(id) AND objectKind(id) = centerKind() THEN
    homeX = objectX(id)
    homeY = objectY(id)
  END IF
NEXT i
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectOwned(id) AND objectIdle(id) THEN
    IF objectKind(id) = factoryKind() THEN
      ignored = build(id, tankKind(), 0, 0)
    END IF
    IF objectKind(id) = builderKind() THEN
      FOR resource = 0 TO 1
        kind = mineKind()
        IF resource = 1 THEN kind = refineryKind()
        IF ownCount(kind) = 0 THEN
          CALL nearbyDeposit(id, resource, kind)
          IF depositPlaced THEN END
        END IF
      NEXT resource
      kind = powerKind()
      IF ownCount(kind) > 0 THEN kind = factoryKind()
      IF ownCount(kind) = 0 THEN
        FOR dx = -8 TO 8 STEP 4
          FOR dy = -8 TO 8 STEP 4
            x = homeX + dx
            y = homeY + dy
            IF canBuild(id, kind, x, y) THEN
              ignored = build(id, kind, x, y)
              END
            END IF
          NEXT dy
        NEXT dx
      END IF
    END IF
    IF objectKind(id) = tankKind() OR objectKind(id) = scoutKind() THEN
      ignored = attackMove(id, mapSize() - 1 - homeX, mapSize() - 1 - homeY)
    END IF
  END IF
NEXT i
END

SUB nearbyDeposit(builder, resourceType, buildingKind)
  REM Resource delivery requires an unwrapped distance of at most 20 tiles.
  depositPlaced = 0
  IF depositChecks >= 8 THEN EXIT SUB
  depositCandidates = 0
  depositTotal = depositCount(resourceType)
  IF depositTotal > 128 THEN depositTotal = 128
  FOR depositIndex = 0 TO depositTotal - 1
    depositXValue = depositX(resourceType, depositIndex)
    depositYValue = depositY(resourceType, depositIndex)
    depositDx = depositXValue - homeX
    depositDy = depositYValue - homeY
    IF depositDx < 0 THEN depositDx = -depositDx
    IF depositDy < 0 THEN depositDy = -depositDy
    IF depositDx <= 18 AND depositDy <= 18 THEN
      IF depositDx > mapWidth \ 2 THEN depositDx = mapWidth - depositDx
      IF depositDy > mapWidth \ 2 THEN depositDy = mapWidth - depositDy
      depositScore = (depositDx * depositDx + depositDy * depositDy) * mapWidth * mapWidth + depositXValue * mapWidth + depositYValue
      IF depositScore > depositAfter(resourceType) THEN
        IF depositCandidates < 8 OR depositScore < depositRank(7) THEN
          depositPosition = depositCandidates
          IF depositPosition > 7 THEN depositPosition = 7
          DO WHILE depositPosition > 0
            IF depositRank(depositPosition - 1) <= depositScore THEN EXIT DO
            depositRank(depositPosition) = depositRank(depositPosition - 1)
            depositSiteX(depositPosition) = depositSiteX(depositPosition - 1)
            depositSiteY(depositPosition) = depositSiteY(depositPosition - 1)
            depositPosition = depositPosition - 1
          LOOP
          depositRank(depositPosition) = depositScore
          depositSiteX(depositPosition) = depositXValue
          depositSiteY(depositPosition) = depositYValue
          IF depositCandidates < 8 THEN depositCandidates = depositCandidates + 1
        END IF
      END IF
    END IF
  NEXT depositIndex
  FOR depositCandidate = 0 TO depositCandidates - 1
    IF depositChecks >= 8 THEN EXIT SUB
    depositChecks = depositChecks + 1
    IF canBuild(builder, buildingKind, depositSiteX(depositCandidate), depositSiteY(depositCandidate)) THEN
      depositPlaced = build(builder, buildingKind, depositSiteX(depositCandidate), depositSiteY(depositCandidate))
      IF depositPlaced THEN depositAfter(resourceType) = 0
      EXIT SUB
    END IF
    depositAfter(resourceType) = depositRank(depositCandidate)
  NEXT depositCandidate
  IF depositCandidates < 8 THEN depositAfter(resourceType) = 0
END SUB
