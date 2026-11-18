# Human-reference storage experiment, 2026-11-18

**Select platform SQLite with 64 KiB uncompressed ASCII chunks.** On the
3.106-billion-base human assembly, the resulting file occupied 1.00846 bytes
per base. Opening validated all 2,580 contig descriptors in under 9.1 ms
on this route. The [v1 format contract](../reference-format.md) defines the
portable file. The [experiment](../../Benchmarks/ReferenceFormat/measure.py)
runs separately from the application.

## Results

Sequential creation and probing in 64, 256, 256, 64 KiB order on the internal
disk of an Apple M4 (arm64, 16 GiB RAM), macOS 27.2.1 (26B131). Each row covers
one complete creation and 102 fresh-handle opens, first reads, and immediate
rereads. Latencies show nearest-rank p95 for that row. RSS is Darwin
`ru_maxrss`, measured for the entire isolated creator process.

| Chunk / trial | Create (s) | Peak RSS (MiB) | Final bytes | Open (ms) | First read (ms) | Reread (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 KiB / A | 19.678 | 103.09 | 3,131,998,208 | 3.085 | 1.060 | 0.084 |
| 256 KiB / A | 18.463 | 103.88 | 3,113,811,968 | 3.194 | 1.137 | 0.181 |
| 256 KiB / B | 18.778 | 103.47 | 3,113,811,968 | 3.600 | 1.585 | 0.213 |
| 64 KiB / B | 29.286 | 102.62 | 3,131,998,208 | 3.209 | 2.361 | 0.084 |

All 3,105,715,063 bases were imported. All 2,580 names, lengths and computed
M5s matched the publisher's index and FASTA headers. All 408 first reads and
408 repeats matched independent reads from the original FASTA. The 102
expected intervals in route order had concatenated SHA-256
`39c2624a150fc3b42604dff69237bce22a16b1208bdc0dae562f1a1fab0553fb`.
The query planner used an integer primary-key range lookup. For intervals up
to 10 kb the largest observed application payload was two rows, 131,072 bytes
at 64 KiB and 524,288 bytes at 256 KiB. These counts measure BLOB payload.
The OS and SQLite may read other pages.

The smaller chunks used 18,186,240 extra bytes (0.58% of the larger-chunk
file). They cut first-read median latency from 0.173–0.185 ms to
0.056–0.059 ms and reduced reread p95 in both trials. First-read p95 varied
with trial order, with the slowest value in the final 64 KiB trial. That
trial also had the slowest creation at 29.3 s. The run did not isolate
the cause. The smaller worst-case payload and consistently faster rereads
favor 64 KiB for repeated short viewer requests. An indexed binary alternative could use a fixed-endian versioned
header, a contig directory with checked offsets/lengths/M5, and concatenated
ASCII bases read via positioned I/O. Its raw payload alone would need
3,105,715,063 bytes, giving a maximum saving of 26,283,145 bytes (0.84% of
the selected file) before its directory. It could read a narrower byte range,
but would require new directory, validation and extension machinery. The
measured SQLite sizes, first-read p95 and bounded row counts resolve this selection.
No binary candidate was timed.

## Proposed production qualification limits

For agreement before [issue #56](https://github.com/micknudsen/bamdalf/issues/56),
the proposed gates apply to this pinned FASTA, machine and local disk.

- In each of two complete creations, finish within **60 seconds**, including
  validation, commit, close, structural reopen and publication. Use a fresh
  release process without a BAM. Record **at most 256 MiB total peak creator
  process RSS** and a final file **at most 1.02 bytes per input base**.
- For 102 fresh reference handles, require **validated open p95 at most 50 ms**.
  Start at the accepted URL and end when the full dictionary and checked
  indexes are available. Exclude human picker time. Report OS cache conditions.

These proposed allowances leave about 2× the slower creation, 2.5× observed
peak RSS, over 10× the slower open p95 and about 1.1% file-size headroom for
native integration. Freeze the integrated protocol, including cache state,
before qualification. The native reference-enabled, reference-only, and
BAM-only viewer measurements remain separate work. This experiment measures
storage calls and includes neither AppKit latency nor compositor performance.

## Input and reproduction

The input is the NCBI GRCh38 no-alt plus hs38d1 analysis set used by the
[GIAB WGS workload](../../Benchmarks/Data/README.md). Source size is
874,637,925 compressed bytes and 3,150,409,646 uncompressed bytes. The
publisher lists compressed MD5 `a056c57649f3c9964c68aead3849bbf8`.
[NCBI source files and checksums](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/)

Use a new empty directory on local disk, with about 17 GB available to retain
the four results and the inputs. Run from the repository root on macOS.
The FAI serves only as an independent oracle in the probing process.
The candidate importer takes only the uncompressed FASTA.

```sh
set -eu
data=$(mktemp -d)
stem=GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna
base=https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids
curl -fL "$base/$stem.gz" -o "$data/$stem.gz"
curl -fL "$base/$stem.fai" -o "$data/publisher.fai"
test "$(md5 -q "$data/$stem.gz")" = a056c57649f3c9964c68aead3849bbf8
gzip -dc "$data/$stem.gz" > "$data/$stem"
(
  cd "$data"
  shasum -a 256 -c <<EOF
08959902840a28f410ad1220e36b2a3fbe2cb90beecceb6ea5b050a0e68ed96d  $stem.gz
592502666381c995059a6b4a5dda11e6b1f6b8efeea04e7dacfffe1e0d2f0d25  $stem
e33afb84eb6463b2607798f86c6060e55eb549698c586268d6011f3ce815b122  publisher.fai
EOF
)
exp=Benchmarks/ReferenceFormat
/usr/bin/python3 -m unittest discover -s "$exp"
for trial in 64-a 256-a 256-b 64-b
do
  /usr/bin/python3 "$exp/measure.py" create "$data/$stem" "$data/$trial.bref" "${trial%-*}" > "$data/create-$trial.json"
  /usr/bin/python3 "$exp/measure.py" probe "$data/$stem" "$data/publisher.fai" "$data/$trial.bref" > "$data/probe-$trial.json"
done
```

The [real-file fixture](../../Benchmarks/ReferenceFormat/test_candidate.py)
was specified before implementing the candidate. It pins two literal M5 values
(from OpenSSL on the independently spelled uppercase records), every supported
DNA code in both cases, and exact slices at start, end, and chunk boundaries.
It deletes the source, moves the bundle into a read-only directory, reads it
through a read-only handle, and checks unchanged bytes/mtime and absence of
sidecars at close.

The writer streams FASTA through platform SQLite, validates and commits in a
single transaction, closes, reopens structurally, then publishes to a fresh
destination on the same volume. The timing includes that whole operation.
Each probe prepares source expectations outside its timed section. Its
seeded route (49) reads 1, 80, 1,000 and 10,000 bases on chr1, chr20 and chrX
plus 100-base intervals crossing each candidate's alignment boundary.
Opening uses a new connection and validates the dictionary and chunk index
extrema. The prototype checks core column names and integer primary keys,
then checks metadata values after loading them. Its timings exclude full
declared-type checks and the pre-allocation bounds required of the production
reader. The first read uses that connection and each repeat uses the same
connection. No application cache, memory mapping or OS cache flush was used.
These are app-uncached connections with uncontrolled OS cache after creation
and source verification. The 4 MiB page-cache request, 4 KiB pages, FULL
synchronization and DELETE journal mode were identical for the candidates.

The [observations and SQLite build details](../../Benchmarks/ReferenceFormat/results-v1.json)
record the measured scripts' hashes, Python 3.9.6 (Apple Clang 21.0.0),
SQLite 3.54.0 source ID and compile options, and individual timing samples.
The prototype runs in the system Python interpreter. The release application
must measure its own native paths, cancellation and replacement behavior.
