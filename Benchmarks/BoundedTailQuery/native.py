#!/usr/bin/env python3
"""Focused native integration check using the unchanged VisibilityBaseline."""
import csv
import json
import pathlib
import re
import statistics
import subprocess
import sys

from run import CASES, INPUTS, ROOT, digest

EXPECTED_QUERIED = {
    "ordinary_1000": 1349, "ordinary_10000": 7448,
    "dense_1000": 5289, "dense_10000": 16353,
    "original_dense_1000": 15676, "original_dense_10000": 48911,
}


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python3 Benchmarks/BoundedTailQuery/native.py VISIBILITY_BASELINE NEW_OUTPUT_DIRECTORY")
    executable = pathlib.Path(sys.argv[1]).resolve()
    out = pathlib.Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=False)
    hashes = {str(executable): digest(executable)}
    for relative, expected in INPUTS.values():
        actual = digest(ROOT / relative)
        if actual != expected:
            raise SystemExit(f"Unexpected input checksum: {relative}")
        hashes[relative] = actual
        hashes[relative + ".bai"] = digest(ROOT / (relative + ".bai"))
    for path in [ROOT / "Package.swift", ROOT / "Benchmarks/VisibilityBaseline.swift",
                 *sorted((ROOT / "Sources").rglob("*.swift")),
                 *sorted((ROOT / "Sources/CBAM").rglob("*.c")), *sorted((ROOT / "Sources/CBAM").rglob("*.h")),
                 pathlib.Path(__file__), pathlib.Path(__file__).with_name("run.py")]:
        hashes[str(path.relative_to(ROOT))] = digest(path)
    (out / "sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (out / "worktree.patch").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    (out / "commit.txt").write_bytes(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT))
    rows = []
    for case, source, start, end, complete_start, complete_end in CASES:
        if start - 250 < complete_start or end + 250 > complete_end:
            raise SystemExit(f"Expanded native query exceeds complete extraction: {case}")
        for repetition in range(1, 6):
            prefix = out / f"{case}-r{repetition}"
            process = subprocess.run([
                "/usr/bin/time", "-l", str(executable), str(ROOT / INPUTS[source][0]),
                f"chr20:{start}-{end}", str(prefix), "2000",
            ], cwd=ROOT, capture_output=True, text=True, check=True)
            prefix.with_suffix(".stdout.json").write_text(process.stdout)
            prefix.with_suffix(".time.txt").write_text(process.stderr)
            result = json.loads(process.stdout)
            match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", process.stderr, re.MULTILINE)
            if not match or result["regional_query_calls"] != 1 or result["queried_eligible_records"] != EXPECTED_QUERIED[case]:
                raise SystemExit(f"Native expanded-query or RSS evidence differs: {prefix}")
            rows.append({
                "case": case, "repetition": repetition,
                "queried_records": result["queried_eligible_records"],
                "displayed_records": result["alignments"], "retained_groups": result["retained_groups"],
                "rows": result["rows"], "is_downsampled": result["is_downsampled"],
                "load_layout_wall_ms": result["query_pack_native_layout_wall_ms"],
                "first_draw_wall_ms": result["renderer_draw_wall_ms"][0],
                "five_draw_mean_wall_ms": result["renderer_draw_wall_mean_ms"],
                "peak_rss_bytes": int(match.group(1)),
            })
    with (out / "results.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summaries = []
    for case, *_ in CASES:
        group = [row for row in rows if row["case"] == case]
        summaries.append({
            "case": case,
            **{key: group[0][key] for key in ["queried_records", "displayed_records", "retained_groups", "is_downsampled"]},
            "load_layout_wall_median_ms": statistics.median(row["load_layout_wall_ms"] for row in group),
            "load_layout_wall_max_ms": max(row["load_layout_wall_ms"] for row in group),
            "first_draw_wall_max_ms": max(row["first_draw_wall_ms"] for row in group),
            "peak_rss_max_bytes": max(row["peak_rss_bytes"] for row in group),
        })
    (out / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
    print(f"Completed {len(rows)} native loads; results: {out / 'summary.json'}")


if __name__ == "__main__":
    main()
