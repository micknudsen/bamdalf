# Qualification protocol v1 — 2026-11-08

This protocol was fixed before qualification performance measurements for
[issue #11](https://github.com/micknudsen/bamdalf/issues/11), against the
[accepted plan](qualification-plan-2026-11-08.md). The product baseline was
`micknudsen/bamdalf@f0b3348adcc1663ac71fb0318d6e14c75df1e549`.
Preparation profiles establish data characteristics, not performance results.
The exact case order, repetitions, actions, coordinates, assertions, and targets
are in [protocol v1](../../Benchmarks/qualification-protocol-v1.json).
Any later protocol revision must preserve this version and its results.

## Machine and inputs

The qualification machine was verified as Apple M4 with 17,179,869,184 bytes
(16 GiB) RAM, macOS 27.2 build 26B123, Xcode 27.2 build 27B52, and Swift 6.4.2.
Use an optimized release executable, the production 2,000-group budget and
10,000-base visibility cutoff, and controlled session seed 42. No new product
settings are introduced. Record executable, source, protocol, and input digests.
Use a light-appearance native 1,100 × 720 point content window; record actual
alignment viewport and backing scale. Stop competing builds, tests, data
preparation, and other native-window automation before measurements.

The derived approximately 100× panel retains about one third of exact RG/QNAME
groups from the documented public HG002 300× chr20 source. Preparation seed
20261108 and length-delimited SHA-256 identities are separate from runtime
sampling. Related source records inside the extraction boundaries stay together;
mates outside them are not fetched. Preserve all 2,580 reference dictionary
entries and record checksums, extraction evidence, actual depths, and independent
record/index validation. Complete extraction spans are:

| Panel part | Complete 1-based inclusive interval |
| --- | --- |
| Ordinary long stretch | chr20:9,830,401–10,354,688 |
| Second ordinary stretch | chr20:19,988,481–20,119,552 |
| Locally dense stretch | chr20:29,818,881–30,081,024 |

Timed targets use centers 10,025,000 and 20,050,000 for ordinary cases and
29,892,600 for designated dense cases, at widths 1,000 and 10,000 bases.
Retain the original unthinned 300× dense slice as a separate stress input at the
same dense center. Neither entire extraction spans nor every 1 kb target are
assumed to have exactly 100× depth. Never navigate outside complete source spans
and interpret missing extracted data as biological absence.

A separate, explicitly nonbiological resource fixture contains one exact
RG/QNAME group of 10,000 alignments with 148M CIGARs at `stress:1001`, including
9,999 supplementary alignments. The target is `stress:501-1500`. All 10,000
records must be retained without a downsampling warning. This probes large-group
behavior, which the public panel's two-record groups do not establish.

## Timing and independent checks

The harness drives the actual native interval field, toolbar control actions,
pointer handlers, wheel handling, session, query reader, and renderer. Wall time
begins immediately before native input/action handling and ends after regional
readiness, native layout/display requests, and synchronous rasterization of the
actual alignment/ruler views into reusable viewport-sized bitmaps. This includes
query, decoding, sampling, packing, input handling, and native CPU drawing.
It excludes OS event-queue delivery, compositor presentation, image encoding,
validation, and result serialization. Thus it does not prove display frame rate
or input-to-photon latency. Readiness polling may add approximately 1 ms.
Synthetic `performClick` animation delays are not part of an action-dispatch
measurement; record the native dispatch used by the harness.

Fresh-session cases open a new session for each of 20 repetitions. Each must
make a query and match independently enumerated eligible candidate counts.
Report the first observation and the subsequent observations separately as well
as the complete distribution. These are cold **application** loads. Data
preparation and input hashing can warm OS filesystem caches; OS caches remain
uncontrolled, and no cold-disk claim is made. Cached navigation must make zero
queries. These measurements distinguish application reuse from operating-system
caching without a systemwide cache purge.

| Case family | Work per input | v1 target |
| --- | --- | --- |
| Ordinary fresh load, two loci × two widths | 20 fresh sessions per case | At least 95% ≤500 ms |
| Derived and original dense fresh load, two widths | 20 fresh sessions per case | At least 95% ≤1,000 ms |
| Synthetic large-group fresh load | 20 fresh sessions, all records retained | At least 95% ≤1,000 ms |
| Cached navigation, each of four genomic inputs | 20 repetitions each of pan right/left and zoom out/in inside primed 10 kb coverage | At least 95% ≤100 ms for each action and case |
| Drag, ordinary 1/10 kb, derived dense 1/10 kb, original dense 10 kb, large group | 120 alternating native preview updates per case | At least 95% ≤33 ms per case |
| Scroll, same six views | 60 downward then 60 upward pixel-wheel updates per case | At least 95% ≤33 ms per case |
| Integrated native demonstration | Typed targets, toolbar pan/zoom, sampled/wide/unsampled transitions, clicked zoom, drag commit, scroll | Report each step against its recorded target; this single demonstration does not establish a percentile |

Report every case and each cached action independently; do not pool easy and
dense cases into a passing headline. Use the nearest-rank 95th percentile
(`ceil(0.95 × n)` after sorting), maximum, first observation, and exact number
meeting the limit. Twenty observations can establish only the observed fraction,
not a population confidence guarantee. Retained record IDs and rows are checked
outside timing; continuous actions must preserve surviving rows and nonshrinking
row extent. Capture selected native views after timing and inspect their contents.

## Ten-minute memory route

Run this case in its own process. The primary memory metric is whole-process
**peak resident set size in bytes**, from `getrusage`, independently reported by
macOS `/usr/bin/time -l`. The strict target is below 2,147,483,648 bytes (2 GiB).
Sample `task_vm_info` resident size and physical footprint every 250 ms, plus
per-navigation values, to expose continuing growth; retain the full trace.
These metrics include the harness and drawing buffers, not only BAM storage.
The peak RSS high-water mark catches peaks between trace samples.

The fixed route repeatedly opens an ordinary 10 kb anchor, pans 40 half-window
steps right and 40 back through a 200 kb stretch, visits 12 disjoint ordinary and
dense targets across all three spans, revisits the anchor, loads the dense peak,
scrolls, and crosses the wide-view boundary in both directions. It uses 100 ms
pauses between actions and completes whole route iterations until at least
600 seconds of navigation have elapsed. The revisit must issue a real reload
after exceeding the eight-inactive-snapshot history and reproduce the anchor's
same-session selected IDs. Row continuity checks run throughout the long pans.
Record total elapsed duration, operations, query counts, row extent, trace
samples, memory peaks, and memory ranges by minute. Pauses are pacing, not part
of per-action latency.

## Interpretation and delivery

Retain failures and incomplete runs with their exact artifacts. Fix measured
implementation defects at the agreed session/native seams, using red/green
regressions where behavior changes, and repeat only affected performance cases
plus final qualification needed to identify the shipped revision. Any target
revision requires explicit dated evidence and preserved v1 results under the
user's accepted revision policy; a new user-visible safeguard still requires a
product decision. Do not silently truncate candidates, split groups, or discard
continuity to meet a target.

Use existing correctness tests for accepted geometry, stale completions, error
restoration, identity, and sampling semantics. Performance timings do not replace
those tests. The local qualification host's Swift version differs from the
supported Xcode 16.4 CI toolchain; passing PR CI remains a separate delivery gate.
No universal malformed-file handling, exact local density preservation, or
comparison with another viewer is claimed.
