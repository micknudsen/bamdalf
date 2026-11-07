#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
test_log=$(mktemp "${TMPDIR:-/tmp}/bamdalf-tests.XXXXXX")
trap 'rm -f "$test_log"' EXIT

swift test --disable-xctest "$@" 2>&1 | tee "$test_log"

# An AppKit run-loop stop can make Swift's async test host exit zero before
# testing finishes. Require Swift Testing's nonempty, successful final summary.
if ! grep -Eq 'Test run with [1-9][0-9]* tests?( in [1-9][0-9]* suites?)? passed after ' "$test_log"; then
    printf '%s\n' 'Native tests did not report a complete, nonempty successful run.' >&2
    exit 1
fi
