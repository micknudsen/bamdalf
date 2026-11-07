# Future functionality

Updated 2026-11-07. These items are outside the agreed first milestone. They are not prioritized, specified, or authorized for implementation. The current scope and decision identifiers are recorded in [design.md](design.md).

The superseded cursor, selection, and focus rules and the withdrawn drag-cancellation proposal are not deferred features or backlog commitments.

## Deferred features

### Data and sequencing workflows

- Reference-base display, mismatch highlighting, coverage, read inspection, and additional tracks (Q1).
- Dedicated RNA-seq and long-read workflows (Q2).

### Alignment display and filtering

- Linked paired-end display with deliberate mate grouping and connecting lines (Q3).
- Configurable alignment filters. The first milestone uses the fixed rules in Q7–Q11.
- Fading alignments based on mapping quality or soft-clipped bases based on base quality (Q49).
- Numeric insertion and deletion length labels. The first MVP retains insertion markers and true-width deletion connectors without numeric size labels (Q55).

### Navigation and index handling

- Gene-name search and location shorthand, including single-position and bare-reference-name entry. The first milestone requires an explicit start and end, with identical endpoints for one base (Q13).
- Browsing to an arbitrary BAM index file, including indexes stored outside the BAM's folder. Choosing among automatically discovered sibling indexes is already included in the first milestone (Q21/Q23).
- Creating a BAM index from within the viewer. The first milestone requires an existing index and discovers it beside the BAM (Q21).

## Possible later enhancements

- Vertical ticks at the junction between soft-clipped sequence and the aligned portion. The first milestone uses full-length colored soft-clipped tails without these ticks (Q5b).
- Region-specific indicators for newly exposed areas whose alignments have not finished loading. Stripes, dots, a plain tint, an outline, and a text label were explored; none is selected or committed for implementation. The spinner beside the interval field remains the sole visible loading indicator in the first MVP (Q31).
- A manual **Redo downsampling** action to generate another random sample (Q36). Sampling priorities remain stable throughout an open-BAM session in the first MVP (Q70). Any future redo control's scope and effect on session priorities would need separate design.

## Future input preparation — requested 2026-11-01

- Ensure that BWA soft-clips **supplementary split-read alignments** when preparing the relevant input data or fixtures. This requirement concerns supplementary split-read alignments, not ordinary secondary alternative mappings. BWA-MEM documents `-Y` for this purpose; check the actual tool/version, CIGAR, and sequence availability on the output. This is a future input-preparation requirement, not an alignment-execution feature or pipeline change in the current viewer milestone. See [research](research/clipping-indicators-and-bwa-2026-11-01.md).
