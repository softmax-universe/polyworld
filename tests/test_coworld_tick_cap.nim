## The Coworld tick-limit check: default cap preserved, lifted by the host.
import std/os
import polyworld/[configs, coworld]

# Existing games keep the 28,800-tick cap by default.
doAssert tickLimitsValid(28_800, 480)
doAssert not tickLimitsValid(28_801, 480)
doAssert not tickLimitsValid(0, 480)
doAssert not tickLimitsValid(100, 0)
doAssert tickCap("") == DefaultDurationTicks
doAssert tickCap("garbage") == DefaultDurationTicks

# A host (Terraform) raises the cap, or disables it with 0.
doAssert tickCap("100000") == 100_000
doAssert tickLimitsValid(100_000, 480, tickCap("100000"))
doAssert not tickLimitsValid(100_001, 480, tickCap("100000"))
doAssert tickCap("0") == 0
doAssert tickLimitsValid(1_000_000, 480, tickCap("0"))
doAssert not tickLimitsValid(0, 480, tickCap("0"))
# Exercise the same environment-reading check used by coworldOptions.
# Restore the caller's environment even when an assertion fails.
block:
  const capEnv = "POLYWORLD_MAX_TICKS_CAP"
  let wasSet = existsEnv(capEnv)
  let previous = getEnv(capEnv)
  defer:
    if wasSet: putEnv(capEnv, previous)
    else: delEnv(capEnv)

  template rejects(ticks, interval: int32) =
    block:
      var rejected = false
      try:
        checkTickLimits(GameConfig(maxTicks: ticks, spawnIntervalTicks: interval))
      except CoworldError as error:
        doAssert error.msg == "Coworld tick limits are invalid"
        rejected = true
      doAssert rejected

  delEnv(capEnv)
  checkTickLimits(GameConfig(maxTicks: 28_800, spawnIntervalTicks: 480))
  rejects(28_801, 480)
  putEnv(capEnv, "100000")
  checkTickLimits(GameConfig(maxTicks: 100_000, spawnIntervalTicks: 480))
  rejects(100_001, 480)
  putEnv(capEnv, "0")
  checkTickLimits(GameConfig(maxTicks: 1_000_000, spawnIntervalTicks: 480))
  rejects(0, 480)
  rejects(100, 0)
  putEnv(capEnv, "garbage")
  rejects(28_801, 480)
echo "Coworld tick cap is configurable (including environment wiring)"
