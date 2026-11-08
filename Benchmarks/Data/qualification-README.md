# Derived approximately 100× qualification panel

On 2026-11-08, issue #11 prepared this broader regional panel from the public
HG002 Illumina HiSeq 300× WGS source described in the [source recipe](README.md).
It retains approximately one third of fragments with fixed seed `20261108`.
Preparation sampling is independent of runtime display sampling. The original
300× slices remain separate stress inputs; neither file is substituted for the
other in a measurement report.

## Reproduce

From the repository root on macOS, with the pinned static HTSlib already built:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build-htslib.sh
sh Benchmarks/Data/qualification-acquire.sh .local/measurements/issue-11/data
```

Choose a new output directory: existing source or derived BAMs are never
overwritten. Requirements are Python 3, curl, Clang, CommonCrypto (provided by
macOS), zlib, and the repository's pinned HTSlib 1.25. The wrapper acquires data,
profiles both BAMs, creates BAI indexes, and independently audits the preparation
selection. It writes `manifest.json`, `plan.json`, `source-profile.txt`,
`derived-profile.txt`, `preparation-audit.txt`, and `SHA256SUMS`.

The final input is `HG002.GRCh38.qualification-100x.bam` with its adjacent
`.bam.bai`. The complete unsampled regional source remains in
`HG002.GRCh38.qualification-source.bam`. No full 12.1 GB BAM is downloaded.

The locked recipe contains these spans. Coordinates in the middle column are
1-based and inclusive; the implementation uses the exact half-open bounds.

| Purpose | Extraction interval | 0-based half-open bounds |
| --- | --- | --- |
| Ordinary long pan route | chr20:9,830,401-10,354,688 | `[9830400, 10354688)` |
| Independent ordinary region | chr20:19,988,481-20,119,552 | `[19988480, 20119552)` |
| Dense region and extended route | chr20:29,818,881-30,081,024 | `[29818880, 30081024)` |

The 917,504 extracted bases include a contiguous 524,288-base ordinary stretch.
They support sustained panning, more than eight distinct historical query
snapshots, disjoint jumps, and revisits. Coverage is complete only inside these
spans; unextracted space is not evidence of empty source data. Records whose
reference spans overlap a selected span are included before preparation
sampling. Mates outside those spans are not fetched by association. Use interior
targets for native qualification, avoiding artificial extraction boundaries.

## Source, selection, and integrity

The source URL, size `12,100,052,820`, multipart ETag
`cf5c661b132e291c32be4c3805be3f60-91`, and SHA-256 pins for the BAI, README, and
header are inherited from the [original acquisition recipe](README.md).
The source documents Novoalign 3.02.07 and reference bundle
`GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz`.
All 2,580 original reference dictionary entries are preserved; chr20 has
64,444,167 bases. The dictionary SHA-256 remains
`981fbe1997369d124482fa33e04c00e9c3fc8482771266c09eeab7a7b9f28e24`.
No FASTA sequence validation or whole-source checksum is claimed.

The BAI-directed plan, fixed before acquisition and qualification measurements,
contains 36 merged byte ranges. The total planned source-body size is
171,917,510 bytes, including header, BAI, and README, below the explicit
300,000,000-byte cap. The 2026-11-08 acquisition downloaded 171,386,947 range
bytes and reused 530,563 bytes of checksum-verified header, BAI, and README
from the previous acquisition. Small HTTP response headers are additional.
Each range must have the exact size, requested Content-Range, full source size,
and ETag. BGZF decompression verifies complete blocks; every cached range also
receives a recorded SHA-256. Distinct records are deduplicated by original BAM
virtual offset, never by name or contents. Sort order is reference start followed
by source offset. Header sort order and `@PG` provenance change; alignment records
remain byte-for-byte unchanged.

Preparation computes SHA-256 over the eight-byte big-endian unsigned seed,
followed by this exact identity:

| Identity | Bytes |
| --- | --- |
| QNAME unavailable (`*`) | `00`, then eight-byte big-endian original source virtual offset |
| Named, absent RG | `01`, QNAME byte length as eight-byte big-endian integer, QNAME bytes |
| Named, present RG | `02`, RG byte length as eight-byte big-endian integer, RG bytes, QNAME byte length in the same format, QNAME bytes |

The first eight digest bytes, interpreted as an unsigned big-endian integer,
must be less than `6148914691236517205`, or `floor(2^64 / 3)`. An empty RG remains
distinct from an absent RG. A present non-string or duplicate RG is rejected.
All records sharing an exact named identity receive the same decision, including
records at different positions or with different flags. Unnamed records would
receive independent stable keys; none occurred in this source panel. No flag,
quality, or CIGAR filter affects preparation retention.

The separate C verifier uses HTSlib decoding and CommonCrypto to rederive every
decision from preserved source offsets. It walks the unsampled and derived BAMs
in order and compares every expected retained record's complete decoded data and
core coordinates, flags, quality, and mate fields. It rejects missing, extra,
changed, or reordered records. Thus preparation selection and whole-fragment
collocation are checked independently of Python extraction/encoding.

HTSlib also checks sorting, all contigs, paired/read-length counts, regional
groups, and depths, builds fresh indexes, and compares indexed query counts with
sequential counts for all three complete spans and six benchmark targets.
This verifies local output and index consistency; it does not prove that a
defective original remote index could never omit records.

## Observed data profile

On 2026-11-08, extraction produced 1,760,787 source records in 894,000 exact
groups. The fixed preparation retained 587,604 records in 298,349 groups
(33.3724% of groups). Every source and derived record was paired and stored
148 bases. After the viewer's fixed unmapped/secondary/QC-failed/duplicate
exclusions, the derived file had 573,712 eligible records. No eligible
supplementary record occurred. The largest named group contained two records;
this public panel alone does not qualify pathological large-group resource use.

Depth counts eligible M/=/X bases over each entire interval, including zero-depth
bases, with no MAPQ/base-quality filter or overlapping-mate correction. These are
regional depths, not a whole-genome depth estimate.

| Region | Eligible records | Groups | Mean depth | Minimum | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Whole ordinary long span | 344,813 | 174,236 | 97.111353 | 0 | 186 |
| Whole second ordinary span | 88,406 | 44,850 | 99.426277 | 6 | 165 |
| Whole dense extended span | 140,493 | 79,263 | 78.873241 | 0 | 1,276 |
| chr20:10,024,501-10,025,500 | 940 | 638 | 121.149000 | 104 | 144 |
| chr20:10,020,001-10,030,000 | 7,040 | 3,745 | 101.980500 | 2 | 148 |
| chr20:20,049,501-20,050,500 | 771 | 555 | 98.808000 | 74 | 120 |
| chr20:20,045,001-20,055,000 | 7,361 | 3,851 | 106.883700 | 57 | 145 |
| chr20:29,892,101-29,893,100 | 3,244 | 2,446 | 385.597000 | 128 | 645 |
| chr20:29,887,601-29,897,600 | 15,753 | 9,496 | 229.120300 | 15 | 774 |

The dense extended span contains low-depth stretches as well as the designated
deep center. Its whole-span average must not be substituted for either dense
benchmark target's depth. All 18 indexed/sequential checks (nine per BAM) and the
587,604-record independent preparation audit passed.

| Artifact | SHA-256 from 2026-11-08 |
| --- | --- |
| Derived approximately 100× BAM | `b5282123828cc68e0048e6c17809e0e811e6cb70b62429018e0fb6119b9aee33` |
| Derived BAI | `b1bb5a7c36b5bf3fb8fd3c5c3b728d4881364e87a45d159d55909c503678c0fd` |
| Expanded unsampled source BAM | `d2c2aba71c005d7b8e8b69841566475ae2c4418105deba15b4d11fa1697b6d08` |
| Expanded source BAI | `4be408f33aa74b94a52b16e17592a3b32abc76e110c136c156c8e09f21d5d815` |

Compressed checksums may change with another zlib version. Compare source pins,
dictionary, exact preparation audit, and profiles as well as compressed bytes.

## Offline reproduction

Create another new directory and copy `source.bam.bai`, `source-README.txt`,
`header.bgzf`, and `source-header-http.txt` into it. Copy or symlink all cached
`range-*.bgzf` and corresponding `range-*.http.txt` files. Do not copy generated
BAMs or `source-offsets.txt`. Then run:

```sh
sh Benchmarks/Data/qualification-acquire.sh .local/measurements/issue-11/data-reproduction --offline
```

Offline mode rejects missing cache inputs and performs no network requests.
The resulting source/derived BAMs, indexes, profiles, selection audit, offsets,
plan, and manifest can be compared directly with the original artifacts.
On 2026-11-08, a separate offline reconstruction produced identical SHA-256
values for all 14 listed artifacts and a byte-identical `SHA256SUMS` file.
Both reconstruction profiles and the independent preparation audit passed.
