#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-htslib.sh
xcrun clang -I .build/htslib/include scripts/generate-fixtures.c \
    .build/htslib/lib/libhts.a -lz -o .build/generate-fixtures
.build/generate-fixtures Tests/BamdalfKitTests/Fixtures/opening.sam Tests/BamdalfKitTests/Fixtures/opening.bam
