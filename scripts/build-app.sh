#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
bash scripts/build-htslib.sh
swift build --configuration release --product bamdalf
binary_dir=$(swift build --configuration release --show-bin-path)
app_dir="$PWD/.build/bamdalf.app"
# Recreate the generated bundle so case-insensitive volumes keep the new spelling
# and obsolete files from earlier builds cannot be shipped.
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources/Licenses"
cp "$binary_dir/bamdalf" "$app_dir/Contents/MacOS/bamdalf"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp .build/htslib/licenses/*.txt "$app_dir/Contents/Resources/Licenses/"
cp LICENSE "$app_dir/Contents/Resources/Licenses/bamdalf.txt"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
