# Native development

This document describes the current implementation. The
[2026-11-10 design revision](design.md#viewport-eligibility-and-complete-candidates)
accepts bounded soft-tail-only visibility and
[rolling prefetch](design.md#rolling-prefetch-and-resource-priority). The bounded
visibility slice uses a fixed 250-base search margin, supported by the
[2026-11-10 measurements](performance/bounded-tail-2026-11-10.md). Rolling
prefetch, background refill during dragging, and separate speculative-error
handling remain pending. This slice retains release-time retrieval during dragging.

## Prerequisites

Use an Apple Silicon Mac running macOS 15 or newer, with Xcode 16.4 or newer
and its macOS SDK. Open Xcode once and complete its license agreement and
component installation. These setup steps require the developer's acceptance;
a successful `xcodebuild -version` alone does not prove setup is complete.

Select the installed Xcode for the current shell without changing the system
selection:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```

CI uses the Apple Silicon `macos-15` runner and explicitly selects
`/Applications/Xcode_16.4.app/Contents/Developer` (Swift 6.1). The runner and
installed Xcode version are described in GitHub's
[runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
and [macOS 15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

## Build, test, and launch

From a fresh checkout:

```sh
bash scripts/build-htslib.sh
swift build
bash scripts/test.sh
bash scripts/build-app.sh
open .build/bamdalf.app
```

The script builds the release executable, packages its native application bundle,
and applies an ad hoc signature for local use. No paid Apple developer account
is needed. This is a development app, not a notarized distribution.

For versioned ZIP packaging and the manual GitHub draft-release workflow, see
[Preview releases](releases.md).

The launch window contains a full-width workspace with **No BAM file open**.
Use **File → Open BAM…** / **Command-O** to select a local BAM. The app discovers
`sample.bam.bai`, `sample.bai`, `sample.bam.csi`, and `sample.csi` beside
`sample.bam`. One candidate opens automatically; multiple candidates require an
explicit choice. Canceling or failing a replacement preserves the open session.
An index failure identifies the selected file without trying another index.

A successful open shows **Enter a genomic interval** and focuses the field.
Enter a complete 1-based inclusive interval, for example `tiny:100-200` with
the opening fixture. Enter validates against the BAM header, formats the field,
and moves the ruler. Malformed or out-of-range input remains editable with an
inline error; editing clears the error without navigating. **Go → Go to
Interval** / **Command-L** focuses and selects the existing text. **Escape**
in the editor restores the target coordinates (or clears it before navigation).

This increment queries real alignments and displays independent rows with full
standard CIGAR geometry, colored/outlined soft clips, and vertical scrolling.
Changed readable targets show their ruler immediately, reuse eligible loaded
records, and show a spinner only while missing query coverage loads. A target
with complete coverage is ready immediately, including an empty region.
Same-target Enter does not reload or reset scrolling. A
failed region restores the prior successful view before its attached error
alert, preserving any newer draft. Wider than 10,000 bases, the app shows
**Zoom in to see alignments** without querying or drawing alignments. The
[initial visibility measurements](performance/visibility-2026-11-07.md) document
that default and its limitations.

Nearby typed targets on the same reference retain rows and vertical scrolling.
Disjoint targets, reference changes, and returns from ruler-only display start
fresh rows at the top once, then honor newer scrolling during loading. These
layout changes still reuse adequate loaded data. The toolbar's **Pan left** and
**Pan right** arrows move by half the inclusive width, rounded up for odd widths
(one base moves one base). They clamp within the current reference without
changing width. A changed pan replaces an older draft/error; a boundary no-op
preserves it. Buttons remain available during regional loading and reuse the
same row, scroll, and failure behavior as typed navigation. **Zoom out** (minus)
and **Zoom in** (plus) double/halve the inclusive width around the current center.
Halving an odd width rounds up; a half-base center tie chooses the lower
placement, then the complete target shifts inside the reference. For example,
`tiny:101-110` zooms in to `tiny:103-107`, and `tiny:101-105` zooms out to
`tiny:98-107`. Plus stops at one base and minus at the whole reference. A changed
zoom replaces an older draft/error, while an unchanged limit preserves it.
Between alignment views, zoom retains surviving rows, row extent, and scrolling,
including crowded insertion decoration. Crossing above 10,000 bases suppresses
all alignment retrieval/drawing. Zooming back starts fresh at the top once,
reuses adequate data, and honors newer scrolling while missing data arrives.
In the alignment area, drag horizontally to preview loaded geometry and ruler
ticks with the pointer. Fractional-base motion stays smooth; release commits the
nearest whole-base displacement (half-base ties away from zero) and requests
missing coverage. Drafts survive preview and an unchanged release. A changed
release replaces the old draft/error. Double-click halves width around the hit
base; Option + left-click doubles it. Even-width center ties use the lower
placement, and targets shift inside reference bounds. These gestures also work
in the ruler-only alignment area. Right-click stays distinct, field editing
uses native behavior, and wheel/vertical trackpad events scroll the rows.
The status slot shows a spinner while loading. A ready downsampled target shows
a small amber triangle; hovering or focusing it explains **Downsampled: some
alignments are not shown.** The same text is available to assistive technology.
Ready unsampled and wide targets leave the slot empty.
There is no permanent file sidebar or Open BAM toolbar button. Close the window or use **bamdalf → Quit bamdalf** /
**Command-Q** to quit.

For a focused check while developing:

```sh
bash scripts/test.sh --filter LaunchTests
```

Run the documentation checks in [CONTRIBUTING.md](../CONTRIBUTING.md) as well.

The test script requires a nonempty Swift Testing completion summary as well as
a successful exit status. On 2026-11-07, local Swift 6.4.2 native-control tests
sometimes exited zero before finishing; an exit-stack trace reached
`swift_task_asyncMainDrainQueue`, consistent with the upstream
[run-loop exit report](https://github.com/swiftlang/swift/issues/91716).
The script rejects those incomplete runs rather than reporting success. CI's
Xcode 16.4 toolchain remains the delivery gate; inspect executed-test totals.
No application event-loop behavior or test assertions are changed to conceal a
test-host failure.

## Implementation and test boundary

Swift 6, AppKit, and Swift Package Manager supply the native application, window,
build, and tests. A narrow C adapter uses source-built **HTSlib 1.25** behind an
actor that owns the BAM, header, and selected index. This is an internal app
boundary, not a public SDK. Header/index loading runs off the main thread, and
obsolete open attempts cannot replace a newer session or show stale errors.

`scripts/build-htslib.sh` downloads the official
[HTSlib 1.25 release](https://github.com/samtools/htslib/releases/tag/1.25)
through its pinned official GitHub release-asset API ID, verifies its pinned
SHA-256, and builds a static library for macOS 15 or newer. The first
build needs network access; subsequent builds reuse the verified archive and
toolchain-specific build. Optional networking, plugins, libdeflate, bzip2, and
LZMA are disabled for this local-BAM scope. The app links system zlib and copies
the upstream HTSlib/HTScodecs licenses into its bundle. It needs no Homebrew
libraries or runtime samtools executable. Run the dependency script again after
cleaning `.build` or changing Xcode. CI runs the same script before Swift builds.
CI supplies its existing read-only GitHub token for the public release-asset API
request; local downloads are anonymous unless `BAMDALF_GITHUB_TOKEN` is set.
The script reads the optional authorization header through stdin, keeps it off
the curl command line, and strips it on the redirect to the asset storage host.
This avoids sharing the anonymous API quota with other hosted-runner users;
the asset ID, checksum, TLS verification, and token permissions stay unchanged.

`ViewerSession` owns the application-facing presentation consumed by the real
native workspace. Swift Testing checks that seam and the actual AppKit window.
Native checks inspect the visible message, workspace sizing, field focus after
real opening, selectable index-menu items, explicit choice, and the attached
selected-index error alert. They exercise the file-selection completion action
used by the actual native chooser. Integration checks use the
production reader and small real BAI/CSI files through the session. Controlled
completion tests deliver older results after newer opens without timing sleeps.
Those opening checks alone do not establish regional drawing or WGS performance;
the regional tests and separate measurements below cover their own boundaries.

Interval tests drive editing/submission/reset through that same session with
real header bounds. Native tests send Enter/Escape through the actual AppKit
field editor, exercise the real Go menu, and inspect inline errors and ruler
labels after focus changes and window resizing. The ruler places full integer
labels at base centers, choosing 1/2/5 steps and reducing density to fit. Targets
use signed 64-bit, 1-based inclusive coordinates; the C query adapter converts them
once to HTSlib's zero-based half-open interval.

The readable opening source fixture is
[`opening.sam`](../Tests/BamdalfKitTests/Fixtures/opening.sam). Its references are
`tiny` (2,000 bases) and `other_reference` (800 bases), with 10-base and 6-base
alignments at positions 101 and 201 respectively. The
[`coordinates.sam`](../Tests/BamdalfKitTests/Fixtures/coordinates.sam) fixture
adds a 300,000,000-base reference and an exact reference name containing a colon
and hyphen. The additional `alignments.sam` fixture covers all nine operations, fixed flags,
MAPQ 0/255, reverse order, literal `=`, skip-only overlap, and absent sequence.
`rows.sam` includes 80 distinct identical records and soft-tail collisions.
`navigation.sam` adds a spanning record, an earlier-drawn newcomer tail, vacant
rows, and another reference for continuity and fresh-layout tests. `zoom.sam`
contains adjacent insertion-bearing records and an overlapping record for
retained-row and native crowded-marker checks.
`scripts/generate-defect-fixtures.c` deliberately writes unavailable/mismatched
CIGAR records and their indexes without a decoder silently repairing them.
Regenerate the committed fixtures using:

```sh
bash scripts/generate-fixtures.sh
```

Opening validates format/header and loads the explicitly selected index. A
known reference-count mismatch between index and header fails that open without
fallback. Regional reads detect decoding failures, unavailable mapped CIGAR,
invalid operations/lengths, sequence-consumption inconsistency, and reference
bounds violations. A detected defect fails the whole regional load; there is no
partial result or invented geometry. Valid missing sequence retains known
geometry and outlined tails. No timestamp heuristic, whole-file scan, full
sorting certification, or exhaustive stale-index guarantee is claimed. No
reference FASTA is required.

Regional session tests use real BAI/CSI files and controlled completions for
latest-request precedence, same-target submissions, successful/empty/wide
restoration, newer drafts/scrolling, populated replacement, and stale BAM
results. Native checks exercise the actual scroll view, spinner, attached
regional-error alert, and supersession of displayed/queued alerts. Renderer
captures complement independently calculated geometry assertions. Every query
finishes before its result becomes a successful view; this development slice
uses complete eligible candidates before whole-view group sampling. The fixed
2,000-group budget and its limits have [representative measurements](performance/sampling-2026-11-08.md).

Record identity is the BAM virtual offset after each record within one opened
file. It preserves distinct byte-identical records and deduplicates overlap
retrievals; it is not a sampling-group key. Fresh row packing sorts by full drawn
start and fills the first nonoverlapping row. Nearby navigation reserves retained
records' rows before placing newcomers, using full drawn bounds and gaps. Active
row extent does not shrink during continuity, even when the target becomes empty.
Existing drawing bounds, H/P information, and the reference span remain distinct
from viewport clipping.

For visible interval V, required search interval R pads each side by a fixed
250 bases and clamps to the reference. The 10,000-base display cutoff applies
to V, so an R wider than 10,000 bases still loads for an eligible visible width.
The indexed reader retains aligned-reference-span query semantics. The session
selects records whose aligned span overlaps R and whose full drawn extent
overlaps V, including tail-only, deletion-only, and reference-skip-only overlap.
Cached tails anchored beyond R remain ineligible; selected tails retain their
full scale and sequence/outline geometry. The finite margin does not guarantee
discovery of arbitrarily distant tails.

Completed query intervals and their complete unsampled records establish reuse
readiness. Coverage from several queries can satisfy R; only its uncovered
intervals are read. Keep these query records separate from visible candidates
and sampled survivors: an offscreen record may become visible in a later target
covered by the same query. Existing flag filters and V/R eligibility precede
whole-view sampling; offscreen groups and group members do not consume its
allowance. Cached geometry alone cannot prove complete R coverage. Each
completed fragment can update the provisional view; the target becomes the
successful recovery view only after all missing coverage completes. Failures
restore the saved presentation without a query, preserving its adequate data
for later reuse. Stale completions cannot publish an older target, status, or
error. Completed same-BAM required results may still enter the bounded cache;
replacement-session results cannot.

After an initial target, typed jump, or zoom becomes ready, optional prefetch
expands R by P = max(visible width, 250) on each side to form desired coverage C.
It queries only missing C coverage in chunks of at most 1,000 bases, visiting the
nearest uncovered side first. Both sides can become reusable by a nearby pan.
The target becomes ready when R completes; optional work never changes a
stationary candidate set, sample, layout, scroll position, spinner, warning,
or recovery snapshot. A drag can use completed buffered data on subsequent
pointer movement. Proactive pan/drag refill and completion-driven preview updates
remain the next increment.

A changed committed target cancels optional work before requesting missing R.
The same native reader owns the BAM handle, header, index, and iterator. Its
synchronous loop checks cancellation before opening and around every native
record read, and every 256 sequence/CIGAR decoding operations. It never suspends
with an iterator open; all exits close the iterator. Cancellation cannot interrupt
one blocking HTSlib call or its native allocation. Task priority alone is not
the scheduling guarantee. Successful BAM replacement retires work and clears
coverage; failed/canceled replacement preserves the existing session.

Only complete successful queries, including empty queries, establish coverage.
Optional malformed-data or budget failures leave the successful presentation
intact, establish no coverage, and suppress further speculative attempts for
that range. Other missing ranges can still load. A required request retries the
range normally and uses ordinary failure restoration if necessary. Failure
metadata is capped at 64 ranges; reaching that cap stops optional loading for
the open BAM. Each optional plan also has an 80-query work cap, including failed
attempts. At the selected 1,000-base chunk size, an unobstructed 10 kb viewport
needs at most 20 optional queries; reference clamping reduces that count.

The optional cache budget is 32 MiB. Coverage is partitioned into disjoint
completed fragments, split at current required and committed recovery bounds.
Those protected bounds retain complete unsampled data independently of the
optional budget. Distant optional fragments are evicted before nearer ones;
optional work stops when its new fragment cannot survive that budget. Every
optional query additionally has a 20,000-decoded-record and 8 MiB conservative
app-storage budget. Required queries have neither cap and are never silently
truncated. Optional queries that exceed a cap throw away the partial result.

Accounting includes twice the inline alignment/segment storage and string
payloads, 256 bytes per alignment, 32 bytes per segment, and query-entry/reference
metadata. Shared copy-on-write payloads are deliberately counted again for each
retaining fragment. A reader preflight also accounts for transient sequence and
CIGAR expansion before Swift materialization. These conservative app-storage
limits do not promise a hard bound on process RSS, HTSlib buffers, one pathological
native record, or mandatory dense-region data. The display-group count is not a
cache-byte limit. The [focused comparison](performance/adjacent-prefetch-2026-11-10.md)
records the chosen limits, real-reader interruption evidence, and remaining
qualification boundaries. Prefetch-disabled measurement/test configurations
retain the historical eight-inactive-snapshot baseline.

Enabled-prefetch session tests exercise complete/empty reuse, quiet failure and
required retry, incomplete R readiness, overlapping-cache pressure, replacement,
supersession, and drag/draft/recovery protection with real BAI/CSI records and
controlled events. Native checks preserve accessible warnings, hidden spinners,
rows, scrolling, and absence of speculative alerts. Earlier no-prefetch query
ordering/candidate comparisons explicitly disable optional loading; ordinary
opening/rendering checks retain the production default.

The `bounded-tails.sam` fixture independently specifies exact 250-base search
boundaries, longer excluded tails, both strands, D/N-only overlaps, missing
sequence, filtered records, identical-looking distinct records, and offscreen
sampling groups. BAI/CSI tests compare fresh, pan, broad-cache, mixed, and
evicted/reloaded candidate sets and samples. Required malformed records outside
V still fail their load and restore the committed view.

Navigation tests cover real BAI/CSI partial/complete/empty reuse, cache gaps and
eviction, identical-record identity, earlier soft-tail newcomers, partial-load
failure, stale results, and replacement ownership. The native continuity check
uses the actual scroll view and spinner to verify preserved positions/extent
during loading and empty reuse, then a top reset on a disjoint cached target.
The numerical row/marker/letter choices and measurement method are documented
with the visibility baseline.

Mouse tests send native pointer and wheel events to the actual alignment view,
with bitmap assertions that bodies and ruler ticks move during fractional-base
previews. Controlled completions cover changed/unchanged release, old successes
and failures during a drag, restoration, newer drafts/scrolling, reference
boundaries, clicked-base zoom, and wide-state hit testing. Preview remains
provisional even when cached data is adequate. An older completion is held until
release and applied only if its original target remains committed; it cannot
replace a preview or promote that preview to the recovery view. Valid explicit
navigation or successful BAM replacement retires a pending preview. There is no
custom Escape-to-cancel gesture.

The [navigation regression check](performance/navigation-2026-11-07.md) records
the retained-row implementation's fresh-load measurements and the correction of
an occupied-range scanning regression, using the same public data and harness.

The `Native macOS` CI job builds, runs the tests, and packages the application.
`Required checks` depends on both native and documentation jobs and accepts
only successful results. All three jobs must be required by branch protection
before this bootstrap can merge.

## Native demonstration

On 2026-11-07, the packaged release app was launched on Apple Silicon macOS
27.2, built with Xcode 27.2 / Swift 6.4.2. The native accessibility tree exposed
the Bamdalf window, its message, standard window controls, and Bamdalf/File/Window
menus. **Command-Q** terminated the app. Both automated session/window tests
passed locally, including workspace resizing. CI independently exercises Xcode
16.4 / Swift 6.1.2 on macOS 15.

![Native Bamdalf workspace with no BAM file open](images/native-workspace.png)

On 2026-11-07, manual use reached the native index chooser and exposed disabled
BAI/CSI choices. A native regression reproduced both disabled menu items and an
ineffective selection. The controller's menu validation had applied its
"window has a sheet" restriction to the popup choices as well as File → Open
BAM. Restricting that validation to the File command restored the native popup
actions. The regression verifies both candidate items remain enabled, no index
is preselected, an explicit CSI selection enables Open, and the File command
stays disabled while the chooser is attached. A separate native check verifies
the selected-index error alert and preservation of the previous workspace.

On 2026-11-07, native interval tests demonstrated valid, one-base, out-of-range,
malformed-comma, and unfinished-edit cases using real BAM header lengths.
They retain the target ruler across rejected/unfinished text, keep errors on
focus loss, and use the actual menu/field-editor actions for focus and Escape.
Native view captures were inspected for each case; the tests also verify
full-coordinate labels remain in bounds and reduce density on resize.

On 2026-11-07, the actual native renderer was inspected with both real HG002
regions and independently specified synthetic CIGAR/sequence fixtures. The
[measurement report](performance/visibility-2026-11-07.md) retains renderer-only
captures, raw timing/RSS data, reproducible acquisition, and explicit limits.
Full-window cache captures with omitted layers were excluded as complete-window
evidence. Separate native tests verified the real ruler/field, scrolling,
spinner, and error sheets.

## Sampling implementation

On 2026-11-08, issue #7 added whole-target selection with a fixed internal budget
of 2,000 groups, selected from [recorded native measurements](performance/sampling-2026-11-08.md).
The application offers no budget or resampling control. The session constructor
accepts controlled seeds, budgets, and priority functions for deterministic tests
and separate measurements at the approved application-facing seam.

Each successful BAM open draws a uniform UInt64 seed. Cancellation or failed
replacement preserves the prior seed. Priorities are the first eight digest
bytes of SHA-256, interpreted as an unsigned big-endian integer, over the
big-endian eight-byte seed followed by this identity encoding:

| Group | Encoded bytes |
| --- | --- |
| Unavailable QNAME (`*`) | `00`, then eight-byte big-endian BAM virtual offset after the record |
| Named, absent RG | `01`, QNAME byte length as eight-byte big-endian integer, UTF-8 QNAME |
| Named, present RG | `02`, RG byte length as eight-byte big-endian integer, UTF-8 RG, QNAME byte length in the same format, UTF-8 QNAME |

An empty RG is present and remains distinct from absent RG. Length prefixes
prevent pairs such as `(a, bc)` and `(ab, c)` from colliding. Reused exact
`(RG, QNAME)` pairs stay together regardless of position, mate/supplementary
flags, or sequence. Unnamed records use their own stable offsets. The seed and
identity determine the priority without requiring a history of earlier groups.
Groups sort by descending priority; equal priorities sort by ascending
lexicographic identity bytes, independent of query or cache order. Exactly
`min(2000, N)` groups survive, with all their eligible loaded records. There are
no bins, local quotas, outside-query mate fetches, or UMI-family aggregation.
SHA-256 priorities implement the pseudorandom equal-inclusion intent; a
particular sample does not preserve exact regional depth ratios.

The sampler reuses priorities only for the immediately preceding candidate
group set. It replaces that map on every sampled selection and clears it for
unsampled/empty selections and every session-seed assignment. This avoids an
inventory of all earlier groups. Internal set keys hash their complete encoded
byte buffer at once; SHA-256 still receives the same seed and identity bytes,
and equal priorities still use the same bytewise tie ordering.

Complete query results stay in the data cache and successful recovery snapshot.
Selection runs again on target-wide eligible candidates during reuse, new
loads, and drag previews. The previous successful candidate snapshot survives
partial-load failure independently of its displayed sample; narrowing after
restoration can therefore recover a previously omitted group. Selection happens
before packing; surviving displayed records retain their rows during nearby
navigation. Disjoint typed targets and returns from ruler-only targets retain
the established fresh-layout behavior. The fixed group budget bounds neither
query work nor retained records, rows, memory, or load latency.

The readable `sampling.sam` fixture includes cross-RG and absent/empty-RG names,
unnamed records, a reused name at a distant position, mates, supplementary pieces,
and filtered records. The `density.sam` fixture checks whole-view priorities
without local quotas; `sampling-unicode.sam` preserves byte-distinct RG values
that Unicode string comparison would consider equivalent. `malformed-rg.sam` checks that present non-Z RG tags fail
the regional load instead of becoming absent RG. Real BAI/CSI tests use independently specified tied-priority
outcomes, exact budget boundaries, stable reloads, complete-candidate reuse,
controlled completion/failure, and native status/renderer checks. Performance
measurements remain separate from timing-insensitive correctness assertions.
