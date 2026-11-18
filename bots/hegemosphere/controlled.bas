REM Build the local economy before issuing one combat intent per unit.
DIM foeId(63)
DIM foeX(63)
DIM foeY(63)
IF worldTick() MOD 20 <> 0 THEN END
mapWidth = mapSize()
foeCount = 0
combatCount = 0
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectEnemy(id) AND foeCount < 64 THEN
    foeId(foeCount) = id
    foeX(foeCount) = objectX(id)
    foeY(foeCount) = objectY(id)
    foeCount = foeCount + 1
  END IF
  IF objectOwned(id) THEN
    combatKind = objectKind(id)
    IF combatKind = centerKind() THEN
      homeX = objectX(id)
      homeY = objectY(id)
    END IF
    IF combatKind = tankKind() OR combatKind = scoutKind() THEN
      combatCount = combatCount + 1
    END IF
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
          FOR d = 0 TO depositCount(resource) - 1
            x = depositX(resource, d)
            y = depositY(resource, d)
            IF canBuild(id, kind, x, y) THEN
              ignored = build(id, kind, x, y)
              END
            END IF
          NEXT d
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
  END IF
NEXT i
IF combatCount = 0 THEN END
combatGroups = (combatCount + 11) \ 12
combatGroup = (worldTick() \ 20) MOD combatGroups
combatOrdinal = 0
FOR i = 0 TO objectCount() - 1
  id = objectId(i)
  IF objectOwned(id) THEN
    combatKind = objectKind(id)
    IF combatKind = tankKind() OR combatKind = scoutKind() THEN
      IF combatOrdinal MOD combatGroups = combatGroup THEN
        combatTarget = 0
        combatDistance = mapWidth * 2
        combatX = objectX(id)
        combatY = objectY(id)
        FOR foe = 0 TO foeCount - 1
          combatDx = foeX(foe) - combatX
          combatDy = foeY(foe) - combatY
          IF combatDx < 0 THEN combatDx = -combatDx
          IF combatDy < 0 THEN combatDy = -combatDy
          IF combatDx > mapWidth \ 2 THEN combatDx = mapWidth - combatDx
          IF combatDy > mapWidth \ 2 THEN combatDy = mapWidth - combatDy
          distance = combatDx
          IF combatDy > distance THEN distance = combatDy
          IF distance < combatDistance THEN
            combatDistance = distance
            combatTarget = foeId(foe)
          END IF
        NEXT foe
        IF combatTarget > 0 THEN
          ignored = attack(id, combatTarget)
        ELSEIF objectIdle(id) THEN
          ignored = attackMove(id, mapWidth - 1 - homeX, mapWidth - 1 - homeY)
        END IF
      END IF
      combatOrdinal = combatOrdinal + 1
    END IF
  END IF
NEXT i
END
