#!/usr/bin/env python3
"""Summarize completed, separately executed qualification cases without pooling them."""

import csv
import hashlib
import json
import math
import pathlib
import statistics
import sys


def csv_file(path, rows):
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: summarize-qualification.py PROTOCOL CASE_RUNS_DIRECTORY NEW_OUTPUT_DIRECTORY")
    protocol_path, runs, output = map(pathlib.Path, sys.argv[1:])
    protocol_bytes = protocol_path.read_bytes()
    digest = hashlib.sha256(protocol_bytes).hexdigest()
    plan = json.loads(protocol_bytes)
    output.mkdir(parents=True, exist_ok=False)
    all_rows, summaries, completions, minute_rows = [], [], [], []
    for case in plan["cases"]:
        case_id = case["id"]
        directory = runs / case_id
        completion = json.loads((directory / "completion.json").read_text())
        if completion.get("completed") is not True or completion.get("protocol_sha256") != digest:
            raise SystemExit(f"Incomplete case or wrong protocol: {case_id}")
        if completion.get("cases") != [case_id]:
            raise SystemExit(f"Case must run in its own process: {case_id}")
        native = directory / "native" / case_id
        result = json.loads((native / "completion.json").read_text())
        rows = [json.loads(line) for line in (native / "samples.jsonl").read_text().splitlines()]
        expected_steps = result["iterations"] * len(case["steps"])
        if result["completed"] is not True or result["steps"] != expected_steps:
            raise SystemExit(f"Incomplete route: {case_id}")
        if len([row for row in rows if row["phase"] == "steps"]) != expected_steps:
            raise SystemExit(f"Missing sample rows: {case_id}")
        if not case.get("duration_seconds") and result["iterations"] != case["repetitions"]:
            raise SystemExit(f"Wrong repetitions: {case_id}")
        all_rows.extend(rows)
        measured = [row for row in rows if row["measured"] and "target_ms" in row]
        labels = sorted({row["action"] for row in measured}) if case_id.startswith("cached_") or case_id == "integrated_workflow" else ["all"]
        for label in labels:
            group = [row for row in measured if label == "all" or row["action"] == label]
            if not group:
                continue
            targets = {row["target_ms"] for row in group}
            if len(targets) != 1:
                # The integrated demonstration may use the same action at
                # different target classes; retain its steps separately.
                for row in group:
                    summaries.append(summarize(case_id, row["step"], [row]))
            else:
                summaries.append(summarize(case_id, label, group))
        peak = completion["external_process_peak_resident_bytes"]
        result["external_process_peak_resident_bytes"] = peak
        result["primary_memory_target_met"] = max(peak, result["process_lifetime_peak_resident_bytes"]) < plan["memory_limit_bytes"]
        if case.get("duration_seconds"):
            if result["navigation_elapsed_seconds"] < case["duration_seconds"]:
                raise SystemExit("Memory route did not reach its fixed duration")
            trace = [json.loads(line) for line in (native / "memory.jsonl").read_text().splitlines()]
            csv_file(output / "memory-trace.csv", trace)
            for minute in sorted({int(row["elapsed_seconds"] // 60) for row in trace}):
                values = [row for row in trace if int(row["elapsed_seconds"] // 60) == minute]
                minute_rows.append({"minute": minute, "samples": len(values),
                                    "resident_min_bytes": min(row["resident_bytes"] for row in values),
                                    "resident_max_bytes": max(row["resident_bytes"] for row in values),
                                    "physical_footprint_min_bytes": min(row["physical_footprint_bytes"] for row in values),
                                    "physical_footprint_max_bytes": max(row["physical_footprint_bytes"] for row in values)})
        completions.append(result)
    csv_file(output / "samples.csv", all_rows)
    csv_file(output / "summary.csv", summaries)
    csv_file(output / "memory-by-minute.csv", minute_rows)
    (output / "completion.json").write_text(json.dumps({
        "protocol_sha256": digest, "cases": completions,
        "measured_product_baseline": plan["baseline_commit"],
        "timing_cases_passed": all(row["observed_target_met"] for row in summaries if not row["demonstration_only"]),
        "memory_target_met": all(row["primary_memory_target_met"] for row in completions if row["case"].startswith("memory_")),
    }, indent=2) + "\n")
    print(f"Summarized {len(completions)} cases and {len(all_rows)} observations")
    for row in summaries:
        if not row["observed_target_met"]:
            print(f"MISS {row['case']}/{row['action']}: {row['within_target']}/{row['n']} <= {row['target_ms']} ms; p95={row['p95_ms']:.3f}")


def summarize(case_id, label, group):
    values = sorted(row["wall_ms"] for row in group)
    target = group[0]["target_ms"]
    within = sum(value <= target for value in values)
    return {"case": case_id, "action": label, "n": len(values), "target_ms": target,
            "within_target": within, "fraction_within_target": within / len(values),
            "observed_target_met": within / len(values) >= 0.95,
            "first_ms": group[0]["wall_ms"], "median_ms": statistics.median(values),
            "p95_ms": values[math.ceil(len(values) * 0.95) - 1], "maximum_ms": values[-1],
            "demonstration_only": case_id == "integrated_workflow"}


if __name__ == "__main__":
    main()
