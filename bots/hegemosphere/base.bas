REM One army per slot. All actions use ordinary, validated player commands.
IF worldTick() MOD 20 <> 0 THEN END
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
    IF objectKind(id) = tankKind() OR objectKind(id) = scoutKind() THEN
      ignored = attackMove(id, mapSize() - 1 - homeX, mapSize() - 1 - homeY)
    END IF
  END IF
NEXT i
END
