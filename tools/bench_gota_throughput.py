#!/usr/bin/env python3
"""Compare GotA OpenGL, synchronous Metal, and asynchronous Metal throughput.

Build first, then explicitly run the serial measurement phase:
  python3 tools/bench_gota_throughput.py build --samples 1
  python3 tools/bench_gota_throughput.py run --samples 1 --frames 300 --trials 1
  python3 tools/bench_gota_throughput.py run --samples 1 --frames 1800 --trials 3

Repeat with --samples 4 for the ordinary GotA antialiasing quality. Results are
offscreen completed-work throughput, not displayed FPS or per-frame latency.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys

import bench_backends as runner

ROOT = runner.ROOT
VARIANTS = ("opengl", "metal-sync", "metal-async")


def read_json(path: Path) -> dict:
    """Reads a recorded JSON object."""
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise runner.BenchmarkError(f"Expected a JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    """Fingerprints an artifact without loading it all into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def dependencies() -> dict:
    """Records dependency revisions and actual tracked/untracked source content."""
    result = {}
    for line in (ROOT / "nimby.lock").read_text().splitlines():
        if not line.strip():
            continue
        name = line.split()[0]
        directory = (ROOT / ".deps" / name).resolve()
        head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=directory, text=True).strip()
        diff = subprocess.check_output(
            ["git", "diff", "--binary", "HEAD"], cwd=directory)
        names = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard",
             "-z"], cwd=directory).decode().split("\0")
        digest = hashlib.sha256()
        for relative in sorted(set(names)):
            path = directory / relative
            if not path.is_file() or path.suffix not in {
                ".nim", ".nims", ".c", ".h", ".cpp", ".m", ".mm", ".metal"
            }:
                continue
            digest.update(relative.encode() + b"\0")
            digest.update(path.read_bytes())
            digest.update(b"\0")
        result[name] = {
            "path": str(directory), "commit": head,
            "trackedDiffSha256": hashlib.sha256(diff).hexdigest(),
            "sourceSha256": digest.hexdigest(),
        }
    return result


def source_snapshot() -> dict:
    """Captures source state outside the timed gameplay interval."""
    return {"commit": runner.repository_commit(),
            "sourceHash": runner.source_hash(), "dependencies": dependencies()}


def variant_args(args: argparse.Namespace, variant: str) -> argparse.Namespace:
    """Selects a separate cache and artifact directory for each treatment."""
    result = argparse.Namespace(**vars(args))
    result.out = args.out / f"samples-{args.samples}" / variant
    result.mode = "throughput"
    result.define = [] if variant == "opengl" else ["metalProfile"]
    if variant == "metal-sync":
        result.define.append("metalSynchronous")
    return result


def backend(variant: str) -> str:
    """Maps treatment names to the actual renderer identity in the payload."""
    return "opengl" if variant == "opengl" else "metal"


def binary_fingerprints(args: argparse.Namespace) -> dict:
    """Checks and fingerprints all three isolated benchmark executables."""
    result = {}
    for variant in VARIANTS:
        path = (variant_args(args, variant).out / "bin" /
                f"gota-{backend(variant)}")
        if not path.is_file() or not os.access(path, os.X_OK):
            raise runner.BenchmarkError(f"Missing executable: {path}")
        result[variant] = {"path": str(path), "sha256": sha256(path),
                           "bytes": path.stat().st_size}
    return result


def clean_environment() -> tuple[dict, list[str]]:
    """Removes validation, capture, overlays, and inherited benchmark settings."""
    environment = dict(os.environ)
    removed = []
    for key in list(environment):
        if (key.startswith(("MTL_", "METAL_", "POLYWORLD_BENCH_")) or
                key in {"NSMetalCaptureEnabled", "CAC_AUTOSTART",
                        "DYLD_INSERT_LIBRARIES"}):
            removed.append(key)
            del environment[key]
    return environment, sorted(removed)


def build(args: argparse.Namespace) -> None:
    """Builds all three arms from one frozen source and dependency state."""
    if args.dry_run:
        print(json.dumps({variant: runner.build_case(
            "gota", backend(variant), variant_args(args, variant))
            for variant in VARIANTS}, indent=2))
        return
    area = args.out / f"samples-{args.samples}"
    manifest = {"started": datetime.now(timezone.utc).isoformat(),
                "samples": args.samples, "mode": "throughput",
                "start": source_snapshot(), "cases": []}
    runner.write_json(area / "build.json", manifest)
    for variant in VARIANTS:
        record = runner.build_case(
            "gota", backend(variant), variant_args(args, variant))
        record["variant"] = variant
        manifest["cases"].append(record)
        runner.write_json(area / "build.json", manifest)
    manifest["end"] = source_snapshot()
    manifest["binaries"] = binary_fingerprints(args)
    manifest["passed"] = manifest["start"] == manifest["end"]
    runner.write_json(area / "build.json", manifest)
    if not manifest["passed"]:
        raise runner.BenchmarkError("Sources or dependencies changed during build")
    print(f"Builds complete: {area / 'build.json'}", flush=True)


def order(trials: int) -> list[tuple[int, str]]:
    """Rotates treatments so each occupies every order position in three trials."""
    result = []
    for trial in range(1, trials + 1):
        shift = (trial - 1) % len(VARIANTS)
        result.extend((trial, variant) for variant in
                      VARIANTS[shift:] + VARIANTS[:shift])
    return result


def validate(data: dict, args: argparse.Namespace, variant: str) -> dict:
    """Requires completed logical frames, bounded work, and total-wall timing."""
    payload = runner.validate_payload(data, args, "gota", backend(variant))
    if payload.get("mode") != "throughput":
        raise runner.BenchmarkError("Expected a throughput build")
    for key in ("submittedFrames", "completedFrames"):
        if payload.get(key) != args.frames:
            raise runner.BenchmarkError(f"Expected {args.frames} {key}")
    expected_capacity = 1 if variant == "metal-sync" else 3
    if payload.get("capacity") != expected_capacity:
        raise runner.BenchmarkError(f"Unexpected {variant} queue capacity")
    outstanding = payload.get("maxOutstanding")
    if not isinstance(outstanding, int) or not 1 <= outstanding <= expected_capacity:
        raise runner.BenchmarkError("Observed queue exceeds the declared bound")
    elapsed, drain = payload.get("elapsedMs"), payload.get("drainMs")
    if (not isinstance(elapsed, (float, int)) or not math.isfinite(elapsed) or
            elapsed <= 0 or not isinstance(drain, (float, int)) or
            not math.isfinite(drain) or not 0 <= drain <= elapsed):
        raise runner.BenchmarkError("Invalid measured wall time or final drain")
    if not math.isclose(payload.get("throughputFps", 0),
                        args.frames * 1000 / elapsed, rel_tol=1e-6):
        raise runner.BenchmarkError("Throughput does not match completed work")
    return payload


def run(args: argparse.Namespace) -> None:
    """Runs exactly one process at a time and preserves every raw payload."""
    area = args.out / f"samples-{args.samples}"
    run_dir = args.run_dir or area / "runs" / datetime.now().strftime(
        "%Y%m%d-%H%M%S")
    if args.dry_run:
        print(json.dumps([{"trial": trial, "variant": variant,
            "command": runner.native_command("gota", backend(variant),
                variant_args(args, variant), run_dir / "saves" /
                f"{variant}-trial{trial}")}
            for trial, variant in order(args.trials)], indent=2))
        return
    built = read_json(area / "build.json")
    snapshot, binaries = source_snapshot(), binary_fingerprints(args)
    if (not built.get("passed") or built.get("mode") != "throughput" or
            built.get("samples") != args.samples or built["end"] != snapshot or
            built["binaries"] != binaries):
        raise runner.BenchmarkError("Build/source/dependency/binary fingerprint mismatch")
    if run_dir.exists():
        raise runner.BenchmarkError(f"Preserve prior results; choose a new path: {run_dir}")
    run_dir.mkdir(parents=True)
    environment, removed = clean_environment()
    manifest = {"started": datetime.now(timezone.utc).isoformat(),
        "start": snapshot, "binariesStart": binaries, "build": built,
        "method": {"mode": "throughput", "samples": args.samples,
            "warmup": args.warmup, "frames": args.frames, "trials": args.trials,
            "width": 1280, "height": 800, "seed": 42, "bots": 10,
            "fixedStepSeconds": 1 / 60, "timedConcurrency": 1,
            "preferences": "Benchmark build defaults; stored preferences ignored",
            "metric": "Completed offscreen frames / wall time including final drain",
            "excludes": ["warmup", "presentation", "vsync"],
            "order": "Rotated treatment order each trial",
            "removedEnvironmentKeys": removed,
            "profileScope": "Engine counters; Silky internal passes/allocations excluded",
            "gpuMsMeaning": "Sum of completed command-buffer GPU timestamp spans",
            "cpuMsMeaning": "Pre-submit elapsed time including frame-begin queue backpressure",
            "submitMsMeaning": "Backend submission elapsed time including synchronous-control completion waits"},
        "cases": []}
    runner.write_json(run_dir / "run.json", manifest)
    reference_ticks = None
    for trial, variant in order(args.trials):
        stem = f"{variant}-trial{trial}"
        raw = run_dir / "raw" / f"{stem}.json"
        saves = run_dir / "saves" / stem
        saves.mkdir(parents=True)
        command = runner.native_command(
            "gota", backend(variant), variant_args(args, variant), saves)
        sample_environment = dict(environment)
        sample_environment.update({"POLYWORLD_BENCH_WARMUP": str(args.warmup),
            "POLYWORLD_BENCH_FRAMES": str(args.frames),
            "POLYWORLD_BENCH_OUTPUT": str(raw)})
        print(f"Measuring {stem} ({args.samples}x)", flush=True)
        stage = runner.logged_process(command, sample_environment,
            run_dir / "logs" / f"{stem}.log", args.timeout)
        payload = validate(read_json(raw), args, variant)
        ticks = [frame["tick"] for frame in payload["framesData"]]
        if reference_ticks is None:
            reference_ticks = ticks
        if ticks != reference_ticks:
            raise runner.BenchmarkError(f"Full simulation tick sequence differs: {stem}")
        manifest["cases"].append({"variant": variant, "trial": trial,
            "raw": str(raw), "stage": stage, "passed": True})
        runner.write_json(run_dir / "run.json", manifest)
    manifest["end"] = source_snapshot()
    manifest["binariesEnd"] = binary_fingerprints(args)
    manifest["passed"] = (manifest["end"] == snapshot and
                          manifest["binariesEnd"] == binaries)
    manifest["fullTickArraysEqual"] = True
    runner.write_json(run_dir / "run.json", manifest)
    if not manifest["passed"]:
        raise runner.BenchmarkError("Source/dependency/binary state changed during timing")
    report(run_dir)
    print(f"Measurements complete: {run_dir / 'summary.json'}", flush=True)


def report(run_dir: Path) -> dict:
    """Summarizes completed-work throughput while preserving all raw samples."""
    manifest = read_json(run_dir / "run.json")
    if not manifest.get("passed"):
        raise runner.BenchmarkError("Cannot summarize an incomplete or changed run")
    args = argparse.Namespace(mode="throughput", **{
        key: manifest["method"][key] for key in ("samples", "warmup", "frames")})
    rows, groups, reference_ticks = [], {}, None
    for case in manifest["cases"]:
        payload = validate(read_json(Path(case["raw"])), args, case["variant"])
        frames = payload["framesData"]
        ticks = [frame["tick"] for frame in frames]
        if reference_ticks is not None and ticks != reference_ticks:
            raise runner.BenchmarkError("Full simulation tick arrays differ")
        reference_ticks = ticks
        intervals = [frame["intervalMs"] for frame in frames if frame["intervalMs"] > 0]
        row = {"variant": case["variant"], "trial": case["trial"],
            "samples": args.samples, "completedFrames": payload["completedFrames"],
            "submittedFrames": payload["submittedFrames"],
            "capacity": payload["capacity"], "maxOutstanding": payload["maxOutstanding"],
            "elapsedMs": payload["elapsedMs"], "finalDrainMs": payload["drainMs"],
            "throughputFps": payload["throughputFps"],
            "cpuMedianMs": statistics.median(frame["cpuMs"] for frame in frames),
            "submitMedianMs": statistics.median(frame.get("submitMs", 0) for frame in frames),
            "cadenceMedianMs": statistics.median(intervals) if intervals else 0,
            "cadenceP95Ms": runner.percentile(intervals, .95) if intervals else 0,
            "startTick": ticks[0], "endTick": ticks[-1], "raw": case["raw"]}
        rows.append(row)
        trial = dict(row)
        if "metal" in payload:
            trial["metalWindowTotals"] = payload["metal"]
            trial["metalPerCompletedFrame"] = {
                key: value / payload["completedFrames"]
                for key, value in payload["metal"].items()
                if key not in {"totalCommandBuffers", "pendingBuffers"}}
        groups.setdefault(case["variant"], []).append(trial)
    summaries = []
    for variant in VARIANTS:
        trials = groups.get(variant, [])
        if len(trials) != manifest["method"]["trials"]:
            raise runner.BenchmarkError(f"Incomplete treatment trials: {variant}")
        rates = [trial["throughputFps"] for trial in trials]
        summaries.append({"variant": variant, "trials": trials,
            "medianThroughputFps": statistics.median(rates),
            "trialThroughputRangeFps": [min(rates), max(rates)]})
    result = {"passed": True, "method": manifest["method"],
              "fullTickArraysEqual": True, "variants": summaries,
              "diagnosticNote": (
                  "cpuMs includes frame-begin queue backpressure; submitMs includes "
                  "backend submission and synchronous-control completion waits. "
                  "These diagnostics measure neither pure CPU/GPU execution time "
                  "nor displayed or completed frame latency.")}
    runner.write_json(run_dir / "summary.json", result)
    with (run_dir / "trials.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return result


def main() -> None:
    """Parses separate build, measurement, and report phases."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("build", "run", "report"))
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/gota-throughput")
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--samples", type=int, choices=(1, 4), default=1)
    parser.add_argument("--warmup", type=int, default=240)
    parser.add_argument("--frames", type=int, default=1800)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--build-timeout", type=float, default=1800)
    parser.add_argument("--nim", default="nim")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    args.mode = "throughput"
    args.out = args.out.resolve()
    if args.run_dir:
        args.run_dir = args.run_dir.resolve()
    if args.warmup < 0 or args.frames < 1 or args.trials < 1:
        parser.error("Frames and trials must be positive; warmup cannot be negative")
    if args.timeout <= 0 or args.build_timeout <= 0:
        parser.error("Timeouts must be positive")
    if args.phase == "build":
        build(args)
    elif args.phase == "run":
        run(args)
    elif args.run_dir:
        print(json.dumps(report(args.run_dir), indent=2))
    else:
        parser.error("report requires --run-dir")


if __name__ == "__main__":
    try:
        main()
    except (runner.BenchmarkError, FileNotFoundError, json.JSONDecodeError) as error:
        sys.exit(str(error))
