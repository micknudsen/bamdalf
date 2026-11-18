"""Check the first native WGS detail captures against the frozen independent oracle."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile

CASES = ("ordinary_a_100", "ordinary_a_1000", "original_dense_100", "original_dense_1000",
         "ordinary_b_1000", "derived_dense_1000")
EXPECTED = Path(__file__).resolve().parents[2] / "docs/performance/data/reference-qualification/oracle.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


class Bitmap:
    def __init__(self, png):
        # macOS Image I/O handles PNG filters, profiles and row order.
        with tempfile.TemporaryDirectory() as directory:
            bmp = Path(directory) / "capture.bmp"
            subprocess.run(["/usr/bin/sips", "-s", "format", "bmp", str(png), "--out", str(bmp)],
                           stdout=subprocess.DEVNULL, check=True)
            self.data = bmp.read_bytes()
        self.offset, = struct.unpack_from("<I", self.data, 10)
        _, self.width, signed_height, planes, bits, compression = struct.unpack_from("<IiiHHI", self.data, 14)
        require(self.data[:2] == b"BM" and planes == 1 and bits in (24, 32), "Unexpected BMP pixels")
        if compression == 3:
            require(struct.unpack_from("<III", self.data, 54) == (0xff0000, 0xff00, 0xff), "Unexpected RGB masks")
        else:
            require(compression == 0, "Unsupported BMP encoding")
        self.height = abs(signed_height)
        self.bottom_up = signed_height > 0
        self.pixel_bytes = bits // 8
        self.stride = (self.width * self.pixel_bytes + 3) // 4 * 4

    def pixel(self, x, y):
        require(0 <= x < self.width and 0 <= y < self.height, "Probe outside bitmap")
        row = self.height - y - 1 if self.bottom_up else y
        offset = self.offset + row * self.stride + x * self.pixel_bytes
        return tuple(self.data[offset:offset + 3][::-1])


def ink(letter, rgb):
    r, g, b = rgb
    return {
        "A": g > r + 38 and g > b + 25,
        "C": b > r + 76 and b > g + 51,
        "G": r > 191 and g > 140 and b < 115,
        "T": r > g + 76 and r > b + 76,
        "quiet": max(rgb) < 90 and max(rgb) - min(rgb) < 10,
    }[letter]


def probes(directory, expected, matches=False):
    suffix = ".matches.json.gz" if matches else ".json.gz"
    data = gzip.decompress((directory / (expected["key"] + suffix)).read_bytes())
    digest = expected["quiet_sha256" if matches else "mismatches_sha256"]
    require(hashlib.sha256(data).hexdigest() == digest, "Independent coordinate list digest differs")
    return json.loads(data)


def audit_case(case, expected, run, oracle):
    case_id = f"uncached_{case}_paired"
    metadata = run / case_id / "native" / case_id / "steps-load.view.json"
    view = json.loads(metadata.read_text())
    start, end = expected["start"], expected["end"]
    sequence = expected["reference"]
    require((view["targetStart"], view["targetEnd"], view["bam"], view["sourceMode"]) ==
            (start, end, expected["bam"], "paired") and view["interval"].startswith("chr20:"), "Wrong source or interval")
    offset = start - view["referenceStart"]
    require(offset >= 0 and view["referenceSequence"][offset:offset + len(sequence)] == sequence,
            "Displayed sequence disagrees with publisher FASTA")
    scale = view["scale"]
    pitch = view["width"] * scale / len(sequence)
    require(view["width"] == view["referenceWidth"], "Alignment and reference horizontal scales differ")
    require(pitch / scale >= 8 if len(sequence) == 100 else 1 <= pitch / scale < 8, "Wrong detail tier")

    images = {}
    hashes = {}
    for name in ("alignments", "reference"):
        path = metadata.with_name(f"steps-load.{name}.png")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        images[name] = Bitmap(path)
        require(images[name].width == math.ceil(view["width"] * scale), "Native raster width differs")
    require(images["alignments"].height == math.ceil(view["height"] * scale), "Native raster height differs")
    visible = {(r["name"], r["start"], r["reverse"]): r["row"] for r in view["records"]}
    require(len(visible) == len(view["records"]), "Ambiguous native row identity")
    counts = Counter()
    examples = []
    errors = []

    def probe(category, coord, base, top, record=None):
        bitmap = images["reference" if category == "reference" else "alignments"]
        left = (coord - start) * pitch
        right = (coord - start + 1) * pitch
        x = math.floor((left + right) / 2)
        whole_body = (top + 3) * scale >= 0 and (top + 15) * scale <= bitmap.height
        if x < left - 1e-8 or x + 1 > right + 1e-8 or not whole_body:
            counts[category + "_skipped_geometry"] += 1
            return
        counts[category + "_checked"] += 1
        colors = [bitmap.pixel(x, math.floor((top + y) * scale)) for y in range(4, 14)]
        observed = next((c for c in colors if ink(base, c)), None)
        if observed is None:
            counts[category + "_failed"] += 1
            if len(errors) < 4:
                errors.append((category, coord, base, record, colors))
        elif category == "mismatch" and len(examples) < 3:
            examples.append(dict(coordinate=coord, reference=sequence[coord - start], aligned=base,
                                 record=record, rgb=observed))

    for i, base in enumerate(sequence):
        probe("reference", start + i, base.upper(), 0)
    for name, pos, reverse, coordinate, base, margin in probes(oracle, expected):
        key = (name, pos, reverse)
        if key in visible:
            if margin < 5:
                counts["mismatch_skipped_segment_end"] += 1
            else:
                probe("mismatch", coordinate, base, visible[key] * 18 - view["originY"], key)
    for name, pos, reverse, coordinate in probes(oracle, expected, matches=True):
        key = (name, pos, reverse)
        if key in visible:
            probe("quiet", coordinate, "quiet", visible[key] * 18 - view["originY"], key)
    require(all(counts[c + "_checked"] > 0 and counts[c + "_failed"] == 0
                for c in ("mismatch", "reference", "quiet")), f"{case_id}: {dict(counts)}; {errors}")
    return dict(case=case_id, points_per_base=pitch / scale, backing_scale=scale, visible_records=len(visible),
                counts=dict(sorted(counts.items())), examples=examples, native_png_sha256=hashes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("oracle", type=Path, help="Regenerated coordinate lists from oracle.py")
    args = parser.parse_args()
    expectations = json.loads(EXPECTED.read_text())
    require(len(expectations) == len(CASES), "Unexpected number of fixed cases")
    print(json.dumps([audit_case(case, expected, args.run, args.oracle)
                      for case, expected in zip(CASES, expectations)], indent=2))


if __name__ == "__main__":
    main()
