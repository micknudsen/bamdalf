# Bamdalf

Domain terminology for a genomic alignment viewer.

## Language

**Genomic interval**:
A contiguous range of base positions on one named reference sequence. Bamdalf describes these intervals using 1-based, inclusive endpoints.

**BAM index**:
A companion data structure mapping genomic regions to file locations in a coordinate-sorted BAM.

**BAI**:
A BAM index format with a fixed coordinate range of up to 2^29 bases per reference sequence.

**CSI**:
A genomic index format supporting larger coordinate ranges than BAI, including for BAM files.

**Alignment**:
A linear placement of a sequenced segment against one reference sequence, represented by a mapped SAM/BAM record. One segment may have multiple alignments.
_Avoid_: Read, when referring specifically to one alignment record.

**Downsampling**:
Selecting a subset of otherwise eligible alignments for display. The intentional omissions are distinct from alignment data that has not yet finished loading.

**Query template**:
The originating sequenced fragment whose segments can yield mate and supplementary alignment records.
_Avoid_: Read group, which identifies sequencing metadata rather than one fragment.

**Sampling group**:
A set of eligible, loaded alignment records treated as one unit for downsampling, intended to represent one originating query template, including mates and supplementary pieces. Missing names and reused identities can prevent exact correspondence to a biological fragment.
_Avoid_: Read group, which has a distinct SAM/BAM metadata meaning.

**SAM/BAM read group**:
A sequencing-metadata category identified by an `@RG` header entry and referenced by the `RG:Z` tag on alignment records. One read group can contain many query templates.
_Avoid_: Sampling group, when referring to this metadata category.

**Secondary alignment**:
An alternative mapping represented by a SAM/BAM record with flag `0x100`. The flag describes alternative placement; split-hit compatibility options can also affect how an aligner assigns it.
_Avoid_: Supplementary alignment, when referring to an alternative mapping.

**Supplementary alignment**:
An additional linear part of a split/chimeric alignment, represented by a SAM/BAM record with flag `0x800`. Its relationship to the other parts differs from alternative mapping of the same sequence.
_Avoid_: Secondary alignment, when referring to an additional split-alignment part.

**Mate**:
The other sequenced segment of a paired-end template, distinct from that segment's alignment records.
_Avoid_: Mate alignment, when referring to the segment itself.

**Insertion (`I`)**:
An alignment operation containing query bases with no corresponding reference bases. Its length contributes to query consumption but not to the alignment's reference span.

**Deletion (`D`)**:
An alignment operation spanning reference bases with no corresponding query bases. Its length contributes to the alignment's reference span but not to query consumption.

**Soft clipping (`S`)**:
Unaligned bases at an end of an alignment that are retained in the record's query sequence when that sequence is present. Soft clipping contributes to query consumption but not to the aligned reference span.

**Hard clipping (`H`)**:
Clipped bases whose length is recorded in CIGAR but whose sequence is omitted from that record's query sequence. Hard clipping consumes neither stored query bases nor reference bases.

**Aligned reference span**:
The interval on a reference consumed by an alignment's reference-consuming CIGAR operations, including deletions and skipped regions. Soft and hard clipping are excluded.

**Drawn extent**:
The horizontal extent occupied by an alignment's visual representation, including any displayed clipped tails. It can extend beyond the aligned reference span.

Alignment terminology follows the [SAM specification, sections 1.2 and 1.4](https://samtools.github.io/hts-specs/SAMv1.pdf). Index terminology follows the [Samtools index manual](https://www.htslib.org/doc/samtools-index.html) and [CSI specification](https://samtools.github.io/hts-specs/CSIv1.pdf). Sources consulted 2026-11-01.

Sampling-group terminology follows Bamdalf Q38 in [design.md](docs/design.md). Read-group metadata terminology was checked on 2026-11-06 against the [SAM specification, section 1.3](https://samtools.github.io/hts-specs/SAMv1.pdf#page=4) and [SAM optional fields specification, section 1.2](https://samtools.github.io/hts-specs/SAMtags.pdf#page=4).
