#!/bin/sh
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo 'usage: acquire.sh OUTPUT_DIRECTORY [--offline]' >&2
    exit 2
fi
output=$1
mode=${2:-}
if [ -n "$mode" ] && [ "$mode" != --offline ]; then
    echo 'The optional second argument must be --offline' >&2
    exit 2
fi
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository=$(CDPATH= cd -- "$script_directory/../.." && pwd)
htslib="$repository/.build/htslib"
if [ ! -f "$htslib/lib/libhts.a" ]; then
    echo 'Build the project pinned HTSlib first with scripts/build-htslib.sh' >&2
    exit 2
fi
if [ -n "$mode" ]; then
    python3 "$script_directory/acquire.py" "$output" "$mode"
else
    python3 "$script_directory/acquire.py" "$output"
fi
clang -O2 -Wall -Wextra -I "$htslib/include" "$script_directory/profile.c" \
    "$htslib/lib/libhts.a" -lz -o "$output/profile"
"$output/profile" "$output/HG002.GRCh38.regions.bam" > "$output/profile.txt"
(
    cd "$output"
    shasum -a 256 HG002.GRCh38.regions.bam HG002.GRCh38.regions.bam.bai \
        source.bam.bai source-README.txt source-header.sam header.bgzf profile.txt > SHA256SUMS
)
