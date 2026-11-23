# bamdalf

A native macOS BAM alignment viewer for Apple Silicon, under development.

Use **File → Open BAM…** to open a local, coordinate-sorted BAM. Bamdalf finds
BAI and CSI indexes beside the BAM and asks you to choose if it finds several.
Enter a genomic interval such as `chr1:10,001-10,500` using a contig name from
your file. The viewer draws alignments with standard CIGAR geometry and full
soft clips. Scroll vertically to see more reads. If a region fails to load,
the viewer restores the previous successful view.

Use the toolbar arrows to pan and the **+** and **−** buttons to zoom. In the
alignment area, drag horizontally to pan, double-click to zoom in around a
base, or Option-click to zoom out. Nearby pans reuse loaded data and preserve
retained rows and vertical scrolling. Views wider than 10,000 bases show the
ruler and prompt you to zoom in to see alignments.

At one screen point per base or closer, click a pileup column to see its base
depth and A, C, G, T counts below the alignments. Counts include all eligible
records before display downsampling. The panel also shows ambiguous bases and
unresolved `=` observations when present. **Close** returns the space to the
pileup.

Use **File → Open Reference…** to browse a `.bref` reference bundle on its own
or alongside a compatible BAM. Zoom in to see reference bases below the ruler
and mismatches highlighted in aligned reads. On `master`, **File → Create
Reference…** builds a named bundle from a local, uncompressed FASTA in a
separate window while you continue browsing.

- [Build, test, and launch](docs/development.md)
- [Prepare releases](docs/releases.md)
- [Design](docs/design.md)
- [Domain glossary](GLOSSARY.md)
- [Future functionality](docs/backlog.md)
- [MVP specification and implementation tickets](https://github.com/micknudsen/bamdalf/issues/1)
- [Contributing and documentation checks](CONTRIBUTING.md)
