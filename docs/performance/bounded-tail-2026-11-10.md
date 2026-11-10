# Bounded soft-tail retrieval margin

On 2026-11-10, the focused issue #33 comparison selected a provisional fixed
**M = 250 bases per side**. This is the smallest nonzero tested margin. It found
the same visible candidates as 500, 1,000, and 2,000 bases in every measured
case while fetching fewer records. M = 0 missed two tail-only alignments in the
original dense 10 kb target. The selection is an engineering choice for bounded
short-read discovery, not an inferred maximum tail length for arbitrary BAMs.

The visible width W still controls the 10,000-base cutoff. Required coverage R
extends V by 250 bases on each side, clamped to the reference; selected tails
retain their full length. Records anchored beyond R can remain undiscovered.
The same fixed margin applies to every BAM and alignment-visible zoom level.
No opening-time sample or user setting was added. Broader prefetch and rolling
navigation qualification remains in issue #36.

## Protocol and inputs

The [production-reader probe](../../Benchmarks/BoundedTailQuery/main.swift) and
[fixed runner](../../Benchmarks/BoundedTailQuery/run.py) compare margins
0, 250, 500, 1,000, and 2,000 at six targets. Each case/margin uses five fresh
processes, for 150 observations. The probe opens the real BAM/index, validates
the expanded interval through the application, and times one production
`BAMFile.alignments(in:)` call. It records complete returned records, visible
candidates, tail-only candidates, and process lifetime peak RSS. Application
validation is suppressed and untimed; it makes no alignment query. This first
comparison does not include sampling, cache management, packing, or drawing.

Measurements used an Apple M4 with 16 GiB RAM, macOS 27.2 build 26B123,
Swift 6.4.2, HTSlib 1.25, and a release build based on
`0b1d25fc3e3fafbc1a0418b86d8fcb38f5fdc1eb` plus the issue #33 working changes.
Builds/tests were paused during measurement. Cases ran sequentially in fixed
case/margin order; operating-system file caches were uncontrolled. These are
small warmed-storage observations, not cold-disk or statistically independent
machine samples. All five repetitions of every case/margin agreed on counts.

The checksum-pinned inputs and prior extraction audits are documented in the
[derived approximately 100× recipe](../../Benchmarks/Data/qualification-README.md)
and [original 300× stress recipe](../../Benchmarks/Data/README.md). All requested
R intervals, including M = 2,000, lie completely inside the extracted source
spans. Empty unextracted space is never used as completed source coverage.

| Case | Visible target on chr20 | Complete extraction span | BAM |
| --- | --- | --- | --- |
| Ordinary / 1 kb | 10,024,501–10,025,500 | 9,830,401–10,354,688 | Derived approximately 100× |
| Ordinary / 10 kb | 10,020,001–10,030,000 | 9,830,401–10,354,688 | Derived approximately 100× |
| Dense / 1 kb | 29,892,101–29,893,100 | 29,818,881–30,081,024 | Derived approximately 100× |
| Dense / 10 kb | 29,887,601–29,897,600 | 29,818,881–30,081,024 | Derived approximately 100× |
| Original dense / 1 kb | 29,892,101–29,893,100 | 29,884,417–29,900,800 | Original 300× |
| Original dense / 10 kb | 29,887,601–29,897,600 | 29,884,417–29,900,800 | Original 300× |

| BAM | SHA-256 |
| --- | --- |
| Derived approximately 100× | `b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33` |
| Original 300× stress | `786c9d3f66ff721d8bbb20bb62c8e055aa589f1e64f930fc8fdfc210e9b689c5` |

The inputs contain 148-base stored reads. They support the tested bounded policy
and its cost on these regions; they cannot establish the optimal discovery
distance for other read lengths or libraries. Dedicated real BAI/CSI fixtures
separately exercise long tails and the exact search boundary.

## Query work and observed cost

Counts below are records returned after the production reader's existing flag
filters, before V eligibility and display sampling. They are not decoded-record
counts or physical I/O bytes. M = 250 adds 500 required bases before reference
clamping, independently of visible width.

| Case | Returned, M=0 | M=250 | M=500 | M=1,000 | M=2,000 | Visible, M=250 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary / 1 kb | 940 | 1,349 | 1,715 | 2,434 | 3,661 | 940 |
| Ordinary / 10 kb | 7,040 | 7,448 | 7,851 | 8,590 | 10,061 | 7,040 |
| Dense / 1 kb | 3,244 | 5,289 | 6,651 | 8,817 | 10,583 | 3,244 |
| Dense / 10 kb | 15,753 | 16,353 | 16,973 | 18,140 | 22,823 | 15,753 |
| Original dense / 1 kb | 9,701 | 15,676 | 19,715 | 26,121 | 31,433 | 9,701 |
| Original dense / 10 kb | 47,160 | 48,911 | 50,745 | 54,130 | 68,328 | 47,162 |

Only the final case gained tail-only candidates at these exact target edges:
two at every tested positive margin. Larger margins added no visible candidates
in any case. This is not a claim that ordinary regions have no soft clipping;
only that their specific boundaries gained no tail-only candidates.

| Case | Median query ms, M=0 | M=250 | M=500 | M=1,000 | M=2,000 | Maximum ms, M=250 | Peak RSS MiB, M=250 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary / 1 kb | 4.93 | 5.54 | 5.95 | 6.76 | 8.24 | 6.28 | 12.09 |
| Ordinary / 10 kb | 12.69 | 13.03 | 13.19 | 13.52 | 15.10 | 13.11 | 15.11 |
| Dense / 1 kb | 11.22 | 13.65 | 15.69 | 17.40 | 19.31 | 14.12 | 13.86 |
| Dense / 10 kb | 24.81 | 25.40 | 26.20 | 27.21 | 33.06 | 26.00 | 19.80 |
| Original dense / 1 kb | 32.01 | 48.40 | 42.22 | 58.87 | 54.80 | 54.60 | 19.73 |
| Original dense / 10 kb | 72.20 | 78.87 | 76.79 | 80.63 | 94.53 | 84.04 | 36.83 |

Peak RSS is the largest whole-process value across five fresh processes,
measured by `/usr/bin/time -l`; MiB means 1,048,576 bytes. `getrusage` values are
also retained. These small query-only peaks do not bound application memory or
long-running navigation. Timing is not strictly monotonic with margin, as the
original dense cases show; work counts provide the direct comparison. No
wall-clock assertions were added to correctness tests.

The [150 observations](data/bounded-tail-2026-11-10/query-results.csv) and
[30 summaries](data/bounded-tail-2026-11-10/query-summary.json) retain unrounded
values. The local archive `.local/measurements/issue-33/margin-comparison/`
contains per-process JSON/time logs, source and input/executable hashes,
worktree diff, environment, and fixed case/margin protocol.

## Native integration with the selected margin

The [native runner](../../Benchmarks/BoundedTailQuery/native.py) then ran the
actual M = 250 session and existing
[VisibilityBaseline renderer harness](../../Benchmarks/VisibilityBaseline.swift)
five times per target in fresh processes, for 30 native loads. The session used
seed 42 and the production 2,000-group budget. All six exact expanded-query
counts matched the comparison above, with one query per load. Native windows
were 1,100 × 720 points with light appearance. No competing builds or native
tests ran during this check.

| Case | Displayed records / groups | Median load/layout ms | Maximum load/layout ms | Maximum first draw ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ordinary / 1 kb | 940 / 638 | 65.98 | 66.53 | 5.40 | 150.58 |
| Ordinary / 10 kb | 3,747 / 2,000 | 76.85 | 78.74 | 8.70 | 156.27 |
| Dense / 1 kb | 2,658 / 2,000 | 82.01 | 86.37 | 5.50 | 153.03 |
| Dense / 10 kb | 3,302 / 2,000 | 90.93 | 93.99 | 8.56 | 162.50 |
| Original dense / 1 kb | 2,666 / 2,000 | 118.03 | 119.63 | 5.71 | 160.11 |
| Original dense / 10 kb | 3,285 / 2,000 | 169.77 | 182.65 | 9.75 | 185.11 |

Load/layout begins immediately before interval submission and ends after its
required task and native layout complete. First draw measures the actual
alignment view's visible-viewport rasterization separately, after the harness's
existing settling pause. These values are not an uninterrupted ready-and-drawn
latency or compositor measurement, and are not added together to claim one.
RSS includes the whole native process, its views, raster buffers, and PNG
exports. The largest measured peak was 194,101,248 bytes. This focused check
does not replace the required ten-minute navigation qualification.

Only ordinary 1 kb was unsampled; the other cases displayed 2,000 groups from
their complete V-eligible candidates. The runner passes budget 2,000 explicitly
because the historical harness otherwise disables sampling. Its measurement
visibility-limit override has no effect on these 1 kb and 10 kb targets.
Representative native renderer captures were visually inspected; they show
the existing bars, colored tails, insertion marks, and row geometry. Separate
native correctness tests establish tail-only clipping/outline behavior.

The [30 native observations](data/bounded-tail-2026-11-10/native-results.csv)
and [six summaries](data/bounded-tail-2026-11-10/native-summary.json) retain exact
values. `.local/measurements/issue-33/native-m250/` preserves source hashes,
executable/input hashes, source diff, per-process logs, and native PNG captures.

## Reproduction

Prepare both documented inputs at the recipe paths, then run from repository
root with a new output directory:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build-htslib.sh
swift build -c release --product BoundedTailQuery
python3 Benchmarks/BoundedTailQuery/run.py \
  .build/release/BoundedTailQuery \
  .local/measurements/issue-33/margin-comparison-reproduction
swift build -c release --product VisibilityBaseline
python3 -B Benchmarks/BoundedTailQuery/native.py \
  .build/release/VisibilityBaseline \
  .local/measurements/issue-33/native-m250-reproduction
```

The runner rejects unexpected BAM checksums, ranges beyond complete extraction,
empty results, differing repetition counts, or missing process-memory evidence.
The native runner additionally requires the selected M = 250 query counts.
Neither runner infers representative library lengths or proves discovery of
tails beyond the fixed margin. Run the native check in a logged-in graphical
macOS session, separately from native tests and other measurement work.
