#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
bash scripts/build-htslib.sh
swift build --configuration release --product Bamdalf
binary_dir=$(swift build --configuration release --show-bin-path)
app_dir="$PWD/.build/Bamdalf.app"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources/Licenses"
cp "$binary_dir/Bamdalf" "$app_dir/Contents/MacOS/Bamdalf"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp .build/htslib/licenses/*.txt "$app_dir/Contents/Resources/Licenses/"
cp LICENSE "$app_dir/Contents/Resources/Licenses/Bamdalf.txt"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
