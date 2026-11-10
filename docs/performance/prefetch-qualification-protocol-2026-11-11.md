# Integrated prefetch qualification protocol — 2026-11-11

On 2026-11-11, this protocol was prepared for
[issue #36](https://github.com/micknudsen/bamdalf/issues/36), after bounded-tail
retrieval, adjacent prefetch, and rolling pan/drag refill merged at
`micknudsen/bamdalf@12187b1f740e0fc00fffe59a40e8c3493877b2a2`.
It defines measurements, not successful results. The exact machine-readable
plan is [prefetch qualification v1](../../Benchmarks/prefetch-qualification-v1.json).
Its frozen SHA-256 is
`cd18bdd8ea6dcc54d3253b1061aaf9c96aa65862b5d9f30c0844bf1a561c6aad`.
The [earlier qualification](qualification-2026-11-08.md) and focused
[tail](bounded-tail-2026-11-10.md),
[adjacent](adjacent-prefetch-2026-11-10.md), and
[rolling](rolling-prefetch-2026-11-10.md) reports remain historical evidence;
none establishes completion of this integrated protocol.

## Baseline and provenance

- Apple M4, arm64, 17,179,869,184 bytes RAM (16 GiB).
- macOS 27.2 build 26B123; Xcode 27.2; Swift 6.4.2; static HTSlib 1.25.
- Release build, light appearance, 1,100 × 720-point window, seed 42, production
  2,000-group display budget and 10 kb alignment-visible cutoff.
- Fixed M = 250 bases; P = max(W, 250); refill at P/2 remaining contiguous
  coverage measured from R; 1,000-base optional chunks; 32 MiB optional cache;
  8 MiB and 20,000-native-record optional-query limits; 80 attempts per demand
  and 64 retained failed/backoff ranges. These are the measured predecessor
  choices being qualified, not user controls.

The wrapper must archive the protocol, commit and working patch, complete source
snapshot, executable and dependency hashes, actual environment, BAM and index
hashes, native output, process resource output, and completion records. A source
change after a measurement receives a new archive; it cannot inherit the old
binary's timings. Qualification starts only after schema/correctness smoke runs
are complete and the protocol has been frozen. Smoke results are not counted.
Do not run competing builds, tests, data preparation, or other qualification
processes during observations.

Each case runs in its own process. A case marked `fresh_session` reopens the BAM
with a new application session for every repetition. Its 20 observations are
app-uncached sessions, not 20 independent processes. Input checksum reads, prior
runs, and the OS can warm file caches; no cache flushing or cold-storage claim
is made. The order of enabled/disabled case pairs alternates between workloads.

## Complete input coverage

Use the checksum-pinned inputs and preparation provenance from the
[derived-panel recipe](../../Benchmarks/Data/qualification-README.md).
Preparation sampling retains approximately one third of complete fragments;
it is separate from runtime display sampling. Qualifying the derived input
still requires reading its entire requested R and C, without a second benchmark
subsample or query prefix limit.

The two extended HG002 inputs are distinct:

| Input | Purpose | BAM SHA-256 |
| --- | --- | --- |
| `HG002.GRCh38.qualification-100x.bam` | Ordinary and derived-dense cases | `b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33` |
| `HG002.GRCh38.qualification-source.bam` | Complete original nominal 300× dense stress and memory route | `d2c2aba71c005d7b8e8b69841566475ae2c4418105deba15b4d11fa1697b6d08` |

Both contain every source record retained by their documented preparation whose
aligned reference span overlaps these extraction regions:

| Region | Inclusive complete source interval |
| --- | --- |
| Ordinary long route | chr20:9,830,401–10,354,688 |
| Independent ordinary region | chr20:19,988,481–20,119,552 |
| Dense extended route | chr20:29,818,881–30,081,024 |

The original dictionary has 2,580 entries; chr20 has 64,444,167 bases. The
acquisition audit, source virtual offsets, exact fragment-selection verification,
independent indexed/sequential counts, and regional depth profiles remain in the
documented data archive. Nominal 100× or 300× labels do not replace measured
regional depth; the dense centers and their lower-depth neighboring route must
be distinguished in the result.

The older small original dense extraction is unsuitable for the full 10 kb C
and sustained route. Use the already audited extended unsampled source instead;
do not count missing extraction as empty source data. For the memory route,
the old target chr20:9,840,001–9,850,000 would require C starting at 9,829,751,
outside complete source coverage. The new first disjoint target is
chr20:9,850,001–9,860,000, whose C starts at 9,839,751.

The `rows` and `rolling` BAMs are wholly known synthetic fixtures with `tiny`
lengths of 20,000 and 60,000 respectively. Isolated copies with only their BAI
indexes avoid the intentional index-choice UI. They supply actual empty,
reference-limit, full-tail, and controlled recovery demonstrations. They do not
establish WGS performance or universal malformed-input handling. BAM and index
checksums are pinned separately in the protocol.

The accepted baseline plan also includes a large-group stress case. Retain the
whole known `stress:1–10000` fixture made by the
[large-group generator](../../Benchmarks/Data/qualification-large-group.py), at
`.local/measurements/issue-11/large-group/large-group.bam`. Its 10,000 distinct
records all have POS 1001, 148M, and one exact RG/QNAME group; all remain visible
and unsampled at `stress:501–1500` and the specified small drag offsets. Check
that every record remains present. The fixture is deliberately nonbiological
and does not replace the HG002 cases. Its BAM SHA-256 is
`04518ed00407ae76c0d841f1ca62275373062a55360e0129f0787a2a05eb2617`; the BAI pin and
the original preparation audit accompany it.

The [preflight](../../Benchmarks/PrefetchQualification/protocol.py) conservatively
simulates every typed/pan/zoom/drag target, including a fractional-edge allowance,
and requires the entire desired C to lie within one complete span. It audits all
fixed repetitions and two full memory cycles; the memory route resets to an
explicit anchor each cycle. The native harness independently checks every actual
required/optional query and each presented desired C. A preflight negative probe
must reject the old 9,840,001 target before measurement; correcting the target
must make the full audit pass.
The recorded preflight rejected that old target as C =
chr20:9,829,751–9,860,250; the corrected 62-case plan passed 6,374 conservative
presentation audits. These are preflight checks, not executed qualification
observations. The generator refuses to replace an existing protocol; changes
after freezing require a new version at a new path.

## Case matrix and routes

Every workload has matched disabled/enabled configurations with the same input,
seed, coordinates, cadence, repetitions, and validation. Disabled mode uses the
existing eight-snapshot retention policy; enabled mode uses its explicit optional
byte budget. Their comparison includes that retention difference and additional
useful preview data, rather than isolating scheduling cost alone.

| Workload | Repetitions per mode | Scope |
| --- | --- | --- |
| App-uncached load | 20 fresh sessions | Ordinary A/B, derived dense, original expanded dense; each at 1 and 10 kb |
| Cached navigation | 20 four-action cycles | Right/left pan and centered zoom out/in for all four regions |
| Drag | 120 actual previews | Ordinary A and original expanded dense at 1 and 10 kb |
| Scroll | 120 actual wheel updates | Same four views; alternate down/up and require every event to change scrolling |
| Rolling route | Five fresh-session routes | Same four views; 24 pans, two reversals, 32 fractional drag updates, and release |
| Large group | 20 fresh loads, 120 drag and 120 scroll updates | One complete 10,000-record group, retained without display-budget truncation |
| Native workflow | One route | Typed, toolbar, mouse zoom, sampled/unsampled/wide transitions, draft-preserving preview, release and scroll |
| Known fixture workflows | One route each | Empty/recovery/reference ends and full soft-tail drag/drawing |
| Sustained memory | At least 600 active seconds | Original expanded source, each mode, after required warmup and optional settling |

The locked matrix has 62 cases: 31 workloads, each disabled and enabled.

The rolling route has eight half-width pans right, eight left, and eight right
at a 100 ms period. A slow action completes rather than being dropped. It then
uses a real pointer-down and 32 native drags at a 33 ms period: two cycles from
one through eight quarter-width displacements and back, with a fractional
0.0025-viewport offset. It does not wait for optional settling between motion
events. Query-free means no required query starts during the measured action;
optional work is counted separately and never hidden.

The memory setup loads the ordinary anchor and lets initial optional work settle.
Active duration starts afterward. Each cycle includes 40 right and 40 left pans,
12 disjoint complete-source targets, an anchor revisit requiring a reload with
the same selected record identities, a dense view, real down/up scrolling,
drag/release, and wide/return transitions. The cycle repeats until at least 600
active seconds have elapsed. Cadence waits are part of route elapsed time, not
action latency. The trace and completion record preserve warmup offset, actual
active duration, cycle count, every action, and all resource observations.

## Metric boundaries and targets

Timing begins before native control/input dispatch and ends after required
readiness, native layout, and immediate synchronous drawing of the actual ruler
and alignment NSViews into reused viewport-sized bitmaps. There is no optional
settling pause between readiness and first drawing. PNG encoding, assertions,
metric output, and cadence waits are outside the timing boundary. Report ready
time and raster time separately as well as their continuous combined boundary.
This excludes OS event-queue delivery, compositor presentation, and physical
display latency; it does not measure input-to-photon latency or a display frame
rate.

Keep the original targets unchanged:

| Case | Required observed proportion |
| --- | --- |
| Ordinary app-uncached ready-and-drawn | At least 95% within 500 ms |
| Designated dense ready-and-drawn | At least 95% within 1,000 ms |
| Query-free navigation | At least 95% within 100 ms |
| Drag/scroll visual updates | At least 95% within 33 ms |
| Each ten-minute route | Peak process RSS strictly below 2 GiB |

For a pan/zoom/release step with both `target_ms` and `query_free_target_ms`,
apply the smaller target when its required-query count is zero. Otherwise use
its declared ordinary/dense target. Drag/scroll remains subject to 33 ms even
when optional reads run concurrently. Group by case and action/target class;
report query-bearing dense pans separately so easy views cannot hide misses.
Nearest-rank p95, count within target, median, maximum, and full observations
must accompany each case. Demonstration actions have too few observations for
population percentiles; list their individual timings and postconditions.

Use process-lifetime peak RSS from `getrusage`, independently checked by
`/usr/bin/time -l`, for the memory gate. Record resident size and physical
footprint every 250 ms plus action-time samples. Keep both raw traces and
per-minute ranges, including warmup and any final partial minute. A passing
finite peak is not evidence of flat memory, no leaks, or unlimited-session
boundedness.

Required/optional query traces retain interval, start/end, outcome, and returned
alignment counts. Returned counts include repeated retrieval and exclude records
discarded during decoding or interruption. They are not native decode counts or
physical I/O bytes. A separate instrumented actual-reader probe must report
decoded-record work, optional iterator closure, foreground first-record ordering,
and cancellation latency on the exact final source. Any OS I/O counters must be
named with their actual meaning and warm-cache limitations; zeros cannot prove
no logical reading.

## Qualification completion

The required-reader probe runs controls and deliberately overlapping
interruptions, not a gate delaying an already-read result. A query finishing
before the foreground request is a non-overlap observation, not interruption
evidence. Instrumentation must live only in an archived measurement source copy;
native timing uses production code. Report inability to interrupt a blocking
HTSlib call and any probe overhead.

Before collecting final results, validate the harness schema and native
postconditions with separately archived smoke runs. Freeze the protocol and
retain its hash with every case. Preserve every failed or incomplete run with
its source and cause. A correction gets a new archive and, if the workload or
measurement semantics change, a new protocol version; do not silently relabel
an old failure. Tuning must preserve complete candidates, sampling identity,
tails, rows, scrolling, readiness, recovery, and reference bounds.

Qualification is incomplete until every applicable target and required
measurement is resolved, the native demonstration and raw evidence are retained,
the full guarded suite has a real completion summary, and required CI passes on
the final PR head. Report the dense 10 kb tradeoff from the predecessor alongside
new measurements: earlier enabled pan p95 was 145.57 ms versus 107.00 ms disabled,
with additional returned alignment work and lower peak RSS. A faster release or improved
preview coverage does not erase that cost.
