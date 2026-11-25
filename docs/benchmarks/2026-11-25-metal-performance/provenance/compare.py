#!/usr/bin/env python3
"""Run a serial OpenGL-control / Metal-before / Metal-after comparison.

Build and validate everything before explicitly invoking the run phase:
  python3 tmp/metal-perf/compare.py run --run-dir tmp/metal-perf/runs/paired
  python3 tmp/metal-perf/compare.py report --run-dir tmp/metal-perf/runs/paired

Only report imports matplotlib; use --no-plot when it is unavailable.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
CONTROL_ROOT = Path("/Users/me/p/polyworld-backends")
AREA = ROOT / "tmp/metal-perf"
VARIANTS = ("opengl-control", "metal-before", "metal-after")
LABELS = {"opengl-control": "OpenGL control", "metal-before": "Metal before",
          "metal-after": "Metal after"}
GAME_NAMES = {"gota": "Gods of the Arena", "lvd": "Light vs Dark",
              "cta": "Call to Adventure", "cac": "Cards and Casters",
              "heartleaf": "Heartleaf", "crewrift": "Crewrift",
              "monster": "Monster"}
TRIALS, WARMUP, FRAMES = 3, 120, 600
CONTROL_REF = "e65a5dee083679a10321d82e79a3fc08a70f1f7c"
BASELINE_SILKY = "b56d00abb346d96e475cd30826f1d4f811f6fba4"
TIMES = ("workMs", "cpuMs", "gpuWaitMs", "intervalMs")
PROFILE_FIELDS = ("gpuMs", "renderPasses", "emptyPasses", "drawCalls",
                  "blitPasses", "commandBuffers", "bufferAllocations",
                  "bufferBytes", "uniformBytes", "gpuTimedBuffers",
                  "gpuUntimedBuffers")

spec = importlib.util.spec_from_file_location(
    "polyworld_benchmark_runner", ROOT / "tools/bench_backends.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def read_json(path: Path) -> dict:
    """Reads a JSON object from a recorded artifact."""
    result = json.loads(path.read_text())
    if not isinstance(result, dict):
        raise runner.BenchmarkError(f"Expected a JSON object: {path}")
    return result


def sha256(path: Path) -> str:
    """Hashes a complete binary or source without loading it all at once."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def executable(game: str, variant: str) -> Path:
    """Resolves an explicitly preserved executable for each comparison arm."""
    if variant == "opengl-control":
        return CONTROL_ROOT / "tmp/benchmarks/bin" / f"{game}-opengl"
    if variant == "metal-before":
        return AREA / "baseline" / f"{game}-metal"
    return AREA / "build/bin" / f"{game}-metal"


def dependencies() -> dict:
    """Captures external dependency heads and tracked working-tree contents."""
    result = {}
    for name in ("silky", "metal4", "shady"):
        directory = ROOT / ".deps" / name
        head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=directory, text=True).strip()
        diff = subprocess.check_output(["git", "diff", "--binary", "HEAD"],
                                       cwd=directory)
        status = subprocess.check_output(["git", "status", "--porcelain"],
                                         cwd=directory, text=True)
        result[name] = {"commit": head, "status": status,
                        "trackedDiffSha256": hashlib.sha256(diff).hexdigest()}
    return result


def binary_fingerprints() -> dict:
    """Verifies and fingerprints all 21 executables before timing."""
    result = {}
    for game in GAME_NAMES:
        for variant in VARIANTS:
            path = executable(game, variant)
            if not path.is_file() or not os.access(path, os.X_OK):
                raise runner.BenchmarkError(f"Missing executable: {path}")
            result[f"{game}/{variant}"] = {
                "path": str(path), "sha256": sha256(path),
                "bytes": path.stat().st_size,
            }
    return result


def clean_environment() -> tuple[dict, list[str]]:
    """Disables GPU validation, debug overlays and the CaC capture fixture."""
    environment = dict(os.environ)
    removed = []
    for key in list(environment):
        if (key.startswith(("MTL_", "METAL_")) or
                key in {"MTL_DEVICE_WRAPPER_TYPE", "MTL_ENABLE_DEBUG_INFO",
                        "NSMetalCaptureEnabled", "CAC_AUTOSTART"}):
            removed.append(key)
            environment.pop(key)
    return environment, sorted(removed)


def schedule() -> list[tuple[str, str, int]]:
    """Balances variant starting position for every game across three rounds."""
    result = []
    for trial in range(1, TRIALS + 1):
        games = list(GAME_NAMES)
        random.Random(42 + trial).shuffle(games)
        for game in games:
            shift = (trial - 1 + list(GAME_NAMES).index(game)) % len(VARIANTS)
            order = VARIANTS[shift:] + VARIANTS[:shift]
            result.extend((game, variant, trial) for variant in order)
    return result


def validate_case(raw: dict, game: str, variant: str) -> dict:
    """Checks shared benchmark invariants and opt-in Metal diagnostics."""
    args = argparse.Namespace(frames=FRAMES, warmup=WARMUP)
    backend = "opengl" if variant == "opengl-control" else "metal"
    payload = runner.validate_payload(raw, args, game, backend)
    if "readback" not in payload.get("metric", "").lower():
        raise runner.BenchmarkError("Expected the one-pixel completion barrier")
    previous_total = -1
    for frame in payload["framesData"]:
        if not math.isclose(frame["cpuMs"] + frame["gpuWaitMs"],
                            frame["workMs"], rel_tol=1e-8, abs_tol=1e-6):
            raise runner.BenchmarkError("CPU and completion wait do not sum to work")
        if not math.isfinite(frame["intervalMs"]) or frame["intervalMs"] <= 0:
            raise runner.BenchmarkError("Invalid frame-start interval")
        if variant == "opengl-control":
            continue
        profile = frame.get("metal", {})
        for key in PROFILE_FIELDS:
            value = profile.get(key)
            if (not isinstance(value, (int, float)) or not math.isfinite(value)
                    or value < 0):
                raise runner.BenchmarkError(f"Invalid Metal profile field {key}")
        if profile["gpuTimedBuffers"] < 1 or profile["gpuMs"] <= 0:
            raise runner.BenchmarkError("Metal frame lacks usable GPU timestamps")
        if profile["gpuUntimedBuffers"] != 0:
            raise runner.BenchmarkError("Metal frame has an untimed command buffer")
        if profile["gpuTimedBuffers"] != profile["commandBuffers"]:
            raise runner.BenchmarkError("Metal GPU timing coverage is incomplete")
        if profile["emptyPasses"] > profile["renderPasses"]:
            raise runner.BenchmarkError("Empty pass count exceeds all render passes")
        total = profile.get("totalCommandBuffers")
        if not isinstance(total, int) or total < previous_total:
            raise runner.BenchmarkError("Cumulative submission count moved backwards")
        previous_total = total
    return payload


def verify_build(path: Path, fingerprint: str | None = None) -> dict:
    """Requires complete profiled Metal build manifests for the seven games."""
    build = read_json(path)
    cases = {(item["game"], item["backend"]): item for item in build["cases"]}
    if build.get("passed") is not True:
        raise runner.BenchmarkError(f"Incomplete build manifest: {path}")
    if fingerprint is not None and build.get("sourceHash") != fingerprint:
        raise runner.BenchmarkError("Candidate sources changed after the final build")
    for game in GAME_NAMES:
        case = cases.get((game, "metal"))
        if not case or case.get("passed") is not True:
            raise runner.BenchmarkError(f"Missing {game}/metal build in {path}")
        command = case["stages"][-1]["command"]
        for flag in ("-d:release", "-d:backendBench", "-d:metalProfile", "-d:useMetal4"):
            if flag not in command:
                raise runner.BenchmarkError(f"Build lacks {flag}: {path}, {game}")
    return build


def run(args: argparse.Namespace) -> None:
    """Runs all paired trials serially and preserves every raw sample."""
    run_dir = args.run_dir or AREA / "runs" / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = run_dir.resolve()
    if run_dir.exists():
        raise runner.BenchmarkError(f"Use a new run directory: {run_dir}")
    head = runner.repository_commit()
    fingerprint = runner.source_hash()
    baseline = verify_build(AREA / "baseline/build.json")
    candidate = verify_build(AREA / "build/build.json", fingerprint)
    binaries = binary_fingerprints()
    dependency_state = dependencies()
    environment, removed = clean_environment()
    run_dir.mkdir(parents=True)
    (run_dir / "provenance").mkdir()
    shutil.copyfile(AREA / "baseline/build.json", run_dir / "provenance/baseline-build.json")
    shutil.copyfile(AREA / "build/build.json", run_dir / "provenance/candidate-build.json")
    control_build = CONTROL_ROOT / "tmp/benchmarks/build.json"
    if control_build.is_file():
        shutil.copyfile(control_build, run_dir / "provenance/opengl-control-build.json")
    hardware = CONTROL_ROOT / "tmp/benchmarks/hardware.json"
    if hardware.is_file():
        shutil.copyfile(hardware, run_dir / "provenance/hardware.json")
    manifest = {
        "generated": datetime.now(timezone.utc).isoformat(), "passed": False,
        "candidateHeadStart": head, "candidateSourceHashStart": fingerprint,
        "baselineCommit": baseline["commit"], "baselineSourceHash": baseline["sourceHash"],
        "candidateBuildCommit": candidate["commit"], "controlReference": CONTROL_REF,
        "baselineSilkyRevision": BASELINE_SILKY,
        "candidateDependenciesStart": dependency_state,
        "scriptSha256Start": sha256(Path(__file__)), "binariesStart": binaries,
        "removedEnvironmentNames": removed,
        "method": {"width": 1280, "height": 800, "samples": 1, "seed": 42,
                   "fixedStepSeconds": 1 / 60, "warmupFrames": WARMUP,
                   "measuredFrames": FRAMES, "trials": TRIALS,
                   "timedConcurrency": 1, "games": list(GAME_NAMES),
                   "variants": list(VARIANTS),
                   "metric": "Simulation and rendering through one-pixel readback",
                   "order": "Seeded game shuffle and balanced variant rotation",
                   "gpuValidation": False, "excludes": ["startup", "presentation", "frame pacing"]},
        "cases": [],
    }
    runner.write_json(run_dir / "run.json", manifest)
    try:
        if args.cooldown > 0:
            print(f"Cooling down for {args.cooldown:g}s before timing", flush=True)
            time.sleep(args.cooldown)
        for game, variant, trial in schedule():
            stem = f"{game}-{variant}-trial{trial}"
            output = run_dir / "raw" / f"{stem}.json"
            output.parent.mkdir(parents=True, exist_ok=True)
            backend = "opengl" if variant == "opengl-control" else "metal"
            launch_args = argparse.Namespace(out=AREA / "build")
            command = runner.native_command(game, backend, launch_args,
                                            run_dir / "saves" / stem)
            command[0] = str(executable(game, variant))
            case_environment = dict(environment)
            case_environment.update({"POLYWORLD_BENCH_WARMUP": str(WARMUP),
                                     "POLYWORLD_BENCH_FRAMES": str(FRAMES),
                                     "POLYWORLD_BENCH_OUTPUT": str(output)})
            print(f"Measuring {stem}", flush=True)
            stage = runner.logged_process(command, case_environment,
                                          run_dir / "logs" / f"{stem}.log", args.timeout)
            payload = validate_case(read_json(output), game, variant)
            manifest["cases"].append({"game": game, "variant": variant,
                                      "backend": backend, "trial": trial,
                                      "passed": True, "raw": str(output), "stage": stage,
                                      "startTick": payload["startTick"],
                                      "endTick": payload["endTick"]})
            runner.write_json(run_dir / "run.json", manifest)
        manifest["candidateHeadEnd"] = runner.repository_commit()
        manifest["candidateSourceHashEnd"] = runner.source_hash()
        manifest["candidateDependenciesEnd"] = dependencies()
        manifest["scriptSha256End"] = sha256(Path(__file__))
        manifest["binariesEnd"] = binary_fingerprints()
        if (manifest["candidateHeadEnd"] != head or
                manifest["candidateSourceHashEnd"] != fingerprint or
                manifest["candidateDependenciesEnd"] != dependency_state or
                manifest["scriptSha256End"] != manifest["scriptSha256Start"] or
                manifest["binariesEnd"] != binaries):
            raise runner.BenchmarkError("Source, dependency or executable changed during timing")
        manifest["passed"] = True
        manifest["finished"] = datetime.now(timezone.utc).isoformat()
        runner.write_json(run_dir / "run.json", manifest)
        print(f"All 63 trials complete: {run_dir}", flush=True)
    except BaseException as error:
        manifest["failure"] = str(error)
        manifest["passed"] = False
        runner.write_json(run_dir / "run.json", manifest)
        raise


def distribution(values: list[float]) -> dict:
    """Returns untrimmed mean, median, p95 and extrema for a single trial."""
    return {"mean": statistics.mean(values), "median": statistics.median(values),
            "p95": sorted(values)[math.ceil(len(values) * .95) - 1],
            "min": min(values), "max": max(values)}


def summarize_metric(trials: list[dict], name: str) -> dict:
    """Preserves mean and median definitions separately across three trials."""
    values = [trial["metrics"][name] for trial in trials]
    medians = [value["median"] for value in values]
    return {"median": statistics.median(medians),
            "mean": statistics.median(value["mean"] for value in values),
            "p95": statistics.median(value["p95"] for value in values),
            "trialMedianMin": min(medians), "trialMedianMax": max(medians)}


def analyze(run_dir: Path) -> tuple[dict, dict, list[dict], list[dict]]:
    """Revalidates coverage, every raw frame and all nine timelines per game."""
    manifest = read_json(run_dir / "run.json")
    if not manifest.get("passed"):
        raise runner.BenchmarkError("Cannot report an incomplete or failed run")
    expected = {(game, variant, trial) for game in GAME_NAMES for variant in VARIANTS
                for trial in range(1, TRIALS + 1)}
    observed, groups, ticks = set(), {}, {}
    for case in manifest["cases"]:
        key = case["game"], case["variant"], case["trial"]
        if key not in expected or key in observed:
            raise runner.BenchmarkError(f"Duplicate or unexpected case {key}")
        observed.add(key)
        if not case.get("passed") or case["stage"]["exitCode"] != 0:
            raise runner.BenchmarkError(f"Failed measured process: {key}")
        payload = validate_case(read_json(Path(case["raw"])), key[0], key[1])
        frames = payload["framesData"]
        timeline = [frame["tick"] for frame in frames]
        if key[0] in ticks and timeline != ticks[key[0]]:
            raise runner.BenchmarkError(f"Per-frame simulation progression differs: {key}")
        ticks[key[0]] = timeline
        metrics = {name: distribution([frame[name] for frame in frames]) for name in TIMES}
        if key[1] != "opengl-control":
            metrics.update({name: distribution([frame["metal"][name] for frame in frames])
                            for name in PROFILE_FIELDS})
            totals = [frame["metal"]["totalCommandBuffers"] for frame in frames]
            metrics["allSubmissionsPerInterval"] = distribution(
                [right - left for left, right in zip(totals, totals[1:])])
        groups.setdefault(key[:2], []).append({"trial": key[2], "raw": case["raw"],
                                               "startTick": payload["startTick"],
                                               "endTick": payload["endTick"], "metrics": metrics})
    if observed != expected:
        raise runner.BenchmarkError(f"Missing {len(expected - observed)} of 63 required cases")
    rows = []
    for game in GAME_NAMES:
        for variant in VARIANTS:
            trials = sorted(groups[(game, variant)], key=lambda value: value["trial"])
            names = list(TIMES)
            if variant != "opengl-control":
                names += list(PROFILE_FIELDS) + ["allSubmissionsPerInterval"]
            metrics = {name: summarize_metric(trials, name) for name in names}
            rows.append({"game": game, "gameName": GAME_NAMES[game], "variant": variant,
                         "trialCount": len(trials), "metrics": metrics, "trials": trials})
    lookup = {(row["game"], row["variant"]): row for row in rows}
    changes = []
    for game in GAME_NAMES:
        before = lookup[(game, "metal-before")]["metrics"]
        after = lookup[(game, "metal-after")]["metrics"]
        control = lookup[(game, "opengl-control")]["metrics"]
        changes.append({"game": game, "gameName": GAME_NAMES[game],
                        "workReductionPercent": 100 * (1 - after["workMs"]["median"] / before["workMs"]["median"]),
                        "workSpeedup": before["workMs"]["median"] / after["workMs"]["median"],
                        "afterOverOpenGL": after["workMs"]["median"] / control["workMs"]["median"],
                        "before": before, "after": after, "control": control})
    validation = {"passed": True, "caseCount": len(observed),
                  "measuredFrameCount": len(observed) * FRAMES,
                  "equalEveryMeasuredTick": True,
                  "tickRanges": {game: [values[0], values[-1]] for game, values in ticks.items()},
                  "notes": ["Tick equality verifies progression, not complete state or pixel identity.",
                            "Engine pass/allocation counters exclude Silky internal allocations and encoders.",
                            "GPU spans include the full shared command buffer, including Silky."]}
    return manifest, validation, rows, changes


def write_csv(path: Path, rows: list[dict]) -> None:
    """Writes full primary statistics and both means and medians of counters."""
    metric_names = list(TIMES) + list(PROFILE_FIELDS) + ["allSubmissionsPerInterval"]
    fields = ["game", "gameName", "variant", "trialCount"]
    fields += [f"{name}_{stat}" for name in metric_names
               for stat in ("median", "mean", "p95", "trialMedianMin", "trialMedianMax")]
    with path.open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            record = {name: row[name] for name in fields[:4]}
            for name, stats in row["metrics"].items():
                record.update({f"{name}_{stat}": value for stat, value in stats.items()})
            writer.writerow(record)


def plot(path: Path, rows: list[dict]) -> None:
    """Plots three latency variants with the range of per-trial medians."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    colors = {"opengl-control": "#6b7c93", "metal-before": "#d78a32", "metal-after": "#199681"}
    fig, axis = plt.subplots(figsize=(12.8, 9.2), dpi=160)
    maximum = max(row["metrics"]["workMs"]["trialMedianMax"] for row in rows)
    centers = np.arange(len(GAME_NAMES), dtype=float)
    for offset, variant in zip((-.24, 0, .24), VARIANTS):
        values = [row["metrics"]["workMs"] for row in rows if row["variant"] == variant]
        medians = np.array([value["median"] for value in values])
        lows = medians - np.array([value["trialMedianMin"] for value in values])
        highs = np.array([value["trialMedianMax"] for value in values]) - medians
        positions = centers + offset
        axis.barh(positions, medians, height=.205, color=colors[variant], label=LABELS[variant], zorder=3)
        axis.errorbar(medians, positions, xerr=np.array([lows, highs]), fmt="none",
                      ecolor="#26313f", capsize=3, elinewidth=1, zorder=4)
        for y, value, high in zip(positions, medians, highs):
            axis.text(value + high + maximum * .012, y, f"{value:.2f}", va="center", fontsize=9)
    axis.set_yticks(centers, list(GAME_NAMES.values()), fontsize=10.5)
    axis.invert_yaxis()
    axis.set_xlim(0, maximum * 1.2)
    axis.set_xlabel("Completed frame work (milliseconds; lower is better)", fontsize=11)
    axis.xaxis.grid(True, color="#dce2e8", linewidth=.7)
    axis.set_axisbelow(True)
    for side in ("top", "right", "left"):
        axis.spines[side].set_visible(False)
    axis.tick_params(axis="y", length=0, pad=10)
    axis.legend(loc="lower right", facecolor="white", edgecolor="#dce2e8", fontsize=10)
    fig.suptitle("Polyworld Metal: before and after", x=.25, y=.965,
                 ha="left", fontsize=20, fontweight="bold")
    fig.text(.25, .915, "Apple M4 Pro · 1280 × 800 · no MSAA · 3 trials × 600 frames\n"
             "Simulation + rendering through one-pixel readback; presentation excluded",
             fontsize=10.5, color="#4c5a6b", linespacing=1.6, va="top")
    fig.text(.25, .035, "Bars: median of three trial medians. Error bars: full trial-median range.\n"
             "120 warmup frames. Serialized completion cost; engine diagnostics enabled for both Metal variants.",
             fontsize=9, color="#4c5a6b", linespacing=1.5)
    fig.subplots_adjust(left=.25, right=.97, bottom=.13, top=.85)
    fig.savefig(path, dpi=160, facecolor="white")
    plt.close(fig)


def write_report(path: Path, manifest: dict, validation: dict,
                 rows: list[dict], changes: list[dict], plotted: bool) -> None:
    """Explains measured costs, counter semantics, provenance and limitations."""
    lines = ["# Polyworld Metal performance comparison", "",
             f"Candidate commit: `{manifest['candidateHeadStart']}`. Source fingerprint: `{manifest['candidateSourceHashStart']}`.", "",
             f"Instrumented baseline: `{manifest['baselineCommit']}`. OpenGL control reference: `{manifest['controlReference']}`.", "",
             f"Silky before: `{manifest['baselineSilkyRevision']}`. Silky after: `{manifest['candidateDependenciesStart']['silky']['commit']}`.", "",
             "All 63 trials ran one process at a time, with seeded game order and rotated variant order. "
             "Each trial used seed 42, default preferences, matching rosters, 1280×800 physical pixels, no MSAA, "
             "a fixed 1/60-second simulation step, 120 warmup frames and 600 measured frames. Native saves were isolated, "
             "benchmark autosaves disabled, and GPU validation/debug/HUD environment variables removed.", "",
             "The primary metric includes CPU simulation, encoding, GPU completion and synchronous one-pixel readback. "
             "Startup, presentation and pacing are excluded. It measures serialized completion latency; a normal pipelined "
             "renderer can overlap CPU and GPU work. Both Metal variants include the same diagnostic instrumentation; "
             "the retained OpenGL control does not have Metal diagnostics.", "",
             f"Validated {validation['caseCount']} cases and {validation['measuredFrameCount']:,} frame samples, "
             "with matching per-frame simulation progress across all nine cases per game. CaC records turn numbers. "
             "Progress equality does not prove complete world-state or pixel identity.", "",
             "## Completed frame work", "", "Median of three per-trial medians, milliseconds; lower is better.", "",
             "| Game | OpenGL control | Metal before | Metal after | Reduction |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for change in changes:
        lines.append(f"| {change['gameName']} | {change['control']['workMs']['median']:.3f} | "
                     f"{change['before']['workMs']['median']:.3f} | {change['after']['workMs']['median']:.3f} | "
                     f"{change['workReductionPercent']:.1f}% |")
    if plotted:
        lines += ["", f"![Completed frame work]({path.parent / 'comparison.png'})"]
    lines += ["", "Reduction is `100 × (before − after) / before`; negative values indicate a regression.", "",
              "## Tail latency and variation", "",
              "P95 is the median of the three nearest-rank trial p95 values. Trial range is not a confidence interval.", "",
              "| Game | Variant | Median ms | P95 ms | Trial-median range ms |",
              "| --- | --- | ---: | ---: | ---: |"]
    for row in rows:
        metric = row["metrics"]["workMs"]
        lines.append(f"| {row['gameName']} | {LABELS[row['variant']]} | {metric['median']:.3f} | "
                     f"{metric['p95']:.3f} | {metric['trialMedianMin']:.3f}–{metric['trialMedianMax']:.3f} |")
    lines += ["", "## Metal diagnostics", "",
              "Each cell below is **mean / median**: respectively the median of three per-trial means and the "
              "median of three per-trial medians. GPU values are completed command-buffer execution spans, "
              "not CPU waits. All measured buffers must have valid GPU timestamps.", "",
              "| Game | Variant | CPU ms | GPU ms | Render passes | Passes without draws | Buffer allocations |",
              "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for row in rows:
        if row["variant"] == "opengl-control":
            continue
        cells = [f"{row['metrics'][name]['mean']:.3f} / {row['metrics'][name]['median']:.3f}"
                 for name in ("cpuMs", "gpuMs", "renderPasses", "emptyPasses", "bufferAllocations")]
        lines.append(f"| {row['gameName']} | {LABELS[row['variant']]} | " + " | ".join(cells) + " |")
    lines += ["", "Pass, draw and allocation counters cover engine operations; Silky's internal encoders and allocations "
              "are excluded from those counters. GPU spans include all work in the shared command buffer, including Silky. "
              "Passes without draws include clear-only passes, which may do useful GPU work.", "",
              "`bufferBytes` counts newly allocated engine buffer capacity, not all CPU writes into reused storage. "
              "`uniformBytes` counts bound uniform data and overlaps large uniform buffer bytes in the baseline. "
              "Cumulative command-buffer differences (`allSubmissionsPerInterval`) expose submissions outside the timed "
              "interval, including an empty command buffer submitted after readback. The first sample is excluded from that difference.", "",
              "Full means, medians, p95 values, ranges, upload/capacity counters and per-trial details are retained "
              "in the CSV and JSON. Small changes whose trial ranges overlap need further measurement. "
              "These seeded scenes cover ten simulation seconds after warmup and do not represent every workload.", "",
              "## Artifacts", "",
              f"- [Full statistics CSV]({path.parent / 'comparison.csv'})",
              f"- [Analysis with every trial]({path.parent / 'analysis.json'})",
              f"- [Validation]({path.parent / 'validation.json'})",
              f"- [Run manifest and binary hashes]({path.parent / 'run.json'})",
              f"- [All 63 raw frame files]({path.parent / 'raw'})", ""]
    path.write_text("\n".join(lines))


def report(args: argparse.Namespace) -> None:
    """Produces reports only after all timed processes have completed."""
    if args.run_dir is None:
        raise runner.BenchmarkError("report requires --run-dir")
    directory = args.run_dir.resolve()
    manifest, validation, rows, changes = analyze(directory)
    runner.write_json(directory / "validation.json", validation)
    runner.write_json(directory / "analysis.json", {
        "candidateCommit": manifest["candidateHeadStart"],
        "candidateSourceHash": manifest["candidateSourceHashStart"],
        "baselineCommit": manifest["baselineCommit"], "controlReference": CONTROL_REF,
        "rows": rows, "changes": changes, "validation": validation})
    write_csv(directory / "comparison.csv", rows)
    if not args.no_plot:
        plot(directory / "comparison.png", rows)
    write_report(directory / "report.md", manifest, validation, rows, changes, not args.no_plot)
    print(json.dumps({"passed": True, "report": str(directory / "report.md"),
                      "csv": str(directory / "comparison.csv"),
                      "image": None if args.no_plot else str(directory / "comparison.png")}, indent=2))


def main() -> None:
    """Requires an explicit run or report phase; never starts work on import."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("run", "report"))
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--timeout", type=float, default=240)
    parser.add_argument("--cooldown", type=float, default=15)
    parser.add_argument("--no-plot", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0 or args.cooldown < 0 or args.cooldown > 60:
        parser.error("Timeout must be positive; cooldown must be between 0 and 60 seconds")
    if args.phase == "run":
        run(args)
    else:
        report(args)


if __name__ == "__main__":
    try:
        main()
    except (runner.BenchmarkError, OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
