"""Reproduce the independent GRCh38 oracle and the two native storage trials."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ReferenceFormat"))
from measure import expected_reads, make_route

BASES = 3_105_715_063
PINS = {
    "fasta": "592502666381c995059a6b4a5dda11e6b1f6b8efeea04e7dacfffe1e0d2f0d25",
    "fai": "e33afb84eb6463b2607798f86c6060e55eb549698c586268d6011f3ce815b122",
    "dictionary.tsv": "a4487e83b32ec20aabf5f20a1e7e6f3edf613dc9f58fc41680d7f2e1f0510c9a",
    "route.tsv": "571a16fb22f813e0f0ea6b3abf3ce6876cfaa2e1dfdaabd34ff548622fe1e2e1",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path, pin):
    if sha256(path) != PINS[pin]:
        raise ValueError(f"SHA-256 mismatch for {path}")


def prepare(args):
    verify(args.fasta, "fasta")
    verify(args.fai, "fai")
    args.oracle.mkdir(parents=True, exist_ok=False)
    index = {}
    for line in args.fai.read_text().splitlines():
        name, *fields = line.split("\t")
        index[name] = tuple(map(int, fields))
    if len(index) != 2_580 or sum(value[0] for value in index.values()) != BASES:
        raise ValueError("Unexpected publisher dictionary")
    with args.fasta.open("rb") as fasta, (args.oracle / "dictionary.tsv").open("x") as output:
        for line in fasta:
            if line.startswith(b">"):
                name, *metadata = line[1:].decode("ascii").split()
                m5, = [value[3:] for value in metadata if value.startswith("M5:")]
                print(name, index[name][0], m5, sep="\t", file=output)
    route = make_route(index)
    with (args.oracle / "route.tsv").open("x") as output:
        for (name, start, end), bases in zip(route, expected_reads(args.fasta, index, route)):
            print(name, start + 1, end, bases.decode("ascii"), sep="\t", file=output)
    for name in ["dictionary.tsv", "route.tsv"]:
        verify(args.oracle / name, name)


def native(executable, action, bundle, source):
    output = bundle.with_name(f"{bundle.stem}-{action}.json")
    resources = output.with_suffix(".log")
    cmd = ["/usr/bin/time", "-l", str(executable), action, str(bundle), str(source)]
    with output.open("x") as out, resources.open("x") as log:
        subprocess.run(cmd, stdout=out, stderr=log, check=True)
    peak = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", resources.read_text(), re.M)
    if not peak:
        raise ValueError(f"No process RSS in {resources}")
    return json.loads(output.read_text()), int(peak[1])


def collect(args):
    verify(args.fasta, "fasta")
    for name in ["dictionary.tsv", "route.tsv"]:
        verify(args.oracle / name, name)
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {
        "start_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "binary_sha256": sha256(args.executable),
        "expected_contigs": 2_580,
        "input_bases": BASES,
        "pins": PINS,
        "trials": [],
    }
    for number in (1, 2):
        bundle = args.output / f"build-{number}.bref"
        creation, rss = native(args.executable, "create", bundle, args.fasta)
        probe, _ = native(args.executable, "probe", bundle, args.oracle)
        opens = probe["validated_open_ns"]
        if len(opens) != 102:
            raise ValueError("Incomplete validated-open route")
        p95 = sorted(opens)[math.ceil(0.95 * len(opens)) - 1]
        size = bundle.stat().st_size
        trial = {
            "trial": number,
            "creation_ns": creation["creation_ns"],
            "creator_peak_rss_bytes": rss,
            "file_bytes": size,
            "bytes_per_base": size / BASES,
            "validated_open_ns": opens,
            "open_p95_ns": p95,
            "passed": creation["creation_ns"] <= 60_000_000_000 and rss <= 256 * 1024**2
                      and size * 100 <= 105 * BASES and p95 <= 50_000_000,
        }
        summary["trials"].append(trial)
    for trial in summary["trials"]:
        trial["bundle_sha256"] = sha256(args.output / f"build-{trial['trial']}.bref")
    summary["passed"] = all(trial["passed"] for trial in summary["trials"])
    (args.output / "storage.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    preparation = commands.add_parser("prepare")
    for name in ["fasta", "fai", "oracle"]:
        preparation.add_argument(name, type=Path)
    collection = commands.add_parser("collect")
    for name in ["executable", "fasta", "oracle", "output"]:
        collection.add_argument(name, type=Path)
    args = parser.parse_args()
    if args.action == "prepare":
        prepare(args)
    else:
        sys.exit(collect(args))
