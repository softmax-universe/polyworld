#!/usr/bin/env python3
"""Build and benchmark Polyworld backends with one timed process at a time.

Build all binaries first, then run the measurements separately:
  python3 tools/bench_backends.py build --jobs 3
  python3 tools/bench_backends.py run --trials 3

The game hooks measure simulation and rendering through GPU completion. These
numbers exclude frame pacing and are not displayed FPS. Browser cadence is
recorded separately by bench_browser.cjs.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import random
import signal
import statistics
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
GAMES = {
    "gota": ("gods_of_the_arena", "gota", 10),
    "lvd": ("light_vs_dark", "lvd", 2),
    "cta": ("call_to_adventure", "cta", 4),
    "cac": ("cac", "cac", 0),
    "heartleaf": ("heartleaf", "heartleaf", 9),
    "crewrift": ("crewrift", "crewrift", 0),
    "monster": ("monster", "monster", 0),
}
BACKENDS = ("opengl", "metal", "webgl")
NODE_MODULES = (
    Path.home() / ".cache/codex-runtimes/codex-primary-runtime"
    / "dependencies/node/node_modules"
)


class BenchmarkError(Exception):
    """Indicates a failed build, benchmark, or measurement invariant."""


def write_json(path: Path, data: object) -> None:
    """Writes a complete JSON record without exposing partially written data."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def selection(text: str, available: object) -> list[str]:
    """Validates a comma-separated list while preserving the requested order."""
    values = text.split(",")
    if not values or any(value not in available for value in values):
        raise argparse.ArgumentTypeError(f"Choose from {', '.join(available)}")
    if len(set(values)) != len(values):
        raise argparse.ArgumentTypeError("Selections must not contain duplicates")
    return values


def source_hash() -> str:
    """Fingerprints benchmark-relevant sources independently of commit staging."""
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    ).decode().split("\0")
    digest = hashlib.sha256()
    for name in sorted(set(names)):
        path = ROOT / name
        if not path.is_file() or path.suffix not in {
            ".nim", ".nims", ".js", ".cjs", ".html", ".lock", ".py"
        }:
            continue
        digest.update(name.encode() + b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def repository_commit() -> str:
    """Returns the checked-out commit without claiming the sources are clean."""
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()


def logged_process(command: list[str], environment: dict[str, str],
                   log: Path, timeout: float) -> dict:
    """Runs one child and terminates its process group if it exceeds its limit."""
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log.open("w") as output:
        output.write("Command: " + json.dumps(command) + "\n")
        output.flush()
        process = subprocess.Popen(
            command, cwd=ROOT, env=environment, stdout=output,
            stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise BenchmarkError(f"Timed out after {timeout:g}s: {log}")
    record = {
        "command": command, "exitCode": code, "log": str(log),
        "started": started, "wallSeconds": time.time() - started,
    }
    if code != 0:
        tail = "\n".join(log.read_text(errors="replace").splitlines()[-20:])
        raise BenchmarkError(f"Command failed ({code}): {log}\n{tail}")
    return record


def build_case(game: str, backend: str, args: argparse.Namespace) -> dict:
    """Checks and compiles one release benchmark using an isolated cache."""
    directory, entry, _ = GAMES[game]
    source = ROOT / "games" / directory / f"{entry}.nim"
    case = f"{game}-{backend}"
    flags = ["--hints:off", "-d:release", "-d:backendBench"]
    flags.extend(f"-d:{name}" for name in args.define)
    if getattr(args, "mode", "latency") == "throughput":
        flags.append("-d:backendThroughput")
    flags.append(f"-d:backendBenchSamples={getattr(args, 'samples', 1)}")
    if backend == "metal":
        flags.append("-d:useMetal4")
    elif backend == "webgl":
        flags.append("-d:emscripten")
    environment = dict(os.environ)
    environment["POLYWORLD_WEB_DIR"] = str(args.out / "web" / game)
    artifact = (
        args.out / "web" / game / f"{entry}.html" if backend == "webgl"
        else args.out / "bin" / case
    )
    compile_flags = [f"--nimcache:{args.out / 'cache' / case}"]
    if backend != "webgl":
        compile_flags.append(f"--out:{artifact}")
    commands = [
        [args.nim, "check", *flags, str(source)],
        [args.nim, "c", *flags, *compile_flags, str(source)],
    ]
    if args.dry_run:
        return {"game": game, "backend": backend, "commands": commands,
                "environment": {"POLYWORLD_WEB_DIR": environment[
                    "POLYWORLD_WEB_DIR"]}, "artifact": str(artifact)}
    artifact.parent.mkdir(parents=True, exist_ok=True)
    stages = []
    for stage, command in zip(("check", "build"), commands):
        print(f"{case}: {stage}", flush=True)
        stages.append(logged_process(
            command, environment, args.out / "logs" / f"{case}-{stage}.log",
            args.build_timeout,
        ))
    if not artifact.is_file():
        raise BenchmarkError(f"Build did not produce {artifact}")
    return {"game": game, "backend": backend, "passed": True,
            "artifact": str(artifact), "stages": stages}


def build(args: argparse.Namespace) -> None:
    """Builds the complete requested matrix before any timed execution."""
    fingerprint = source_hash()
    cases = [(game, backend) for game in args.games for backend in args.backends]
    if args.dry_run:
        print(json.dumps([build_case(*case, args) for case in cases], indent=2))
        return
    manifest = {
        "commit": repository_commit(), "sourceHash": fingerprint,
        "generated": datetime.now(timezone.utc).isoformat(), "cases": [],
        "mode": args.mode, "samples": args.samples,
    }
    args.out.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = {executor.submit(build_case, *case, args): case for case in cases}
        for future in as_completed(futures):
            manifest["cases"].append(future.result())
            write_json(args.out / "build.json", manifest)
    if source_hash() != fingerprint:
        raise BenchmarkError("Sources changed during builds; rebuild before timing")
    manifest["passed"] = True
    manifest["cases"].sort(key=lambda item: (item["game"], item["backend"]))
    write_json(args.out / "build.json", manifest)
    print(f"Builds complete: {args.out / 'build.json'}", flush=True)


def native_command(game: str, backend: str, args: argparse.Namespace,
                   save_dir: Path) -> list[str]:
    """Uses the same seed and bot rosters as the browser benchmark."""
    directory, _, bots = GAMES[game]
    command = [str(args.out / "bin" / f"{game}-{backend}"),
               "--seed", "42", "--windowSize", "1280x800", "--mute"]
    if bots:
        command += ["--bot", str(ROOT / "games" / directory / "players"
                                 / "base.bas") + f":{bots}"]
    if game == "cac":
        command += ["--direct", "--players", "2"]
    if game == "monster":
        command += ["--offline", "--no-voice", "--save-dir", str(save_dir)]
    return command


def ordered_cases(args: argparse.Namespace) -> list[tuple[str, str, int]]:
    """Rotates backend order across trials to distribute thermal/order bias."""
    result = []
    for trial in range(1, args.trials + 1):
        games = list(args.games)
        random.Random(42 + trial).shuffle(games)
        for game in games:
            original_index = args.games.index(game)
            shift = (trial - 1 + original_index) % len(args.backends)
            order = args.backends[shift:] + args.backends[:shift]
            result.extend((game, backend, trial) for backend in order)
    return result


def validate_payload(data: dict, args: argparse.Namespace,
                     game: str, backend: str) -> dict:
    """Rejects unfinished, mismatched, or invalid measurements."""
    payload = data.get("benchmark", data)
    frames = payload.get("framesData", [])
    if payload.get("game") != game or payload.get("backend") != backend:
        raise BenchmarkError("Benchmark identity differs from the launched case")
    if not payload.get("done") or len(frames) != args.frames:
        raise BenchmarkError(f"Expected {args.frames} complete frame samples")
    if payload.get("warmup") != args.warmup:
        raise BenchmarkError("Benchmark warmup differs from the requested value")
    if (payload.get("width"), payload.get("height")) != (1280, 800):
        raise BenchmarkError("Benchmark target must be 1280x800 physical pixels")
    if payload.get("samples") != getattr(args, "samples", 1):
        raise BenchmarkError("Benchmark sample count differs from the request")
    mode = getattr(args, "mode", "latency")
    if payload.get("mode", "latency") != mode:
        raise BenchmarkError("Benchmark measurement mode differs from the request")
    if not math.isclose(payload.get("fixedStepSeconds", 0), 1 / 60):
        raise BenchmarkError("Benchmark simulation step must be 1/60 second")
    previous_tick = -1
    for index, frame in enumerate(frames):
        if frame.get("frame") != args.warmup + index + 1:
            raise BenchmarkError("Benchmark frame sequence is incomplete")
        tick = frame.get("tick")
        if not isinstance(tick, int) or tick < previous_tick:
            raise BenchmarkError("Benchmark simulation ticks moved backwards")
        previous_tick = tick
        keys = ["cpuMs", "gpuWaitMs", "workMs", "intervalMs"]
        if mode == "throughput":
            keys.append("submitMs")
        for key in keys:
            value = frame.get(key)
            if not isinstance(value, (int, float)) or not math.isfinite(value):
                raise BenchmarkError(f"Invalid {key} in frame sample")
            if value < 0 or (key == "workMs" and value == 0):
                raise BenchmarkError(f"Invalid {key} in frame sample")
        submit_ms = frame.get("submitMs", 0) if mode == "throughput" else 0
        if not math.isclose(frame["workMs"], frame["cpuMs"] +
                            frame["gpuWaitMs"] + submit_ms, abs_tol=1e-5):
            raise BenchmarkError("Frame timing components do not sum to workMs")
    if mode == "throughput":
        if backend == "webgl":
            raise BenchmarkError("Throughput measurement requires a native backend")
        if (payload.get("submittedFrames"), payload.get("completedFrames")) != (
                args.frames, args.frames):
            raise BenchmarkError("Throughput did not complete every submitted frame")
        capacity = payload.get("capacity")
        outstanding = payload.get("maxOutstanding")
        if capacity not in (1, 3) or not isinstance(outstanding, int) or not (
                1 <= outstanding <= capacity):
            raise BenchmarkError("Throughput exceeded the bounded frame queue")
        for key in ("elapsedMs", "drainMs", "throughputFps"):
            value = payload.get(key)
            if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise BenchmarkError(f"Invalid throughput {key}")
        if payload["elapsedMs"] <= 0 or payload["drainMs"] > payload["elapsedMs"]:
            raise BenchmarkError("Invalid throughput measured window")
        if not math.isclose(payload["throughputFps"],
                            args.frames * 1000 / payload["elapsedMs"], rel_tol=1e-6):
            raise BenchmarkError("Throughput rate excludes completed work or final drain")
    return payload


class QuietHandler(SimpleHTTPRequestHandler):
    """Serves local game bundles without logging requests into timing output."""

    def log_message(self, format: str, *arguments: object) -> None:
        """Suppresses routine local-server access messages."""
        pass


def run_case(game: str, backend: str, trial: int, args: argparse.Namespace,
             run_dir: Path, base: str) -> dict:
    """Measures one case without overlapping another benchmark or build."""
    stem = f"{game}-{backend}-trial{trial}"
    output = run_dir / "raw" / f"{stem}.json"
    environment = dict(os.environ)
    environment.update({
        "POLYWORLD_BENCH_WARMUP": str(args.warmup),
        "POLYWORLD_BENCH_FRAMES": str(args.frames),
        "POLYWORLD_BENCH_OUTPUT": str(output),
    })
    if game == "cac":
        # The capture fixture changes both the seed and hero roster.
        environment.pop("CAC_AUTOSTART", None)
    if backend == "webgl":
        environment.setdefault("NODE_PATH", str(NODE_MODULES))
        _, entry, _ = GAMES[game]
        relative = (args.out / "web" / game / f"{entry}.html").relative_to(ROOT)
        command = [args.node, str(ROOT / "tools" / "bench_browser.cjs"),
                   "--game", game, "--url", base + relative.as_posix(),
                   "--base", base, "--output", str(output),
                   "--warmup", str(args.warmup), "--frames", str(args.frames),
                   "--trial", str(trial)]
    else:
        command = native_command(
            game, backend, args, run_dir / "saves" / stem
        )
    if args.dry_run:
        return {"game": game, "backend": backend, "trial": trial,
                "command": command, "output": str(output)}
    print(f"Measuring {stem}", flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = logged_process(command, environment,
                           run_dir / "logs" / f"{stem}.log", args.timeout)
    if not output.is_file():
        raise BenchmarkError(f"Benchmark did not produce {output}")
    data = json.loads(output.read_text())
    payload = validate_payload(data, args, game, backend)
    if data.get("passed") is False:
        raise BenchmarkError(f"Browser checks failed: {output}")
    return {"game": game, "backend": backend, "trial": trial,
            "passed": True, "raw": str(output), "stage": stage,
            "startTick": payload.get("startTick"),
            "endTick": payload.get("endTick")}


def percentile(values: list[float], fraction: float) -> float:
    """Returns a nearest-rank percentile without assuming a normal distribution."""
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def summarize(run_dir: Path) -> dict:
    """Aggregates trial summaries while preserving every raw frame sample."""
    manifest = json.loads((run_dir / "run.json").read_text())
    groups = {}
    for case in manifest["cases"]:
        raw = json.loads(Path(case["raw"]).read_text())
        payload = raw.get("benchmark", raw)
        samples = [frame["workMs"] for frame in payload["framesData"]]
        trial = {
            "trial": case["trial"], "medianMs": statistics.median(samples),
            "meanMs": statistics.mean(samples), "p95Ms": percentile(samples, .95),
            "cpuMedianMs": statistics.median(
                frame["cpuMs"] for frame in payload["framesData"]),
            "gpuWaitMedianMs": statistics.median(
                frame["gpuWaitMs"] for frame in payload["framesData"]),
            "startTick": payload.get("startTick"), "endTick": payload.get("endTick"),
            "raw": case["raw"],
        }
        if payload.get("mode") == "throughput":
            trial.update({"throughputFps": payload["throughputFps"],
                          "elapsedMs": payload["elapsedMs"],
                          "drainMs": payload["drainMs"]})
        groups.setdefault((case["game"], case["backend"]), []).append(trial)
    rows = []
    for (game, backend), trials in groups.items():
        medians = [trial["medianMs"] for trial in trials]
        median_ms = statistics.median(medians)
        rows.append({
            "game": game, "backend": backend, "trials": trials,
            "medianFrameMs": median_ms,
            "medianTrialMeanMs": statistics.median(t["meanMs"] for t in trials),
            "medianTrialP95Ms": statistics.median(t["p95Ms"] for t in trials),
            "trialMedianRangeMs": [min(medians), max(medians)],
            "workFpsEquivalent": 1000 / median_ms,
        })
        if "throughputFps" in trials[0]:
            # CPU iteration durations are diagnostics, not completed frame latency.
            rows[-1]["cpuIterationMedianMs"] = rows[-1].pop("medianFrameMs")
            rows[-1].pop("workFpsEquivalent")
            rates = [trial["throughputFps"] for trial in trials]
            rows[-1]["medianThroughputFps"] = statistics.median(rates)
            rows[-1]["throughputFpsRange"] = [min(rates), max(rates)]
    summary = {
        "commit": manifest["commit"], "sourceHash": manifest["sourceHash"],
        "method": manifest["method"], "passed": manifest.get("passed", False),
        "rows": sorted(rows, key=lambda row: (row["game"], row["backend"])),
    }
    write_json(run_dir / "summary.json", summary)
    return summary


def run(args: argparse.Namespace) -> None:
    """Runs the completed build matrix serially using fresh per-trial saves."""
    fingerprint = source_hash()
    run_dir = args.run_dir or args.out / "runs" / datetime.now().strftime(
        "%Y%m%d-%H%M%S")
    run_dir = run_dir.resolve()
    cases = ordered_cases(args)
    if args.dry_run:
        print(json.dumps([run_case(*case, args, run_dir,
                                  "http://127.0.0.1:18935/")
                          for case in cases], indent=2))
        return
    built = json.loads((args.out / "build.json").read_text())
    available = {(case["game"], case["backend"]) for case in built["cases"]}
    if not built.get("passed") or built["sourceHash"] != fingerprint:
        raise BenchmarkError("Build manifest is incomplete or sources changed")
    if (built.get("mode", "latency"), built.get("samples", 1)) != (
            args.mode, args.samples):
        raise BenchmarkError("Build mode or sample count differs from this run")
    if any((game, backend) not in available for game, backend, _ in cases):
        raise BenchmarkError("Build manifest does not cover the requested cases")
    if run_dir.exists():
        raise BenchmarkError(f"Use a new run directory to preserve results: {run_dir}")
    run_dir.mkdir(parents=True)
    manifest = {
        "commit": repository_commit(), "sourceHash": fingerprint,
        "generated": datetime.now(timezone.utc).isoformat(),
        "method": {"width": 1280, "height": 800, "samples": args.samples,
                   "mode": args.mode,
                   "seed": 42, "fixedStepSeconds": 1 / 60,
                   "warmupFrames": args.warmup, "measuredFrames": args.frames,
                   "trials": args.trials, "timedConcurrency": 1,
                   "metric": "Simulation and rendering through one-pixel readback",
                   "excludes": ["startup", "display pacing", "presentation"],
                   "order": "Game shuffle and rotating backend order per trial"},
        "cases": [],
    }
    if args.mode == "throughput":
        manifest["method"]["metric"] = (
            "Completed offscreen frames / total wall time including final drain")
    write_json(run_dir / "run.json", manifest)
    server = None
    try:
        base = ""
        if "webgl" in args.backends:
            server = ThreadingHTTPServer(
                ("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT)))
            threading.Thread(target=server.serve_forever, daemon=True).start()
            base = f"http://127.0.0.1:{server.server_address[1]}/"
        if args.cooldown:
            print(f"Waiting {args.cooldown:g}s after builds before timing", flush=True)
            time.sleep(args.cooldown)
        for case in cases:
            manifest["cases"].append(run_case(*case, args, run_dir, base))
            write_json(run_dir / "run.json", manifest)
        if source_hash() != fingerprint:
            raise BenchmarkError("Sources changed during timing")
        manifest["passed"] = True
        write_json(run_dir / "run.json", manifest)
        summarize(run_dir)
        write_json(args.out / "last-run.json", {"directory": str(run_dir)})
        print(f"Benchmark complete: {run_dir / 'summary.json'}", flush=True)
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()


def main() -> None:
    """Parses the build, measurement, and report commands."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("build", "run", "report"))
    parser.add_argument("--games", type=lambda text: selection(text, GAMES),
                        default=list(GAMES))
    parser.add_argument("--backends", type=lambda text: selection(text, BACKENDS),
                        default=list(BACKENDS))
    parser.add_argument("--out", type=Path, default=ROOT / "tmp" / "benchmarks")
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--mode", choices=("latency", "throughput"), default="latency")
    parser.add_argument("--samples", type=int, choices=(1, 2, 4, 8), default=1)
    parser.add_argument("--warmup", type=int)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--cooldown", type=float, default=10)
    parser.add_argument("--timeout", type=float, default=240)
    parser.add_argument("--build-timeout", type=float, default=1800)
    parser.add_argument("--nim", default="nim")
    parser.add_argument("--define", action="append", default=[],
                        help="Additional Nim compile-time definition; repeatable")
    parser.add_argument("--node", default="node")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.warmup is None:
        args.warmup = 240 if args.mode == "throughput" else 120
    if args.frames is None:
        args.frames = 1800 if args.mode == "throughput" else 600
    if "webgl" in args.backends and (args.mode == "throughput" or args.samples != 1):
        parser.error("Throughput and multisample benchmarks require native backends")
    args.out = args.out.resolve()
    if args.run_dir:
        args.run_dir = args.run_dir.resolve()
    if args.jobs < 1 or args.trials < 1 or args.frames < 1 or args.warmup < 0:
        parser.error("Jobs, trials, and frames must be positive; warmup cannot be negative")
    if args.cooldown < 0 or args.timeout <= 0 or args.build_timeout <= 0:
        parser.error("Timeouts must be positive and cooldown cannot be negative")
    if args.phase == "build":
        build(args)
    elif args.phase == "run":
        run(args)
    elif args.run_dir:
        print(json.dumps(summarize(args.run_dir), indent=2))
    else:
        parser.error("report requires --run-dir")


if __name__ == "__main__":
    try:
        main()
    except (BenchmarkError, FileNotFoundError, json.JSONDecodeError) as error:
        sys.exit(str(error))
