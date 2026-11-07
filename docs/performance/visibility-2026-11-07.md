# Initial alignment visibility limit — 2026-11-07

The initial app limit is **10,000 bases, inclusive**. Wider targets keep their
coordinates and ruler, show **Zoom in to see alignments**, and perform no
alignment query or drawing. This is a fixed internal default, without a user
setting. It is independent of the navigable reference length and of the later
sampling budget.

The choice follows 33 release-build measurements and native renderer inspection
on real public short-read data. At a 1,068-point viewport, typical 148-base
alignment bodies remain recognizable at 10 kb (15.81 points), whereas at 50 kb
(3.16 points) they collapse into tiny arrows/slivers. The deeper 10 kb case still
takes about 443 ms to load; no accepted hard latency target or final WGS
qualification is implied. Width alone cannot bound an arbitrarily deep pileup.

## Data and reproducibility

The source is GIAB HG002/NA24385 Illumina HiSeq paired 148-base data, aligned by
Novoalign 3.02.07 to GRCh38 no-alt plus hs38d1. The source is documented as
**300×**, not the final milestone's 100× workload. The exact BAM, reference
bundle, bounded HTTP extraction, checksums, and reconstruction commands are in
[the acquisition recipe](../../Benchmarks/Data/README.md). No FASTA is needed by
the viewer. The source README and header identify the reference; no independent
sequence-level FASTA comparison was performed.

The regional BAM contains 225,426 unchanged records, including 215,377 after the
fixed flag exclusions. Every extracted record is paired and has 148 stored
bases. Observed mean eligible aligned-base depth across the complete extraction
regions is 311.89× in the ordinary locus and 682.81× in the deeper locus; these
are regional observations, not whole-genome or per-window depth estimates.

| Locus | Complete extraction, inclusive | Comparison center | Widths measured |
| --- | --- | --- | --- |
| Ordinary | chr20:9,994,241-10,059,776 | 10,025,000 | 150, 500, 1,000, 5,000, 10,000, 50,000 bp |
| Deeper | chr20:29,884,417-29,900,800 | 29,892,600 | 150, 500, 1,000, 5,000, 10,000 bp |

Do not interpret space outside those extraction intervals as empty source data.
No full BAM download or sampling was used. The combined BAM/header/index
transfer was 24,553,909 bytes. Offline reconstruction with the checked-in recipe
reproduced the measured BAM, BAI, profile, header, and manifest byte-for-byte.

Run [the native baseline harness](../../Benchmarks/README.md) separately from
native tests. It uses the actual `ViewerSession`, `ViewerWindowController`, and
alignment `NSView`; its explicit unlimited measurement setting allows wider
candidate intervals to be compared after the app default has been selected.

## Measurement conditions and results

Apple M4, 10 logical processors, 16 GiB RAM; macOS 27.2 build 26B123; Xcode 27.2 /
Swift 6.4.2 release; HTSlib 1.25. Native content was 1,100 × 720 points, with a
1,068 × 584 point alignment viewport at 2× backing scale, light appearance, and
top scroll position. Each region/width used three fresh processes; each process
rasterized its visible viewport five times. OS file caches and unrelated system
activity were uncontrolled. No cooperating CPU-heavy build/test ran alongside.

The measurements preceded final cutoff and validation edits. Their base was
`micknudsen/bamdalf@75e95bada4147ca5a8616cf30710adde8b68f3d7` plus the issue's
working implementation. Executable SHA-256 was
`81a16944a01a435cc0eefc53c6fb18d9747e12694197d8b717aaa4d24af289c5`;
working-diff SHA-256 was
`186ddbf761f3d308eef5d99540028e5c3c3b06f1466b958b416aaba65752df71`.
The runner records these and per-source hashes for subsequent reproductions.

Medians below are across three processes. Load includes decoding, row packing,
presentation callbacks, and native layout. Draw is actual visible-viewport CPU
bitmap rendering, excluding PNG encoding and compositor presentation. Peak RSS
is the entire process maximum, including startup and image exports, converted
from macOS bytes to MiB. It is not incremental alignment memory.

| Region | Width | Records | Rows | Load ms | Draw CPU ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary | 150 | 705 | 365 | 51.64 | 3.105 | 140.73 |
| Ordinary | 500 | 1,514 | 375 | 47.09 | 3.182 | 141.08 |
| Ordinary | 1,000 | 2,670 | 378 | 67.66 | 3.719 | 142.44 |
| Ordinary | 5,000 | 10,879 | 421 | 92.18 | 5.439 | 149.05 |
| Ordinary | 10,000 | 20,942 | 430 | 133.54 | 7.571 | 157.64 |
| Ordinary | 50,000 | 104,965 | 434 | 472.47 | 21.682 | 218.89 |
| Deeper | 150 | 2,263 | 1,583 | 70.69 | 2.981 | 141.44 |
| Deeper | 500 | 5,135 | 1,620 | 99.54 | 3.322 | 143.20 |
| Deeper | 1,000 | 9,701 | 1,957 | 157.33 | 3.698 | 145.53 |
| Deeper | 5,000 | 31,433 | 2,251 | 360.96 | 6.168 | 157.28 |
| Deeper | 10,000 | 47,160 | 2,251 | 443.44 | 7.889 | 170.08 |

[All 33 individual measurements](data/visibility-2026-11-07.csv) retain raw
bytes and per-case timings. The ordinary/deeper 10 kb load ranges were
123.12–139.24 ms and 432.39–445.69 ms, respectively. These measurements do not
establish scrolling frame rates, a memory bound, final 100× qualification, or a
performance advantage over another viewer.

## Native readability and geometry

The actual renderer images were inspected at every measured width and locus.
At 150 bases, clipped bases are distinct colored blocks; letters appear when
there are at least eight points per base. At 500–1,000 bases, strand points,
substantial clips, and insertion markers remain clear. At 5 kb, typical bodies
span 31.61 points. At 10 kb, bodies and strand points remain recognizable, but
individual bases and short gaps are not readable. At 50 kb, the dense sliver
pattern and marker size relative to bodies make feature inspection unsuitable.
The initial 10 kb limit selects the largest tested readable width; it is not a
claim to have found an optimal cutoff. Smaller windows, other read lengths,
density, hardware, or future sampling warrant remeasurement.

Separate synthetic captures from the same native renderer verify exact geometry:
[palette, literal equals, and reverse strand](../images/native-alignment-palette.png),
[all standard CIGAR operations](../images/native-alignment-cigar.png), and
[missing-sequence outlines clipped at the viewport](../images/native-alignment-missing-sequence.png).
These are renderer-only images, not whole-window screenshots. Supplemental
AppKit full-content captures omitted static layers and were excluded as complete
window evidence; actual native field/ruler/menu tests cover those controls.

Rows are 18 points high with 12-point bodies. Strand tips stay inside the first
reverse or last forward mapped block and shrink with narrow bodies. Insertions
use a purple 4-point-wide I-shaped glyph at the exact boundary, clipped to the
record's full drawn extent; they do not widen the genomic axis or justify moving
retained rows. Deletion/skip connectors have their true reference widths.
Outlined tails are drawn at full extent before viewport clipping, without an
artificial closing edge. These simple bounds are implementation choices within
the accepted geometry contract.
