import std/unittest
import vmath
import polyworld/[stats, gameuis]
import ../[game, ui, presets, content]

suite "LvD Tab match clock":
  test "remaining applied ticks round up to MM:SS and clamp at zero":
    var config = defaultConfig()
    config.maxTicks = TickRate * 200
    initializeLocalMatch(config, ["", ""])
    when compiles(currentStatsOptions().statusText):
      for item in [(0'i32, "Time remaining: 03:20"),
          (1'i32, "Time remaining: 03:20"),
          (TickRate * 20 - 1, "Time remaining: 03:01"),
          (TickRate * 20, "Time remaining: 03:00"),
          (config.maxTicks - 1, "Time remaining: 00:01"),
          (config.maxTicks, "Time remaining: 00:00"),
          (config.maxTicks + 1, "Time remaining: 00:00")]:
        run.world.tick = item[0]
        check currentStatsOptions().statusText == item[1]
      run.world.tick = 0
      check currentStatsOptions().statusText == "Time remaining: 03:20"
    else:
      check false
  test "optional status row fits compact through large cards without changing defaults":
    when compiles(StatsOptions(statusText: "Time remaining: 03:00")):
      for size in [vec2(640,480), vec2(1000,700), vec2(1920,1080)]:
        for count in [2, 16, 64]:
          for scale in [0.4'f32, 0.75'f32, 1.25'f32]:
            let viewport = statsViewport(initGameUiLayout(size / scale, 56), scale)
            var table = StatsTable(kind: RtsStats)
            for slot in 0 ..< count: table.rows.add StatsRow(slot: slot)
            let old = statsLayout(viewport, table)
            let empty = statsLayout(viewport, table, StatsOptions(statusText: ""))
            check old == empty
            check old.status.size.y == 0
            for headline in ["", "Commander wins"]:
              let options = StatsOptions(statusText: "Time remaining: 03:00", headline: headline)
              let slots = statsLayout(viewport, table, options)
              check slots.panel.inside(viewport.gameAreaSize)
              check slots.status.size.y > 0
              check slots.status.origin.y >= slots.headline.origin.y + slots.headline.size.y
              check slots.status.origin.y + slots.status.size.y <= slots.header.origin.y
              check slots.body.size.y > 0
    else:
      check false
