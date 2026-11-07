# Clipping indicators and the future BWA check

Research date: 2026-11-01. Source findings supporting clipping display and the future BWA preparation check. [design.md](../design.md) is the authority for current scope; this note does not authorize pipeline work.

## Context

The future input-preparation request concerns **supplementary split-read alignments only**. Earlier wording referred to “secondary” alignments; that was clarified and is historical. The check concerns soft clipping and sequence availability in the chosen BWA version, not ordinary secondary alternative mappings. The IGV comparison also informs the deferred idea of ticks at soft-clip/aligned junctions.

## BWA-MEM findings

Source inspection used BWA commit `d82444c17edc2384420409f85557c6ae84019732`; its manual is headed `bwa-0.7.19-r1273`.

- **Secondary and supplementary differ:** secondary records describe alternative mappings; supplementary records describe additional portions of a split/chimeric alignment. Their SAM flags are `0x100` and `0x800`, respectively. [SAM specification, sections 1.2 and 1.4](https://samtools.github.io/hts-specs/SAMv1.pdf)
- **Documented `-Y` behavior:** BWA-MEM normally uses soft clipping for the primary alignment and hard clipping for supplementary alignments. `-Y` selects soft clipping for supplementary alignments. [BWA manual](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwa.1#L356-L359)
- **Shared CIGAR path:** `-Y` suppresses hard-clip conversion in the shared CIGAR emitter. It would therefore be too categorical to say that `-Y` cannot affect secondary CIGAR strings. [CIGAR output](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwamem.c#L838-L847)
- **Ordinary secondary sequence is omitted:** records carrying BWA's ordinary internal secondary flag emit `SEQ=*` and `QUAL=*`, independently of `-Y`. A soft-clipped CIGAR alone is therefore insufficient to display colored clipped bases from such a record. SAM recommended practice also recommends omitting secondary sequence and qualities. [BWA sequence output](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwamem.c#L896-L917), [SAM specification, section 2.5.2](https://samtools.github.io/hts-specs/SAMv1.pdf)
- **`-M` nuance:** shorter split hits relabeled secondary use a different internal flag, converted to external `0x100` during output. They do not take the ordinary secondary sequence-omission branch merely because the output record has the secondary flag. Every externally secondary record must not be assumed sequence-free. [Split-hit flagging](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwamem.c#L1055-L1058), [flag output](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwamem.c#L868-L877), [sequence output](https://github.com/lh3/bwa/blob/d82444c17edc2384420409f85557c6ae84019732/bwamem.c#L896-L917)

The secondary-output findings are background evidence and do not expand the supplementary-only preparation request.

## IGV comparison

These findings were verified in IGV v2.19.8, commit `e2bcf420046d7d8263dd575359a4233fbabf986a`, alongside the official documentation:

- IGV has optional **clipping indicators**, with a threshold applied to the combined hard-plus-soft clipping length at each end. [Threshold checks](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L605-L610), [official clipping-indicator documentation](https://igv.org/doc/desktop/UserGuide/tracks/alignments/chimeric_reads/#clipping-indicator)
- The renderer applies clipping-end drawing to the first and last display blocks. The indicator can be an angled chevron where the end has the strand-arrow shape or a vertical line where the edge is straight. Supplementary-alignment information can produce additional colored connectors. [Display-block loop](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L701-L783), [end-indicator drawing](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L1043-L1106)
- These indicators are related to, but not identical to, the possible Bamdalf boundary ticks. IGV's clipping flags are at the outer displayed ends; the Bamdalf tick concept marks the internal junction between displayed soft-clipped sequence and the aligned portion. The inspected IGV display-block loop did not show a separate thin tick at every internal soft-clip/aligned junction. [Display-block loop](https://github.com/igvteam/igv/blob/e2bcf420046d7d8263dd575359a4233fbabf986a/src/main/java/org/broad/igv/sam/AlignmentRenderer.java#L701-L783)

This is source inspection, not a live GUI comparison. No user BAM, saved IGV preference, aligner invocation, or pipeline was inspected or changed.
