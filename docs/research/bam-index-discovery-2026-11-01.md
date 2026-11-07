# BAM index formats and discovery

Research date: 2026-11-01. Supporting evidence for index discovery and opening behavior (Q21–Q25). [design.md](../design.md) is the authority for current requirements; HTSlib is a candidate, not a selected dependency.

## Verified format and filename facts

Samtools 1.25 can create either BAI or CSI indexes for coordinate-sorted BAM files. Without an explicit output filename, `sample.bam` produces `sample.bam.bai` or `sample.bam.csi`, according to the chosen format; BAI is the default in the consulted version. [Samtools index manual](https://www.htslib.org/doc/samtools-index.html)

BAI's coordinate range is limited to 2^29 bases per reference (536,870,912 bases, called 512 Mbp in the manual). CSI is needed for mapped positions beyond that range. [Samtools index manual](https://www.htslib.org/doc/samtools-index.html)

CSI generalizes the binning scheme through configurable minimum interval size and depth. It avoids BAI's fixed range ceiling, but does not change the BAM format's own reference-length constraint of less than 2^31 bases. [CSI specification](https://samtools.github.io/hts-specs/CSIv1.pdf), [SAM/BAM specification, sections 1.3 and 4.2](https://samtools.github.io/hts-specs/SAMv1.pdf)

HTSlib 1.25 documents loading both BAI and CSI for BAM. Its local discovery implementation recognizes these four names for `sample.bam`:

| Format | Appended suffix | Replaced suffix |
| --- | --- | --- |
| BAI | `sample.bam.bai` | `sample.bai` |
| CSI | `sample.bam.csi` | `sample.csi` |

These are verified naming conventions supported by that library, rather than mandatory filenames imposed by the binary index formats. [HTSlib BAM index API](https://github.com/samtools/htslib/blob/1.25/htslib/sam.h#L1195-L1235), [local discovery source](https://github.com/samtools/htslib/blob/1.25/hts.c#L4853-L4943)

The inspected local discovery code checks appended CSI, replaced CSI, appended BAI, then replaced BAI. This describes the library's behavior; Bamdalf's Q23 instead requires user choice when multiple candidates are present. [HTSlib local discovery](https://github.com/samtools/htslib/blob/1.25/hts.c#L4909-L4943)

## Design implications

Bamdalf's index policy uses both formats and the four names above, requires a choice among multiple candidates, and forbids automatic fallback after the chosen index fails to load. These product choices are defined in [design.md](../design.md), rather than inherited from HTSlib's search order. The reason for explicit choice is that multiple indexes may indicate an input-file problem worth examining.

Recognizing a filename or successfully loading an index does not establish that it matches the BAM. Validation of corrupt, stale, or mismatched indexes remains distinct from discovery. Existing library support offers an implementation route, not a measured effort estimate or a verified integration.

No index was created, no BAM was loaded, and no application or library integration was tested.
