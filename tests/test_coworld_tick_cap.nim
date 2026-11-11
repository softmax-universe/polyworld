## The Coworld tick-limit check: default cap preserved, lifted by the host.
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
echo "Coworld tick cap is configurable"
