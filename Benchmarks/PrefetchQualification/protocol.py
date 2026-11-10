#!/usr/bin/env python3
"""Generate and audit the frozen integrated-prefetch qualification protocol.

This is a conservative route/source audit, not an alternative viewer. The native
harness independently rejects every actual query and desired C outside coverage.
"""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / "Benchmarks/prefetch-qualification-v1.json"
DERIVED = ".local/measurements/issue-11/data/HG002.GRCh38.qualification-100x.bam"
SOURCE = ".local/measurements/issue-11/data/HG002.GRCh38.qualification-source.bam"
ROWS = ".local/measurements/issue-36/fixtures/rows.bam"
ROLLING = ".local/measurements/issue-36/fixtures/rolling.bam"
LARGE_GROUP = ".local/measurements/issue-11/large-group/large-group.bam"
REGIONS = [
    {"reference": "chr20", "start": 9830401, "end": 10354688},
    {"reference": "chr20", "start": 19988481, "end": 20119552},
    {"reference": "chr20", "start": 29818881, "end": 30081024},
]
WORKLOADS = [
    ("ordinary_a_1000", DERIVED, "chr20:10024501-10025500", 500, False),
    ("ordinary_a_10000", DERIVED, "chr20:10020001-10030000", 500, True),
    ("ordinary_b_1000", DERIVED, "chr20:20049501-20050500", 500, False),
    ("ordinary_b_10000", DERIVED, "chr20:20045001-20055000", 500, True),
    ("derived_dense_1000", DERIVED, "chr20:29892101-29893100", 1000, True),
    ("derived_dense_10000", DERIVED, "chr20:29887601-29897600", 1000, True),
    ("original_dense_1000", SOURCE, "chr20:29892101-29893100", 1000, True),
    ("original_dense_10000", SOURCE, "chr20:29887601-29897600", 1000, True),
]


def step(identifier, action, **fields):
    return {"id": identifier, "action": action, **fields}


def load(identifier, interval, **fields):
    return step(identifier, "type", interval=interval, **fields)


def settle(identifier="settle"):
    return step(identifier, "settle_optional", measure=False)


def case(identifier, bam, category, steps, *, setup=None, repetitions=1,
         fresh_session=False, finish=None, **fields):
    length = 20000 if bam == ROWS else 60000 if bam == ROLLING else 10000 if bam == LARGE_GROUP else 64444167
    reference = "tiny" if bam in (ROWS, ROLLING) else "stress" if bam == LARGE_GROUP else "chr20"
    coverage = ([{"reference": reference, "start": 1, "end": length}]
                if bam in (ROWS, ROLLING, LARGE_GROUP) else copy.deepcopy(REGIONS))
    return {"id": identifier, "bam": bam, "category": category,
            "repetitions": repetitions, "fresh_session": fresh_session,
            "complete_regions": coverage, "reference_lengths": {reference: length},
            "setup": setup or [], "steps": steps, "finish": finish or [], **fields}


def motion_step(identifier, action, target, **fields):
    return step(identifier, action, target_ms=target,
                query_free_target_ms=100, expected_continuity=True, **fields)


def build():
    prototypes = []
    for name, bam, interval, target, sampled in WORKLOADS:
        prototypes.append(case("uncached_" + name, bam, "first_ready", [
            load("load", interval, expected_query="positive", target_ms=target,
                 expected_interval=interval, expected_sampled=sampled, capture=True)
        ], repetitions=20, fresh_session=True))

    for name, bam, wide, narrow in [
        ("ordinary_a", DERIVED, "chr20:10020001-10030000", "chr20:10024501-10025500"),
        ("ordinary_b", DERIVED, "chr20:20045001-20055000", "chr20:20049501-20050500"),
        ("derived_dense", DERIVED, "chr20:29887601-29897600", "chr20:29892101-29893100"),
        ("original_dense", SOURCE, "chr20:29887601-29897600", "chr20:29892101-29893100"),
    ]:
        prototypes.append(case("cached_" + name, bam, "cached", [
            motion_step("pan_right", "pan_right", 100, expected_query="zero"),
            motion_step("pan_left", "pan_left", 100, expected_query="zero", expected_interval=narrow),
            step("zoom_out", "zoom_out", target_ms=100, expected_query="zero"),
            step("zoom_in", "zoom_in", target_ms=100, expected_query="zero", expected_interval=narrow),
        ], setup=[load("prime", wide, measure=False), settle(),
                  load("narrow", narrow, measure=False), settle("settle_narrow")], repetitions=20))

    # Both widths, ordinary and original dense: actual visual updates, including
    # moves beyond initial C. Derived dense already has separate first-ready and
    # cached cases; do not multiply equivalent timing routes unnecessarily.
    for name, bam, interval, target, sampled in [WORKLOADS[i] for i in (0, 1, 6, 7)]:
        setup = [load("load", interval, measure=False), settle()]
        prototypes.append(case("drag_" + name, bam, "drag", [
            step("left_preview", "mouse_drag", fraction=0.49, expected_query="zero",
                 target_ms=33, expected_continuity=True, period_ms=33),
            step("right_preview", "mouse_drag", fraction=0.51, expected_query="zero",
                 target_ms=33, expected_continuity=True, period_ms=33),
        ], setup=setup + [step("down", "mouse_down", fraction=0.5, measure=False)],
            repetitions=60, finish=[
                step("restore_preview", "mouse_drag", fraction=0.5, measure=False),
                step("release", "mouse_up", fraction=0.5, measure=False,
                     expected_interval=interval, expected_query="zero", capture=True)]))
        prototypes.append(case("scroll_" + name, bam, "scroll", [
            step("down", "scroll", delta=-180, expected_query="zero", target_ms=33,
                 expected_continuity=True, expected_scroll_change=True, period_ms=33, capture=True),
            step("up", "scroll", delta=180, expected_query="zero", target_ms=33,
                 expected_continuity=True, expected_scroll_change=True, period_ms=33),
        ], setup=setup, repetitions=60))

        route = [load("anchor", interval, measure=False), settle("initial_buffer")]
        for leg, direction in enumerate(("right", "left", "right")):
            route.extend(motion_step(f"pan_{leg}_{i:02d}", "pan_" + direction,
                                    target, period_ms=100, capture=(leg == 1 and i == 0))
                         for i in range(8))
        route.append(step("down", "mouse_down", fraction=0.75, measure=False))
        for cycle in range(2):
            for i, shift in enumerate(list(range(1, 9)) + list(range(7, -1, -1))):
                route.append(step(f"drag_{cycle}_{i:02d}", "mouse_drag",
                                  fraction=0.75 - shift * 0.25 - 0.0025,
                                  expected_query="zero", target_ms=33,
                                  expected_continuity=True, period_ms=33,
                                  capture=(cycle == 0 and i in (7, 15))))
        route.append(motion_step("release", "mouse_up", target, fraction=0.7475, capture=True))
        prototypes.append(case("rolling_" + name, bam, "rolling", route,
                               repetitions=5, fresh_session=True))

    # The accepted baseline plan explicitly includes large groups. All 10,000
    # distinct fixture records belong to one RG/QNAME group; the display-group
    # budget must not truncate it. Geometry is known from the generator.
    large_interval = "stress:501-1500"
    prototypes.append(case("large_group_uncached", LARGE_GROUP, "first_ready", [
        load("load", large_interval, target_ms=1000, expected_query="positive",
             expected_sampled=False, expected_records=10000, capture=True),
    ], repetitions=20, fresh_session=True))
    large_setup = [load("load", large_interval, measure=False, expected_records=10000), settle()]
    prototypes.append(case("drag_large_group", LARGE_GROUP, "drag", [
        step("left_preview", "mouse_drag", fraction=0.49, expected_query="zero", target_ms=33,
             expected_continuity=True, expected_records=10000, period_ms=33),
        step("right_preview", "mouse_drag", fraction=0.51, expected_query="zero", target_ms=33,
             expected_continuity=True, expected_records=10000, period_ms=33),
    ], setup=large_setup + [step("down", "mouse_down", fraction=0.5, measure=False)],
        repetitions=60, finish=[
            step("restore_preview", "mouse_drag", fraction=0.5, measure=False),
            step("release", "mouse_up", fraction=0.5, measure=False,
                 expected_interval=large_interval, expected_records=10000, capture=True)]))
    prototypes.append(case("scroll_large_group", LARGE_GROUP, "scroll", [
        step("down", "scroll", delta=-180, expected_query="zero", target_ms=33,
             expected_continuity=True, expected_scroll_change=True, expected_records=10000,
             period_ms=33, capture=True),
        step("up", "scroll", delta=180, expected_query="zero", target_ms=33,
             expected_continuity=True, expected_scroll_change=True, expected_records=10000, period_ms=33),
    ], setup=large_setup, repetitions=60))

    prototypes.append(case("integrated_workflow", DERIVED, "demonstration", [
        load("typed_unsampled", "chr20:10024501-10025500", expected_sampled=False, target_ms=500, capture=True),
        settle(),
        motion_step("toolbar_pan", "pan_right", 500),
        step("toolbar_zoom", "zoom_out", target_ms=500, query_free_target_ms=100),
        load("typed_sampled", "chr20:10020001-10030000", expected_sampled=True, target_ms=500, capture=True),
        settle("sampled_buffer"),
        step("wide", "zoom_out", expected_query="zero", expected_suppressed=True, target_ms=100, capture=True),
        step("return", "zoom_in", expected_suppressed=False, target_ms=500, query_free_target_ms=100),
        step("mouse_in", "double_click", fraction=0.25, target_ms=500, query_free_target_ms=100),
        step("mouse_out", "option_click", fraction=0.75, target_ms=500, query_free_target_ms=100),
        step("draft", "draft", interval="unfinished coordinate draft", measure=False),
        step("down", "mouse_down", fraction=0.75, measure=False),
        step("preview", "mouse_drag", fraction=0.2475, target_ms=33, expected_continuity=True,
             expected_draft="unfinished coordinate draft", capture=True),
        motion_step("commit", "mouse_up", 500, fraction=0.2475, capture=True),
        step("scroll_down", "scroll", delta=-180, expected_query="zero", target_ms=33,
             expected_scroll_change=True, expected_continuity=True, capture=True),
        step("scroll_up", "scroll", delta=180, expected_query="zero", target_ms=33,
             expected_scroll_change=True, expected_continuity=True),
    ]))

    prototypes.append(case("empty_recovery_reference_limits", ROWS, "demonstration", [
        load("nonempty", "tiny:101-200", expected_sampled=False, target_ms=500, capture=True),
        settle(),
        load("empty", "tiny:5000-5099", expected_records=0, expected_sampled=False, target_ms=500, capture=True),
        load("restore_nonempty", "tiny:101-200", target_ms=500, expected_selection_of="nonempty"),
        step("failed_target", "required_failure", interval="tiny:15000-15099",
             expected_interval="tiny:101-200", expected_selection_of="nonempty", capture=True, measure=False),
        step("dismiss", "dismiss_error", measure=False),
        load("left_end", "tiny:1-100", target_ms=500, capture=True),
        load("right_end", "tiny:19901-20000", expected_records=0, target_ms=500, capture=True),
        load("whole_reference", "tiny:1-20000", expected_suppressed=True,
             expected_query="zero", target_ms=100, capture=True),
    ]))
    prototypes.append(case("tail_workflow", ROLLING, "demonstration", [
        load("before_tail", "tiny:1450-1549", expected_records=80, target_ms=500, capture=True),
        settle(),
        step("draft", "draft", interval="tail inspection draft", measure=False),
        step("down", "mouse_down", fraction=0.75, measure=False),
        step("latest_preview", "mouse_drag", fraction=-0.2525, target_ms=33,
             expected_continuity=True, expected_interval="tiny:1550-1649",
             expected_draft="tail inspection draft", capture=True),
        settle("preview_buffer"),
        step("scroll_tail_rows", "scroll", delta=-1800, target_ms=33,
             expected_continuity=True, expected_draft="tail inspection draft", capture=True),
        motion_step("release", "mouse_up", 500, fraction=-0.2525,
                    expected_interval="tiny:1550-1649", expected_records=83, capture=True),
    ]))

    memory = [load("anchor", "chr20:10000001-10010000", capture=True)]
    for direction in ("right", "left"):
        memory += [motion_step(f"long_pan_{direction}_{i:02d}", "pan_" + direction,
                               1000, period_ms=100) for i in range(40)]
    for i, start in enumerate((9850001, 9880001, 9910001, 9940001, 9970001,
                               20010001, 20040001, 20070001,
                               29840001, 29870001, 29930001, 29960001)):
        memory.append(load(f"disjoint_{i:02d}", f"chr20:{start}-{start + 9999}",
                           target_ms=1000, query_free_target_ms=100, period_ms=100))
    memory += [
        load("anchor_revisit", "chr20:10000001-10010000", target_ms=1000,
             query_free_target_ms=100, expected_query="positive", expected_selection_of="anchor"),
        load("dense", "chr20:29887601-29897600", target_ms=1000, query_free_target_ms=100),
        step("dense_scroll_down", "scroll", delta=-180, target_ms=33, expected_query="zero",
             expected_scroll_change=True, expected_continuity=True),
        step("dense_scroll_up", "scroll", delta=180, target_ms=33, expected_query="zero",
             expected_scroll_change=True, expected_continuity=True),
        step("drag_down", "mouse_down", fraction=0.75, measure=False),
        step("drag", "mouse_drag", fraction=0.2475, target_ms=33, expected_query="zero",
             expected_continuity=True, period_ms=33),
        motion_step("release", "mouse_up", 1000, fraction=0.2475),
        step("wide", "zoom_out", target_ms=100, expected_query="zero", expected_suppressed=True),
        step("return", "zoom_in", target_ms=1000, query_free_target_ms=100, expected_suppressed=False),
    ]
    prototypes.append(case("memory_600_seconds", SOURCE, "memory", memory,
                           setup=[load("warmup", "chr20:10000001-10010000", measure=False), settle()],
                           duration_seconds=600, pause_ms=0))

    paired = []
    for index, prototype in enumerate(prototypes):
        # Alternate which mode gets the first process for each workload.
        for enabled in ((False, True) if index % 2 == 0 else (True, False)):
            item = copy.deepcopy(prototype)
            item["prefetch_enabled"] = enabled
            item["id"] += "_enabled" if enabled else "_disabled"
            paired.append(item)
    return {
        "schema_version": 1, "protocol_id": "prefetch-qualification-v1-2026-11-11",
        "baseline_commit": "12187b1f740e0fc00fffe59a40e8c3493877b2a2",
        "prepared_date": "2026-11-11", "timezone": "Europe/Copenhagen",
        "window_width_points": 1100, "window_height_points": 720, "sampling_seed": 42,
        "memory_limit_bytes": 2147483648, "timing_pass_fraction": 0.95,
        "settings": {"margin_bases": 250, "prefetch_buffer": "max(W,250)",
                     "refill_fraction": 0.5, "optional_chunk_bases": 1000,
                     "optional_cache_bytes": 33554432, "optional_query_bytes": 8388608,
                     "optional_query_records": 20000, "maximum_attempts": 80,
                     "maximum_failed_ranges": 64, "alignment_visible_width": 10000},
        "hardware": {"cpu": "Apple M4", "memory_bytes": 17179869184},
        "build": {"configuration": "release", "swift": "6.4.2", "htslib": "1.25",
                  "xcode": "27.2", "macos": "27.2", "macos_build": "26B123",
                  "provenance": "Each run archives actual environment, source, executable, protocol, and input hashes; reject a baseline mismatch rather than relabel it."},
        "inputs": {
            DERIVED: "b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33",
            SOURCE: "d2c2aba71c005d7b8e8b69841566475ae2c4418105deba15b4d11fa1697b6d08",
            ROWS: "4cf5e2539c9143bd70b5c0b9d2826381fef5b7e59b0d881b267a39fd6bcb8880",
            ROLLING: "733dd9d4690d80025e567d88e0096641eda28d709885928756ff77c0687e9f3b",
            LARGE_GROUP: "04518ed00407ae76c0d841f1ca62275373062a55360e0129f0787a2a05eb2617",
        },
        "indexes": {
            DERIVED + ".bai": "b1bb5a7c36b5bf3fb8fd3c5c3b728d4881364e87a45d159d55909c503678c0fd",
            SOURCE + ".bai": "4be408f33aa74b94a52b16e17592a3b32abc76e110c136c156c8e09f21d5d815",
            ROWS + ".bai": "a55fd31ba10d604b5c73f0d8dae5a0a73adb2a091c81f92bb33c9dc70a257891",
            ROLLING + ".bai": "564375e9d43f18812c1f00edba403c362028a779d32548e96474b331f92c0838",
            LARGE_GROUP + ".bai": "35fab6b26111ebe8deea04ea7a2c8e3fb9d2c1a88baf13d72431134db792b124",
        },
        "cache_conditions": "Each case runs in its own process. fresh_session resets app state for every iteration, not OS caches. Input checksum reads and prior runs warm file caches; no cold-disk claim.",
        "timing_boundary": "Native input dispatch through required readiness, layout, and immediate actual viewport/ruler bitmap raster. Excludes compositor, physical presentation, captures, validation, and cadence waits.",
        "cases": paired,
    }


def parse_interval(value):
    reference, bounds = value.replace(",", "").rsplit(":", 1)
    start, end = map(int, bounds.split("-"))
    if start < 1 or end < start:
        raise ValueError(f"Invalid interval {value}")
    return reference, start, end


def nearest(value):
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def audit_case(item, settings):
    target = None
    drag = None
    envelopes = {}
    audited = 0
    maximum_width = settings["alignment_visible_width"]
    margin = settings["margin_bases"]

    def check(value, fractional=False):
        nonlocal audited
        reference, start, end = value
        length = item["reference_lengths"][reference]
        if start < 1 or end > length:
            raise ValueError(f"{item['id']}: target outside reference: {value}")
        width = end - start + 1
        if width > maximum_width:
            return
        # One extra base at each fractional edge is a conservative envelope.
        rounding = 1 if fractional else 0
        padding = margin + max(width + 2 * rounding, margin) + rounding
        desired = (max(1, start - padding), min(length, end + padding))
        if not any(region["reference"] == reference and region["start"] <= desired[0]
                   and desired[1] <= region["end"] for region in item["complete_regions"]):
            raise ValueError(f"{item['id']}: desired C {reference}:{desired[0]}-{desired[1]} exceeds complete source")
        span = envelopes.setdefault(reference, [desired[0], desired[1]])
        span[0], span[1] = min(span[0], desired[0]), max(span[1], desired[1])
        audited += 1

    def actions(steps):
        nonlocal target, drag
        for entry in steps:
            action = entry["action"]
            if action in ("type", "required_failure"):
                target = parse_interval(entry["interval"])
                drag = None
            elif action in ("pan_left", "pan_right"):
                reference, start, end = target
                width = end - start + 1
                movement = (width + 1) // 2 * (-1 if action == "pan_left" else 1)
                start = min(max(1, start + movement), item["reference_lengths"][reference] - width + 1)
                target = reference, start, start + width - 1
            elif action in ("zoom_in", "zoom_out", "double_click", "option_click"):
                reference, start, end = target
                length = item["reference_lengths"][reference]
                width = end - start + 1
                narrowing = action in ("zoom_in", "double_click")
                new_width = (width + 1) // 2 if narrowing else min(length, width * 2)
                if action in ("double_click", "option_click"):
                    locus = start + min(width - 1, int(min(1, max(0, entry["fraction"])) * width))
                    start = locus - new_width // 2
                else:
                    start += (width - new_width) // 2
                start = min(max(1, start), length - new_width + 1)
                target = reference, start, start + new_width - 1
            elif action == "mouse_down":
                drag = target, entry["fraction"]
            elif action == "mouse_drag":
                (reference, start, end), origin_fraction = drag
                width = end - start + 1
                delta = nearest(-(entry["fraction"] - origin_fraction) * width)
                delta = min(max(1 - start, delta), item["reference_lengths"][reference] - end)
                target = reference, start + delta, end + delta
            elif action == "mouse_up":
                drag = None
            elif action not in ("scroll", "settle_optional", "draft", "dismiss_error"):
                raise ValueError(f"Unknown protocol action: {action}")
            if target is not None:
                check(target, fractional=drag is not None)
            if action == "required_failure":
                target = parse_interval(entry["expected_interval"])
                check(target)

    actions(item["setup"])
    # A duration route has a fixed reset anchor. Audit two cycles to catch any
    # carried-state errors; actual runtime queries/C remain independently checked.
    repetitions = 2 if item.get("duration_seconds") else item["repetitions"]
    for _ in range(repetitions):
        actions(item["steps"])
        if item["fresh_session"]:
            actions(item["finish"])
            target = drag = None
            actions(item["setup"])
    if not item["fresh_session"]:
        actions(item["finish"])
    return {"case": item["id"], "audited_presentations": audited,
            "desired_coverage_envelopes": envelopes,
            "complete_regions": item["complete_regions"]}


def audit(plan):
    identifiers = [item["id"] for item in plan["cases"]]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Duplicate case identifiers")
    results = [audit_case(item, plan["settings"]) for item in plan["cases"]]
    return {"protocol_id": plan["protocol_id"], "cases": results,
            "case_count": len(results), "audited_presentations": sum(r["audited_presentations"] for r in results),
            "scope": "Conservative target and full desired C route audit; actual queries and C are independently validated by native harness."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", nargs="?", type=Path, default=DEFAULT)
    parser.add_argument("--generate", action="store_true", help="write protocol before qualification collection")
    args = parser.parse_args()
    if args.generate:
        if args.protocol.exists():
            parser.error("Protocol exists; preserve it and generate a new version at a new path")
        plan = build()
        audit(plan)
        args.protocol.write_text(json.dumps(plan, indent=2) + "\n")
    data = args.protocol.read_bytes()
    result = audit(json.loads(data))
    result["protocol_sha256"] = hashlib.sha256(data).hexdigest()
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
