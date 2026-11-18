"""Derive detail expectations directly from publisher FASTA/FAI and HG002 BAM bytes."""
import argparse
import gzip
import hashlib
import json
import struct
import sys
from pathlib import Path

BENCHMARKS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BENCHMARKS / "Data"))
from acquire import read_reference_index
sys.path.insert(0, str(BENCHMARKS / "ReferenceFormat"))
from measure import expected_reads

# One-based inclusive starts. Keep the two depths distinct even at the same locus.
CASES = [
    ("100x", 10_000_001, 100), ("100x", 10_024_501, 1000),
    ("source", 29_892_101, 100), ("source", 29_892_101, 1000),
    ("100x", 20_049_501, 1000), ("100x", 29_892_101, 1000),
]
ALPHABET = "=ACMGRSVTWYHKDBN"


def u32(stream):
    return struct.unpack("<I", stream.read(4))[0]


def reference_dictionary(bam):
    with gzip.open(bam, "rb") as stream:
        if stream.read(4) != b"BAM\1":
            raise ValueError("Invalid BAM")
        header = stream.read(u32(stream))
        references = {}
        for _ in range(u32(stream)):
            name = stream.read(u32(stream)).rstrip(b"\0").decode()
            references[name] = u32(stream)
    return references, sum(b"\tM5:" in row for row in header.splitlines() if row.startswith(b"@SQ\t"))


def region_records(bam, reference_id, start, end):
    _, linear = read_reference_index(bam.with_suffix(".bam.bai"), reference_id)
    offset = linear[(start - 1) >> 14]
    seen = set()
    with bam.open("rb") as raw:
        raw.seek(offset >> 16)
        with gzip.GzipFile(fileobj=raw) as stream:
            stream.read(offset & 65535)
            while size := stream.read(4):
                record = stream.read(struct.unpack("<I", size)[0])
                tid, zero_start, name_info, flags_cigar = struct.unpack_from("<iiII", record)
                if tid != reference_id or zero_start >= end:
                    break
                flags = flags_cigar >> 16
                if flags & 0x704:  # unmapped, secondary, vendor QC failure or duplicate
                    continue
                cursor = 32 + (name_info & 255)
                name = record[32:cursor - 1].decode()
                key = (name, zero_start + 1, bool(flags & 16))
                if key in seen:
                    raise ValueError(f"Ambiguous visible record identity {key}")
                seen.add(key)
                count = flags_cigar & 65535
                cigar = struct.unpack_from("<" + "I" * count, record, cursor)
                sequence_length = struct.unpack_from("<I", record, 16)[0]
                if sequence_length:
                    begin = cursor + count * 4
                    yield (*key, cigar, record[begin:begin + (sequence_length + 1) // 2])


def comparisons(start, reference, cigar, packed, pos):
    """Yield one-based coordinates and read bases, plus distance to segment ends."""
    query = 0
    for encoded in cigar:
        op, n = encoded & 15, encoded >> 4
        if op in (0, 7, 8):  # M, =, X consume query and reference
            for i in range(max(0, start - pos), min(n, start + len(reference) - pos)):
                index = i + query
                byte = packed[index // 2]
                base = ALPHABET[byte & 15 if index % 2 else byte >> 4]
                expected = reference[pos + i - start].upper()
                if base in "ACGT" and expected in "ACGT":
                    yield pos + i, base, min(i, n - i - 1), base != expected
        if op in (0, 1, 4, 7, 8):
            query += n
        if op in (0, 2, 3, 7, 8):
            pos += n


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("measurements", type=Path, help="Parent of issue-11 and issue-49")
    parser.add_argument("output", type=Path, help="New directory for generated expectations")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    reference_dir = args.measurements / "issue-49"
    source, = reference_dir.glob("*.fna")
    index = {}
    for row in (reference_dir / "publisher.fai").read_text().splitlines():
        name, *fields = row.split("\t")
        index[name] = tuple(map(int, fields))
    summary = []
    for panel, start, width in CASES:
        bam = args.measurements / "issue-11/data" / f"HG002.GRCh38.qualification-{panel}.bam"
        refs, m5_count = reference_dictionary(bam)
        if any(index[name][0] != length for name, length in refs.items()):
            raise ValueError(f"Incompatible dictionary in {bam}")
        end = start + width - 1
        reference = expected_reads(source, index, [("chr20", start - 1, end)])[0].decode()
        rows = []
        matches = []
        for name, pos, reverse, cigar, sequence in region_records(bam, list(refs).index("chr20"), start, end):
            quiet = []
            for coordinate, base, margin, differs in comparisons(start, reference, cigar, sequence, pos):
                if differs:
                    rows.append([name, pos, reverse, coordinate, base, margin])
                elif margin >= 5:
                    quiet.append(coordinate)
            if quiet:
                nearest = min(quiet, key=lambda coordinate: (abs(2 * coordinate - start - end), coordinate))
                matches.append([name, pos, reverse, nearest])
        # The digest pins every true mismatch, before any view or row selection.
        payload = json.dumps(sorted(rows), separators=(",", ":")).encode()
        key = f"{panel}-{start}-{width}"
        (args.output / f"{key}.json.gz").write_bytes(gzip.compress(payload, mtime=0))
        controls = json.dumps(sorted(matches), separators=(",", ":")).encode()
        (args.output / f"{key}.matches.json.gz").write_bytes(gzip.compress(controls, mtime=0))
        summary.append(dict(key=key, quiet_sha256=hashlib.sha256(controls).hexdigest(), bam=bam.name, start=start, end=end, reference=reference,
                            true_mismatches=len(rows), interior_mismatches=sum(r[5] >= 5 for r in rows),
                            mismatches_sha256=hashlib.sha256(payload).hexdigest(),
                            compatible_contigs=len(refs), bam_m5_count=m5_count))
    (args.output / "oracle.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
