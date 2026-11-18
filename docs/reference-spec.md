# Reference milestone specification

The product design and test interfaces were confirmed on 2026-11-18.
Published as [GitHub issue #48](https://github.com/micknudsen/bamdalf/issues/48).
See the [decision record](reference-milestone.md) for the design history.
The [v1 format](reference-format.md) and [storage measurements](performance/reference-storage-2026-11-18.md)
record the subsequent storage decision and proposed qualification limits.

## Problem Statement

Users can navigate alignment geometry but cannot inspect the reference bases
or see how aligned sequence differs from them. Repeatedly selecting external
FASTA and index files would also make reference use dependent on those files'
continued existence and contents. The viewer needs an optional, reusable
reference that stays selected across compatible BAM changes and can later
support annotations.

## Solution

Create a self-contained, single-file `.bref` from a local, uncompressed FASTA.
Creation validates the input, preserves case, builds lookup indexes and SAM
sequence MD5 values, and saves safely with modal progress and cancellation.
Creation does not select the result. Users open bundles explicitly, browse
reference-only regions or attach compatible BAMs, and see reference bases and
mismatch highlighting when zoom permits. A rounded reference field beside the
interval input identifies the selected bundle without its suffix.

## User Stories

1. As a user, I want to create a reference from an uncompressed FASTA without
   preparing a `.fai`, so that preparation is one operation in bamdalf.
2. As a user, I want one self-contained `.bref`, so that moving or deleting the
   source FASTA does not affect my saved reference.
3. As a user, I want lowercase bases and valid ambiguity codes preserved, so
   that creation does not discard sequence information.
4. As a user, I want invalid FASTA to fail with a specific diagnostic, so that
   I can correct it before using the reference.
5. As a user, I want progress and cancellation while creation runs, so that a
   lengthy operation remains understandable and controllable.
6. As a user, I want creation to pause browsing while leaving the application
   responsive, so that completion has a predictable interaction model.
7. As a user, I want a canceled or failed operation to preserve an existing
   destination and leave no incomplete new bundle, so that my files stay usable.
8. As a user, I want standard confirmation before replacing an existing bundle,
   so that replacement is deliberate.
9. As a user, I want the currently open reference protected from replacement,
   so that the data I am viewing remain stable.
10. As a user, I want creation to save without opening, so that preparing another
    reference leaves my current viewer unchanged.
11. As a user, I want to open an existing bundle without the original FASTA,
    so that the bundle is portable.
12. As a user, I want BAM browsing to work without a reference, so that my
    existing workflow remains available.
13. As a user, I want to open the reference before or after a BAM, so that I
    can choose whichever loading order suits my task.
14. As a user, I want the reference to remain selected across compatible BAM
    changes, so that switching samples does not require selecting it again.
15. As a user, I want incompatible BAM/reference opens rejected without changing
    my current view, so that I do not inspect misleading comparisons.
16. As a user, I want every BAM contig checked for exact name and length, so
    that incompatibility is detected before navigating to that contig.
17. As a user, I want available BAM sequence MD5 values checked, so that a
    same-length reference with different bases can be rejected.
18. As a user, I want BAMs lacking MD5 values accepted through dictionary checks,
    so that optional metadata does not become a universal input requirement.
19. As a user, I want to browse reference sequences without a BAM, so that I
    can inspect the reference independently.
20. As a user, I want all selected-reference contigs navigable, so that a BAM
    containing only a subset does not restrict reference browsing.
21. As a user, I want intervals preserved across compatible BAM changes, so
    that I can compare samples at the same locus.
22. As a user, I want fresh rows at the top for a newly opened BAM, so that old
    row placement is not confused with the new sample's data.
23. As a user, I want valid intervals preserved when replacing a reference,
    so that replacement does not cause unnecessary navigation.
24. As a user, I want invalid intervals cleared after reference replacement,
    so that the viewer does not silently rename or clamp my chosen location.
25. As a user, I want Close Reference to keep the BAM and valid view, so that
    I can continue without comparison data.
26. As a user, I want interval entry restored when closing the reference makes
    my current contig unavailable, so that navigation has a valid dictionary.
27. As a user, I want every launch to start without a reference, so that the
    application does not reopen a bundle automatically.
28. As a user, I want the rounded reference field beside interval input to show
    `GRCh38` for `GRCh38.bref`, so that the selected reference is easy to identify.
29. As a user, I want the same field to show No reference when empty, so that
    the current comparison state is explicit.
30. As a user, I want a reference row fixed below the ruler, so that scrolling
    alignment rows does not move the reference sequence away.
31. As a user, I want colored cells and readable letters at suitable zoom,
    so that reference detail follows the genomic scale.
32. As a user, I want matching aligned bases visually quiet and differing
    unambiguous bases highlighted, so that differences are easy to find.
33. As a user, I want ambiguous comparisons neutral gray, so that uncertainty
    is not presented as a definite mismatch or match.
34. As a user, I want missing sequence outlined without invented bases, so
    that unavailable evidence is visible.
35. As a user, I want stored sequence `=` interpreted correctly, so that its
    declaration of agreement is not treated as a nucleotide mismatch.
36. As a user, I want required reference-read failures reported with safe
    restoration, so that incomplete data do not appear successfully loaded.
37. As a user, I want a new BAM retained if its first regional load fails,
    so that file-opening success is distinct from regional-reading success.
38. As a user, I want responsive, bounded-memory reference browsing, so that
    adding sequence comparison preserves the viewer's existing usability.

## Implementation Decisions

### Accepted behavior

- File commands are **Create Reference…**, **Open Reference…**, and
  **Close Reference**. The selected-reference field is read-only, not another
  picker. Keep native dialog and focus behavior.
- Enforce `.bref` for bundle files; validate contents independently of suffix.
  Omit only the terminal bundle suffix in the displayed reference name.
- Creation runs off the UI thread under modal progress with Cancel. Close and
  validate a complete candidate before publishing it at the chosen destination.
  An existing destination survives failure/cancellation. Recognize the actual
  open reference file when preventing replacement, including path aliases.
- FASTA parsing must accept valid DNA ambiguity codes and preserve case. Reject
  duplicate/missing sequence names and unsupported characters; do not silently
  repair or skip records. No external index is required or consumed.
- Preserve sequence case in storage/display while calculating per-contig MD5
  according to SAM normalization. Stored digests describe imported sequences,
  not FASTA formatting. These are identity metadata, not custom block checksums.
- Viewer reads must use the bundle directly with bounded regional access.
  They must not load an entire genome or unpack files to retrieve a region.
  Viewing is read-only. Creation and opening retain distinct success boundaries.
- A BAM's complete declared contig dictionary must be a subset of the reference
  dictionary with exact case-sensitive names and identical lengths. Ordering
  may differ. Compare each available `M5`; missing values are unverified, not
  mismatches. Never infer compatibility from filenames or apply name aliases.
- Validate compatibility in either loading order before committing the changed
  source. Failed/canceled file selection or compatibility checks preserve the
  preceding source/view. No automatic reference detachment or alternative-file
  fallback is introduced.
- The selected reference supplies navigation names/lengths when present;
  otherwise the BAM does. A reference contig absent from the BAM has no alignment
  query and is not a BAM read failure. Its display makes no biological
  zero-coverage claim.
- Preserve the interval on a successful compatible BAM open with a selected
  reference, but clear BAM rows/cache and start new rows at the top. With no
  reference, retain existing successful-open interval-entry behavior.
- A successful reference replacement preserves a valid interval or clears an
  invalid interval without aliases/clamping. Closing a reference preserves BAM
  rows/scroll and a BAM-valid interval; otherwise it returns to interval entry.
  With neither source left, return to the empty viewer state.
- Match the reviewed rounded reference field to neighboring control height and
  border treatment. Use the bundle name without `.bref`, or **No reference**.
  Validate native truncation and sizing at the minimum window width. The local
  mockup is design evidence, not a native screenshot or rendering test.
- The fixed reference row uses the soft-clip nucleotide palette. At eight or
  more screen points per base, show letters, retaining source lowercase. At
  one to less than eight points, show colored cells. Below one point, leave the
  row blank and omit reads made solely for invisible sequence detail.
- Aligned A/C/G/T comparisons are case-insensitive. Matching bases retain the
  body appearance; differing unambiguous bases use the nucleotide palette.
  Either base ambiguous makes the comparison indeterminate, shown neutral gray
  with the aligned letter when readable.
- Missing aligned sequence uses outlined bodies when a reference is selected,
  retaining CIGAR/strand geometry and no invented bases. Without a reference,
  preserve existing appearance. Existing soft clips and indel/skip geometry
  remain unchanged. Secondary alignments remain filtered out.
- Aligned sequence `=` is a declared match against an unambiguous reference;
  an ambiguous reference uses the indeterminate appearance. Soft-clipped `=`
  remains literal and neutral. The sequence symbol and CIGAR operation are
  distinct. Comparison must honor query/reference consumption for every CIGAR
  operation and must not reverse-complement stored reverse-strand bases twice.
- Mismatch detail uses the reference row's one/eight-point zoom limits. Do not
  inflate mismatches into wider markers. The existing wide alignment cutoff,
  sampling, bounded-tail retrieval, and row/scroll continuity still apply.
- Required reference failures follow existing regional restoration, draft
  preservation, and stale-request rules. Optional failures must not become
  completed coverage. Keep the reference selected. A first regional failure
  after a successful new BAM open keeps that BAM/reference, clears the failed
  view, and returns to interval entry with an error.
- Opening validates structure, metadata, and index bounds. Report detected
  read/decode errors. No custom block integrity scheme or whole-bundle scan is
  required. Do not advertise exhaustive corruption detection.

### Proposed module changes

These proposals map the accepted behavior to the current application; they do
not select a storage engine or require new public abstractions for every step.

- Extend the existing **ViewerSession** module and presentation with selected
  reference identity, reference-aware navigation, regional sequence readiness,
  and source-safe lifecycle/restoration. Keep caller actions close to the
  existing open/navigate/close interaction model.
- Add one deep **reference-bundle module** whose small interface creates a
  bundle, opens validated metadata, and reads sequence intervals. Hide file
  layout, normalization, indexing, caching, and publication mechanisms behind
  that interface. Do not expose database queries or storage offsets to callers.
- Extend the existing BAM-reading module to expose optional contig `M5` values
  and retain aligned sequence needed for comparison, including the distinction
  between missing sequence and present sequence. Revisit storage accounting and
  budgets when retaining additional bases.
- Extend existing native drawing and window controls for the reference row,
  comparison appearance, reference field, menus, and modal creation. Keep I/O
  and comparison preparation outside drawing callbacks.
- Reuse deterministic load-control mechanisms for tests; do not add a protocol
  for every internal type solely to mock its implementation.

### Storage investigation

Evaluate a versioned single-file format against these requirements before
selecting it: preserved sequence case, bounded regional reads, portable closed
bundles, read-only viewing, safe cancelable publication, bounded cache use, and
an extension path for annotations. Compare SQLite with bounded sequence BLOBs
against an indexed binary container. An archive requiring extraction does not
satisfy the accepted regional-access contract.

The chosen design must specify unknown/newer format handling, metadata and
record bounds, sequence MD5 normalization, minimal provenance, ownership of
temporary files/sidecars, and the relationship between stored contig identity
and sequence data. These are engineering specifications to review, not reasons
to introduce reference downloads, annotation rendering, or custom integrity
verification into the milestone.

The initial [storage investigation](research/reference-bundle-storage-2026-11-18.md)
proposed comparing SQLite with 64 KiB and 256 KiB case-preserving ASCII
chunks. It documents read-only opening, rollback-journal publication, WAL and
immutable-mode pitfalls, source normalization, and destination preservation.
The subsequent [whole-genome experiment](performance/reference-storage-2026-11-18.md)
selected 64 KiB for the [v1 format](reference-format.md).

## Testing Decisions

The user accepted these test interfaces on 2026-11-18. Test observable behavior
through the same interfaces callers use; avoid tests of private SQL, cache
containers, helper call counts, or encoding details unless they exercise a
documented file-format guarantee.

### Primary interface: ViewerSession

Extend existing session-level tests using real small BAMs and reference bundles
with independently derived sequences/expected geometry. Exercise both loading
orders and reference-only navigation. Keep the existing deterministic suspended
load gates for obsolete completion, failure, cancellation, and draft/scroll
ordering. No wall-clock sleeps should be needed for correctness assertions.

Cover every accepted lifecycle transition, including compatibility failure,
missing/partial/matching/mismatching `M5`, contig subset/order differences,
extra-reference navigation, reference replacement/close, first-region failure,
creation without selection, and startup without automatic reopening. No
previous-file data may be restored as if it belonged to a newly selected file.

### Real-file interface: reference-bundle creation/open/read

Create bundles from small independently specified FASTAs, then rename/remove
the sources before reopening and reading regions. Exercise first/last bases,
cross-block/contig bounds, lowercase, each supported ambiguity code, wrapping
and line-ending variants, digest normalization, duplicate/missing names, invalid
characters, truncated/unsupported bundles, cancellation, and destination
preservation. Test open-file identity protection through alias paths.

Assert returned sequence and external file outcomes. Resource instrumentation
may establish bounded reads/memory in performance qualification; correctness
tests must not mirror a particular private caching strategy.

### Native interface: focused AppKit checks

Extend existing native window/rendering tests for menu availability, reference
field/empty state, fixed row during vertical scrolling, aligned coordinate
movement during fractional drag, light/dark palette legibility, comparison
categories, lowercase and literal `=`, outline geometry, and one/eight-point
thresholds. Check short/long filenames at default and minimum window sizes.
Validate modal progress/cancellation and native Save/Open/error behavior with
focused automated or explicitly recorded manual checks as appropriate.

### Correctness and performance gates

Freeze fixture/protocol versions and independently derived expected results
before qualification. Add mixed-CIGAR and reverse-strand cases, ambiguous/missing
sequence, stale reference/BAM completions, and source replacement during loads.
Run existing BAM-only regressions and the required native suite with its actual
completion summary, not merely an exit-zero process.

Reference-enabled WGS navigation must meet existing responsiveness and memory
targets under the recorded workload protocol, with reference detail enabled.
Reference-only and no-reference modes are separate validation cases. Measure
human-reference creation time, peak memory, bundle size, and opening latency
before proposing new limits. A storage microbenchmark does not establish full
viewer qualification. No new performance result is claimed by this spec.

## Out of Scope

- Gene/GTF or other annotation import/rendering; reserve an extension path only.
- Coverage, read inspection, extra BAM tracks, configurable filters, or enabling
  secondary alignments.
- Compressed FASTA input, reference downloads, hosted assemblies, or external
  FASTA/index dependence during viewing.
- Continued browsing during creation, automatic opening after creation, or
  automatic reference reopening on launch.
- Contig aliases, mismatch aggregation at wide zoom, custom block checksums,
  whole-bundle integrity scans, or claims of exhaustive corruption detection.

## Further Notes

Deliver reference creation, opening, and base display first, followed by
mismatch highlighting. Measure the storage candidate before selecting the
format and setting creation/opening targets. Qualify the integrated viewer
against the existing WGS workloads.
