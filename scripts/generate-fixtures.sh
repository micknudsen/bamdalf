#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-htslib.sh
xcrun clang -I .build/htslib/include scripts/generate-fixtures.c \
    .build/htslib/lib/libhts.a -lz -o .build/generate-fixtures
for fixture in opening coordinates alignments rows; do
    .build/generate-fixtures "Tests/BamdalfKitTests/Fixtures/$fixture.sam" "Tests/BamdalfKitTests/Fixtures/$fixture.bam"
done
xcrun clang -I .build/htslib/include scripts/generate-defect-fixtures.c \
    .build/htslib/lib/libhts.a -lz -o .build/generate-defect-fixtures
for defect in missing inconsistent; do
    .build/generate-defect-fixtures "Tests/BamdalfKitTests/Fixtures/$defect-cigar.bam" "$defect"
done
