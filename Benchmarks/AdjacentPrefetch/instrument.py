#!/usr/bin/env python3
"""Archive/build a probe-only source snapshot; interrupt actual optional reading."""
import json
import os
import pathlib
import shutil
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Benchmarks/BoundedTailQuery"))
from run import CASES, INPUTS, digest  # noqa: E402

PROBE = r'''import Foundation

/// Measurement-only source, absent from production/library builds.
public enum AdjacentPrefetchProbe {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var callback: (@Sendable () -> Void)?
        var interval: GenomicInterval?
        var count = 0
        var first = 0.0
        var last = 0.0
        var closed = 0.0
        var requiredFirst = 0.0
    }
    private static let state = State()

    public static func arm(_ callback: @escaping @Sendable () -> Void) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.callback = callback
        state.interval = nil
        state.count = 0
        state.first = 0
        state.last = 0
        state.closed = 0
        state.requiredFirst = 0
    }

    public static func decoded(_ interval: GenomicInterval, optional: Bool) {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
        state.lock.lock()
        var callback: (@Sendable () -> Void)?
        if !optional {
            if state.interval != nil, state.requiredFirst == 0 { state.requiredFirst = now }
            state.lock.unlock()
            return
        }
        if state.interval == nil, state.callback != nil {
            state.interval = interval
            state.first = now
            callback = state.callback
            state.callback = nil
        }
        if interval == state.interval {
            state.count += 1
            state.last = now
        }
        state.lock.unlock()
        callback?()
    }

    public static func closed(_ interval: GenomicInterval, optional: Bool) {
        guard optional else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.interval == interval { state.closed = now }
    }

    public static func snapshot() -> (decodedRecords: Int, firstRecordMilliseconds: Double, lastRecordMilliseconds: Double,
                                     optionalClosedMilliseconds: Double, foregroundFirstRecordMilliseconds: Double) {
        state.lock.lock()
        defer { state.lock.unlock() }
        return (state.count, state.first, state.last, state.closed, state.requiredFirst)
    }

    public static func disarm() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.callback = nil
    }
}
'''


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: python3 Benchmarks/AdjacentPrefetch/instrument.py NEW_OUTPUT_DIRECTORY [CHUNK_BASES]")
    out = pathlib.Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=False)
    chunk = int(sys.argv[2]) if len(sys.argv) == 3 else 1000
    snapshot = out / "source-snapshot"
    snapshot.mkdir()
    for name in ["Sources", "Benchmarks", "Tests"]:
        shutil.copytree(ROOT / name, snapshot / name, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(ROOT / "Package.swift", snapshot / "Package.swift")
    (snapshot / ".build").mkdir()
    (snapshot / ".build/htslib").symlink_to(ROOT / ".build/htslib", target_is_directory=True)
    reader = snapshot / "Sources/BamdalfKit/BAMFile.swift"
    before = reader.read_text()
    anchor = "            let status = bamdalf_query_next(query)\n"
    if before.count(anchor) != 1:
        raise SystemExit("Reader probe insertion point changed; inspect before adapting")
    close_anchor = "        defer { bamdalf_query_close(query) }\n"
    if before.count(close_anchor) != 1:
        raise SystemExit("Reader close-probe insertion point changed; inspect before adapting")
    instrumented = before.replace(anchor, anchor + "            if status >= 0 { AdjacentPrefetchProbe.decoded(interval, optional: budget != nil) }\n")
    instrumented = instrumented.replace(close_anchor,
        "        defer { bamdalf_query_close(query); AdjacentPrefetchProbe.closed(interval, optional: budget != nil) }\n")
    reader.write_text(instrumented)
    (snapshot / "Sources/BamdalfKit/AdjacentPrefetchProbe.swift").write_text(PROBE)
    (out / "production-worktree.patch").write_bytes(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT))
    (out / "commit.txt").write_bytes(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT))
    (out / "probe-insertion.txt").write_text(
        "Immediately after a successful native bamdalf_query_next, before the next cancellation check, record optional counts or the first foreground native record. Record optional iterator closure immediately after bamdalf_query_close.\n"
        "Probe source is archived in source-snapshot/Sources/BamdalfKit/AdjacentPrefetchProbe.swift. No production source is edited.\n"
    )
    hashes = {}
    for source in sorted(snapshot.rglob("*")):
        if source.is_file() and ".build" not in source.parts:
            hashes[str(source.relative_to(snapshot))] = digest(source)
    for relative, expected in INPUTS.values():
        if digest(ROOT / relative) != expected:
            raise SystemExit(f"Input checksum differs: {relative}")
        hashes[relative] = expected
        hashes[relative + ".bai"] = digest(ROOT / (relative + ".bai"))
    hashes["htslib/lib/libhts.a"] = digest(ROOT / ".build/htslib/lib/libhts.a")
    (out / "sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    environment = dict(os.environ)
    environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    command = ["swift", "build", "--package-path", str(snapshot), "--scratch-path", str(out / "build"),
               "-c", "release", "--product", "AdjacentPrefetch", "-Xswiftc", "-DADJACENT_PREFETCH_PROBE"]
    (out / "build-command.json").write_text(json.dumps(command, indent=2) + "\n")
    with (out / "build.log").open("w") as log:
        subprocess.run(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    executable = out / "build/release/AdjacentPrefetch"
    (out / "executable-sha256.txt").write_text(digest(executable) + "\n")
    cases = [case for case in CASES if case[0] in ("ordinary_1000", "dense_1000", "original_dense_1000")]
    rows = []
    for case, source, start, end, complete_start, complete_end in cases:
        width = end - start + 1
        jump_start, jump_end = start + 5000, end + 5000
        if start - 250 - width < complete_start or jump_end + 250 + width > complete_end:
            raise SystemExit(f"Probe route exceeds complete R/C extraction: {case}")
        for mode in ["drain", "interrupt"]:
            for repetition in range(1, 6):
                name = f"{case}-{mode}-r{repetition}"
                command = ["/usr/bin/time", "-l", str(executable), str(ROOT / INPUTS[source][0]),
                           f"chr20:{start}-{end}", "enabled", str(chunk), str(32 * 1024 * 1024),
                           str(8 * 1024 * 1024), "20000", str(out / (name + ".json")),
                           mode, f"chr20:{jump_start}-{jump_end}"]
                process = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True)
                (out / (name + ".time.txt")).write_text(process.stderr)
                if process.returncode:
                    (out / (name + ".stdout.txt")).write_text(process.stdout)
                    raise SystemExit(f"Probe observation failed ({process.returncode}): {name}\n{process.stderr}")
                result = json.loads(process.stdout)
                result.update(case=case, repetition=repetition)
                rows.append(result)
    summaries = []
    for case, *_ in cases:
        controls = [row for row in rows if row["case"] == case and row["mode"] == "drain"]
        interrupted = [row for row in rows if row["case"] == case and row["mode"] == "interrupt"]
        full_counts = {row["native_decoded_records_before_stop"] for row in controls}
        if len(full_counts) != 1 or any(row["native_decoded_records_before_stop"] >= min(full_counts) for row in interrupted):
            raise SystemExit(f"Probe did not establish partial active reading interruption: {case}")
        summaries.append({
            "case": case, "chunk_bases": chunk, "complete_native_decoded_records": min(full_counts),
            "interrupted_native_decoded_records": [row["native_decoded_records_before_stop"] for row in interrupted],
            "interrupted_optional_outcomes": sorted({row["first_optional_outcome"] for row in interrupted}),
            "control_optional_drain_median_ms": statistics.median(row["first_optional_total_wall_ms"] for row in controls),
            "interrupted_optional_total_wall_max_ms": max(row["first_optional_total_wall_ms"] for row in interrupted),
            "jump_ready_median_ms": statistics.median(row["jump_ready_ms"] for row in interrupted),
            "jump_ready_max_ms": max(row["jump_ready_ms"] for row in interrupted),
            "first_record_to_jump_max_ms": max(row["jump_issued_uptime_ms"] - row["first_native_record_uptime_ms"] for row in interrupted),
            "cancel_to_native_close_max_ms": max(row["optional_close_uptime_ms"] - row["jump_issued_uptime_ms"] for row in interrupted),
            "native_close_before_foreground_decode": all(row["optional_close_uptime_ms"] <= row["first_foreground_record_uptime_ms"] for row in interrupted),
        })
    (out / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
    print(f"Completed {len(rows)} actual-reader observations; {out / 'summary.json'}")


if __name__ == "__main__":
    main()
