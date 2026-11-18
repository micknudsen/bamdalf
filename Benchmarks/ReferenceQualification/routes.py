"""Expand the pinned production-prefetch routes for the three viewer source modes."""

import argparse
import copy
import hashlib
import json
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / "prefetch-qualification-v1.json"
BUNDLE = ".local/measurements/issue-56/storage/build-1.bref"


def detail_cases(workloads):
    cases = []
    for locus, start in (("ordinary_a", 10000001), ("original_dense", 29892101)):
        interval = f"chr20:{start}-{start + 99}"
        for action in ("uncached", "drag", "scroll"):
            case = copy.deepcopy(workloads[f"{action}_{locus}_1000"])
            case["id"] = f"{action}_{locus}_100"
            for step in case["setup"] + case["steps"] + case["finish"]:
                if "interval" in step:
                    step["interval"] = interval
                if "expected_interval" in step:
                    step["expected_interval"] = interval
                # Counts and actual sampling in this additional 100-base window
                # need not equal those of the original 1 kb panel.
                step.pop("expected_sampled", None)
            cases.append(case)
    return cases


def memory_detail(case):
    for label, start, width, target in (("ordinary_letters", 10000001, 100, 500),
                                       ("ordinary_cells", 10024501, 1000, 500),
                                       ("dense_letters", 29892101, 100, 1000),
                                       ("dense_cells", 29892101, 1000, 1000)):
        case["steps"].append(dict(id=label, action="type", interval=f"chr20:{start}-{start + width - 1}",
                                  target_ms=target, query_free_target_ms=100))


def standalone(original):
    case = copy.deepcopy(original)
    case.pop("bam")
    # A reference-only window has no BAM rows to scroll or sample.
    case["steps"] = [s for s in case["steps"] if s["action"] != "scroll"]
    for step in case["setup"] + case["steps"] + case["finish"]:
        step.pop("expected_sampled", None)
        step.pop("expected_suppressed", None)
        step["expected_query"] = "zero"
        if "target_ms" in step:
            step["target_ms"] = min(100, step["target_ms"])
    return case


def build():
    source = BASE.read_bytes()
    if hashlib.sha256(source).hexdigest() != "cd18bdd8ea6dcc54d3253b1061aaf9c96aa65862b5d9f30c0844bf1a561c6aad":
        raise ValueError("Historical source protocol has changed")
    plan = json.loads(source)
    workloads = {c["id"].removesuffix("_enabled"): c for c in plan["cases"] if c["prefetch_enabled"]}
    expanded = []
    for case in workloads.values():
        case["id"] = case["id"].removesuffix("_enabled")
        if case.get("duration_seconds"):
            memory_detail(case)
    for i, case in enumerate(list(workloads.values()) + detail_cases(workloads)):
        is_wgs = "HG002." in case["bam"]
        modes = ["paired", "bam"] if i % 2 == 0 else ["bam", "paired"]
        if not is_wgs:
            modes = ["bam"]
        if case["id"] in {
            "uncached_ordinary_a_100", "uncached_ordinary_a_1000", "uncached_ordinary_a_10000",
            "cached_ordinary_a", "drag_ordinary_a_100", "drag_ordinary_a_1000",
            "drag_ordinary_a_10000", "integrated_workflow", "memory_600_seconds",
        }:
            modes += ["reference"]
        for mode in modes:
            item = standalone(case) if mode == "reference" else copy.deepcopy(case)
            item["id"] = f"{case['id']}_{mode}"
            if mode != "bam":
                item["reference_bundle"] = BUNDLE
            expanded.append(item)
    plan.update(protocol_id="reference-milestone-v1", prepared_date="2026-11-18",
                baseline_commit="a42863fda106b45aed98beb4152b42fbf510317f", cases=expanded,
                timing_boundary="Native input through required readiness, layout and actual ruler, reference and alignment track drawing. See frozen protocol.")
    plan["build"].update(macos="27.2.1", macos_build="26B131")
    return plan


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("output", type=Path, help="New protocol file")
    args = cli.parse_args()
    with args.output.open("x") as output:
        json.dump(build(), output, indent=2)
        output.write("\n")
