# bamdalf

A native macOS BAM alignment viewer for Apple Silicon, under development.

Open a local BAM through **File → Open BAM…**, with sibling BAI/CSI discovery
and explicit choice when multiple indexes exist. Enter a full genomic interval
to inspect real alignments with standard CIGAR geometry, full soft clips,
vertical scrolling, and safe loading/error restoration. Views wider than
10,000 bases retain the ruler and ask you to zoom in. Nearby typed navigation
reuses loaded data and preserves retained rows and vertical scrolling.
Graphical pan/zoom controls remain in the next implementation tickets.

- [Build, test, and launch](docs/development.md)
- [Prepare releases](docs/releases.md)
- [Design](docs/design.md)
- [Domain glossary](GLOSSARY.md)
- [Future functionality](docs/backlog.md)
- [MVP specification and implementation tickets](https://github.com/micknudsen/bamdalf/issues/1)
- [Contributing and documentation checks](CONTRIBUTING.md)
