# Missing sequence in mapped alignments

Research date: 2026-11-01. Primary source: SAM/BAM specification 1.6, printing `b5341fb` dated 2025-08-12. Supporting evidence for Q48, accepted 2026-11-02; [design.md](../design.md) is the authority for current requirements. No BAM parser or native renderer was implemented or tested.

## Verified format facts

- SAM permits `SEQ=*` when sequence is not stored. The SEQ/CIGAR length requirement applies when sequence is present. Sequence absence alone does not mean unmapped; FLAG `0x4` determines unmapped status. Thus missing sequence does not by itself invalidate an otherwise valid mapped record with POS and CIGAR. [SAM §1.4, pages 7–9](https://samtools.github.io/hts-specs/SAMv1.pdf#page=7)
- POS and reference-consuming CIGAR operations describe mapped geometry. `S` supplies soft-clipped query length without consuming reference; `H` consumes neither stored query nor reference. When the whole sequence is omitted, an `S` operation does not become `H`, and CIGAR alone cannot supply the clipped nucleotide identities. [SAM §1.4, page 8](https://samtools.github.io/hts-specs/SAMv1.pdf#page=8)
- A stored ambiguous `N` is a sequence symbol; `SEQ=*` means sequence is absent. In BAM, omitted sequence uses `l_seq=0` and zero-length sequence/quality arrays, whereas stored bases have encoded values, including `N`. [SAM/BAM §4.2.3, page 16](https://samtools.github.io/hts-specs/SAMv1.pdf#page=16)

For example, an otherwise valid mapped record at POS 1001 with `6S24M4S` and `SEQ=*` still describes a 1001–1024 mapped span and soft-clip lengths six and four. Their base identities are unavailable. This is an illustrative deduction from the format, not a tested fixture.

## Design implication

Q48 uses CIGAR-derived mapped geometry and empty outlined soft-clip tails to distinguish unavailable sequence from stored ambiguity bases. Missing `SEQ` is not hard clipping, and no bases can be inferred from the soft-clip length alone. The complete rendering requirements and unresolved format cases belong in [design.md](../design.md).
