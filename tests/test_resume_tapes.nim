## Reports replay contents for the headless resume integration test.
import std/[json, os]
import fixxy
import ../games/gods_of_the_arena/replays as gota
import ../games/call_to_adventure/replays as cta
import ../games/light_vs_dark/replays as lvd
import ../games/heartleaf/replays as heartleaf
import ../games/cac/src/core/replays as cac

proc `%`(value: Fixed): JsonNode =
  ## Preserves fixed-point action coordinates as their exact raw integers.
  %int32(value)

template inspect(data: untyped) =
  let tape = data
  echo %*{"hashes": tape.hashes, "actions": tape.actions}

let arguments = commandLineParams()
doAssert arguments.len == 2
case arguments[0]
of "gota":
  let tape = gota.loadReplay(arguments[1])
  echo %*{
    "hashes": tape.hashes,
    "actions": tape.actions,
    "heroes": tape.header.setup.heroes,
    "movementKinds": [gota.ActionWalkTo, gota.ActionAttackTarget,
      gota.ActionAttackMove]
  }
of "cta": inspect(cta.loadReplay(arguments[1]))
of "lvd": inspect(lvd.loadReplay(arguments[1]))
of "heartleaf": inspect(heartleaf.loadReplay(arguments[1]))
of "cac": inspect(cac.loadReplay(arguments[1]))
else: doAssert false, "Unknown resume fixture game"
