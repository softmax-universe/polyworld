## Aggregate the independent launches from bench_backends into a local report.
import std/[algorithm, json, math, os, strformat, strutils, xmltree]

const Output = "tmp/livetest/benchmarks"

proc mean(values: seq[float64]): float64 =
  for value in values: result += value
  result /= values.len.float64

proc values(row: JsonNode, key: string): seq[float64] =
  for sample in row[key]:
    let ms = sample.getFloat()
    if ms <= 0 or classify(ms) in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "Invalid frame time")
    result.add ms

proc percentile(sorted: seq[float64], p: float64): float64 =
  sorted[max(0, ceil(sorted.len.float * p).int - 1)]

proc main() =
  if paramCount() notin 1..4:
    quit("bench_report RUN-ID [expected repetitions] [game] [backends]", 2)
  let
    id = paramStr(1)
    repeats = if paramCount() >= 2: parseInt(paramStr(2)) else: 3
    dump = newJArray()
    summary = newJArray()
  doAssert id.len > 0 and id.allCharsInSet(Letters + Digits + {'-'}) and repeats > 0
  const games = ["gota", "lvd", "cta", "cac", "heartleaf", "crewrift", "monster"]
  let selected = if paramCount() >= 3: paramStr(3) else: ""
  if selected.len > 0 and selected notin games: quit("Unknown game: " & selected, 2)
  const supported = ["OpenGL", "WebGL", "DirectX", "Vulkan"]
  let backends = if paramCount() == 4: paramStr(4).split(',') else: @supported
  for backend in backends:
    if backend notin supported: quit("Unknown backend: " & backend, 2)
  let firstGame = if selected.len > 0: selected else: games[0]
  let runMode = parseFile(Output / &"{firstGame}-{backends[0]}-{id}-1.json"){"mode"}.getStr("synchronized")
  var html = """<!doctype html><html lang="en"><meta charset="utf-8"><title>Polyworld backend benchmarks</title>
<style>body{max-width:1100px;margin:3rem auto;padding:0 1rem;font:16px/1.5 system-ui;color:#17232e}table{border-collapse:collapse;margin:2rem 0;width:100%;font-variant-numeric:tabular-nums}th,td{text-align:right;padding:.4rem .75rem;border-bottom:1px solid #d6dde3}th{text-align:right;background:#edf2f5}td:first-child,th:first-child,td:nth-child(2),th:nth-child(2){text-align:left}tr.group td{border-top:2px solid #7b8e9d}h1{font-weight:620}</style>
<h1>Polyworld backend benchmarks</h1>"""
  let machine = getEnv("BENCH_MACHINE")
  if machine.len > 0: html.add "<p>" & xmltree.escape(machine) & "</p>"
  let methodText = if runMode == "pipelined":
    "Active time spans the game callback through presentation. The mean interval includes the event loop and the final GPU drain. Frames overlap during measurement."
  else:
    "Active time includes simulation, scene and UI submission, and a GPU completion wait. Frame intervals also include presentation and the event loop."
  html.add "<p>800 × 560, single-sample, seed 42. " & methodText & " P50 and P95 use nearest rank over all measured frames.</p>"
  html.add "<table><thead><tr><th>Game</th><th>Backend</th><th>Runs</th><th>Frames</th><th>Mean active ms</th><th>P50 ms</th><th>P95 ms</th><th>Mean interval ms</th></tr></thead><tbody>"
  var webGpu = ""
  for game in games:
    if selected.len > 0 and game != selected: continue
    for backend in backends:
      var active, interval, runMeans: seq[float64]
      for i in 1 .. repeats:
        let
          path = Output / &"{game}-{backend}-{id}-{i}.json"
          row = parseFile(path)
          samples = values(row, "frame_ms")
          cadence = values(row, "interval_ms")
        doAssert samples.len == cadence.len and row["game"].getStr == game and
          row["backend"].getStr == backend and row["repetition"].getInt == i
        let mode = row{"mode"}.getStr("synchronized")
        doAssert runMode == mode, "Mixed benchmark modes"
        active.add samples
        interval.add cadence
        runMeans.add samples.mean
        if backend == "WebGL": webGpu = row["renderer"].getStr
        dump.add row
      active.sort()
      interval.sort()
      let
        avg = active.mean
        p50 = active.percentile(0.5)
        p95 = active.percentile(0.95)
        intervalMs = interval.mean
      summary.add %*{"game": game, "backend": backend, "runs": repeats, "frames": active.len,
        "mean_active_ms": avg, "p50_active_ms": p50, "p95_active_ms": p95,
        "mean_interval_ms": intervalMs, "p95_interval_ms": interval.percentile(0.95), "run_mean_active_ms": runMeans}
      html.add(if backend == "OpenGL": "<tr class=group>" else: "<tr>")
      html.add &"<td>{game}</td><td>{backend}</td><td>{repeats}</td><td>{active.len}</td><td>{avg:.2f}</td><td>{p50:.2f}</td><td>{p95:.2f}</td><td>{intervalMs:.2f}</td></tr>"
  html.add "</tbody></table>"
  if webGpu.len > 0: html.add "<p>WebGL renderer: " & xmltree.escape(webGpu) & ".</p>"
  html.add "<p><a href='results-" & id & ".json'>Download all frame samples and run means</a>.</p></html>"
  writeFile(Output / ("results-" & id & ".json"), $(%*{"machine": machine, "mode": runMode, "summary": summary, "runs": dump}))
  writeFile(Output / ("report-" & id & ".html"), html)
  echo "Wrote ", summary.len, " configurations from ", dump.len, " launches"

main()
