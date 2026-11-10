# Rolling prefetch measurements, 2026-11-10

This report records focused implementation measurements for
[issue #35](https://github.com/micknudsen/bamdalf/issues/35). The provisional refill
threshold is at or below half the buffer P, measured from each relevant edge of R.
Final repetitions showed query-free pans on ordinary and dense 1 kb routes,
available alignments throughout the measured drags, and native drag updates below
25 ms. Dense 10 kb panning remained slower than the disabled baseline under the
bounded cache policy. That tradeoff and an earlier corrected pressure problem
are retained below. This is not the integrated ten-minute qualification required
by issue #36.

## Native boundary and protocol

The release-mode `RollingPrefetch` executable uses the production `ViewerSession`,
its ordinary reader, and a real `ViewerWindowController`. Each observation opens a
fresh process and BAM session with sampling seed 42, an Aqua window with an
1100 × 720-point content area, and a visible-viewport bitmap raster at the window's
backing scale. The timed boundary includes session work, native layout, and the
actual alignment renderer. It excludes compositor presentation and does not
establish input-to-photon latency.

The recorded machine was an Apple M4 with 16 GiB RAM, macOS 27.2 (26B123), and
Apple Swift 6.4.2 from Xcode 27.2. The executable used `swift build -c release`.

The initial target is measured before waiting for optional work. The initial
buffer then settles before a fixed route starts:

1. Eight right half-width pans, eight left, and eight right, with a 100 ms
   period. A slow committed pan finishes before the next step; it is not dropped.
2. Thirty-two actual native pointer-drag events at a 33 ms period. Two cycles
   move from one through eight quarter-width displacements and back to zero,
   with an additional 0.0025-viewport displacement to retain fractional motion.
3. Pointer release, missing required loading, and the final native raster.

Motion does not wait for optional work to become idle. Every query records its
interval, start/end timestamps, completion/cancellation/budget outcome, and
returned alignment count. A query outside the documented complete extraction
fails validation, including a speculative query. Checksum verification reads the
input subsets before the series, and later observations can reuse OS file caches.
Caches are not flushed; these are fresh-process measurements, not cold-disk
measurements. The injected
query tracing adds actor-call overhead and is identical across configurations.
Reported p95 values use the nearest-rank percentile across the relevant motion
events pooled over repetitions; a reversal event is the first pan after either
direction change.

Returned alignment counts are work proxies. They exclude records decoded and
discarded by filtering, cancellation, or budget rejection. No native decoded-record
or physical-I/O count is claimed here. The actual-reader interruption proof in
the [adjacent-prefetch report](adjacent-prefetch-2026-11-10.md) remains a separate
boundary.

## Inputs and complete route bounds

Inputs come from the checksum-pinned
[qualification acquisition](../../Benchmarks/Data/qualification-README.md).
Ordinary cases use the derived approximately 100× panel. Dense cases use the
complete extended unsampled source from the original nominal 300× BAM; they do
not use the smaller original dense extraction. Depth varies along each route.

| Case | Initial viewport | Complete extracted reference-span interval |
| --- | --- | --- |
| Ordinary 1 kb | chr20:10,024,501-10,025,500 | chr20:9,830,401-10,354,688 |
| Ordinary 10 kb | chr20:10,020,001-10,030,000 | chr20:9,830,401-10,354,688 |
| Dense 1 kb | chr20:29,892,101-29,893,100 | chr20:29,818,881-30,081,024 |
| Dense 10 kb | chr20:29,887,601-29,897,600 | chr20:29,818,881-30,081,024 |

The runner checks the full route's expanded C, including fractional-edge rounding,
against those bounds before starting. It also checks every actual required and
optional query. The dense route stays inside the extended extraction even at
10 kb; missing extraction is never interpreted as empty data.

The derived BAM SHA-256 is
`b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33`.
The unsampled extended source SHA-256 is
`d2c2aba71c005d7b8e8b69841566475ae2c4418105deba15b4d11fa1697b6d08`.
Their BAI checksums, executable and source hashes, operating-system/toolchain
information, and complete source snapshots accompany every local archive.

## Initial candidate comparison and observed pressure problem

On 2026-11-10, the first implementation based on `a42d420` compared disabled
prefetch with refill thresholds of P/4, P/2, and 3P/4. It retained M = 250,
P = max(W, 250), 1,000-base chunks, 32 MiB of optional cache, and optional-query
limits of 8 MiB and 20,000 decoded records. Three repetitions per configuration
and case produced 48 observations and 2,688 motion events. Configuration order
alternated between forward and reverse on successive repetitions.

| Case | Disabled pan p95 | P/2 pan p95 | Disabled query-free pans | P/2 query-free pans |
| --- | --- | --- | --- | --- |
| Ordinary 1 kb | 77.78 ms | 9.81 ms | 66.7% | 100% |
| Ordinary 10 kb | 81.71 ms | 20.05 ms | 66.7% | 100% |
| Dense 1 kb | 114.42 ms | 22.19 ms | 66.7% | 100% |
| Dense 10 kb | 109.53 ms | 152.44 ms | 66.7% | 63.9% |

The dense 10 kb result was a regression, not a passing result. Optional limits
were reached twice per observation, and repeated motion restarted work after
cache eviction. For example, one P/2 trace fetched optional
chr20:29,955,851-29,956,850 four times. The median total returned alignments were
333,438 with P/2 versus 110,872 disabled. Failed budget ranges themselves were
not retried; their quiet-failure suppression worked. The separate cache-pressure
restart behavior required correction before final selection.

Across this initial comparison, every native drag frame completed in less than
25 ms, and peak process RSS was 253.44 MiB. Those finite results do not excuse the
dense pan regression or establish ten-minute memory behavior.

Preserved initial evidence:

- [Observation CSV](data/rolling-prefetch-2026-11-10/initial-candidates-observations.csv)
- [Summary JSON](data/rolling-prefetch-2026-11-10/initial-candidates-summary.json)
- [Protocol JSON](data/rolling-prefetch-2026-11-10/initial-candidates-protocol.json)
- [Source and input hashes](data/rolling-prefetch-2026-11-10/initial-candidates-sha256.json)

The full local archive is `.local/measurements/issue-35/candidates-v1/`, including
per-query events, every motion event, source snapshot, worktree patch, and
`/usr/bin/time -l` output. The preceding single ordinary smoke observation is
kept separately at `smoke-v1/` and is not part of the comparison.

## Pressure correction and remaining tradeoff

On 2026-11-10, a real-fixture regression reproduced a completed but unretainable
optional chunk being requested again after another pointer movement. The session
was changed to retain that interval in its bounded optional-backoff state.
Required navigation can still load the interval normally. This applies to
resource pressure generally; it does not recognize benchmark coordinates.

Twelve subsequent dense 10 kb observations repeated every threshold and the
disabled baseline on the corrected source. The specific four-times unretainable
query was no longer repeated. Other data legitimately left the bounded cache
and could be fetched on later visits. The unretainable-query restart was fixed,
but the dense latency tradeoff remained:

| Threshold | Pan p95 | Query-free pans | Median returned alignments | Peak RSS |
| --- | --- | --- | --- | --- |
| Disabled | 109.57 ms | 66.7% | 110,872 | 252.17 MiB |
| P/4 | 144.23 ms | 63.9% | 311,096 | 226.31 MiB |
| P/2 | 144.54 ms | 65.3% | 326,040 | 229.66 MiB |
| 3P/4 | 146.36 ms | 68.1% | 336,930 | 229.77 MiB |

The enabled configuration has a 32 MiB optional byte budget; the disabled
baseline retains its historical eight-snapshot policy. This comparison therefore
includes their different retention behavior. It does not isolate scheduling
alone. Enabling prefetch also does additional useful work during a gesture:
in the first P/2 dense observation, frames 7, 8, and 23 displayed 2,460, 3,239,
and 3,174 records. The matching disabled frames displayed zero because the drag
had moved beyond loaded data. Those counts describe available display candidates,
not a claim of complete preview R coverage.

P/2 remains the provisional choice: it starts before a second half-width pan
consumes the remaining buffer and performed well on the ordinary and dense 1 kb
cases. The short dense 10 kb comparison does not establish a universal threshold
winner. In particular, the retained memory bound can trade repeated foreground
work for lower memory, and optional loading cannot guarantee smooth navigation
at every depth or speed. The final paired repetitions below use the corrected
source.

Post-correction evidence:

- [Observation CSV](data/rolling-prefetch-2026-11-10/pressure-candidates-observations.csv)
- [Summary JSON](data/rolling-prefetch-2026-11-10/pressure-candidates-summary.json)
- [Protocol JSON](data/rolling-prefetch-2026-11-10/pressure-candidates-protocol.json)
- [Source and input hashes](data/rolling-prefetch-2026-11-10/pressure-candidates-sha256.json)

The full archive is `.local/measurements/issue-35/pressure-candidates-v2/`.
It supersedes the earlier pressure implementation for final selection while
preserving the earlier measured regression.

## Final selected repetitions

Five fresh-process repetitions per case and configuration produced 40
observations and 2,240 motion events. The selected threshold was P/2, with the
same margin, buffer, chunk size, and resource budgets. No timing was discarded
or relabeled to improve these results.

| Case | Mode | Pan p95 | Reversal p95 | Drag p95 / maximum | Query-free pans | Peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| Ordinary 1 kb | Disabled | 48.02 ms | 9.18 ms | 6.70 / 8.81 ms | 66.7% | 140.16 MiB |
| Ordinary 1 kb | P/2 | 8.72 ms | 8.65 ms | 7.46 / 8.97 ms | 100% | 142.73 MiB |
| Ordinary 10 kb | Disabled | 82.32 ms | 20.08 ms | 14.66 / 15.44 ms | 66.7% | 177.38 MiB |
| Ordinary 10 kb | P/2 | 19.92 ms | 19.76 ms | 16.50 / 18.24 ms | 100% | 173.84 MiB |
| Dense 1 kb | Disabled | 115.24 ms | 20.81 ms | 12.67 / 13.89 ms | 66.7% | 178.00 MiB |
| Dense 1 kb | P/2 | 21.22 ms | 19.79 ms | 13.31 / 14.60 ms | 100% | 177.75 MiB |
| Dense 10 kb | Disabled | 107.00 ms | 40.75 ms | 21.18 / 23.70 ms | 66.7% | 258.50 MiB |
| Dense 10 kb | P/2 | 145.57 ms | 39.58 ms | 22.01 / 24.74 ms | 63.3% | 237.38 MiB |

The maximum selected first-ready-and-raster latency was 176.54 ms. Maximum
selected release-and-raster latency was 30.98 ms, compared with a maximum of
75.99 ms across the disabled cases. Every selected drag frame displayed
alignments; 240 of the 640 disabled drag frames displayed zero. Those baseline
frames moved beyond already loaded geometry while waiting until release to load
more data. The selected protocol therefore performs additional useful work
during the gesture; it is not a claim that prefetch reduces total BAM work.

| Case | Disabled median returned alignments | P/2 median returned alignments | P/2 optional budget stops per run |
| --- | --- | --- | --- |
| Ordinary 1 kb | 4,824 | 8,127 | 0 |
| Ordinary 10 kb | 36,058 | 68,224 | 0 |
| Dense 1 kb | 31,604 | 51,556 | 0 |
| Dense 10 kb | 110,872 | 328,176 | 2 |

The dense 10 kb result remains a documented limitation: P/2 did not improve its
overall pan latency or query-free fraction. Its smaller retained memory budget,
speculative reads, and new preview data have costs. The pressure fix stops the
specific repeated-unretainable-chunk behavior; it does not make bounded memory
equivalent to retaining every previously visited region. The measured native
frame responsiveness and faster release do not erase the slower pan result.

Selected evidence:

- [Observation CSV](data/rolling-prefetch-2026-11-10/selected-observations.csv)
- [Every motion event, including displayed-record counts](data/rolling-prefetch-2026-11-10/selected-motions.csv)
- [Summary JSON](data/rolling-prefetch-2026-11-10/selected-summary.json)
- [Protocol JSON](data/rolling-prefetch-2026-11-10/selected-protocol.json)
- [Source and input hashes](data/rolling-prefetch-2026-11-10/selected-sha256.json)

The full final archive is `.local/measurements/issue-35/selected-v2/`. Across the
three phases, 100 observations and 5,600 motion events were retained. These are
short fresh-process runs; they do not establish ten-minute memory stability,
performance on every BAM, or all of the separate integrated qualification cases.

## Native regression boundary

The independently readable `rolling.sam` fixture contains 80 distinct long
alignments spanning 1001–1700 and three alignments anchored at 1800 with 300-base
left soft clips: forward stored A bases, reverse stored C bases, and missing
sequence represented by an outline. Initial V = 1450–1549 has R ending at 1799,
so the tail alignments are absent despite overlapping drawn geometry. Native
pointer events then move twice, ending at V = 1550–1649 with a 0.25-base offset
before the controlled optional result completes.

The native tests assert tail colors/outlines, the latest fractional position,
the original gesture anchor on further motion, retained rows and scrolling,
newer wheel scrolling that reveals the new tail rows, preserved drafts, no
preview loading decorations, and normal required loading after release. Separate
success and failure cases retain the committed recovery-view checks. Both BAI
and CSI variants use the real indexed reader.

Before the implementation, the BAI case failed because `tail_forward` was still
absent after the completion was processed. Local native runs also encountered
the documented Swift async-host exit without a final test summary. Those runs
are not counted as passing; the unchanged native completion guard and the full
required PR CI remain the delivery gate. The performance executable runs its
own normal native application loop and completed every retained measurement.
After the cancellation-safe test cleanup and visible-tail scrolling assertions
were finalized, the isolated BAI success case completed with a successful
one-test summary in 0.289 seconds. That result does not substitute for the CSI,
failure-path, and complete-suite CI requirements.

## Reproduction

Build with the documented native prerequisites and use a fresh output directory:

```sh
swift build -c release --product RollingPrefetch
python3 Benchmarks/RollingPrefetch/run.py .build/release/RollingPrefetch OUTPUT_DIRECTORY
```

An optional positional threshold selects the paired disabled/selected protocol
with five repetitions. Case and repetition filters support focused reruns:

```sh
python3 Benchmarks/RollingPrefetch/run.py .build/release/RollingPrefetch OUTPUT_DIRECTORY 0.5 --case dense_10000 --repetitions 3
```

Use the archived source snapshot and its recorded HTSlib prerequisites for an
exact historical implementation comparison. The parent commit alone does not
include the uncommitted implementation measured in the initial archive.
