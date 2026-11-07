# Bamdalf MVP design

Updated 2026-11-07. This is the authoritative record of the current design, consolidated from the design interview. It is input to `to-spec`, not an implementation-ready specification. No native viewer or performance benchmark has been completed.

Use US English in documentation and UI text. Terms are defined in [GLOSSARY.md](../GLOSSARY.md); deferred features are in [backlog.md](backlog.md). The [decision index](#decision-index) preserves the identifiers used in research notes without requiring the interview transcript.

## Scope and benchmark

The first milestone is a native macOS application for Apple Silicon that opens one local, coordinate-sorted, indexed BAM, navigates to an explicit genomic interval, and displays a ruler and correctly positioned alignments with pan and zoom controls. Target short-read DNA sequencing. Reference bases, mismatch highlighting, coverage, read inspection, and additional tracks are outside this milestone.

The representative benchmark is **100× WGS, paired-end reads around 150 bases per read (approximately 2 × 150 bp), aligned to hg38**. Include ordinary regions and locally much deeper pileups. These are benchmark characteristics, not input restrictions or a cap on local depth. The viewer does not require a reference FASTA or restrict accepted BAMs to hg38 or exact 150-base reads.

Actual datasets, reference bundles and contig sets, sequencing platform, test hardware, and measurable responsiveness/memory targets remain to be selected. Choose the internal sampling budget and alignment-visibility threshold using representative measurements. No numerical budget or visibility cutoff, or performance advantage over IGV, has been established.

## Window and native controls

- Give alignments the full available content width, with no permanent file sidebar.
- Open files through native **File → Open BAM…**, without a permanent Open BAM toolbar button.
- Provide an interval field, a ruler, four toolbar navigation buttons, and vertically scrollable alignment rows.
- Provide **Go → Go to Interval**, without an ellipsis, with **Command-L (⌘L)**. It focuses the existing field and selects its current text, including drafts or rejected entries. It does not submit, format, clear an error, navigate, or interrupt loading. Disable it when interval entry is unavailable or a native modal control blocks the window.
- Use native text-field and dialog behavior for text cursor placement, selection, keyboard traversal, and focus restoration. Do not add custom selection after Enter or Esc, first-click/Tab overrides, pre-alert focus capture/fallback, or cursor positioning after error restoration. Command-L is an explicit focus/select command; successful BAM opening also focuses the field as specified below.
- Background results must not deliberately refocus the editor or reselect its text. Native alerts retain their normal modal behavior.

The native-behavior policy supersedes Q82–Q86, Q88, Q91, and Q92 under the user-authorized simplification of 2026-11-07. Q93's proposed Esc-to-cancel-drag gesture was withdrawn. Neither the superseded details nor that gesture are deferred feature commitments. Routine interaction details need no further interview round; exact visual styling and mockup dimensions are not requirements.

## Opening files and indexes

Discover supported indexes beside the selected BAM. For `sample.bam`, recognize:

| Format | Candidate filenames |
| --- | --- |
| BAI | `sample.bam.bai`, `sample.bai` |
| CSI | `sample.bam.csi`, `sample.csi` |

With no candidate, show a clear missing-index error. With one, select it automatically. With multiple candidates, show them and require the user to choose; do not apply a format or filename priority. Multiple indexes may indicate an input problem, but do not prove any particular index is invalid.

If the chosen index cannot be read or loaded, stop the open attempt and show an error identifying it, with a specific cause when known. Do not fall back automatically to another index. Index creation and browsing to an arbitrary index path are outside the milestone.

A failed or canceled open, including cancellation of the index chooser, preserves the existing BAM, genomic interval, zoom, and vertical scroll position. A successful open replaces the previous view with **Enter a genomic interval**, focuses the interval field, and waits for a valid interval before requesting alignments. Opening a BAM/index is distinct from successfully loading a region.

Access permissions, validation depth, detection of stale/mismatched indexes, chooser presentation, and other file-opening error details remain open. Successful index loading is not proof that every index problem has been detected. See the [index research](research/bam-index-discovery-2026-11-01.md).

## Interval input and editing

### Coordinates and formatting

Use 1-based, inclusive endpoints in input and display: positions 100–200 cover 101 bases. Require the complete form `reference:start-end`; a single base uses identical endpoints, such as `chr1:100-100`. Match the BAM's `@SQ SN` reference names exactly and case-sensitively, without aliases (`1` and `chr1` are distinct).

Accept coordinate numbers with no commas or correctly grouped thousands commas. Trim whitespace surrounding the complete entry, but reject whitespace inside it. Accept only the regular hyphen (`-`, U+002D) between the numeric endpoints; do not convert other dash characters. Examples:

<!-- markdownlint-disable MD038 -- Spaces inside code spans in this table are inputs being tested. -->

| Entry | Result |
| --- | --- |
| `chr1:1000-2000` or `chr1:1,000-2,000` | Same interval, if valid for the BAM |
| `  chr1:1,000-2,000  ` | Accept surrounding whitespace |
| `chr1:10,00-20,000` | Reject malformed comma grouping |
| `chr1:1000 - 2000` | Reject internal whitespace |
| `chr1:1,000–2,000` | Reject the en dash |

<!-- markdownlint-enable MD038 -->

On Enter, require a known reference and `1 <= start <= end <= reference length`. Reject invalid input without silently correcting or clamping it. Immediately format a valid submission with thousands commas, a regular hyphen, and the exact reference name. Do not rewrite drafts or rejected input as a formatting side effect.

All app-generated full intervals use that same format. Ruler labels use full integer base coordinates with thousands commas at every zoom level, including wide views; use fewer labels to avoid crowding instead of kb/Mb abbreviations. Internal coordinate representation, conversion boundaries, rounding, and exact ruler spacing remain to be specified.

### Validation and draft preservation

- Retain rejected text for correction and show a short inline error directly below the field, such as **Start must be at or before end.** Preserve the current view and any valid load already running; an invalid submission does not supersede it.
- Clear the inline error when the text is actually edited, and validate again only on Enter. Merely moving focus or changing selection does not clear it. Editing does not navigate, establish validity, cancel loading, or dismiss a regional-load alert.
- Losing focus alone preserves the draft/rejected text and its inline error. Do not submit, validate, format, or discard on focus loss.
- A committed genomic pan/zoom to a changed interval replaces the preceding draft or rejected text with the target coordinates and clears its inline error, without submitting the discarded entry. During a drag preview retain the draft; replace it on release only if a changed interval is committed. Vertical row scrolling, unchanged navigation, and an uncommitted drag preserve it.
- **Esc in the active interval editor** discards the draft/rejected entry, restores the currently displayed target's formatted coordinates, and clears its inline error. If there is no target, clear the field. If the target is loading, use its coordinates, not the previous successful view. This action does not navigate, reload, repack, resample, reset scrolling, cancel loading, or alter request precedence. Do not override Esc in native dialogs or other controls.
- New edits made after navigation or an editor reset remain protected from delayed results. A field containing a deliberate draft need not match the displayed region; the ruler continues to identify the view. Error restoration follows the rules below.

## Navigation and alignment visibility

Mouse and trackpad gestures below apply in the alignment area.

| Control | Behavior |
| --- | --- |
| Left/right toolbar arrows | Pan by half the visible interval |
| Minus/plus toolbar buttons | Double/halve interval width around its center |
| Horizontal drag in alignment area | Pan along the current reference |
| Double-click | Halve interval width, centered on the clicked locus |
| Option + left-click | Double interval width, centered on the clicked locus; distinct from right-click |
| Mouse wheel / vertical trackpad scrolling | Scroll alignment rows vertically |

Keep navigation within the current reference. Clamp pans at its ends while preserving interval width. Shift zoom targets as needed at boundaries; cap zoom-out at the full reference length and zoom-in at one base. Navigation does not cross into another reference. Typed out-of-range intervals are rejected rather than clamped. Whole-base rounding and control feedback at limits remain open. Ruler-drag selection, pinch zoom, and modifier-plus-wheel zoom are not selected controls.

Above the alignment-visibility threshold, retain the ruler and location field and show **Zoom in to see alignments**. Do not query or draw alignments, including already-cached or sampled ones. This is distinct from a loaded empty region. The threshold is independent of the maximum navigable interval and takes precedence over downsampling; sampling does not make arbitrarily wide views readable. No numerical cutoff has been selected. See the [navigation research](research/navigation-and-visibility-2026-11-01.md).

Submitting the same parsed reference/start/end as the current ready view or active target within the same BAM does not reload, repack, reset scrolling, resample, or duplicate/restart a pending load. Apply normal valid-input formatting and let any existing load finish under the usual rules. This does not prevent retry after a failed request has restored a different view or the empty state.

## Alignment eligibility and rendering

### Fixed eligibility filters

Include mapped primary and supplementary alignments. Exclude any record flagged unmapped (`0x4`), secondary (`0x100`), QC-failed (`0x200`), or duplicate (`0x400`). A record flagged both secondary and supplementary is excluded. Use the supplied duplicate/QC flags; do not detect duplicates. Apply no MAPQ cutoff: 0 and 255 remain eligible if the record passes the flags. These filters are fixed, with no configuration UI in the MVP, and apply before downsampling.

### Geometry and sequence

Draw and pack each selected alignment independently; do not deliberately group mates into rows or connect them. Reserve each alignment's full drawn extent, including soft-clipped tails, so neighboring alignments do not overlap on the same row. Additional rows are available through vertical scrolling. Sampling groups do not determine row placement.

Support all nine standard CIGAR operations and their format-defined query/reference consumption. An uncommon standard operation is not an unsupported-record error merely because it is unusual.

| Operation | Display |
| --- | --- |
| `M`, `=`, `X` | Aligned blocks, without reference-base display or mismatch highlighting |
| `I` | Small purple I marker at the insertion boundary, without adding reference bases or widening the genomic axis |
| `D` | True-width gap with a thin solid foreground-color connector (black in a light theme) |
| `N` | True-width gap with a thin solid blue-gray connector, distinct from a deletion |
| `S` | Full-length soft-clipped tail at the same base scale as the alignment |
| `H` | No extension, label, tick, or other hard-clipping indicator; retain the operation's information |
| `P` | Padding, advancing neither query nor reference coordinates |

Preserve operation lengths and aligned-block positions. Omit numeric insertion/deletion length labels and inserted-sequence inspection. A valid `H` operation is not grounds to discard the remaining alignment or its soft-clipped sequence. Standard `N` support does not add an RNA workflow or assert that every skip represents an intron or deletion. The stored sequence symbol `=` is a separate unresolved case from the supported CIGAR `=` operation.

Show full soft-clipped sequence with **no vertical boundary ticks**. Tails extend the drawn extent, not the mapped reference span. Follow stored CIGAR order along increasing reference coordinates, including reverse-strand alignments. Use letters when readable and colored blocks otherwise, without a manual letters toggle:

| Stored base | Color |
| --- | --- |
| A | Green |
| C | Blue |
| G | Yellow |
| T | Red |
| Ambiguity codes, including N | Neutral gray; retain the actual symbol when letters are readable |

Color indicates nucleotide identity, not a claim that a clipped base maps or mismatches at its drawn position. Exact shades, text contrast, and the readability threshold remain open.

If an otherwise valid mapped record has no stored sequence, draw its mapped geometry normally. Show known soft-clip lengths from valid CIGAR as full-length empty outlined tails at normal row height and base scale. Do not invent bases, substitute N, fetch sequence from another record, reconstruct it from a reference, or turn `S` into `H`. Missing sequence alone is not an exclusion. Outlines distinguish unavailable sequence from filled gray ambiguity bases. Omit quality-based fading for alignments and bases, without inventing missing quality scores.

Indicate strand with a small pointed end inside the mapped body: right for forward, left for reverse. Clip drawings at viewport edges while preserving their full geometry and packing bounds. Add no continuation mark, moved strand point, or artificial closure of an outlined tail at the viewport edge. Marker dimensions, padding, crowding, and behavior for very narrow bodies remain open and must respect row continuity. Retrieval when only a soft-clipped tail or skipped reference interval overlaps the view is not settled by these drawing rules.

Format evidence is retained in the [CIGAR](research/cigar-errors-2026-11-02.md), [reference-skip](research/skipped-reference-2026-11-02.md), [missing-sequence](research/missing-sequence-2026-11-01.md), [hard-clipping](research/hard-clipping-2026-11-01.md), and [clipping/BWA](research/clipping-indicators-and-bwa-2026-11-01.md) research notes. The accepted future BWA preparation check concerns supplementary split-read alignments only and is recorded in the backlog; alignment execution is outside the viewer milestone.

## Loading and status

### Target presentation and request precedence

Keep navigation available during loading. A valid changed target supersedes the previous request; only the latest valid request may update the view, spinner, downsampling status, or error. Ignore stale completions and failures. A wide ruler-only target also supersedes earlier loading, although it needs no alignment query. Same-target Enter is the exception described above. This does not promise immediately cancellable I/O or add a manual cancellation control.

On valid typed navigation, toolbar navigation, or click-to-zoom, immediately show target coordinates and ruler. Reuse applicable loaded data, drawing alignments selected for the target at the correct positions and scale. Keep missing data blank; an entirely unloaded target is blank while loading. Do not blank useful available data solely because more data is needed. A changed sample may omit previously displayed groups even when they are cached.

During horizontal dragging, move the ruler and already-loaded alignments immediately with the pointer, preserving relative genomic positions. Load any missing data on release, subject to the visibility threshold. Older load completions must not replace an active drag preview.

A pending or drag-preview view is provisional. It becomes the last successful view only when the target is ready; retain the previous successful view for failure restoration. Determine readiness from completed query coverage and adequate candidate/sampling information, not from the presence or absence of drawn shapes. Loaded reads can extend into regions whose query is incomplete. An already-complete target needs no alignment-loading spinner. Successful empty queries and completed samples are valid results.

### One status spot beside the interval field

| State | Visible indicator |
| --- | --- |
| Loading missing alignment data | Spinner |
| Ready and downsampled | Small amber warning triangle |
| Ready without downsampling | Empty |

The spinner is the sole visible loading indicator: no Loading text or stripes, dots, tinted regions, outlines, or labels over unloaded areas. It takes precedence while loading, including when reusing sampled data. For a ready sampled view, keep the warning visible while eligible alignments are omitted. On hover or keyboard focus, show **Downsampled: some alignments are not shown.** Provide an equivalent accessible description. An already-ready sampled target shows the warning immediately.

Keep the sampling status with reused or restored views. Loading, intentional sampling omissions, the wide-view message, validation errors, and actual load failures are distinct states; the status spot remains dedicated to loading/sampling.

## Downsampling

A **sampling group** contains eligible, loaded records from one query template, including mates and supplementary pieces. It is distinct from SAM/BAM `@RG` metadata and does not combine duplicate molecules or UMI families. For example, eligible loaded R1 primary, R1 supplementary, and R2 primary records can form one group of three records.

Keep or omit all eligible loaded members of a group together, including members in different parts of the interval; when a group leaves the sample, remove its retained members together. Filters apply first. Do not fetch records outside the regional query just to complete groups, and continue to draw their members independently. Exact group identity and coordination across separately loaded/cached data remain open.

Use one uniform whole-view sample, with **no bins or local quotas**. Let `N` be the number of eligible groups for the target and `B` the fixed internal group budget. Retain `min(B, N)` groups. Show all when `N <= B`; otherwise each group has inclusion probability `B/N`, uniformly without replacement. An empty candidate set is a successful empty view. The same rule covers cached data; the candidate set must represent the target, not merely an already-sampled cached subset.

Equal inclusion probability preserves relative density in expectation, including differences across duplications/deletions. It does not guarantee exact local fractions, unchanged depth ratios, independent selections, or retention of uncommon supporting alignments. This is display sampling, not coverage or copy-number analysis.

Give each group a stable pseudorandom priority derived reproducibly from one random seed for the current open-BAM session and a stable group identifier. Recompute priorities when needed; no inventory of every previously encountered group is required. Retain the groups with the **highest** priorities. Overlapping views intentionally share priorities, making nearby selections correlated. Returning to the same eligible candidates/settings reproduces the sample even after eviction and reload. A changed candidate set can change membership; reopening the BAM may choose a new seed. There is no manual Redo downsampling action in the MVP.

Choose one numerical `B` through representative testing and keep it fixed across views, without a user-facing setting. The retained fraction varies with `N`. Each group counts once, so `B` is not a cap on alignment records, rows, local depth, total memory, or query time, and downsampling does not guarantee faster BAM scanning. Priority function, encoding, collision/tie handling, exact candidates, selection algorithm, cache reconciliation, and separate resource limits remain unresolved. Stable priorities alone do not guarantee stable row placement.

See the [downsampling evidence](research/downsampling-2026-11-01.md), [navigation-stability research](research/navigation-stability-2026-11-05.md), and [priority/memory research](research/sampling-priorities-memory-2026-11-06.md) for source findings and illustrative mechanisms, rather than additional implementation requirements.

## Row and scroll continuity

| Navigation | Layout and vertical position |
| --- | --- |
| Horizontal pan at unchanged zoom | Keep rows of alignments still visible and selected; preserve scrolling |
| Zoom in or out, with alignments displayed before and after | Keep retained visible/selected rows; preserve scrolling |
| Changed typed interval overlapping the current interval on the same reference, with alignments displayed before and after | Same continuity, regardless of width change |
| Typed interval on another reference or with no genomic overlap | Fresh rows, start at top when entering alignment display |
| Return from a wide ruler-only view through zoom or typed coordinates | Fresh rows, start at top, including overlapping typed targets |
| Same parsed interval submitted again | Keep view and pending load unchanged |
| Failed regional load restores a previous view | Start at top of the restored alignment stack |

For continuity cases, place newcomers in non-overlapping spaces or new rows, reserve full drawn extents, and allow gaps. Do not compact or renumber retained rows because of navigation, additional loading, cache boundaries, newcomers, or hypothetical insertion-marker overlap. Q74 explicitly has no marker-overlap exception. Keep sufficient active row extent so trimming vacancies does not reset, recenter, or clamp the scrollbar. Honor newer manual scrolling through successful load completion.

For fresh-layout cases, initialize rows/scrolling once for the target, then honor newer scrolling rather than resetting again on completion. Reuse adequate loaded data and session priorities; a new layout does not require a new seed, cache eviction, or an unnecessary query. A disjoint typed target starts fresh even if a long alignment or soft-clipped tail spans both intervals.

Continuity protects records that remain visible and selected; sampling may still remove groups. It does not require a permanent inventory of historical row assignments or promise identical layout after revisiting evicted regions. Other large jumps, resizing constraints, historical recovery, and the row/cache mechanisms remain open.

## Regional loading failures

When the latest valid regional request fails:

1. Stop its spinner and restore the current BAM's last successful view, with that view's coordinates and sampling status. This can be an alignment view, a successful empty/sampled result, or a wide ruler-only view. If none exists, restore the empty interval-entry state.
2. Start a restored alignment stack at the top; do not restore the prior vertical scroll offset. This does not require a new sample.
3. Restore the interval field to that view's coordinates, or clear it if there is no prior successful view, **unless the user has edited a new draft since the failed request began**. Preserve that newer draft. The ruler identifies the restored region even when the draft differs.
4. After restoration, present a native window-attached alert with one **OK** button, the failed interval, and a concise cause when known. For example: **Could not load chr1:2,001-2,600**. Omit narration about restoring the previous region, invented causes, and raw stack traces as the main message. The alert blocks that window until acknowledged; focus/selection use native behavior.

Recheck request identity before restoring or presenting a queued alert. Stale failures must not restore a view, change the field, or show an alert. If application state changes while an alert is open, an obsolete alert must not remain presented as current. New valid requests supersede old ones; editing alone and invalid submissions do not.

This regional-load policy is separate from inline validation and file-opening errors. Standard CIGAR support does not select exhaustive validation, a blanket failure policy for every unusual record, IGV-style partial results, or recovery behavior. Which defects fail a load and how missing/malformed CIGAR is handled remain unresolved.

## Remaining specification work

The following are open choices, not accepted implementation requirements. Resolve material correctness gaps before treating a specification as implementation-ready; routine native interaction details need no separate interview.

| Area | Work remaining |
| --- | --- |
| Input and rendering correctness | Stored sequence `=`; unavailable/malformed CIGAR; validation depth and recovery; viewport eligibility/retrieval for soft-tail-only or reference-skip-only overlap |
| Coordinates and layout | Internal representation/conversion boundaries; integer rounding; ruler spacing; marker bounds/crowding; row packing consistent with continuity; narrow-body drawing |
| Sampling and resources | Stable group identity; priority function/encoding/ties; adequate candidates across loads; selection algorithm; bounded cache and active row state; cancellation/scheduling and independent resource limits |
| File handling | Permissions; index chooser; stale/mismatched-index detection; file-opening error presentation |
| Benchmark and validation | Actual data/reference bundle/regions/hardware; measurable latency and memory goals; numerical group budget/visibility cutoff; agreed public test boundaries |
| Native application and delivery | Toolchain and dependency choices; build/CI setup; effective repository protection and checks; ticket/tracker configuration |

Swift, SwiftUI/AppKit, a narrow HTSlib adapter, and native drawing are candidate architecture choices. No specific adapter, hash, streaming algorithm, cache design, or renderer is selected by this record. Introduce Metal or other specialized optimization only when measurements justify it. The installed tools and repository settings must be verified during setup; historical local tool observations are not a portable build guarantee.

## Delivery and validation workflow

Follow `grill-with-docs` → `to-spec` → `to-tickets` → `implement`, reading the installed skills when entering each phase. The design interview uses one focused question at a time and continues after an answer unless redirected. The benchmark profile and routine UI discussion are complete; specification work should synthesize the accepted behavior and surface any remaining material product choices.

Agree and record the public boundaries where tests exercise observable behavior, including what they cover and miss. Use TDD during implementation, small reproducible synthetic BAM fixtures, independently derived expected results, and integration tests that exercise real file reading/indexing. Add coordinate, CIGAR, filtering, and error cases as features are introduced. Validate asynchronous behavior deterministically; measure performance separately from correctness tests. Use focused UI/visual checks where useful and explain justified test-first exceptions.

Agree the ticket breakdown and tracker configuration before publishing tickets. Each ticket must deliver a complete, demonstrable or independently verifiable result without a later ticket finishing its integration. Implementation starts when the user requests an agreed ticket; this authorizes its branch, changes, tests, required review, and PR. Merging remains separately authorized. Report each ticket's result and CI before starting another unless a batch is authorized.

All contributions, including documentation and CI, use dedicated branches and PRs into protected `master`. Require all configured checks/tests to pass on the current revision before merge; skipped or unexecuted checks do not count and local checks do not replace CI. Enforce required checks, squash-only merging, linear history, and automatic deletion of merged branches. Configure and verify these settings, a macOS build, and relevant tests when repository setup is authorized; documenting the desired settings does not establish that they are enforced.

## Sources and retained evidence

The design originated in the project's November 2026 development start prompt (`CODEX-START-PROMPT.md`), October feasibility study (`FEASIBILITY-2026-10-30.md`), layout notes (`LAYOUT-NOTES.md`), and subsequent user decisions through Q96. This document incorporates the agreed scope and workflow; those source documents are not required to interpret it. Feasibility architecture proposals and simulated mockups were not implementation evidence.

Dated research notes retain primary-source links, inspection revisions, calculations, and verification limits. Their historical proposals do not override this current design. The full pre-consolidation notes, source context, and exploratory mockups are preserved locally and excluded from Git. No committed document depends on those local files or the generated preview wrappers.

## Decision index

These identifiers preserve traceability for research references. The topical sections above define current behavior; superseded requirements are not carried forward or automatically put in the backlog.

| Decisions | Current location or disposition |
| --- | --- |
| Q1–Q2 | Scope and benchmark |
| Q3 | Independent alignment display and row packing |
| Q4–Q6, Q5b | Alignment geometry, soft clips without ticks, and no hard-clipping indicator |
| Q7–Q11 | Fixed eligibility filters |
| Q12–Q15 | Coordinate convention, full interval syntax, exact reference names, validation |
| Q16–Q20 | Wide-view cutoff and toolbar/mouse navigation |
| Q21–Q26 | BAM/index discovery, selection, opening failures, initial empty view |
| Q27 | Restore the last successful view on regional failure |
| Q28–Q35 | Loading/reuse/request precedence and shared status spot |
| Q36 | Random selection, refined by Q70 to remain stable within a session |
| Q37 | Superseded by Q43/Q44; no per-bin sampling allowances |
| Q38–Q39 | Coordinated sampling groups and group counting |
| Q40 | Superseded by Q44; no group-to-bin assignment |
| Q41 | Total view group budget retained; bin allocation superseded |
| Q42 | Superseded by Q44; no bin boundaries |
| Q43–Q45 | Uniform whole-view sampling without bins, fixed internal budget |
| Q46–Q56 | Soft-clip letters/palette/missing sequence, strand, packing, clipping, indels, standard CIGAR |
| Q57–Q59 | Native regional-error alert, draft-safe field restoration, scroll reset on failure |
| Q60–Q62 | Retained rejected input and inline validation |
| Q63–Q69 | Commas, whitespace, regular hyphens, submission formatting, full ruler coordinates |
| Q70 | Recomputable session priorities; select highest priorities |
| Q71–Q74 | Retained rows and scrolling through pan/zoom; no overlap exception |
| Q75–Q79 | Fresh versus retained layout for ruler-only returns and typed navigation |
| Q80–Q81 | Pan/zoom draft replacement and editor Esc reset |
| Q82–Q86 | Superseded by native editing/focus behavior on 2026-11-07 |
| Q87 | Preserve draft and error on focus loss alone |
| Q88 | Superseded by native keyboard traversal on 2026-11-07 |
| Q89–Q90 | Command-L and native Go to Interval menu command |
| Q91–Q92 | Superseded by native alert/focus/selection behavior on 2026-11-07 |
| Q93 | Withdrawn; no custom Esc-to-cancel-drag requirement |
| Q94–Q96 | 100× WGS, approximately 2 × 150 bp, hg38 benchmark |
