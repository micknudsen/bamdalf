#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
version=1.25
sha256=158c271e4e2986bb2dd11283b640edc10c56695b293df77a109ce99480303730
destination="$PWD/.build/htslib"
build_key=$( { shasum -a 256 "$0"; xcrun clang --version; xcrun --show-sdk-path; } | shasum -a 256)
if [[ -f "$destination/build-key" && -f "$destination/lib/libhts.a" ]] &&
   [[ "$(cat "$destination/build-key")" == "$build_key" ]]; then
    exit 0
fi

archive="$PWD/.build/dependencies/htslib-$version.tar.bz2"
mkdir -p "$(dirname "$archive")"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 \
        "https://github.com/samtools/htslib/releases/download/$version/htslib-$version.tar.bz2" \
        --output "$archive"
fi
printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 --check

build_directory=$(mktemp -d "$PWD/.build/dependencies/build.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT
tar -xjf "$archive" -C "$build_directory"
cd "$build_directory/htslib-$version"
SDKROOT="$(xcrun --show-sdk-path)" CC="$(xcrun --find clang)" CFLAGS="-O2 -mmacosx-version-min=15.0" \
    ./configure --disable-libcurl --disable-s3 --disable-gcs --disable-plugins \
        --disable-bz2 --disable-lzma --without-libdeflate || { cat config.log; exit 1; }
SDKROOT="$(xcrun --show-sdk-path)" make -j "$(sysctl -n hw.ncpu)" libhts.a
mkdir -p "$destination/lib" "$destination/include" "$destination/licenses"
cp libhts.a "$destination/lib/"
cp -R htslib "$destination/include/"
cp LICENSE "$destination/licenses/HTSlib.txt"
cp htscodecs/LICENSE.md "$destination/licenses/HTScodecs.txt"
printf '%s\n' "$build_key" > "$destination/build-key"
