# Coverage and base counts

Product design confirmed on 2026-11-23. Decisions Q1–Q28 define the first
coverage milestone. Selecting one position in the pileup will show base depth,
counts, and percentages from qualifying alignments before display downsampling.
The [glossary](../GLOSSARY.md) defines the counting terms used below.
The [published specification](https://github.com/micknudsen/bamdalf/issues/82)
includes the confirmed native-viewer acceptance tests.

## Q1. Inspect one genomic position

Accepted 2026-11-22. The first milestone will show depth and base counts at
one selected genomic position. A coverage track across the interval is deferred.

The motivating question is how much support a base has at that position.

## Q2. Count before display downsampling

Accepted 2026-11-22. Depth and base counts include all qualifying observations
at the selected position, including those omitted from the displayed rows by
downsampling. For example, if 90 observations contribute A and 10 contribute T,
depth is 100 and the counts are A 90 and T 10, even when only 20 rows are shown.

## Q3. Apply the viewer's alignment filters

Accepted 2026-11-22. Use the viewer's existing BAM record filters for depth
and base counts. Mapped primary and supplementary alignments are eligible.
Exclude any record flagged as unmapped, secondary, QC-failed, or duplicate.
There is no minimum mapping quality (MAPQ).

## Q4. Count overlapping mates separately

Accepted 2026-11-22. When both mates contribute a qualifying base at the
selected position, count each observation. Two T observations from the same
pair add two to depth and two to T. An A and a T from that pair also add two
to depth, with one count for each base.

## Q5. Count deletions separately from base depth

Accepted 2026-11-22. An eligible alignment with a CIGAR deletion (`D`) spanning
the selected position contributes one to the deletion count and zero to base
depth. For example, eight qualifying A observations and two deletions give a
base depth of eight, an A count of eight, and a deletion count of two.

## Q6. Count reference skips separately

Accepted 2026-11-22. Each eligible alignment whose CIGAR `N` skips the
selected position adds one to the reference-skip count, zero to base depth,
and zero to the deletion count. Eight qualifying A observations, two deletions,
and three reference skips give base depth 8, A 8, deletions 2, and reference
skips 3.

## Q7. Group ambiguous read bases

Accepted 2026-11-22. Each qualifying aligned read base carrying an ambiguity
code such as `N` (unknown) or `R` (A or G) adds one to base depth and one to
the ambiguous count. It contributes zero to the individual A, C, G, and T
counts. Eight A calls, one N, and one R give base depth 10, A 8, and
ambiguous 2.

## Q8. Resolve a stored equals sign against the reference

Accepted 2026-11-22. A qualifying aligned `=` in the read sequence adds one
to base depth. If the selected reference has A, C, G, or T at that position,
add one to the corresponding base count. If no reference is open or the
reference base is ambiguous, add one to the separate unresolved `=` count.
Resolving the observation after opening a reference leaves base depth unchanged.

## Q9. Count aligned positions with missing read sequence separately

Accepted 2026-11-22. If an eligible record has missing read sequence
(`SEQ=*`) and its CIGAR places a query base at the selected position, add one
to **sequence unavailable** and zero to base depth. Eight A observations and
one such record give base depth 8, A 8, and sequence unavailable 1.

## Q10. Count bases regardless of individual base quality

Accepted 2026-11-22. In the first milestone, each otherwise qualifying base
contributes one observation regardless of its individual base quality. This
includes bases with a missing quality score. Three T observations with
qualities 35, 5, and unavailable contribute three to base depth and three to T.

## Q11. Omit soft-clipped bases

Accepted 2026-11-22. Omit soft-clipped bases from all inspector counts, including
when a clipped tail is drawn over the selected position. The inspector has no
separate soft-clip tally. If eight alignments report A at position 100 and a
ninth begins aligning at 101 with a clipped T drawn over 100, the counts at
100 are base depth 8, A 8, and T 0.

## Q12. Count alignments with an insertion after the selected base

Accepted 2026-11-22. **Insertion after this base** counts eligible alignments
with an insertion between the selected reference base and the next position.
Each supporting alignment contributes one regardless of insertion length.
Inserted bases contribute zero to base depth and the nucleotide counts.
If eight alignments report A at position 100 and two of them carry an insertion
between 100 and 101, selecting 100 shows base depth 8, A 8, and insertion
after this base 2.

## Q13. Select a position by clicking its pileup column

Accepted 2026-11-22. A single unmodified click in the alignment area selects
the genomic position under the pointer for inspection. Clicking a mismatch,
a read body, or empty space below the reads in the same column selects the
same position and shows counts for the whole column. A drag pans, a
double-click zooms in, and an Option-click zooms out. These navigation gestures
do not select a new position for inspection.

## Q14. Show the counts in a panel below the pileup

Accepted 2026-11-22. The first selection opens a panel below the pileup with
the selected coordinate beside its counts. Selecting another column updates
the same panel in place. The panel uses vertical space and preserves the full
width of the pileup.

## Q15. Keep the selected position when panning

Accepted 2026-11-22. Panning the selected position offscreen keeps its
coordinate and counts in the panel. Mark the position **outside current view**
while it is offscreen. Panning it back into view clears that label.

## Q16. Clear the selection when opening a different BAM

Accepted 2026-11-22. Successfully opening a different BAM clears the selected
position and closes the counts panel. If the user cancels the replacement or
the new BAM fails to open, keep the original selection and counts.

## Q17. Keep the selection when changing the reference

Accepted 2026-11-22. With the same BAM open, opening, replacing, or closing
the reference keeps the selected position, including when it is offscreen.
Update the counts in the panel using the reference at that position. For eight
stored C bases and two stored `=` symbols, opening a reference with C there
changes C 8 and unresolved `=` 2 to C 10 and unresolved `=` 0. Closing the
reference restores the original counts. Base depth stays 10 throughout.

## Q18. Show numbers only when the selected position's counts are complete

Accepted 2026-11-22. On selection, show the new coordinate immediately. If
its counts are pending, show **Loading…** in place of numbers. Show **Counts
unavailable** if the query fails. A completed query with no observations shows
base depth 0. Results for an earlier selection must never appear under the
new coordinate.

## Q19. Select by click at one screen point per base or closer

Accepted 2026-11-22. A single click can select a new pileup column when each
reference base spans at least one screen point. Below that threshold, a single
click leaves the selection unchanged. Double-click still zooms in.

## Q20. Mark the selected column

Accepted 2026-11-22. Mark the selected position on the ruler and outline its
column through the reference row (when present) and the pileup. Keep base
letters and mismatch colors readable. The marker and outline follow the
genomic position during panning. When it goes offscreen, the panel identifies
the selection as **outside current view** (Q15).

## Q21. Close the panel and clear the selection

Accepted 2026-11-22. The panel's **Close** button clears the selected position,
removes its ruler marker and column outline, and returns the panel's space to
the pileup. Preserve the current genomic interval and scroll position. The
next eligible click starts a fresh inspection.

## Q22. Keep base depth and A/C/G/T counts visible

Accepted 2026-11-22. Once counts are ready, show base depth followed by A, C,
G, and T in that order, including zeros. Show each additional category only
when its count is nonzero. For example, 30 A observations and two deletions
display as base depth 30, A 30, C 0, G 0, T 0, and deletions 2.

## Q23. Show the reference base beside the selected coordinate

Accepted 2026-11-22. When a reference is open, display its base beside the
selected coordinate, including when the position is offscreen. Preserve the
stored letter, including lowercase and ambiguity codes. For example, show
**chr1:100 · Reference C** if the reference carries uppercase C. With no
reference open, show the coordinate alone in that heading.

## Q24. Show percentages for observations that contribute to base depth

Accepted 2026-11-22. At positive base depth, show the percentage alongside
each displayed A, C, G, T, ambiguous, and unresolved `=` count. Divide each
count by total base depth. For example, six T observations at depth 30 appear
as **T 6 (20%)**. Deletions, reference skips, sequence unavailable, and
insertion after this base show counts only. At zero base depth, omit all
percentages.

## Q25. Require a BAM that includes the selected contig

Accepted 2026-11-22. Starting an inspection requires an open BAM with the
selected contig in its header. A click while browsing a reference alone or
on a reference contig absent from the BAM leaves the inspector unchanged.
For example, a reference-only `chrM` remains browsable. Base depth 0 means
a completed query at a position in the BAM found zero qualifying base
observations.

## Q26. Keep exact-coordinate inspection out of the first milestone

Decided 2026-11-22. Omit the proposed **Go → Inspect Position…** command for
entering an exact coordinate. Select a pileup column by clicking as described
in Q13 and Q19. **⌘L** continues to focus the interval navigation field.

## Q27. Count overlapping primary and supplementary alignments separately

Accepted 2026-11-23. If an eligible primary alignment and an eligible
supplementary alignment from the same read each supply a base at the selected
position, count both observations. A primary A and a supplementary G together
contribute two to base depth, one to A, and one to G.

## Q28. Keep the selection across contig changes in the same BAM

Accepted 2026-11-23. Navigating to another contig in the same BAM keeps the
original selected coordinate and its counts in the panel, marked **outside
current view**. For example, after selecting `chr1:100` and navigating to
`chr2:1-500`, the panel still identifies `chr1:100`. Returning to an interval
containing that position restores its marker and clears the offscreen label.
Selecting a base on the new contig replaces the original selection.
