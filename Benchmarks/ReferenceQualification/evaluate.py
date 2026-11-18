"""Apply the frozen reference gates to every measured event in a complete native run."""

import argparse
from collections import defaultdict
from pathlib import Path
import hashlib
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "PrefetchQualification"))
from audit import audit_case
from summarize import summarize, write_csv

MOTION = {"mouse_drag", "scroll"}
NAVIGATION = {"type", "pan_left", "pan_right", "zoom_in", "zoom_out", "double_click", "option_click", "mouse_up"}


def limit(row):
    if row["action"] in MOTION:
        return 33
    if row["action"] not in NAVIGATION:
        raise ValueError(f"Unclassified measured action {row['case']}/{row['step']}")
    # The historical memory route times each ordinary anchor but omits its
    # limit. The global query-free gate applies to every navigation action.
    cap = row.get("target_ms")
    if cap is None:
        if row["step"] != "anchor" or not row["case"].startswith("memory_600_seconds_"):
            raise ValueError(f"Missing load class in {row['case']}/{row['step']}")
        cap = 500
    return min(100, cap) if row["required_query_calls"] == 0 else cap


def evaluate(protocol, runs, output):
    data = protocol.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    plan = json.loads(data)
    if digest != "3375c1bc239eb91065f00ff853db801c5581e2ffa25f5921d8d6599ab29c587f":
        raise ValueError("Viewer route differs from the frozen reference protocol")
    root = Path(__file__).resolve().parents[2]
    bundle, = {case["reference_bundle"] for case in plan["cases"] if case.get("reference_bundle")}
    storage = json.loads((root / bundle).with_name("storage.json").read_text())
    hashes = json.loads((runs / "sha256.json").read_text())
    if not storage["passed"] or storage["trials"][0]["bundle_sha256"] != hashes[bundle]:
        raise ValueError("Viewer input differs from the first approved storage trial")
    completed = json.loads((runs / "execution-completion.json").read_text())
    expected = [case["id"] for case in plan["cases"]]
    if not completed["all_protocol_cases"] or completed["cases"] != expected or completed["protocol_sha256"] != digest:
        raise ValueError("Expected every frozen case, in protocol order")
    output.mkdir(parents=True, exist_ok=False)
    timing, cases, memory_detail = [], [], []
    for case in plan["cases"]:
        case_id = case["id"]
        source_mode = case_id.rsplit("_", 1)[1]
        directory = runs / case_id
        native = directory / "native" / case_id
        route = audit_case(case, directory, digest)
        stats = json.loads((native / "completion.json").read_text())
        observations = [json.loads(line) for line in (native / "samples.jsonl").read_text().splitlines()]
        measured = [row for row in observations if row["measured"]]
        measured_steps = {step["id"] for step in case["steps"] if step.get("measure", True)}
        expected_steps = sum(step.get("measure", True) for step in case["steps"])
        if len(measured) != stats["iterations"] * expected_steps:
            raise ValueError(f"Incomplete measured events in {case_id}")
        if case.get("duration_seconds"):
            if stats["navigation_elapsed_seconds"] < case["duration_seconds"]:
                raise ValueError(f"Incomplete active memory duration in {case_id}")
        elif stats["iterations"] != case["repetitions"]:
            raise ValueError(f"Incomplete repetitions in {case_id}")
        groups, detail = defaultdict(list), defaultdict(list)
        for row in observations:
            if row["measured"] != (row["phase"] == "steps" and row["step"] in measured_steps):
                raise ValueError(f"Incorrect event measurement flag in {case_id}")
            if row["reference_selected"] != (source_mode != "bam") or row["bam_selected"] != (source_mode != "reference"):
                raise ValueError(f"Incorrect selected sources in {case_id}")
        for row in measured:
            row["target_ms"] = limit(row)
            groups[row["action"], row["target_ms"]].append(row)
            if case.get("duration_seconds") and row["step"] in {"anchor", "ordinary_cells", "ordinary_letters", "dense_cells", "dense_letters"}:
                detail[row["step"], row["target_ms"]].append(row)
        for values, destination in [(groups, timing), (detail, memory_detail)]:
            for (label, target), rows in sorted(values.items()):
                summary = summarize(case, label, rows)
                summary.pop("prefetch_enabled")
                destination.append({"source_mode": source_mode, **summary})
        resource = json.loads((directory / "completion.json").read_text())
        peak = max(resource["external_process_peak_resident_bytes"], stats["process_lifetime_peak_resident_bytes"])
        cases.append(dict(case=case_id, source_mode=source_mode, iterations=stats["iterations"],
                          route_events=route["events_checked"], measured_events=len(measured),
                          elapsed_s=stats["navigation_elapsed_seconds"], peak_rss_bytes=peak,
                          rss_target_met=peak < plan["memory_limit_bytes"], samples_sha256=route["samples_sha256"]))
    write_csv(output / "timing.csv", timing)
    write_csv(output / "memory-detail.csv", memory_detail)
    write_csv(output / "cases.csv", cases)
    misses = [row for row in timing + memory_detail if not row["observed_target_met"]]
    for row in misses:
        print(f"MISS {row['case']}/{row['action']} at {row['target_ms']} ms: {row['within_target']}/{row['n']}")
    return not misses and all(case["rss_target_met"] for case in cases)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    for name in ["protocol", "runs", "output"]:
        cli.add_argument(name, type=Path)
    args = cli.parse_args()
    sys.exit(0 if evaluate(args.protocol, args.runs, args.output) else 1)
