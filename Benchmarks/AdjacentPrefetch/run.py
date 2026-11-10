#!/usr/bin/env python3
"""Fresh-process enabled/disabled native comparison with complete R/C inputs."""
import csv
import json
import pathlib
import re
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Benchmarks/BoundedTailQuery"))
from run import CASES, INPUTS, provenance_hashes  # noqa: E402


def main():
    if len(sys.argv) not in (3, 4):
        raise SystemExit("usage: python3 Benchmarks/AdjacentPrefetch/run.py EXECUTABLE NEW_OUTPUT_DIRECTORY [CHUNK_BASES]")
    executable = pathlib.Path(sys.argv[1]).resolve()
    out = pathlib.Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=False)
    chunks = [int(sys.argv[3])] if len(sys.argv) == 4 else [250, 1000]
    repetitions = 5 if len(sys.argv) == 4 else 3
    configurations = [("disabled", chunks[0]), *[("enabled", chunk) for chunk in chunks]]
    cases = [case for case in CASES if case[0] != "original_dense_10000"]
    hashes = provenance_hashes(executable, [pathlib.Path(__file__), pathlib.Path(__file__).with_name("main.swift")])
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
        "cases": cases, "configurations": configurations, "repetitions": repetitions,
        "margin_bases": 250, "buffer": "max(viewport_width, 250)",
        "maximum_cache_bytes": 32 * 1024 * 1024, "maximum_query_bytes": 8 * 1024 * 1024,
        "maximum_query_records": 20000,
        "order": "Alternate forward/reversed configuration order for each repetition within each case",
        "excluded": "original_dense_10000: full C exceeds its complete extraction; never treat missing extraction as empty data",
    }, indent=2) + "\n")
    rows = []
    for case, source, start, end, complete_start, complete_end in cases:
        width = end - start + 1
        desired_start, desired_end = start - 250 - max(width, 250), end + 250 + max(width, 250)
        if desired_start < complete_start or desired_end > complete_end:
            raise SystemExit(f"Full C exceeds complete extraction: {case}")
        for repetition in range(1, repetitions + 1):
            order = configurations if repetition % 2 else list(reversed(configurations))
            for enabled, chunk in order:
                name = f"{case}-{enabled}-c{chunk}-r{repetition}"
                process = subprocess.run([
                    "/usr/bin/time", "-l", str(executable), str(ROOT / INPUTS[source][0]),
                    f"chr20:{start}-{end}", enabled, str(chunk), str(32 * 1024 * 1024),
                    str(8 * 1024 * 1024), "20000", str(out / (name + ".json")),
                ], cwd=ROOT, capture_output=True, text=True)
                (out / (name + ".time.txt")).write_text(process.stderr)
                if process.returncode:
                    (out / (name + ".stdout.txt")).write_text(process.stdout)
                    raise SystemExit(f"Observation failed ({process.returncode}): {name}\n{process.stderr}")
                result = json.loads(process.stdout)
                match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", process.stderr, re.MULTILINE)
                if not match:
                    raise SystemExit(f"Missing peak RSS: {name}")
                rows.append({
                    "case": case, "enabled": enabled, "chunk_bases": chunk, "repetition": repetition,
                    **{key: result[key] for key in [
                        "first_ready_ms", "first_raster_ms", "first_ready_and_raster_ms",
                        "pan_ready_and_raster_ms", "pan_required_queries", "optional_query_count",
                        "optional_returned_records", "optional_errors", "displayed_records", "is_downsampled",
                    ]}, "peak_rss_bytes": int(match.group(1)),
                })
    with (out / "results.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summaries = []
    for case, *_ in cases:
        for enabled, chunk in configurations:
            group = [row for row in rows if row["case"] == case and row["enabled"] == enabled and row["chunk_bases"] == chunk]
            summaries.append({
                "case": case, "enabled": enabled, "chunk_bases": chunk,
                "first_ready_and_raster_median_ms": statistics.median(row["first_ready_and_raster_ms"] for row in group),
                "first_ready_and_raster_max_ms": max(row["first_ready_and_raster_ms"] for row in group),
                "pan_ready_and_raster_median_ms": statistics.median(row["pan_ready_and_raster_ms"] for row in group),
                "pan_ready_and_raster_max_ms": max(row["pan_ready_and_raster_ms"] for row in group),
                "pan_required_queries": sorted(set(row["pan_required_queries"] for row in group)),
                "optional_query_count": sorted(set(row["optional_query_count"] for row in group)),
                "optional_returned_records": sorted(set(row["optional_returned_records"] for row in group)),
                "optional_errors": sorted(set(row["optional_errors"] for row in group)),
                "peak_rss_max_bytes": max(row["peak_rss_bytes"] for row in group),
            })
    (out / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
    print(f"Completed {len(rows)} native observations; {out / 'summary.json'}")


if __name__ == "__main__":
    main()
