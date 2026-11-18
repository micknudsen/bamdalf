"""Independent real-file observations for the storage experiment."""

import hashlib
import os
from pathlib import Path
import tempfile
import unittest

from candidate import Bundle, create


class CandidateRoundTrip(unittest.TestCase):
    def test_relocated_read_only_bundle(self):
        for chunk_bytes in (65536, 262144):
            with self.subTest(chunk_bytes=chunk_bytes), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source.fa"
                # The second record crosses both candidate chunk boundaries.
                source.write_bytes(b">mixed description\r\nACGTRYSWKMBDHVN\r\n"
                                   b"acgtryswkmbdhvn\r\n>edge\n" + b"A" * 262142 + b"tR\nysG")
                candidate = root / "initial.bref"
                create(source, candidate, chunk_bytes)
                source.unlink()
                folder = root / "moved folder #1"
                folder.mkdir()
                moved = candidate.rename(folder / "portable?.bref")
                stamp = moved.stat().st_mtime_ns
                digest = hashlib.sha256(moved.read_bytes()).digest()
                moved.chmod(0o444)
                folder.chmod(0o555)
                try:
                    with Bundle(moved) as reader:
                        self.assertEqual(reader.dictionary, {
                            "mixed": (30, "bbecac2bf7f252c05b5bc85337c9bf70"),
                            "edge": (262147, "fc9c099100ff1b23b56dbe99c95bfb90"),
                        })
                        self.assertEqual(reader.read("mixed", 0, 30), b"ACGTRYSWKMBDHVNacgtryswkmbdhvn")
                        self.assertEqual(reader.read("edge", 0, 1), b"A")
                        self.assertEqual(reader.read("edge", 65535, 65537), b"AA")
                        self.assertEqual(reader.read("edge", 262141, 262147), b"AtRysG")
                        self.assertEqual(reader.read("edge", 262146, 262147), b"G")
                        with self.assertRaises(ValueError):
                            reader.read("mixed", 29, 31)
                    self.assertEqual(list(folder.iterdir()), [moved])
                    self.assertEqual(moved.stat().st_mtime_ns, stamp)
                    self.assertEqual(hashlib.sha256(moved.read_bytes()).digest(), digest)
                finally:
                    os.chmod(folder, 0o755)

    def test_header_name_survives_long_padding_and_description(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "headers.fa"
            bundle = Path(tmp) / "headers.bref"
            source.write_bytes(b">chr1" + b" " * 65531 + b"description\nA\n"
                               b">" + b" " * 65533 + b"chr2\tmore\nc\n")
            create(source, bundle, 65536)
            with Bundle(bundle) as reader:
                self.assertEqual(reader.read("chr1", 0, 1), b"A")
                self.assertEqual(reader.read("chr2", 0, 1), b"c")
