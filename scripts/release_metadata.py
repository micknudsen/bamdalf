#!/usr/bin/env python3
"""Validate a release tag against the app's committed version metadata."""

import json
from pathlib import Path
import plistlib
import re
import sys


def release_metadata(tag, info):
    if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ValueError("Use a tag of the form vMAJOR.MINOR.PATCH, for example v0.1.0")
    version = info["CFBundleShortVersionString"]
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag} does not match Info.plist version {version}")
    build = info["CFBundleVersion"]
    if not isinstance(build, str) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("CFBundleVersion must be a positive integer string")
    return {
        "tag": tag,
        "version": version,
        "build": build,
        "minimum_macos": info["LSMinimumSystemVersion"],
        "architecture": "arm64",
        "signing": "ad-hoc",
        "notarized": False,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/release_metadata.py vMAJOR.MINOR.PATCH")
    try:
        path = Path(__file__).resolve().parent.parent / "Resources/Info.plist"
        with path.open("rb") as source:
            info = plistlib.load(source)
        print(json.dumps(release_metadata(sys.argv[1], info), indent=2))
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
