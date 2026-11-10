#!/usr/bin/env python3
"""Fresh-process, paced native rolling-pan/drag comparison on complete inputs."""
import argparse
import csv
import hashlib
import json
import math
import os
import pathlib
import re
import shutil
import signal
import statistics
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
INPUTS = {
    "ordinary": (
        ".local/measurements/issue-11/data/HG002.GRCh38.qualification-100x.bam",
        "b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33",
        "b1bb5a7c36b5bf3fb8fd3c5c3b728d4881364e87a45d159d55909c503678c0fd",
    ),
    "dense": (
        ".local/measurements/issue-11/data/HG002.GRCh38.qualification-source.bam",
        "d2c2aba71c005d7b8e8b69841566475ae2c4418105deba15b4d11fa1697b6d08",
        "4be408f33aa74b94a52b16e17592a3b32abc76e110c136c156c8e09f21d5d815",
    ),
}
CASES = [
    ("ordinary_1000", "ordinary", 10024501, 10025500, 9830401, 10354688),
    ("ordinary_10000", "ordinary", 10020001, 10030000, 9830401, 10354688),
    ("dense_1000", "dense", 29892101, 29893100, 29818881, 30081024),
    ("dense_10000", "dense", 29887601, 29897600, 29818881, 30081024),
]


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def write_csv(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def observe(command):
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        # Retire this observation's own native window as well as time(1).
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        stderr += "\nObservation exceeded the 60-second safety limit.\n"
        return subprocess.CompletedProcess(command, 124, stdout, stderr)
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=pathlib.Path)
    parser.add_argument("output_directory", type=pathlib.Path)
    parser.add_argument("selected_refill_fraction", type=float, nargs="?")
    parser.add_argument("--case", action="append", choices=[case[0] for case in CASES],
                        help="Limit observations to this case; repeat to select several")
    parser.add_argument("--repetitions", type=int, help="Override candidate (3) or selected (5) repetitions")
    args = parser.parse_args()
    executable = args.executable.resolve()
    out = args.output_directory.resolve()
    out.mkdir(parents=True, exist_ok=False)
    selected = args.selected_refill_fraction
    configurations = [-1, selected] if selected is not None else [-1, 0.25, 0.5, 0.75]
    repetitions = args.repetitions if args.repetitions is not None else (5 if selected is not None else 3)
    if repetitions <= 0:
        raise SystemExit("Repetitions must be positive")
    cases = [case for case in CASES if args.case is None or case[0] in args.case]
    if any(fraction != -1 and not 0 <= fraction <= 1 for fraction in configurations):
        raise SystemExit("Refill fractions must be within 0...1")
    hashes = {str(executable): digest(executable)}
    for relative, expected_bam, expected_index in INPUTS.values():
        for suffix, expected in [("", expected_bam), (".bai", expected_index)]:
            actual = digest(ROOT / (relative + suffix))
            if actual != expected:
                raise SystemExit(f"Input checksum differs: {relative + suffix}")
            hashes[relative + suffix] = actual
    source = out / "source"
    source.mkdir()
    for directory in ["Sources", "Benchmarks"]:
        shutil.copytree(ROOT / directory, source / directory, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(ROOT / "Package.swift", source / "Package.swift")
    for path in sorted(source.rglob("*")):
        if path.is_file():
            hashes[str(path.relative_to(source))] = digest(path)
    (out / "sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (out / "worktree.patch").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    environment = {}
    for name, command in {
        "commit": ["git", "rev-parse", "HEAD"], "status": ["git", "status", "--short"],
        "os": ["sw_vers"], "cpu": ["sysctl", "-n", "machdep.cpu.brand_string"],
        "memory": ["sysctl", "-n", "hw.memsize"], "swift": ["swift", "--version"],
    }.items():
        environment[name] = subprocess.check_output(command, cwd=ROOT, text=True).strip()
    (out / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    (out / "protocol.json").write_text(json.dumps({
        "cases": cases, "refill_fractions": configurations, "repetitions": repetitions,
        "margin_bases": 250, "buffer": "max(viewport_width, 250)", "chunk_bases": 1000,
        "maximum_cache_bytes": 32 * 1024 * 1024, "maximum_query_bytes": 8 * 1024 * 1024,
        "maximum_query_records": 20000, "pan_period_ms": 100, "drag_period_ms": 33,
        "pan_route": "8 right half-width pans, 8 left, 8 right; at most +4W from initial",
        "drag_route": "Two cycles: quarter-width displacement 1...8 then 7...0, plus 0.0025W fractional displacement; maximum +2.0025W from drag origin",
        "order": "Alternate forward/reversed configuration order per repetition within each case",
        "cache_conditions": "Fresh process and session per observation, OS file cache uncontrolled; initial buffer allowed to settle before motion; motion never waits for optional idle",
        "source": "Full extended unsampled regional source for dense routes, derived approximately100x panel for ordinary; no small original-dense extraction",
    }, indent=2) + "\n")
    observations, motions = [], []
    for case, source_key, start, end, complete_start, complete_end in cases:
        width = end - start + 1
        # Includes rounded/fractional edge handling of every route target.
        lowest = start - 250 - max(width, 250)
        highest = end + math.ceil(6.0025 * width) + 1 + 250 + max(width, 250)
        if lowest < complete_start or highest > complete_end:
            raise SystemExit(f"Full route C exceeds complete extraction: {case} [{lowest}, {highest}]")
        for repetition in range(1, repetitions + 1):
            order = configurations if repetition % 2 else list(reversed(configurations))
            for fraction in order:
                name = f"{case}-f{fraction}-r{repetition}"
                process = observe([
                    "/usr/bin/time", "-l", str(executable), str(ROOT / INPUTS[source_key][0]),
                    f"chr20:{start}-{end}", str(fraction), str(complete_start), str(complete_end),
                    "100", str(out / (name + ".json")),
                ])
                (out / (name + ".time.txt")).write_text(process.stderr)
                if process.returncode:
                    (out / (name + ".stdout.txt")).write_text(process.stdout)
                    raise SystemExit(f"Observation failed ({process.returncode}): {name}\n{process.stderr}")
                result = json.loads(process.stdout)
                match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", process.stderr, re.MULTILINE)
                if not match:
                    raise SystemExit(f"Missing peak RSS: {name}")
                identity = {"case": case, "refill_fraction": fraction, "repetition": repetition}
                observations.append({
                    **identity,
                    **{key: result[key] for key in [
                        "first_ready_ms", "first_raster_ms", "first_ready_and_raster_ms",
                        "release_ready_and_raster_ms", "release_required_queries",
                        "required_queries", "optional_queries", "optional_canceled", "optional_budget_stops",
                        "required_returned_records", "optional_returned_records",
                    ]}, "peak_rss_bytes": int(match.group(1)),
                })
                for kind, key, latency in [("pan", "pans", "ready_and_raster_ms"), ("drag", "drag_frames", "event_and_raster_ms")]:
                    for index, event in enumerate(result[key]):
                        motions.append({
                            **identity, "kind": kind, "index": index,
                            "start": event["start"], "end": event["end"], "latency_ms": event[latency],
                            "raster_ms": event["raster_ms"], "required_queries": event.get("required_queries", 0),
                            "was_loading": event.get("was_loading", False),
                            "displayed_records": event.get("displayed_records", ""),
                        })
                write_csv(out / "observations.csv", observations)
                write_csv(out / "motions.csv", motions)
                print(f"Completed {name}", flush=True)
    summaries = []
    for case, *_ in cases:
        for fraction in configurations:
            group = [row for row in observations if row["case"] == case and row["refill_fraction"] == fraction]
            events = [row for row in motions if row["case"] == case and row["refill_fraction"] == fraction]
            summary = {
                "case": case, "refill_fraction": fraction, "observations": len(group),
                "first_ready_and_raster_median_ms": statistics.median(row["first_ready_and_raster_ms"] for row in group),
                "first_ready_and_raster_max_ms": max(row["first_ready_and_raster_ms"] for row in group),
                "required_queries_median": statistics.median(row["required_queries"] for row in group),
                "optional_queries_median": statistics.median(row["optional_queries"] for row in group),
                "optional_canceled_max": max(row["optional_canceled"] for row in group),
                "optional_budget_stops_max": max(row["optional_budget_stops"] for row in group),
                "returned_records_median": statistics.median(row["required_returned_records"] + row["optional_returned_records"] for row in group),
                "release_max_ms": max(row["release_ready_and_raster_ms"] for row in group),
                "release_required_queries_max": max(row["release_required_queries"] for row in group),
                "peak_rss_max_bytes": max(row["peak_rss_bytes"] for row in group),
            }
            for kind in ["pan", "drag"]:
                timings = [row["latency_ms"] for row in events if row["kind"] == kind]
                summary.update({f"{kind}_median_ms": statistics.median(timings), f"{kind}_p95_ms": percentile(timings, 0.95), f"{kind}_max_ms": max(timings)})
            drag_events = [row for row in events if row["kind"] == "drag"]
            summary["empty_drag_frames"] = sum(row["displayed_records"] == 0 for row in drag_events)
            pan_events = [row for row in events if row["kind"] == "pan"]
            summary["query_free_pan_fraction"] = sum(row["required_queries"] == 0 for row in pan_events) / len(pan_events)
            summary["pan_queries"] = sum(row["required_queries"] for row in pan_events)
            summary["reversal_p95_ms"] = percentile([row["latency_ms"] for row in pan_events if row["index"] in [8, 16]], 0.95)
            summaries.append(summary)
    (out / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
    print(f"Completed {len(observations)} observations and {len(motions)} motion events; {out / 'summary.json'}")


if __name__ == "__main__":
    main()
