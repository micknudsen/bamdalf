# Downsampling deep alignment views

Research date: 2026-11-01. Supporting evidence for sampling groups, view budgets, and stable priorities (Q35–Q45, Q70). [design.md](../design.md) is the authority for current policy. No BAM was read or benchmarked and no application code was changed.

## Verified IGV Desktop behavior

IGV downsamples deep short-read alignment views by default to reduce memory usage. Its documented settings are a 50-base sampling window and 100 reads per window. Black rectangles below the coverage track identify affected regions. Coverage still reflects all reads, although the alignment track shows a subset. Long-read tracks are not downsampled by default. These are documentation facts, not proposed Bamdalf defaults. [IGV downsampling documentation](https://igv.org/doc/desktop/UserGuide/tracks/alignments/viewing_alignments_basics/#downsampling)

Source was inspected at commit `f4b78d6412fa31eaca9b5bad7b3c35a8925828da`:

- The loader iterates the regional query and applies record filters before passing eligible records to the tile. Sampling does not stop iteration when the sample fills. [Query loop](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L158)
- Coverage counts are updated before downsampling. Sampling groups are based on alignment starts; selection uses reservoir-style replacement. [Record handling](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L501)
- Randomness is seeded from the current time. This implementation does not establish a stable sample across reloads. [Random seed](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L454)
- Within one loaded interval/tile, eligible records with the same read name share keep/reject handling. Comments identify mates and chimeric alignments among the reasons. This is not a guarantee that every biological mate or supplementary alignment is displayed; the scope and exclusions below matter. [Sampling implementation](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L529)

### Sampling unit and keep-together scope — checked for Q38

IGV Desktop uses the alignment's read-name string as its grouping key. A later record with a retained name is appended to that name's list without a new sampling draw; a name marked rejected causes later records with that name to be omitted. Replacing a selected name removes its entire accumulated list and marks that name rejected. Thus, within a normally completed sampling operation, same-name group retention is enforced rather than merely preferred. A selected name may contribute multiple records, so the sampling allowance is not a strict maximum count of individual alignment records. [Keep/reject logic](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L538), [group replacement](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L756)

Changing sampling windows resets counters and an offset, but does not clear the read-name map. Consequently, the decision also applies to later same-name records in other sampling windows of that loaded interval. [Window transition](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L578)

The limits of this guarantee are explicit in the source:

- The regional query and filtering happen before sampling. Records outside that query or excluded by the active filters do not participate. The sampler does not fetch missing mates or split-read pieces elsewhere. [Query](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L155), [filters](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L214)
- Each tile load creates a new tile and read-name map. There is no shared keep/drop decision across separately loaded intervals, references or reloads. [Tile creation](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L126), [map construction](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L479), [interval load](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentDataManager.java#L304)
- Group identity is read name alone. The sampling method does not build a group using read-group identifiers, mate flags or supplementary-alignment tags. This behavior is independent of whether the resulting records are drawn as linked pairs. [Grouping key and selection](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L538)

These findings concern the pinned IGV Desktop source, not IGV.js. They are source inspection, not a runtime test or a promise that every member of a template is visible.

### Window allowances versus a total view budget — checked for Q43

The pinned IGV Desktop sampler gives each sampling window the same configured allowance. `samplingDepth` is loaded from the sampling options, and starting a new window resets its effective count to zero. Those options come directly from preferences; the sampler does not divide a total view budget among windows or redistribute unused capacity from sparse windows. [Allowance selection and reset](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L468), [sampling and reset](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L557), [preference-backed options](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentDataManager.java#L518)

IGV's windows also start at encountered alignment starts, with a new window begun when an alignment start reaches or passes the current window end. They are not a reference-anchored grid. Related same-name records can span windows and share their earlier decision, so IGV's allowance is not a strict per-base coverage or individual-record cap. [Window creation](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L514), [grouping](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L538)

Consequently, more loaded windows can retain more groups overall. IGV separately checks the alignment visibility range before loading; this is a zoom-span cutoff, not redistribution of sampling capacity. The loader also checks available memory, independently of sampling. [Visibility check](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentDataManager.java#L224), [memory check](https://github.com/igvteam/igv/blob/f4b78d6412fa31eaca9b5bad7b3c35a8925828da/src/main/java/org/igv/alignment/AlignmentTileLoader.java#L240)

### Identifier facts for the remaining grouping design

SAM defines QNAME as the template name and treats records with identical QNAMEs as originating from the same template, without a read-group qualifier. A QNAME of `*` means the name is unavailable. Chimeric alignment records share QNAME and first/last-segment flags. [SAM sections 1.2 and 1.4](https://samtools.github.io/hts-specs/SAMv1.pdf)

RG is optional metadata identifying the read's group; when read-group headers exist, its value must match a header ID. [SAMtags section 1.2](https://samtools.github.io/hts-specs/SAMtags.pdf#page=4) A proposed `(RG, QNAME)` key would therefore be a Bamdalf policy, not a requirement of the SAM definition. Missing names and missing or inconsistent read-group metadata remain cases to resolve; the unavailable-name marker must not be interpreted as evidence that records share a known template.

## Design implications

Downsampling can reduce retained alignment data and drawing work. It does not by itself bound the work needed to scan and decode a dense BAM interval: the inspected IGV implementation still examines candidate records. Memory limits, cancellation and malformed-input handling remain separate concerns. This is an inference from the query and sampling flow above, not a measured Bamdalf performance result.

Omitting alignments can omit rare variant-supporting or split-read evidence. A sampled view therefore cannot establish that an unshown alignment or pattern is absent. This follows from sampling a subset; a persistent indicator makes the limitation explicit but does not recover omitted evidence.

Coordinated group sampling is compatible with drawing individual alignment records independently. Keeping eligible loaded members together does not imply fetching supplementary records outside the query or retaining records excluded by filters. Bamdalf's corresponding requirements are Q3 and Q38; IGV's exact grouping key is not automatically adopted.

For a uniform sample of `min(B, N)` eligible groups, where `B` is the group budget and `N > 0` the candidate count, each group has inclusion probability `p = min(1, B/N)`. All groups are shown when `N ≤ B`; an empty candidate set requires no division. This is a mathematical description of whole-view sampling, not IGV's window-based algorithm.

By linearity of expectation, the expected displayed depth at a position is `p` times the eligible full-data depth there, even though records within a group are selected together. This avoids deliberately flattening dense regions with equal local quotas, but actual regional proportions remain noisy in any particular sample. It is a probability argument, not a benchmark or a quantitative coverage/copy-number feature.

## Bamdalf context and implementation limits

Bamdalf uses a total per-view group budget and coordinated selection of eligible loaded members. Q70 selects the highest `min(B, N)` stable session priorities, recomputed from one seed and group identity. See [design.md](../design.md) for the current sampling and navigation contract, and [stateless-priority evidence](sampling-priorities-memory-2026-11-06.md) for the samtools precedent. Earlier local-bin alternatives (Q37/Q40/Q42) and Q36's fresh-per-operation randomness are historical; Q43/Q44/Q70 supersede them.

The remaining technical limits are independent of those product choices:

- A selected group can contain several alignment records. A group budget therefore does not strictly bound records, rows, per-base depth, memory, or query time.
- Stable priorities reproduce selection for unchanged candidates and settings, but do not guarantee unchanged membership when candidates change. Sample stability and row placement are separate concerns; see [navigation research](navigation-stability-2026-11-05.md).
- Cached samples cannot simply be combined and assumed to satisfy the current view's selection rule. Candidate discovery, off-screen handling, group identity/encoding, missing names, ties, selection structures, and cache reconciliation still require an implementation design.
- No numerical group budget or performance result was established. A displayed/total count would need an accurate, explicit definition of the current view's candidates.

Alignment visibility by genomic span, sampling by group count, and resource limits are distinct controls. IGV's full-data coverage track is not implied by Bamdalf's sampling policy. Current warning presentation and scope belong in [design.md](../design.md).
