# Hard clipping and IGV display

Research date: 2026-11-01. Supporting evidence for hard-clipping display (Q6). [design.md](../design.md) is the authority for current requirements.

## Meaning and common sources

In CIGAR, `H` records clipped length while omitting those bases from that alignment record's `SEQ`. It consumes neither stored query sequence nor reference sequence. `S` instead retains the clipped sequence when `SEQ` is present. These are properties of an alignment record; hard-clipped bases can still exist in another record for the same read or in the original FASTQ. [SAM specification, sections 1.2 and 1.4](https://samtools.github.io/hts-specs/SAMv1.pdf)

One relevant source in short-read DNA workflows is supplementary alignment output. The BWA-MEM manual states that its default is soft clipping for the primary alignment and hard clipping for supplementary alignments; `-Y` changes supplementary alignments to soft clipping. This finding was checked against the pinned manual headed `bwa-0.7.19-r1273`, dated 22 March 2025, rather than the older SourceForge manual. [BWA manual, `-Y`](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwa.1#L356-L359)

For an illustrative same-strand split of a 150-base read, the records could be:

| Record | CIGAR | Bases stored in this record's SEQ |
| --- | --- | --- |
| Primary alignment at one locus | `100M50S` | 150 |
| Supplementary alignment at another locus | `100H50M` | 50 |

This is a constructed example, not an observation from the user's files. It illustrates why a supplementary record may omit sequence retained in the primary record. The SAM specification also illustrates primary and supplementary records of the same read using soft and hard clipping in its `r003` example. [SAM specification](https://samtools.github.io/hts-specs/SAMv1.pdf)

Hard clipping can also be introduced during downstream processing. For example, `samtools ampliconclip` clips primer-overlapping alignment ends using soft clipping by default and offers `--hard-clip` to remove the clipped sequence from the output record. [Samtools ampliconclip documentation, version 1.25 as consulted](https://www.htslib.org/doc/samtools-ampliconclip.html)

## IGV Desktop behavior

Source inspection covered IGV **v2.19.8**, whose tag resolves to commit `e2bcf420046d7d8263dd575359a4233fbabf986a`. The newer source snapshot `f4b78d6412fa31eaca9b5bad7b3c35a8925828da` was also inspected and has the same distinctions below. No installed binary was launched or tested. [Versioned source](https://github.com/igvteam/igv/tree/e2bcf420046d7d8263dd575359a4233fbabf986a)

- **No full-length hard-clipped tail:** IGV skips `H` while constructing sequence-display blocks. Its soft-clip preference adds `S` blocks and adjusts display bounds for those bases; it does not turn `H` into nucleotide blocks or length-scaled tails. [SAMAlignment.java, lines 632–716](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/SAMAlignment.java#L632-L716)
- **Optional end indicators do include hard clipping:** the clipping-flag renderer compares the combined hard-plus-soft clip length at each end with the configured threshold. It draws compact end indications rather than a tail proportional to the clipped length. Thus it would be inaccurate to say that IGV ignores hard clipping completely. [Renderer conditions](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L605-L610), [combined clipping counts](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/ClippingCounts.java#L119-L133), [end-indicator rendering](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L1043-L1124)
- **Defaults differ by experiment type:** v2.19.8's general alignment defaults disable clipping flags. Its Third Gen overrides enable them with a threshold of 20 bases; the renderer tests strictly greater than the threshold. These are source defaults, not a reading of the user's saved preferences. [General defaults](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/resources/org/broad/igv/prefs/preferences.tab#L135-L149), [Third Gen overrides](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/resources/org/broad/igv/prefs/preferences.tab#L201-L222)
- **Read details expose hard clipping:** the popup includes CIGAR, explicit left/right hard/soft clipping counts, and a read-length breakdown that accounts for omitted hard-clipped bases. Long CIGARs are shortened in the middle while preserving the ends. [Read-length breakdown](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/SAMAlignment.java#L368-L386), [popup details](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/SAMAlignment.java#L969-L1018)

For split reads, IGV separately offers an SA-tag-based supplementary alignment diagram and split-screen navigation. These features describe the relationship between alignments; they do not recover nucleotide sequence missing from an individual hard-clipped record. [Official chimeric-read documentation](https://igv.org/doc/desktop/UserGuide/tracks/alignments/chimeric_reads/)

## Design implication

The historical proposal for a neutral, length-scaled hard-clip tail would have been a new Bamdalf presentation choice, not a reproduction of IGV's main alignment display. It was not adopted: Q6 handles valid `H` without a tail or special indicator. See [design.md](../design.md) for the display contract and scope.

No user's BAM was inspected, so these sources cannot establish whether hard-clipped records occur in their daily data or which aligner options were used. No live IGV UI comparison or application test was performed.
