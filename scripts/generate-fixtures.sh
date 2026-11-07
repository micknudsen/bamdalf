#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-htslib.sh
xcrun clang -I .build/htslib/include scripts/generate-fixtures.c \
    .build/htslib/lib/libhts.a -lz -o .build/generate-fixtures
for fixture in opening coordinates; do
    .build/generate-fixtures "Tests/BamdalfKitTests/Fixtures/$fixture.sam" "Tests/BamdalfKitTests/Fixtures/$fixture.bam"
done
