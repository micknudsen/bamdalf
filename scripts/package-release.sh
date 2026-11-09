#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
    printf 'Usage: bash scripts/package-release.sh vMAJOR.MINOR.PATCH\n' >&2
    exit 1
fi
metadata=$(python3 scripts/release_metadata.py "$1")
test "$(uname -m)" = arm64
bash scripts/build-app.sh

app="$PWD/.build/bamdalf.app"
binary="$app/Contents/MacOS/bamdalf"
test "$(lipo -archs "$binary")" = arm64
codesign --verify --strict "$app"
# This distribution bundles HTSlib statically. Never ship an accidental
# dependency on a developer's Homebrew installation or build directory.
otool -L "$binary" | tail -n +2 | awk '
    $1 !~ /^\/System\/Library\// && $1 !~ /^\/usr\/lib\// {
        print "Non-system dynamic dependency: " $1 > "/dev/stderr"; bad = 1
    }
    END { exit bad }
'

destination="$PWD/.build/release"
mkdir -p "$destination"
# Replace only this script's generated output, including on a version change.
rm -f "$destination"/bamdalf-*-macos-arm64*.zip \
    "$destination/SHA256SUMS" "$destination/BUILD-INFO.txt" \
    "$destination/release-metadata.json"
archive="bamdalf-$1-macos-arm64.zip"
contents=$(mktemp -d "$PWD/.build/release-contents.XXXXXX")
trap 'rm -rf "$contents"' EXIT
ditto "$app" "$contents/bamdalf.app"
printf '%s\n' "$metadata" > "$contents/release-metadata.json"
{
    printf 'Tag: %s\nCommit: %s\n' "$1" "$(git rev-parse HEAD)"
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'Source tree: dirty (local development build)\n'
    else
        printf 'Source tree: clean\n'
    fi
    printf 'Signing: ad hoc; NOT Developer ID signed; NOT notarized\n'
    sw_vers
    xcodebuild -version
    swift --version
} > "$contents/BUILD-INFO.txt"
ditto -c -k "$contents" "$destination/$archive"
(
    cd "$destination"
    shasum -a 256 "$archive" > SHA256SUMS
    shasum -a 256 --check SHA256SUMS
)
printf 'Prepared release in %s\n' "$destination"
