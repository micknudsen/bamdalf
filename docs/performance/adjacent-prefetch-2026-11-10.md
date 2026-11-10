# Adjacent prefetch: focused measurements

On 2026-11-10, the issue #34 measurements selected these provisional engineering
settings: **P = max(W, 250 bases), 1,000-base optional chunks, 32 MiB of accounted
optional cache storage, and an 8 MiB / 20,000-native-record limit per optional
query**. The fixed 250-base required search margin from
[issue #33](bounded-tail-2026-11-10.md) remains unchanged. These settings are not
user controls or guarantees for arbitrary depth, read lengths, or storage.

With these settings, all 25 enabled observations reused completed buffer data
for the next half-width right pan with **zero required queries**. Their native
ready-and-raster median times were 9.64–26.11 ms, compared with 57.33–137.96 ms
and one required query with prefetch disabled. A separate actual-reader probe
interrupted all 15 deliberately overlapping optional queries before their full
drain; native iterator closure preceded foreground decoding in every case.

This is the complete safe initial/jump/zoom prefetch slice. Proactive pan/drag
refill, sustained navigation, and the ten-minute integrated qualification remain
issues #35 and #36. The measurements below do not claim those results.

## Protocol and source coverage

The [native harness](../../Benchmarks/AdjacentPrefetch/main.swift) uses the
production session, reader, sampling, layout, and native alignment renderer.
The [runner](../../Benchmarks/AdjacentPrefetch/run.py) creates a fresh process
for each observation. Windows are 1,100 × 720 points with light appearance;
sampling uses the production 2,000-group budget and seed 42. The first timing
starts before interval submission and ends after required readiness, native
layout, and the first actual viewport `NSView.draw` bitmap raster. No settling
pause separates readiness and this raster. The compositor and physical screen
presentation are outside this boundary.

The harness then waits for optional work to settle and performs one half-width
right pan, measuring through its first viewport raster. It verifies that optional
completion leaves the stationary target, selected alignments, rows, downsampling
state, loading state, and errors unchanged. Query counts and returned records
come from wrappers around the production loading calls. Returned-record totals
include repeated records crossing chunk boundaries; they are not unique records,
native decoded-record counts, or physical I/O bytes.

Measurements used Apple M4 / 16 GiB, macOS 27.2 build 26B123, Swift 6.4.2,
HTSlib 1.25, and release builds of
`micknudsen/bamdalf@0d78619298ec4b86987ee51a6555ee4ac2828d9b` plus the issue #34
working changes. Source/executable/input checksums and working patches were
archived. No competing builds or native tests ran during observations. System
activity and OS file caches were uncontrolled; these are finite observations
with warmed storage, not cold-disk guarantees or independent machine samples.

All initial, optional, and measured subsequent target coverage lies inside
the audited source extractions. With M = 250, a 1 kb viewport requests at most
1.5 kb required / 3.5 kb desired coverage; a 10 kb viewport requests at most
10.5 kb required / 30.5 kb desired coverage, before reference clamping.

| Case | Visible target on chr20 | Complete extraction span | Input |
| --- | --- | --- | --- |
| Ordinary / 1 kb | 10,024,501–10,025,500 | 9,830,401–10,354,688 | Derived approximately 100× |
| Ordinary / 10 kb | 10,020,001–10,030,000 | 9,830,401–10,354,688 | Derived approximately 100× |
| Dense / 1 kb | 29,892,101–29,893,100 | 29,818,881–30,081,024 | Derived approximately 100× |
| Dense / 10 kb | 29,887,601–29,897,600 | 29,818,881–30,081,024 | Derived approximately 100× |
| Original dense / 1 kb | 29,892,101–29,893,100 | 29,884,417–29,900,800 | Original approximately 300× |

The original dense 10 kb case is deliberately excluded: its full desired C
extends outside the existing original-data extraction. Treating those missing
source regions as empty would invalidate the comparison. The
[derived recipe](../../Benchmarks/Data/qualification-README.md) and
[original recipe](../../Benchmarks/Data/README.md) retain extraction provenance.
The BAM SHA-256 values are respectively
`b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33` and
`786c9d3f66ff721d8bbb20bb62c8e055aa589f1e64f930fc8fdfc210e9b689c5`.

## Chunk comparison and selected native results

The first comparison used three repetitions of disabled, 250-base, and
1,000-base configurations for each case: 45 observations in fixed
case/configuration order. Both enabled sizes made the next pan query-free.
The larger chunk reduced repeated boundary decoding and cache-entry work while
retaining per-record cancellation. With 1,000-base chunks, all two or twenty
planned optional queries completed, and the next pan retained complete required
coverage. The dense 10 kb / 250-base case stopped at 77 attempts
under that budget; it still retained the next pan's complete required coverage.

| Case | Optional calls, 250-base | Calls, 1,000-base | Returned records, 250-base | Records, 1,000-base |
| --- | ---: | ---: | ---: | ---: |
| Ordinary / 1 kb | 8 | 2 | 2,263 | 1,649 |
| Ordinary / 10 kb | 80 | 20 | 22,020 | 15,912 |
| Dense / 1 kb | 8 | 2 | 7,093 | 5,093 |
| Dense / 10 kb | 77 | 20 | 49,472 | 36,965 |
| Original dense / 1 kb | 8 | 2 | 20,952 | 15,127 |

The selected configuration was then rebuilt and repeated five times per
enabled/disabled case: **50 native observations**, alternating configuration
order between repetitions. The buffer P = max(W, M) was sufficient to serve the
tested half-width right pan from the initial required region; no larger
buffer was selected or claimed optimal. No optional query reported an error.

| Case | Initial median ms, disabled | Enabled | Initial maximum ms, enabled | Pan median ms, disabled | Enabled | Pan maximum ms, enabled | Enabled peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary / 1 kb | 89.18 | 40.88 | 101.93 | 57.33 | 9.64 | 10.62 | 117.28 |
| Ordinary / 10 kb | 99.25 | 91.39 | 99.02 | 85.25 | 20.98 | 22.63 | 133.11 |
| Dense / 1 kb | 92.73 | 96.87 | 108.33 | 70.57 | 15.68 | 17.56 | 123.84 |
| Dense / 10 kb | 106.35 | 116.18 | 122.61 | 69.20 | 26.11 | 27.58 | 152.08 |
| Original dense / 1 kb | 150.37 | 133.13 | 143.26 | 137.96 | 23.41 | 23.86 | 139.23 |

These are continuous submit-to-ready-and-raster measurements, unlike the
separately settled drawing boundary in the older issue #33 native report.
Disabled initial maxima were 133.87, 104.36, 111.71, 109.20, and 155.78 ms in
table order. The initial dense 10 kb median increased by 9.83 ms with prefetch;
the result does not claim zero additional CPU contention or an initial-load
speedup. Native/system variation reached tens of milliseconds between runs.
All measured initial views remained below the existing provisional latency
targets, and the direct work-count improvement for the subsequent pan was
consistent. No target was revised to make these observations pass.

RSS comes from `/usr/bin/time -l` over the whole process, including native views
and raster allocations. MiB means 1,048,576 bytes. The highest selected-run RSS,
including disabled observations, was 153.05 MiB. The earlier candidate comparison
peaked at 157.59 MiB. Neither number bounds long-running navigation or process
memory for an arbitrary BAM.

The checked-in [candidate observations](data/adjacent-prefetch-2026-11-10/candidate-results.csv),
[candidate summaries](data/adjacent-prefetch-2026-11-10/candidate-summary.json),
[selected observations](data/adjacent-prefetch-2026-11-10/native-results.csv), and
[selected summaries](data/adjacent-prefetch-2026-11-10/native-summary.json) retain
unrounded values. Local complete archives are
`.local/measurements/issue-34/candidates-v1/` and `selected-v1/`.

## Actual-reader interruption and ownership

The production `BAMFile` actor keeps one native handle. Optional tasks receive
bounded chunks and explicit query budgets. New committed navigation cancels
the optional task before required loading. The reader checks cancellation
before and after each native query step, and during sequence/CIGAR expansion.
It does not suspend with a live shared-handle iterator; `defer` closes that
iterator before another actor task can seek the BAM. A currently blocking
HTSlib call is not immediately interruptible.

The [instrumentation runner](../../Benchmarks/AdjacentPrefetch/instrument.py)
copies the complete build sources into an isolated archived snapshot. Only that
snapshot gains native read/close probes; no observer API is added to production.
Immediately after the first successful optional `bamdalf_query_next`, a signal
wakes a waiting main-actor task that submits a 5,000-base forward jump through
the real `ViewerSession`. There is no artificial read delay or post-read gate.
The probe counts native records and timestamps iterator closure immediately
after `bamdalf_query_close`, plus the first successful foreground native record.

This probe uses the production session and reader **without a native window or
controller**. It measures reader priority and session readiness, not native
layout, rasterization, or compositor responsiveness. The native observations
above supply the separate drawing boundary. Probe bookkeeping and locks add
measurement overhead. All three 1 kb routes and their full R/C coverage fit
inside the source spans listed above, using the selected 1,000-base chunk.

Five uninterrupted controls and five active interruptions per source produced
30 observations. Every interrupted optional query returned cancellation and
established no completed coverage. In all 15 active interruptions, the native
optional iterator closed before the first foreground native record.

| Source / 1 kb | Native records in full chunk | Records before interruption, five runs | Maximum request-to-native-close ms | Maximum foreground session-ready ms |
| --- | ---: | --- | ---: | ---: |
| Ordinary | 821 | 13, 33, 28, 22, 1 | 0.071 | 3.86 |
| Derived dense | 3,674 | 25, 1, 10, 41, 35 | 0.221 | 15.84 |
| Original dense | 10,877 | 38, 46, 43, 1, 31 | 0.055 | 47.91 |

The request-to-close boundary begins before committing the new target and
ends after actual native iterator destruction. It includes session cancellation
dispatch; it is not an I/O deadline. Native decoded counts include records later
excluded by flags, unlike returned-record totals in the chunk table.

The [reader observations](data/adjacent-prefetch-2026-11-10/reader-results.csv)
and [reader summary](data/adjacent-prefetch-2026-11-10/reader-summary.json) retain
ordering timestamps and counts. The complete source snapshot, instrumentation,
native/executable hashes, build log, individual traces, and timing logs are in
`.local/measurements/issue-34/reader-probe-v5/`. A preceding v4 probe established
active cancellation but lacked explicit native-close/foreground-decode probes;
v5 supersedes it for the ownership-order claim.

Earlier v1/v2 harness attempts rejected a formatted-coordinate assertion and
an inaccessible parser call. The v3 native-window attempt observed a tiny
ordinary query finishing before the foreground task ran, so it did not establish
active interruption. Those archives are retained and do not count as proof of
preemption or as product failures. They are not silently relabeled as successes.

## Resource accounting and limits

Optional cache accounting uses conservative app-owned storage estimates:
twice each alignment's inline/string/segment payload, 256 bytes per alignment,
32 bytes per segment, plus per-entry/reference overhead. Shared copy-on-write
payload retained by multiple entries is counted repeatedly. Complete coverage
is partitioned at overlaps and required/recovery boundaries, so historical
optional portions do not become exempt merely by touching a required interval.
The current required region and saved committed recovery data remain protected;
distant optional fragments are evicted first.

The optional reader separately bounds native decoded-record work and app-owned
expansion/retained allocations. The 8 MiB preflight includes decoded sequence
and CIGAR expansion before materializing them. A limit produces an error and
discards the incomplete query, never a truncated successful result. Mandatory
queries have no optional record/byte cap. The driver also caps each speculative
plan at 80 attempts and failure metadata at 64 ranges, after which speculation
stops while required navigation remains available.

The 32 MiB / 8 MiB / 20,000-record limits admitted the selected workloads and
kept measured process RSS below 154 MiB. The 250-base candidate showed optional
cache pressure in the dense 10 kb case, while 1,000-base chunks reduced duplicate
storage/work and retained the tested next pan. Controlled small-budget tests
separately verify eviction/reload equality and mandatory/recovery protection.
These chosen limits are conservative engineering budgets, not empirically
optimal values or total-process caps. HTSlib buffers, a single pathological raw
record, required data, native layout, and allocator behavior lie outside this
optional accounting. Display-group count is never used as a cache-byte bound.

## Reproduction and verification boundary

With the checksum-pinned datasets acquired, run the selected comparison:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release --product AdjacentPrefetch
python3 Benchmarks/AdjacentPrefetch/run.py .build/release/AdjacentPrefetch NEW_NATIVE_OUTPUT 1000
python3 Benchmarks/AdjacentPrefetch/instrument.py NEW_READER_OUTPUT 1000
```

Omit the final chunk argument from `run.py` to compare 250 and 1,000 bases.
Output directories must be new; runners preserve source/input provenance and
do not replace an earlier result. The final runner alternates configuration
order; the archived first candidate run used its recorded fixed order.

Thin native checks exercise ready sampled/unsampled status, warning accessibility,
spinner visibility, rows/scrolling, actual renderer output, and absence of an
alert after optional failure. Their controlled second-query gate proves the
failure was handled before checking the native state. Logical session/reader
tests cover the wider correctness matrix separately from wall-clock measurements.

This focused report does not establish cold-storage latency, physical I/O bytes,
continuous pan/drag refill, arbitrary-depth responsiveness, or ten-minute memory
behavior. Full integration and sustained qualification remain issue #36; guarded
full-suite completion and required CI remain independent delivery gates.
