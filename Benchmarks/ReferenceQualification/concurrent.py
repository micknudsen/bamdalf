"""Summarize completed concurrent native runs against existing viewer expectations."""

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re


def summarize(directory):
    results = json.loads((directory / "results.json").read_text())
    if not results["completed"] or results["mode"] != "concurrent":
        raise ValueError("Expected a completed concurrent run")
    groups = defaultdict(list)
    overlapping = [sample for sample in results["samples"]
                   if sample["import_running_before"] and sample["import_running_after"]]
    if not overlapping or not any(sample["progress_bytes_after"] > sample["progress_bytes_before"]
                                  for sample in overlapping):
        raise ValueError("No observed concurrent import progress and navigation")
    for sample in overlapping:
        groups[(sample["action"], sample["target_ms"])].append(sample["elapsed_ms"])
    timings = []
    for (action, target), values in sorted(groups.items()):
        within = sum(value <= target for value in values)
        timings.append({"action": action, "target_ms": target, "count": len(values),
                        "first_ms": values[0], "p95_ms": sorted(values)[math.ceil(.95 * len(values)) - 1],
                        "maximum_ms": max(values), "within_target": within,
                        "passed": within / len(values) >= .95})
    resources = directory.with_suffix(".time.log").read_text()
    match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", resources, re.M)
    if not match:
        raise ValueError("Missing Darwin time peak RSS")
    peak = max(int(match[1]), max(sample["process_peak_resident_bytes"] for sample in results["memory"]))
    return {"trial": directory.name, "creation_seconds": results["creation_seconds"],
            "total_navigation_count": results["navigation_count"], "overlapping_navigation_count": len(overlapping),
            "other_navigation_count": results["navigation_count"] - len(overlapping),
            "timings": timings, "memory_sample_count": len(results["memory"]),
            "peak_resident_bytes": peak,
            "peak_sampled_physical_footprint_bytes": max(sample["physical_footprint_bytes"] for sample in results["memory"]),
            "passed_existing_viewer_expectations": peak < 2 * 1024**3 and all(group["passed"] for group in timings)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trials", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([summarize(path) for path in args.trials], indent=2))
