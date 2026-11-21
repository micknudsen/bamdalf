# Reference milestone design

Updated 2026-11-18. This document records the reference design interview. Only
decisions explicitly accepted below are settled; remaining details are open.
The existing viewer behavior is described in [design.md](design.md).

Product design confirmed by the user on 2026-11-18 (Q41). The
[engineering specification](reference-spec.md) synthesizes the accepted
decisions. Product agreement does not select a storage engine or authorize
feature implementation, issue publication, or merging.

On 2026-11-21, the accepted creation decisions in
[issue #70](https://github.com/micknudsen/bamdalf/issues/70) superseded R30
(filename-derived names) and R32 (modal generation and paused browsing).
The [creation acceptance record](reference-creation-acceptance.md) maps C1–C13
to the delivered named, nonmodal workflow and evidence. The original dated
decisions below remain historical records.

## Accepted decisions

### R1: Milestone scope

Accepted 2026-11-14.

The milestone includes reference-base display and mismatch highlighting:

1. Load a local reference FASTA and display its bases in a fixed row below the
   ruler.
2. Compare aligned bases with the reference and highlight differences.

Deliver reference loading/display first, followed by mismatch highlighting.
Coverage, alignment inspection, and additional BAM tracks remain separate
milestones.

### R2: Reference input formats

Accepted 2026-11-14.

Initially support local, uncompressed FASTA files with an existing sibling
`.fai` index (the FASTA filename with `.fai` appended). Users prepare the index
outside bamdalf. Compressed references, automatic index creation, and reference
downloads are deferred.

### R3: Optional reference attachment

Accepted 2026-11-14.

A reference is optional. Opening and navigating a BAM without a reference
retains the current alignment display. **File → Open Reference…** attaches a
reference to the current BAM and enables the reference row and mismatch
highlighting. R6 revises reference selection to opening a bundle, and R9
supersedes the original BAM-first selection restriction.

### R4: Retain the reference across BAM changes

Accepted 2026-11-14, following the user's correction of the proposed lifecycle.

Keep the selected reference when another BAM is opened. Reject an incompatible
BAM with an error instead of detaching the reference. A rejected open preserves
the current BAM, reference, and view. The proposed automatic detachment on a
successful BAM open was not accepted.

R9 permits reference-first loading, and R10 defines compatibility behavior for
reference replacement. R26 excludes automatic reference reopening across
application restarts.
R5 defines basic compatibility, and R17 defines available sequence-checksum
comparison.

### R5: Basic BAM/reference compatibility

Accepted 2026-11-14.

Every contig declared in the BAM header must exist in the selected reference
under the exact same case-sensitive name and with the same length. Extra FASTA
contigs are allowed, and contig ordering does not matter. Do not apply contig
aliases. Check the complete BAM header dictionary when opening a BAM against
the selected reference, including contigs outside the viewed interval.

Reject the BAM if any declared contig is absent or has a different length,
preserving the current BAM, reference, and view. Matching names and lengths
establish dictionary compatibility, not proof of identical reference bases.

### R6: Create and open self-contained reference bundles

Accepted 2026-11-14.

**Create Reference…** imports a FASTA into a self-contained reference bundle.
**Open Reference…** opens an existing bundle. Creation parses and validates the
sequence, calculates per-contig checksums, and stores the data required for
regional access. The original source files are no longer required after
successful creation; modifying, moving, or deleting them does not affect the
bundle. Bundles are read-only during viewing.

This revises R2's direct-FASTA opening model: FASTA is an input to creation;
opening a reference uses a bundle. R8 removes the source `.fai` requirement.
R3's optional-reference behavior and R4's
retention across BAM changes continue to apply.

Annotation import is a future extension, not part of this milestone. R7 settles
the single-file storage boundary. R11/R32/R35 define creation behavior, and
R18 defines the integrity-validation boundary. The internal representation
remains an engineering investigation.

### R7: Single-file reference bundle

Accepted 2026-11-14.

Store each reference bundle as one self-contained binary file containing
sequence data, lookup indexes, per-contig checksums, and provenance, with an
extensible format for future annotations. Support regional access without
loading the entire reference into memory or unpacking it into external files.
Use a true single file rather than a macOS directory package.

Complete creation before making a bundle available to open. Viewing is
read-only. The exact internal format remains an engineering investigation;
this decision does not select a particular database or encoding.

### R8: Create indexes from the source FASTA

Accepted 2026-11-14.

**Create Reference…** accepts a local, uncompressed FASTA without an external
`.fai`. Parse and validate the FASTA, compute per-contig checksums, and build
the bundle's internal lookup indexes during creation. Do not require or use
an external `.fai`, even if one exists. This supersedes R2's source-index
requirement; compressed FASTA input remains deferred.

### R9: Either reference/BAM loading order

Accepted 2026-11-14.

**Create Reference…** and **Open Reference…** are available without an open
BAM. Users may prepare or select a reference first, then open compatible BAMs,
or open a BAM first and subsequently select a reference. References remain
optional. R13 enables reference-only navigation. R11 separates creation from
opening.

### R10: Compatibility when opening or replacing a reference

Accepted 2026-11-14.

When a BAM is already open, apply R5's compatibility rule before attaching a
selected reference bundle. Reject an incompatible reference with an error,
preserving the current BAM, reference (if any), genomic interval, and view.
Opening a compatible reference attaches or replaces it without changing the
interval. Reference-opening compatibility checks apply in addition to those
performed when opening a BAM against an existing reference.

### R11: Creation does not change the viewer

Accepted 2026-11-14.

**Create Reference…** saves a completed bundle without opening or selecting it.
Leave the current BAM, reference, interval, and view unchanged. Users select a
created bundle separately through **Open Reference…**. Creating a bundle for
a different reference does not invoke compatibility checks against the
currently open BAM; compatibility is checked when the bundle is opened.

Reaffirmed 2026-11-17 after considering automatic opening with modal creation.
Successful creation still saves without selecting or opening the bundle. The
automatic-opening proposal in Q33 was not accepted.

### R12: Close a reference without closing the BAM

Accepted 2026-11-15.

**File → Close Reference** removes the selected reference from the viewer,
including its reference row and mismatch highlighting. Preserve the current
BAM, genomic interval, alignment rows, and vertical scroll position. Leave the
bundle file untouched. Closing the reference permits subsequently opening a
BAM that would be incompatible with that reference.

If no BAM is open, closing the reference leaves no source for navigation;
return to the empty viewer state.

### R13: Reference-only navigation

Accepted 2026-11-15.

With a reference open and no BAM, accept genomic intervals and support the
existing pan/zoom controls to explore the ruler and reference sequence without
alignment rows. Use the reference's contig names and lengths for navigation
and interval validation. Preserve the existing full interval syntax and
coordinate conventions. This provides a foundation for future annotation
browsing without adding annotations to this milestone.

R14 defines navigation when both a reference and BAM are open.

### R14: The selected reference defines navigation

Accepted 2026-11-15.

When both a reference and BAM are open, use the reference's contig names and
lengths for navigation and interval validation. Permit navigation to reference
contigs absent from the BAM header; display the reference without alignments
there and do not report a BAM loading error for their absence. This describes
the loaded BAM's dictionary coverage, not a biological claim of zero depth.

Without a selected reference, use the BAM's contig dictionary as before.
R15 qualifies R12's interval-preservation rule when closing the reference.

### R15: Close Reference on a contig absent from the BAM

Accepted 2026-11-15.

If the current contig is absent from the open BAM, **Close Reference** keeps
the BAM open but clears the interval and returns to **Enter a genomic
interval**. This is an exception to R12's view-preservation rule. If the
current contig exists in the BAM, preserve the interval and view as specified
in R12. If no BAM is open, return to the empty viewer state.

### R16: Preserve the interval when opening a BAM with a reference selected

Accepted 2026-11-15.

With a reference selected, successfully opening a compatible BAM preserves
the reference and current interval, whether opening the first BAM or replacing
one. Load the new BAM's alignments with fresh rows starting at the top. If the
current contig is absent from the new BAM, continue displaying the reference
without alignments as specified in R14. With no current interval, wait for
interval entry.

Without a selected reference, retain the existing behavior: a successful BAM
open waits for interval entry. Failed or canceled opens continue to preserve
the preceding state. R39 defines first-region load failure after a successful
BAM open.

### R17: Compare available BAM sequence checksums

Accepted 2026-11-15.

In addition to R5's name/length checks, compare every available BAM-header
`@SQ M5` checksum with the corresponding per-contig sequence MD5 calculated
during bundle creation. A mismatching checksum rejects the attempted BAM or
reference open, preserving the current viewer. Apply this rule in both loading
orders.

Accept BAM contigs without `M5` using name/length checks for those contigs;
their sequence identity remains unverified. Missing checksums are not evidence
of incompatibility. A partly populated `M5` dictionary must not be described
as verifying the identity of all BAM reference sequences. R18 defines bundle
validation. Handling malformed checksum fields is part of header-validation
engineering and must not bypass the accepted compatibility checks.

### R18: MVP bundle validation boundary

Accepted 2026-11-16.

Validate source FASTA during creation. On opening a bundle, validate its format,
metadata, and index bounds. Report detected read/decode errors. Retain R17's
per-contig sequence MD5 comparisons with available BAM `M5` values.

Do not add custom sequence-block integrity checksums or whole-bundle scans in
this milestone. The bundle prevents dependency on changes to original source
files; it does not promise detection of every possible corruption of its own
stored data. Integrity checks inherent in a selected storage library or format
do not require a separate custom verification subsystem.

### R19: Reference-row zoom behavior

Accepted 2026-11-16.

Keep the reference row fixed below the ruler and aligned with genomic
coordinates. When letters fit, display colored base cells with letters using
the existing soft-clip palette and letter threshold. When individual bases
remain distinguishable but letters do not fit, display colored cells without
letters. When bases are narrower than one screen point, leave the row blank
and do not fetch sequence solely to draw it.

The current soft-clip letter threshold is eight screen points per base;
reference rendering uses that same threshold. This rendering rule does not
remove sequence retrieval needed for mismatch comparison or other accepted
behavior.

### R20: Aligned match and mismatch appearance

Accepted 2026-11-16.

With a selected reference, keep matching aligned bases in the existing
alignment-body appearance. Color mismatching aligned bases using the nucleotide
palette, displaying mismatch letters at the same zoom threshold as reference
letters. Preserve the existing soft-clip appearance.

R21/R22 define ambiguous and unavailable bases, R23 defines wider-zoom
behavior, and R37 defines stored sequence `=`.

### R21: Ambiguous bases are indeterminate

Accepted 2026-11-16.

Compare A/C/G/T case-insensitively. Highlight a mismatch only when both the
aligned base and reference base are unambiguous and different. If either base
is `N` or another ambiguity code, treat the comparison as indeterminate and
display the aligned base in neutral gray, with its letter when readable. Do
not present an indeterminate comparison as a confirmed match or mismatch.

R22 defines missing sequence, and R37 defines stored SAM sequence `=`.

### R22: Missing alignment sequence

Accepted 2026-11-16.

When a reference is selected, display aligned portions of records with missing
sequence as outlined bodies without base letters. Preserve their positions,
strand indications, and CIGAR geometry. Skip base comparison; do not infer
missing alignment bases from the reference. Preserve existing insertion,
deletion, skip, and soft-clip behavior. Without a reference, retain the existing
appearance.

Include this distinction now so it also applies if a future filtering option
allows secondary alignments. Secondary alignments remain excluded in this
milestone. This accepts the outline proposal in preference to the subsequent
suggestion to defer it. R37 defines stored SAM sequence `=`. Outline rendering
at narrow widths is an engineering detail within the existing CIGAR geometry
and zoom limits, to be checked visually.

### R23: Mismatch-detail zoom limits

Accepted 2026-11-16.

Use the reference row's zoom limits for mismatch highlighting. Display colored
mismatch cells when each base occupies at least one screen point, adding
letters at the shared readable-letter threshold. Below one screen point per
base, use the ordinary alignment overview without widening mismatches into
larger markers. Do not fetch reference sequence solely for comparisons whose
results would be invisible at that scale.

### R24: Interval handling when replacing the reference

Accepted 2026-11-16.

When successfully replacing a reference, preserve the current interval if it
is valid in the replacement reference. Otherwise clear the interval and wait
for a new interval. Do not apply contig aliases, clamp coordinates, or select
another location automatically. This qualifies R10's interval-preservation
rule for reference-only browsing and extra reference contigs absent from the
BAM. Any open BAM must still pass compatibility checks against the replacement
reference before the replacement succeeds.

### R25: Remember the selected reference across launches

Accepted then superseded by R26 on 2026-11-16.

Remember the selected reference and reopen it when bamdalf launches.
**Close Reference** clears the remembered selection so the next launch starts
without a reference. This persistence covers the reference only; restoring
BAMs or browsing sessions is separate work. Startup behavior when the remembered
bundle is missing, unreadable, or invalid was not settled and is no longer
needed for automatic startup reopening.

### R26: Start without a reference

Accepted 2026-11-16, superseding R25.

Every application launch starts without a selected reference. Do not
automatically reopen a previously selected reference. Users explicitly select
a bundle through **Open Reference…**. A selected reference continues to remain
selected across BAM changes within the current session as specified in R4.
The proposed startup recovery policy for remembered bundles was not accepted
and is no longer applicable. A recent-reference menu, if any, is not settled
by this decision.

### R27: Preserve source base case

Accepted 2026-11-16.

Preserve lowercase bases from the source FASTA in the bundle and their
lowercase appearance in the reference row, retaining potential soft-masking
information. Nucleotide colors and mismatch comparison remain case-insensitive:
`a` and `A` match. Per-contig sequence MD5 calculation must follow SAM `M5`
normalization rather than hashing the case-preserving stored representation.

### R28: Reference label beside the interval input

Accepted 2026-11-16, following the user's placement preference after reviewing
the title/ruler mockups.

Place the selected reference label next to the interval input box. Do not put
it in the window title or beside the ruler's interval label. R29 settles
styling, R30 defines the displayed name, and R31 defines the empty state.
Truncation, tooltip, and minimum-width sizing are native-layout engineering
details to validate against the reviewed mockup; the mockup does not establish
native AppKit behavior.

### R29: Rounded reference field

Accepted 2026-11-16.

Use a rounded, read-only reference field with a file icon beside the interval
input. Match the neighboring navigation controls' height and border treatment.
This does not introduce a reference-selection button or menu.

R30 defines the enforced file suffix and the stored display name.

### R30: Reference-file suffix and display name

Accepted 2026-11-16.

Use `.bref` as the enforced reference-bundle suffix. Omit the terminal suffix
from the reference field's displayed name: `GRCh38.bref` displays as `GRCh38`.
Earlier `.reference` and `.bamdalfref` examples were proposals, not accepted
formats. The mockup retains the complete filename in its tooltip. A recognized
suffix alone does not establish that a file contains a valid reference bundle;
R18's format validation still applies.

Superseded 2026-11-21 by [persistent bundle naming #71](https://github.com/micknudsen/bamdalf/issues/71):
the reference field displays the required stored name independently of the file
name, retaining all name characters. The current creation flow stores the FASTA
basename without its final extension. The filename remains in the tooltip;
`.bref` remains the enforced file suffix. Old unnamed bundles require regeneration.

### R31: Reference field without a selected reference

Accepted 2026-11-16.

Keep the reference field visible when no reference is selected, displaying
**No reference**. Use the same field placement and styling to keep the layout
stable and make the optional-reference state explicit. This read-only field
does not select a reference; use **Open Reference…**.

### R32: Modal reference creation

Accepted 2026-11-17. Superseded on 2026-11-21 by
[safe concurrent creation](https://github.com/micknudsen/bamdalf/issues/73):
the independent creation window permits browsing and source changes while
protecting publication, cancellation, and close/quit cleanup. See the
[delivered workflow](development.md).

The earlier decision is retained below as history.

Use a modal progress dialog with **Cancel** during reference creation. Keep
the application responsive by performing creation work off the UI thread,
but pause browsing while creation runs. Do not implement continued browsing
and a separate background-completion workflow in this milestone.

Measure creation time with a representative human FASTA during engineering
investigation. Revisit continued browsing if measurements justify it. This
decision does not revise R11's save-without-opening policy, which was
subsequently reaffirmed. R34/R35 define destination protection, replacement,
and cancellation cleanup.

### R33: Required reference-read failures

Accepted 2026-11-17.

If reference data required for a regional load cannot be read, fail that
regional load. Restore the last successful view and show an error following
the existing regional-load policy, including stale-request protection and
preservation of newer interval drafts. If no successful view exists, return
to interval entry. Keep the reference selected so the user can retry or close
it explicitly. Do not silently display unverified matches or detach the
reference as recovery.

The existing distinction between required loads and speculative prefetch
failures still applies. This policy does not require sequence retrieval solely
for invisible detail at wide zoom (R19/R23).

### R34: Protect the open reference from replacement

Accepted 2026-11-17.

**Create Reference…** must refuse to overwrite the currently open reference
bundle. Require a different destination or closing that reference before
creating a replacement. Preserve the selected reference and current viewer
when the destination is rejected. Detect the actual open file rather than
relying solely on the spelling of its path.

R35 defines replacement of an existing bundle that is not open.

### R35: Safe destination replacement and cancellation

Accepted 2026-11-17.

Allow replacing an existing bundle that is not open after the standard Save
dialog replacement confirmation. Keep the existing destination intact until
creation succeeds. Cancellation or failure preserves that existing file.
For a new destination, cancellation or failure must not leave an incomplete
`.bref`. Complete and validate the new bundle before publishing it at the
chosen destination. R34's prohibition on replacing the open reference still
applies.

### R36: Fail creation on invalid FASTA input

Accepted 2026-11-17.

Invalid source FASTA fails the entire creation operation with a specific
error. Examples include duplicate contig names, missing sequence names, and
unsupported sequence characters. Preserve any existing destination as
specified in R35. Accept valid ambiguity codes and lowercase bases; do not
silently skip invalid records or replace invalid bases with `N`.

### R37: Stored sequence `=`

Accepted 2026-11-18.

Treat `=` in aligned stored sequence as a declared match to the reference,
distinct from the CIGAR `=` operation. With an unambiguous reference base, use
the ordinary matching-body appearance. With an ambiguous reference base, use
the indeterminate appearance from R21. An `=` in a soft clip has no aligned
reference position; preserve its existing neutral-gray, literal `=` display.
Without a reference, preserve the existing appearance.

### R38: Performance validation

Accepted 2026-11-18.

Reference-enabled browsing must meet the existing navigation, dragging,
scrolling, and memory targets on the representative WGS workloads. Qualify
with reference display and mismatch highlighting enabled, and check both
reference-only browsing and BAM browsing without a reference.

Measure creation and opening with a representative human reference before
setting justified limits. Record creation time, peak memory, bundle size, and
opening latency. Do not invent unmeasured creation/opening limits. Freeze the
measurement protocol before qualification; historic performance results do
not establish qualification of this milestone.

### R39: Failure of the first region after a successful BAM open

Accepted 2026-11-18.

If a new BAM opens successfully but loading the preserved interval fails,
keep the newly opened BAM and reference selected, clear the failed view, and
return to interval entry with the regional-load error. The user may retry or
enter another region. Do not restore the preceding BAM or show its alignments
as data from the new BAM. Opening a file and reading a region are separate
success boundaries.

## Reference bundle discussion

Raised by the user on 2026-11-14; R6 settles the self-contained ownership model.
The following preserves the motivation and unresolved verification details.

Consider a reference bundle associating the FASTA and index with reference
identity metadata and, in a later milestone, annotation files such as GTF.
The user clarified that the intended bundle is self-contained: source files
are imported into the bundle, not referenced by external paths. Original
FASTA and annotation files should no longer be required after import, and
changes to those originals must not affect the bundle. R6–R8, R11, R32, and
R34–R36 settle the creation workflow. The internal storage representation
remains an engineering investigation. R17 defines per-contig sequence MD5
comparison, and R18 limits bundle integrity validation for this milestone.
BAMs without `M5` values cannot provide sequence-identity verification through
that field. Annotation provenance and compatibility belong to a future
annotation milestone.

The earlier proposal to defer checksum verification was not accepted; R17 now
defines comparison of available BAM checksums. Annotation rendering remains
outside the accepted milestone scope.

## Design history and supporting evidence

On 2026-11-17, the user requested arguments for and against creation in the
background; R32 accepts modal progress with cancellation instead. The user
also reopened R11's save-without-opening decision by suggesting automatic
opening after successful creation, then explicitly chose to retain R11.
The automatic-opening proposal was not accepted.

The initial Q29 title/ruler placement proposals were superseded by R28's
placement beside the interval input. Revised local exploratory previews show
that placement with short/long filenames and the 640-point minimum window
width. Sizing details are layout proposals, not native AppKit verification or
agreed file-extension choices.

On 2026-11-16, the user questioned custom incremental integrity checks as
potential MVP overkill. R18 excludes them from the milestone. Inspection of IGV
commit `bc6ef372164de5776f53d24f71ad8356c90f10a4`, specifically
[`FastaIndexedSequence`](https://github.com/igvteam/igv/blob/bc6ef372164de5776f53d24f71ad8356c90f10a4/src/main/java/org/igv/feature/genome/fasta/FastaIndexedSequence.java),
found indexed reads of FASTA byte ranges without sequence-block checksum
verification in that reader. This is a scoped source inspection, not an audit
of every IGV input path or dependency. This supported R18's simpler boundary.

## Engineering follow-up

The user confirmed shared understanding of the product decisions on 2026-11-18.
Remaining engineering work must implement these contracts rather than silently
reopen settled behavior:

- Investigate and document the versioned single-file storage format, regional
  lookup, sequence encoding, bounded caches, and extension path for annotations.
- Specify source parsing and diagnostic details, SAM-compatible checksum
  normalization, provenance fields, and safe destination publication.
- Validate native reference-field sizing and truncation at the 640-point
  minimum width, with short and long filenames.
- Specify asynchronous source/request identity, regional restoration, and
  reference/BAM lifecycle tests, including reference-only navigation and errors.
- Freeze correctness and performance protocols; measure creation/opening and
  agree justified limits from those measurements before qualification.

At the close of this interview no storage engine had been selected, feature implementation had not started,
and the mockup is not native-rendering evidence. On 2026-11-18, the user also
agreed to the specification's test interfaces: existing ViewerSession behavior,
real-file reference-bundle creation/open/read integration, and focused native
rendering checks.

This interview does not authorize feature implementation or ticket publication.

## Storage decision after the interview

On 2026-11-18, the [GRCh38 experiment](performance/reference-storage-2026-11-18.md)
selected SQLite with 64 KiB chunks for the [v1 bundle format](reference-format.md)
and proposed creation and opening limits for integrated qualification.

The user subsequently approved two fresh native saves at ≤60 s, ≤256 MiB
whole-process peak RSS and ≤1.05 bytes per input base, with validated-open p95
≤50 ms on each 102-handle route. The [integrated protocol](performance/reference-qualification-protocol-2026-11-18.md)
and [qualification measurements](performance/reference-qualification-2026-11-18.md)
record the accepted M4 workload and the native viewer evidence.
