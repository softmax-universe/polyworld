## Reports late arrivals and displaced destinations in the traffic workloads.
import trafficfixture

for workload in [(100, "opposing"), (300, "crossing")]:
  let
    fixture = trafficFixture(workload[0], workload[1])
    w = fixture.world
  var
    ever = newSeq[bool](w.units.len)
    stalled = newSeq[int](w.units.len)
    previous = fixture.starts
  for tick in 0 ..< 900:
    w.tickWorld(nil)
    for i, unit in w.units:
      if length(unit.body.pos - fixture.goals[i]) <= 0.4'fx:
        ever[i] = true
      if tick >= 600 and previous[i] == unit.body.pos:
        inc stalled[i]
      previous[i] = unit.body.pos
  var completed, displaced, active, failed: int
  echo "WORKLOAD ", workload
  for i, unit in w.units:
    if length(unit.body.pos - fixture.goals[i]) <= 0.4'fx:
      inc completed
      continue
    if ever[i]: inc displaced
    if unit.hasGoal: inc active
    if unit.orderFailed: inc failed
    echo "unit=", i, " pos=", unit.body.pos, " goal=", unit.goal,
      " state=", unit.state, " active=", unit.hasGoal, " ever=", ever[i],
      " stationary=", stalled[i], " blocked=", unit.blockedTicks,
      " path=", unit.path, " index=", unit.pathIndex
  echo "complete=", completed, " displaced=", displaced,
    " active=", active, " failed=", failed
