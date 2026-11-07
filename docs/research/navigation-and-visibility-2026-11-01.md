# Navigation and alignment visibility

Research date: 2026-11-01. Findings from official IGV Desktop documentation as consulted on that date, supporting navigation and visibility decisions (Q16–Q20). [design.md](../design.md) is the authority for Bamdalf's current requirements.

## Verified IGV behavior

IGV provides toolbar plus/minus controls and a zoom slider. Double-click or Shift-click zooms in, centered on the clicked locus; Alt-click zooms out similarly. Dragging across the ruler selects a region to zoom into. Dragging in a data track pans; arrow keys also pan, while Home/End move a screen width. Clicking the ruler or ideogram recenters without changing zoom. These are documented interactions, not a live GUI test. [IGV navigation](https://igv.org/doc/desktop/UserGuide/navigation/#navigation-controls)

IGV separates the visible coordinate interval from alignment loading. Beyond its visibility threshold, it does not load alignments and displays a zoom-in message. The documented defaults are 30 kb for Other (including short-read DNA), 300 kb for RNA, and 1,000 kb for third-generation sequencing. Users can adjust them for their data. [IGV visibility window](https://igv.org/doc/desktop/UserGuide/tracks/alignments/viewing_alignments_basics/#visibility-window)

Downsampling is a separate response to deep coverage: some reads are omitted from display, with marked locations. The documented defaults are 50-base sampling windows and at most 100 reads per window. Third-generation tracks are not downsampled by default. [IGV downsampling](https://igv.org/doc/desktop/UserGuide/tracks/alignments/viewing_alignments_basics/#downsampling)

Dynamic coverage also disappears beyond the visibility threshold because alignments have not been loaded. Precomputed coverage can provide whole-chromosome or whole-genome views. [IGV coverage](https://igv.org/doc/desktop/UserGuide/tracks/alignments/viewing_alignments_basics/#dynamic-vs-pre-computed)

## Implications for Bamdalf

A whole-reference viewport need not trigger whole-reference BAM loading. This separation informed Q16's ruler-only wide views and Q17's navigation boundaries; their complete requirements are in [design.md](../design.md).

Span alone cannot bound work: a small interval can still contain many alignments. Representative datasets should therefore inform both a span threshold and a separate resource budget. The IGV 30 kb default is a comparison point, not a Bamdalf setting or performance guarantee. A sampled view is also distinct from a completed query containing no eligible alignments. See [downsampling research](downsampling-2026-11-01.md) for sampling and resource-limit implications.

No application was built, no user BAM was benchmarked, and no local IGV settings were inspected.
