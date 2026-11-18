"""Protocol v1, macOS. Run each create and probe in a fresh interpreter."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import resource
import sqlite3
import sys
from time import perf_counter_ns

from candidate import Bundle, REGIONAL_QUERY, create


def make_route(index):
    rng = random.Random(49)
    route = []
    for contig in ("chr1", "chr20", "chrX"):
        for width in (1, 80, 1000, 10000):
            for _ in range(8):
                start = rng.randrange(index[contig][0] - width + 1)
                route.append((contig, start, start + width))
        for boundary in (65536, 262144):
            route.append((contig, boundary - 50, boundary + 50))
    rng.shuffle(route)
    return route


def expected_reads(source, index, route):
    expected = []
    with source.open("rb") as fasta:
        for contig, start, stop in route:
            _, offset, bases, stride = index[contig]
            first = offset + start // bases * stride + start % bases
            end = offset + (stop - 1) // bases * stride + (stop - 1) % bases + 1
            fasta.seek(first)
            value = fasta.read(end - first).replace(b"\n", b"").replace(b"\r", b"")
            if len(value) != stop - start:
                raise ValueError("Publisher FAI and FASTA disagree")
            expected.append(value)
    return expected


def probe(source, fai, bundle):
    index = {}
    for row in fai.read_text().splitlines():
        name, *fields = row.split("\t")
        index[name] = tuple(map(int, fields))
    # The assembly publisher supplied one digest in each FASTA header.
    with source.open("rb") as fasta:
        dictionary = {}
        for line in fasta:
            if line.startswith(b">"):
                name = line[1:].split(None, 1)[0].decode()
                m5, = (field[3:].decode() for field in line.split() if field.startswith(b"M5:"))
                dictionary[name] = (index[name][0], m5)
    route = make_route(index)
    oracle = expected_reads(source, index, route)
    samples = []
    for region, expected in zip(route, oracle):
        start = perf_counter_ns()
        with Bundle(bundle) as db:
            opened = perf_counter_ns()
            value = db.read(*region)
            fetched = perf_counter_ns()
            repeated = db.read(*region)
            finished = perf_counter_ns()
            if value != expected or repeated != expected or db.dictionary != dictionary:
                raise ValueError("Mismatch with publisher FASTA, FAI or M5")
            samples.append({"open_ms": (opened - start) / 1e6, "first_ms": (fetched - opened) / 1e6,
                            "repeat_ms": (finished - fetched) / 1e6, "region": region,
                            "payload_rows": db.payload_rows // 2, "payload_bytes": db.payload_bytes // 2})
    times = {}
    for field in ("open_ms", "first_ms", "repeat_ms"):
        ordered = sorted(row[field] for row in samples)
        times[field] = {key: ordered[math.ceil(len(samples) * fraction) - 1]
                        for key, fraction in (("p50", .5), ("p95", .95), ("max", 1))}
    with Bundle(bundle) as db:
        plan = list(db.db.execute("EXPLAIN QUERY PLAN " + REGIONAL_QUERY, (65536, 1, 1)))
        options = [row[0] for row in db.db.execute("PRAGMA compile_options")]
        source_id = db.db.execute("SELECT sqlite_source_id()").fetchone()[0]
    return {"samples": samples, "latency": times, "contigs": len(dictionary),
            "bases": sum(value[0] for value in dictionary.values()), "query_plan": plan,
            "sqlite_source_id": source_id, "compile_options": options,
            "expected_region_sha256": hashlib.sha256(b"".join(oracle)).hexdigest()}


def main():
    parser = argparse.ArgumentParser(__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    build = commands.add_parser("create")
    build.add_argument("source", type=Path)
    build.add_argument("bundle", type=Path)
    build.add_argument("kib", type=int, choices=(64, 256))
    read = commands.add_parser("probe")
    read.add_argument("source", type=Path)
    read.add_argument("fai", type=Path)
    read.add_argument("bundle", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("The pinned benchmark reports Darwin ru_maxrss in bytes")
    if args.action == "create":
        start = perf_counter_ns()
        create(args.source, args.bundle, args.kib * 1024)
        report = {"creation_seconds": (perf_counter_ns() - start) / 1e9}
    else:
        report = probe(args.source, args.fai, args.bundle)
    report.update(bundle_bytes=args.bundle.stat().st_size, sqlite=sqlite3.sqlite_version,
                  python=sys.version, process_peak_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
