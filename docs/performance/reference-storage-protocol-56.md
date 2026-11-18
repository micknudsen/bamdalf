# Integrated reference storage protocol

[Issue 56](https://github.com/micknudsen/bamdalf/issues/56) uses two fresh
native saves and two 102-handle validated-open routes. The reference feature
baseline is `a42863fda106b45aed98beb4152b42fbf510317f`. Record the integrated
protocol commit and release executable SHA-256 with the observations.

## Inputs and independent expectations

Use the [GRCh38 no-alt plus hs38d1 acquisition recipe](reference-storage-2026-11-18.md).
The [preparation script](../../Benchmarks/ReferenceQualification/storage.py)
verifies SHA-256 and recreates the following two oracle files before timing.
The FAI supplies contig lengths and line offsets. Publisher FASTA headers
supply the SAM M5 values. The [seed-49 route](../../Benchmarks/ReferenceFormat/measure.py)
uses chr1, chr20 and chrX, widths 1, 80, 1,000 and 10,000, and 100-base
intervals crossing 64/256 KiB boundaries. Encode coordinates as 1-based
inclusive alongside the expected bytes. No bundle reader participates in
creating the expectations.

| Input or oracle | SHA-256 |
| --- | --- |
| Uncompressed FASTA | `592502666381c995059a6b4a5dda11e6b1f6b8efeea04e7dacfffe1e0d2f0d25` |
| Publisher FAI | `e33afb84eb6463b2607798f86c6060e55eb549698c586268d6011f3ce815b122` |
| Ordered name, length and M5 for 2,580 contigs | `a4487e83b32ec20aabf5f20a1e7e6f3edf613dc9f58fc41680d7f2e1f0510c9a` |
| 102 ordered intervals and expected sequences | `571a16fb22f813e0f0ea6b3abf3ce6876cfaa2e1dfdaabd34ff548622fe1e2e1` |

## Machine and measurements

Use the Apple M4 with 16 GiB RAM and its internal APFS SSD, macOS 27.2.1
(26B131), Xcode 27.2 (27B52), macOS SDK 27.2, Apple Swift 6.4.2
(swiftlang-6.4.2.1.9), release optimization, static HTSlib 1.25 and platform
SQLite 3.54.0. Use the system Python 3.9.6. Run sequentially without competing
builds, tests, or benchmarks. Input verification warms the source file.
Newly created bundles and repeated opens can benefit from the OS cache. Leave
the OS cache uncontrolled and unflushed.

1. Start a fresh [native process](../../Benchmarks/ReferenceQualification/Storage/main.swift)
   for each save with the production empty 1,100 × 720-point viewer shown. Supply
   a fresh approved destination at the Save-panel boundary. Start the monotonic
   timer immediately before the native `saveReference` call. Include its real
   progress sheet, detached import, closed-file validation, publication, and
   sheet dismissal. Stop at completion. Confirm the file exists, the sheet
   is gone, and neither a BAM nor a reference was selected.
2. Use Darwin `/usr/bin/time -l` for the creator's complete process peak RSS.
   Count the final closed file's logical bytes per 3,105,715,063 source bases.
   For **each** of the two creations require elapsed time ≤60 s, peak RSS
   ≤268,435,456 bytes (256 MiB), and final size ≤1.05 bytes/base.
3. After each creation run a separate probe process. Time only the production
   `ReferenceBundle(opening:)` initializer with a monotonic clock for every
   fresh handle, including the first. This includes structural, dictionary,
   and index-bounds validation. It excludes any subsequent regional read,
   viewer layout or measurement bookkeeping. After opening, compare all
   2,580 descriptors, read the prescribed interval twice, and compare both
   results byte for byte. End that handle's lifetime before the next iteration.
   Require nearest-rank p95 (97th of 102 sorted durations) ≤50 ms for each
   bundle independently. Preserve all 204 durations and both creation results,
   including failures. Hash both outputs after the second probe.
4. Use the first qualified creation for the integrated viewer routes. Native
   Open/Save panels, cancellation, alias protection, source removal and failure
   recovery are exercised by the separate native correctness routes.

From the repository root, use fresh output directories on the internal disk.
Set `data` to the acquisition directory and `out` to the run directory.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fasta="$data/GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna"
runner=Benchmarks/ReferenceQualification/storage.py
swift build -c release --product ReferenceStorageQualification
/usr/bin/python3 "$runner" prepare "$fasta" "$data/publisher.fai" "$out/oracle"
/usr/bin/python3 "$runner" collect .build/release/ReferenceStorageQualification "$fasta" "$out/oracle" "$out/storage"
```
