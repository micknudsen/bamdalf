#!/usr/bin/env python3
"""Fixed expanded-query comparison; every observation gets a fresh process."""
import csv
import hashlib
import json
import pathlib
import re
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
INPUTS = {
    "derived": (
        ".local/measurements/issue-11/data/HG002.GRCh38.qualification-100x.bam",
        "b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33",
    ),
    "original": (
        ".local/measurements/issue-5/data/HG002.GRCh38.regions.bam",
        "786c9d3f66ff721d8bbb20bb62c8e055aa589f1e64f930fc8fdfc210e9b689c5",
    ),
}
CASES = [
    ("ordinary_1000", "derived", 10024501, 10025500, 9830401, 10354688),
    ("ordinary_10000", "derived", 10020001, 10030000, 9830401, 10354688),
    ("dense_1000", "derived", 29892101, 29893100, 29818881, 30081024),
    ("dense_10000", "derived", 29887601, 29897600, 29818881, 30081024),
    ("original_dense_1000", "original", 29892101, 29893100, 29884417, 29900800),
    ("original_dense_10000", "original", 29887601, 29897600, 29884417, 29900800),
]
MARGINS = [0, 250, 500, 1000, 2000]


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def provenance_hashes(executable, extra_sources):
    hashes = {str(executable): digest(executable)}
    for relative, expected in INPUTS.values():
        actual = digest(ROOT / relative)
        if actual != expected:
            raise SystemExit(f"Unexpected input checksum: {relative}")
        hashes[relative] = actual
        hashes[relative + ".bai"] = digest(ROOT / (relative + ".bai"))
    for path in [ROOT / "Package.swift", *sorted((ROOT / "Sources").rglob("*.swift")),
                 *sorted((ROOT / "Sources/CBAM").rglob("*.c")), *sorted((ROOT / "Sources/CBAM").rglob("*.h")),
                 pathlib.Path(__file__), *extra_sources]:
        hashes[str(path.relative_to(ROOT))] = digest(path)
    return hashes


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python3 Benchmarks/BoundedTailQuery/run.py EXECUTABLE NEW_OUTPUT_DIRECTORY")
    executable = pathlib.Path(sys.argv[1]).resolve()
    out = pathlib.Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=False)
    hashes = provenance_hashes(executable, [pathlib.Path(__file__).with_name("main.swift")])
    (out / "sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    environment = {}
    for name, command in {
        "commit": ["git", "rev-parse", "HEAD"], "status": ["git", "status", "--short"],
        "os": ["sw_vers"], "cpu": ["sysctl", "-n", "machdep.cpu.brand_string"],
        "memory": ["sysctl", "-n", "hw.memsize"], "swift": ["swift", "--version"],
    }.items():
        environment[name] = subprocess.check_output(command, cwd=ROOT, text=True).strip()
    (out / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    (out / "worktree.patch").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    (out / "protocol.json").write_text(json.dumps({"cases": CASES, "margins": MARGINS, "repetitions": 5}, indent=2) + "\n")
    rows = []
    for case, source, start, end, complete_start, complete_end in CASES:
        for margin in MARGINS:
            if start - margin < complete_start or end + margin > complete_end:
                raise SystemExit(f"Expanded query exceeds complete source extraction: {case} M={margin}")
            for repetition in range(1, 6):
                name = f"{case}-m{margin}-r{repetition}"
                process = subprocess.run([
                    "/usr/bin/time", "-l", str(executable), str(ROOT / INPUTS[source][0]),
                    "chr20", str(start), str(end), str(margin),
                ], cwd=ROOT, capture_output=True, text=True, check=True)
                (out / (name + ".json")).write_text(process.stdout)
                (out / (name + ".time.txt")).write_text(process.stderr)
                result = json.loads(process.stdout)
                match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", process.stderr, re.MULTILINE)
                if not match or result["query_records"] == 0:
                    raise SystemExit(f"Missing successful query/RSS evidence: {name}")
                result.update(case=case, repetition=repetition, time_peak_rss_bytes=int(match.group(1)))
                rows.append(result)
    with (out / "results.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = []
    for case, *_ in CASES:
        for margin in MARGINS:
            group = [r for r in rows if r["case"] == case and r["margin"] == margin]
            for key in ["required_bases", "query_records", "visible_records", "tail_only_records"]:
                if len({r[key] for r in group}) != 1:
                    raise SystemExit(f"Inconsistent repeated query counts: {case} M={margin}")
            summary.append({
                "case": case, "margin": margin,
                **{key: group[0][key] for key in ["required_bases", "query_records", "visible_records", "tail_only_records"]},
                "query_wall_median_ms": statistics.median(r["query_wall_ms"] for r in group),
                "query_wall_max_ms": max(r["query_wall_ms"] for r in group),
                "time_peak_rss_max_bytes": max(r["time_peak_rss_bytes"] for r in group),
            })
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Completed {len(rows)} queries; results: {out / 'summary.json'}")


if __name__ == "__main__":
    main()
