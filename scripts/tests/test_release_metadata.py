"""Release tags must identify exactly the version installed by the user."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_metadata import release_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "15.0",
        }

    def test_matching_tag(self):
        metadata = release_metadata("v1.2.3", self.info)
        self.assertEqual(metadata["version"], "1.2.3")
        self.assertFalse(metadata["notarized"])

    def test_mismatched_version(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            release_metadata("v0.2.0", self.info)

    def test_noncanonical_tags(self):
        for tag in ["1.2.3", "v01.1.0", "v1.2.3-rc.1", "v1.2.3\n", "--help"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_metadata(tag, self.info)

    def test_invalid_build_numbers(self):
        for build in ["0", "-1", "01", "1.2", "", 1]:
            with self.subTest(build=build), self.assertRaises(ValueError):
                release_metadata("v1.2.3", dict(self.info, CFBundleVersion=build))


if __name__ == "__main__":
    unittest.main()
