# Public regional BAM for the early visibility baseline

This recipe retrieves two small regions of real public HG002 human short-read whole-genome data. It does not generate reads or downsample. It uses the GIAB 300× source, not the final 100× benchmark profile.

From repository root:

```sh
bash scripts/build-htslib.sh
sh Benchmarks/Data/acquire.sh .local/measurements/issue-5/data
```

Choose an output directory without an existing `HG002.GRCh38.regions.bam`; the extractor refuses to overwrite that artifact. Requirements are Python 3, curl, clang, zlib, and the repository's pinned static HTSlib build. The wrapper finds the repository relative to itself and links the independent profile helper using only `libhts.a` and `-lz`.

## Public source and reference

- [Source BAM](https://giab.s3.amazonaws.com/data/AshkenazimTrio/HG002_NA24385_son/NIST_HiSeq_HG002_Homogeneity-10953946/NHGRI_Illumina300X_AJtrio_novoalign_bams/HG002.GRCh38.300x_chr20.bam), with [matching BAI](https://giab.s3.amazonaws.com/data/AshkenazimTrio/HG002_NA24385_son/NIST_HiSeq_HG002_Homogeneity-10953946/NHGRI_Illumina300X_AJtrio_novoalign_bams/HG002.GRCh38.300x_chr20.bam.bai).
- [Source README](https://giab.s3.amazonaws.com/data/AshkenazimTrio/HG002_NA24385_son/NIST_HiSeq_HG002_Homogeneity-10953946/NHGRI_Illumina300X_AJtrio_novoalign_bams/README_NHGRI_Novoalign_bams): HG002 / NA24385, Illumina HiSeq, 300× source profile, Novoalign 3.02.07, SAMtools 0.1.18. The [primary GIAB study](https://pmc.ncbi.nlm.nih.gov/articles/PMC11642750/) describes 2×148 bp sequencing; every extracted record independently has 148 stored bases and the paired flag.
- Reference bundle: `GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz`, identified by that README at `ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz`. The header's assembly label is `GRCh38_full_plus_hs38d1_analysis_set_minus_alts`; all 2,580 reference dictionary entries are preserved, including chr20 length 64,444,167. No FASTA is downloaded or sequence-verified, and the viewer does not require one for this rendering path.
- [AWS dataset registry](https://registry.opendata.aws/giab/) identifies NIST as manager and describes unrestricted use. Source accessed 2026-11-07.
- Remote source length: 12,100,052,820 bytes; ETag `cf5c661b132e291c32be4c3805be3f60-91`; Last-Modified 2020-11-13 01:29:20 GMT. This multipart ETag is not a whole-file MD5. No whole-source checksum is asserted.

## Acquisition and completeness

`acquire.py` applies the [SAM/BAM specification's](https://samtools.github.io/hts-specs/SAMv1.pdf) BAI bin/linear-index rules, merges overlapping virtual chunks, and retrieves only their bounded BGZF byte ranges. It pins the index, source README, and initial header range by SHA-256. Each data range must have the expected size, Content-Range, full source size, and ETag; zlib checks complete BGZF blocks. Cached range files and response headers remain available for offline reconstruction.

The **30,000,000-byte cap** includes planned BAM range bodies, initial header range, BAI, and README; small HTTP headers are additional. Observed total body transfer is 24,555,256 bytes: 24,024,693 bytes of regional ranges + 262,144 header bytes + 267,072 index bytes + 1,347 README bytes. curl also receives an individual maximum-size guard, so a server ignoring Range cannot silently download the 12.1 GB source.

| Purpose | 1-based inclusive extraction interval | 0-based half-open interval |
| --- | --- | --- |
| Ordinary | chr20:9,994,241-10,059,776 | [9,994,240, 10,059,776) |
| Deeper | chr20:29,884,417-29,900,800 | [29,884,416, 29,900,800) |

Records overlapping those reference spans are preserved byte-for-byte, without flag/quality filtering or downsampling. Overlapping index chunks are deduplicated by source virtual offset, preserving distinct identical records. Records are sorted by reference start and source virtual offset. The derived header changes the original misleading `SO:unsorted` to `SO:coordinate` and appends an extraction `@PG`; `source-header.sam` preserves the original.

The subset is complete only within these reference-span intervals. Do not treat empty space elsewhere as empty source data. Mates outside the intervals are not fetched by mate association. Soft-tail-only records at the outer extraction boundary are not fetched; use interior targets with at least 148 bases of margin for drawn-tail policies. The ordinary benchmark center 10,025,000 supports widths through 50,000 bp; deeper center 29,892,600 supports widths through 10,000 bp. Deeper 50,000 bp is intentionally unsupported.

## Expected independent validation

`profile.c` reads the resulting BAM through HTSlib, checks chr20 identity and coordinate ordering, calculates the profile, creates a fresh BAI, and compares indexed regional eligible counts against a sequential pass. This independently verifies the local output's readability/index consistency, not the original remote index's correctness.

Expected with HTSlib 1.25:

- 225,426 total paired records, all with 148 stored bases; 215,377 eligible after unmapped/secondary/QC-failed/duplicate exclusions (`0x704`).
- 19,528 eligible soft-clipped records; observed CIGAR operations M/I/D/S. No eligible supplementary or MAPQ-0 records in this subset; use dedicated fixtures for those cases.
- Ordinary: 138,726 eligible records; mean aligned-base depth 311.891357, minimum 9, maximum 434.
- Deeper: 76,651 eligible records; mean aligned-base depth 682.811096, minimum 0, maximum 3,868.

Depth counts eligible M/=/X bases across the entire extraction interval, including zero-depth bases; no MAPQ/base-quality filter or overlapping-mate correction is applied. These are regional measurements, not whole-genome coverage estimates or final 100× qualification.

Expected SHA-256 values from the 2026-11-07 baseline:

| Artifact | SHA-256 |
| --- | --- |
| Derived BAM, 21,342,967 bytes | `786c9d3f66ff721d8bbb20bb62c8e055aa589f1e64f930fc8fdfc210e9b689c5` |
| Derived BAI | `c1712ac8989c65ea7cb3179f382cedca7334000fbdcaf8817b542a0bcc9add19` |
| Source BAI | `942df9668bc25daccf78ec8a0922f742f1e587622272d6801121fcd1631e091b` |
| Initial header BGZF range | `8671667598b5c05ee2db751ff539c0c898c3d0b3f8ffb60cfa74fbb18903f15d` |
| Original SAM header | `87ff26a9e925aaa3cacb4d2aaa2f2d80967812f90a4531ce11acb1307ac27d29` |
| Binary reference dictionary | `981fbe1997369d124482fa33e04c00e9c3fc8482771266c09eeab7a7b9f28e24` |
| HTSlib profile text | `249bb0844ceb9886b71492e63f4803d45fdf59168d62e069e33b66e117536218` |

A different zlib version may change derived compression bytes without changing records; compare profile and source provenance as well as compressed digests. The source metadata digests are fixed and must match. The wrapper writes `SHA256SUMS`, `manifest.json`, and `profile.txt` beside the BAM.

## Offline reproduction

Create a new output directory and copy the three source inputs (`source.bam.bai`, `source-README.txt`, `header.bgzf`) plus `source-header-http.txt` into it. Copy or symlink the previously verified `range-*.bgzf` and matching `range-*.http.txt` files. Do not copy the old derived BAM. Then run:

```sh
sh Benchmarks/Data/acquire.sh .local/measurements/issue-5/reproduction-check --offline
```

Offline mode rejects missing cache files and never invokes curl. The checked-in scripts were verified this way in a separate directory: derived BAM, BAI, profile, original SAM header, and manifest were byte-identical to the original baseline artifacts. Original acquisition and performance artifacts were preserved. The helper does not run AppKit or any performance measurements.
