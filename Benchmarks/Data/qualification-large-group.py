#!/usr/bin/env python3
"""Create a deliberately nonbiological large-group resource stress BAM."""

import hashlib
import json
import pathlib
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: qualification-large-group.py NEW_OUTPUT_DIRECTORY")
    root = pathlib.Path(__file__).resolve().parents[2]
    output = pathlib.Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=False)
    sam = output / "large-group.sam"
    bam = output / "large-group.bam"
    with sam.open("w") as stream:
        stream.write("@HD\tVN:1.6\tSO:coordinate\n@SQ\tSN:stress\tLN:10000\n@RG\tID:resource-stress\n")
        for index in range(10000):
            flag = 0 if index == 0 else 2048
            stream.write(f"large-template\t{flag}\tstress\t1001\t60\t148M\t*\t0\t0\t{'ACGT' * 37}\t*\tRG:Z:resource-stress\n")
    subprocess.run(["xcrun", "clang", "-O2", "-I", str(root / ".build/htslib/include"),
                    str(root / "scripts/generate-fixtures.c"), str(root / ".build/htslib/lib/libhts.a"),
                    "-lz", "-o", str(output / "generate-fixtures")], check=True)
    subprocess.run([str(output / "generate-fixtures"), str(sam), str(bam)], check=True)
    # Keep both generated indexes as evidence, but expose one to native opening.
    pathlib.Path(str(bam) + ".csi").rename(output / "large-group.csi.saved")
    subprocess.run(["xcrun", "clang", "-O2", "-I", str(root / ".build/htslib/include"),
                    str(root / "Benchmarks/Data/profile-sampling.c"), str(root / ".build/htslib/lib/libhts.a"),
                    "-lz", "-o", str(output / "profile-sampling")], check=True)
    with (output / "profile.tsv").open("w") as records, (output / "profile-counts.txt").open("w") as counts:
        subprocess.run([str(output / "profile-sampling"), str(bam), "stress:501-1500"],
                       stdout=records, stderr=counts, check=True)
    rows = [line.split("\t") for line in (output / "profile.tsv").read_text().splitlines()]
    if len(rows) != 10000 or {(row[0], row[1]) for row in rows} != {("resource-stress", "large-template")}:
        raise SystemExit("Independent HTSlib enumeration did not preserve the 10,000-record group")
    manifest = {
        "purpose": "Nonbiological resource stress: one exact RG/QNAME group with 10,000 independently stored alignments",
        "interval": "stress:501-1500", "eligible_records": 10000, "sampling_groups": 1,
        "expected_displayed_records": 10000, "expected_downsampled": False,
        "sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in [sam, bam, pathlib.Path(str(bam) + ".bai"), output / "large-group.csi.saved"]},
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
