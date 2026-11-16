import std/math

const HudDaySeconds* = 300'i32
  ## Simulation seconds in one in-game day, starting at 08:00.

proc hudDayTicks*(tickRate: int32): int32 =
  ## Ticks in one in-game day at this simulation rate.
  tickRate * HudDaySeconds

proc clockMinutes(tick, tickRate: int32): int =
  ## Absolute spectator minutes since 8:00 on day 1.
  8 * 60 + int(tick) * 24 * 60 div int(hudDayTicks(tickRate))

proc clockHour*(tick, tickRate: int32): float32 =
  ## The accelerated clock in hours, 0 ..< 24 with a fraction.
  float32(clockMinutes(tick, tickRate) mod (24 * 60)) / 60

proc clockHour*(tick: float32, tickRate: int32): float32 =
  ## Interpolates the same clock between simulation ticks for smooth lighting.
  var minutes =
    8.0'f * 60.0'f +
    tick * 24.0'f * 60.0'f / float32(hudDayTicks(tickRate))
  minutes = minutes - float32(24 * 60) * floor(minutes / float32(24 * 60))
  minutes / 60.0'f

proc hudClock*(
  tick, tickRate: int32
): tuple[day, hour, minute: int] =
  ## Converts simulation ticks into day, hour, and minute.
  let
    totalMinutes = clockMinutes(tick, tickRate)
    minuteOfDay = totalMinutes mod (24 * 60)
  result.day = totalMinutes div (24 * 60) + 1
  result.hour = minuteOfDay div 60
  result.minute = minuteOfDay mod 60

proc isNight*(hour: float32): bool {.raises: [].} =
  ## Matches the shared arena's night hours from 18:00 until 06:00.
  let wrapped = ((hour mod 24) + 24) mod 24
  wrapped < 6 or wrapped >= 18
