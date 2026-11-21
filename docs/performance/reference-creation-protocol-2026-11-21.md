# Concurrent reference creation protocol

Fixed before collecting issue [#74](https://github.com/micknudsen/bamdalf/issues/74)
measurements on 2026-11-21. Product baseline is
`4757784604359e69e354e5bc110617f537cdb37f`; this qualification adds a driver,
integrated acceptance checks and documentation. Record the exact measurement
commit and executable hashes with results.

## Inputs and environment

Use the same Apple M4, 16 GiB RAM, internal APFS storage, macOS 27.2.1 (26B131),
Xcode 27.2 / Swift 6.4.2, static HTSlib 1.25 and system SQLite as the
[reference qualification](reference-qualification-2026-11-18.md). Build in
release mode. Run processes in series without competing builds or tests.
Use a light native viewer, 1,100 × 720 points, recording actual backing scale.
Input hashing warms the uncontrolled, unflushed OS cache; each trial starts
a fresh application process and session. Do not report cold-disk results.

Reuse the full 3,105,715,063-base, 2,580-contig NCBI GRCh38 no-alt plus hs38d1
[FASTA and acquisition provenance](reference-storage-2026-11-18.md#input-and-reproduction),
and the [derived approximately 100× HG002 BAM](../../Benchmarks/Data/qualification-README.md).
Verify these pins before measurement:

| Input | SHA-256 |
| --- | --- |
| Uncompressed FASTA | `592502666381c995059a6b4a5dda11e6b1f6b8efeea04e7dacfffe1e0d2f0d25` |
| Publisher FAI | `e33afb84eb6463b2607798f86c6060e55eb549698c586268d6011f3ce815b122` |
| Derived HG002 BAM | `b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33` |
| Derived BAI | `b1bb5a7c36b5bf3fb8fd3c5c3b728d4881364e87a45d159d55909c503678c0fd` |

Create a named v2 viewing bundle with the production storage driver first.
Historical v1 artifacts remain unchanged. The second trial may select the first
trial's output, whose sequence and dictionary are checked independently, allowing
the generated setup bundle to be retired without retaining three full copies.
Keep both measured outputs and their hashes. Generate the existing 102-interval
FAI oracle before timing; after each trial, probe every dictionary entry and
the independently expected sequences using the existing storage probe.

## Native route and repetition

Perform two complete human-reference creations in two fresh processes. Select
the existing named reference and derived BAM before import. Enter the source
path and a chosen display name in the actual creation form and supply a fresh
destination at the native Save approval boundary. Start timing when the
approved response initiates the real worker; stop only after validated atomic
publication and quiet form closure. Do not gate, sleep or throttle the importer.
Preserve the original selected sources and the final navigated interval.

During import, repeat this ten-action route, allowing 100 ms after each
completed action. Finish the current cycle if import completes during it;
mark which observations overlap generation and evaluate them separately.

1. Type `chr20:10,025,001-10,025,100` through the native interval editor.
2. Activate Pan right, Pan left, Zoom out, then Zoom in through native buttons.
3. Type `chr20:20,050,001-20,050,100` through the native interval editor.
4. Repeat Pan right, Pan left, Zoom out, then Zoom in.

Both locations lie inside the fully extracted ordinary regions. This focuses
on letter/cell browsing with real alignments, reference data and source I/O.
It is not a new comprehensive renderer, dense-pileup or sustained-memory study.
No drag or scroll timing claim follows from this route. Existing deterministic
native tests separately qualify reference-only browsing, source changes,
cancellation, errors and lifetime/publication races.

## Measurement and interpretation

Use the established boundary: native input action through required data
readiness, layout, synchronous display and CPU rasterization of visible ruler,
reference and alignment tracks at actual backing scale. Record every action's
interval, required BAM query count, elapsed time and whether creation remained
active. OS event delivery, compositor and physical presentation are excluded.
Record import progress alongside actions to distinguish actual overlap from
merely enabled controls. Keep all raw observations, including failures.

Report counts, first observation, nearest-rank p95, maximum and fraction meeting
each applicable existing expectation per action and trial: at least 95% within
100 ms when no required BAM query runs, or 500 ms for ordinary required loads.
Do not invent a concurrent-import threshold. Report creation time against the
existing 60-second no-viewer storage reference as context, not a new combined
gate. The 256 MiB isolated-creator target does not apply to a combined viewer
and importer; compare combined process RSS with the existing 2 GiB viewer
ceiling and record that distinction.

Sample resident bytes and physical footprint every 250 ms, and record process
RSS high-water using both `getrusage` and Darwin `time -l`. Use the larger peak.
Finite full-import runs describe measured memory ranges, not a ten-minute
stability qualification. If timing or resource results expose a regression,
preserve them and compare the same route without import before broadening the
investigation. Fix feature regressions without weakening the accepted behavior.

## Reproduction

Set `fasta`, `bam`, `viewing_bundle`, `oracle` and `out` to local input/output
paths. Use a fresh result directory and a fresh output filename for each trial.
The native driver accepts `-` instead of a BAM for optional reference-only
investigation; the prescribed measurements use the paired BAM.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release --product ReferenceStorageQualification
swift build -c release --product ReferenceConcurrentQualification
.build/release/ReferenceStorageQualification create "$viewing_bundle" "$fasta"
/usr/bin/time -l .build/release/ReferenceConcurrentQualification "$fasta" "$out/trial-1.bref" "$viewing_bundle" "$bam" "$out/trial-1"
.build/release/ReferenceStorageQualification probe "$out/trial-1.bref" "$oracle"
/usr/bin/time -l .build/release/ReferenceConcurrentQualification "$fasta" "$out/trial-2.bref" "$out/trial-1.bref" "$bam" "$out/trial-2"
.build/release/ReferenceStorageQualification probe "$out/trial-2.bref" "$oracle"
```
