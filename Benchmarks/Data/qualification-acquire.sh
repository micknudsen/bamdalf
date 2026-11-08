#!/bin/sh
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo 'usage: qualification-acquire.sh NEW_OUTPUT_DIRECTORY [--offline]' >&2
    exit 2
fi
out=$1
mode=${2:-}
if [ -n "$mode" ] && [ "$mode" != --offline ]; then
    echo 'The optional second argument must be --offline' >&2
    exit 2
fi
scripts=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository=$(CDPATH= cd -- "$scripts/../.." && pwd)
htslib="$repository/.build/htslib"
if [ -n "$mode" ]; then
    python3 "$scripts/qualification-acquire.py" "$out" "$mode"
else
    python3 "$scripts/qualification-acquire.py" "$out"
fi
clang -O2 -Wall -Wextra -Wno-deprecated-declarations -I "$htslib/include" \
    "$scripts/qualification-profile.c" "$htslib/lib/libhts.a" -lz -o "$out/qualification-profile"
source="$out/HG002.GRCh38.qualification-source.bam"
derived="$out/HG002.GRCh38.qualification-100x.bam"
"$out/qualification-profile" "$source" > "$out/source-profile.txt"
"$out/qualification-profile" "$derived" > "$out/derived-profile.txt"
"$out/qualification-profile" "$source" "$derived" "$out/source-offsets.txt" > "$out/preparation-audit.txt"
(
    cd "$out"
    shasum -a 256 HG002.GRCh38.qualification-source.bam HG002.GRCh38.qualification-source.bam.bai \
        HG002.GRCh38.qualification-100x.bam HG002.GRCh38.qualification-100x.bam.bai \
        source.bam.bai source-README.txt source-header.sam header.bgzf source-offsets.txt \
        source-profile.txt derived-profile.txt preparation-audit.txt manifest.json plan.json > SHA256SUMS
)
