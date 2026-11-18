# Reference bundle storage investigation

Research date: 2026-11-18. The accepted product behavior is in
[reference-milestone.md](../reference-milestone.md). This note recommends an
engineering candidate; it does not select the format, change product decisions,
or establish performance. No storage prototype, whole-genome benchmark, or
feature implementation was run.

## Recommendation

Prototype **SQLite with bounded sequence BLOB chunks**, using the platform C
library behind a small reference-bundle interface. Compare it with a minimal
indexed binary container only if its measured size, latency, or creation cost
misses the agreed targets. Start with case-preserving, one-byte-per-base ASCII
chunks and no custom compression or block checksums. Chunk size and cache
budgets are measurement candidates, not requirements.

SQLite supports application-specific suffixes, a single-file document model,
and schema extension. Those capabilities fit `.bref` and later annotation
metadata without requiring a bespoke metadata engine. That is a design
inference, not evidence that SQLite will be fast enough for bamdalf.
[SQLite application file formats](https://www.sqlite.org/appfileformat.html)

## Options compared

| Candidate | Fit and tradeoff | Recommendation |
| --- | --- | --- |
| SQLite, sequence chunks plus contig/provenance metadata | Indexed regional lookup, bounded payloads, future tables; requires explicit journaling/read-only configuration and accounting for database overhead | First candidate to measure |
| Small indexed binary container | Header, contig directory, offsets, and raw sequence payloads can satisfy single-file regional access; bamdalf owns bounds checking, byte order, versioning, metadata growth, and all parser behavior | Reserve as a measured alternative |
| Archive containing FASTA and index | Preserves familiar inputs, but an ordinary archive does not itself provide genomic lookup; direct access needs archive-entry offsets plus FASTA indexing or a seekable entry stream | Less attractive for this MVP |

The last two assessments are engineering inferences. A ZIP archive is not
necessarily extraction-only: stored entries can be mapped to their contained
bytes, while compressed entries require a decompression strategy. SQLite's own
ZIP interface exposes entries and distinguishes stored and deflated payloads;
it is an extension, not evidence that platform SQLite includes ZIP support or
provides bounded genomic slicing. Do not adopt it merely to avoid choosing a
container. [SQLite ZIP module](https://www.sqlite.org/zipfile.html)

## Candidate layout and regional access

Proposed logical contents:

- Bundle identity, schema version, creation provenance, and completion state.
- Contig identifier, exact name, source order, length, and normalized sequence MD5.
- Sequence chunks keyed by contig and chunk ordinal, with bounded BLOB payloads.

Use exact bytewise contig-name matching. Preserve source case and valid DNA
ambiguity characters in payloads. Separate payload encoding from biological
identity. Compute regional chunk ordinals arithmetically, fetch only those rows
in explicit order, validate their lengths/coverage, and slice the result to the
requested interval. Stream results rather than collecting every chunk for a
contig. These are proposed implementation rules.

For the first experiment, compare 64 KiB and 256 KiB chunks. For an interval of
length `W` and chunk size `C`, at most `W + 2(C - 1)` bases are covered by its
intersecting chunks; this is an upper-bound calculation, not a measured I/O
cost. Raw one-byte encoding uses `N` payload bytes for `N` bases before database
overhead. It preserves case/ambiguity directly; compact encoding can follow
only if measurements justify its complexity.

SQLite limits individual BLOB/row size, and SELECT/INSERT processing can encode
a complete row. Therefore chunking is needed even though the database itself
can be much larger. SQLite also offers incremental BLOB I/O if measurements
justify reading slices without materializing a bounded chunk; its handle
interface requires rowid tables. It is not necessary for the initial chunked
candidate. [SQLite limits](https://www.sqlite.org/limits.html),
[incremental BLOB interface](https://www.sqlite.org/c3ref/blob_open.html)

Bound the application chunk cache separately from SQLite's page cache. A
negative `cache_size` requests an approximate KiB budget under the built-in
page cache; it is not a process-RSS cap. Start with memory-mapped I/O disabled
to make initial resource accounting easier, then compare only if justified.
[SQLite cache and mapping pragmas](https://www.sqlite.org/pragma.html#cache_size)

## Identity and format validation

SAM `M5` is calculated per reference sequence, not over the FASTA file or BLOB
encoding. SAM normalization removes bytes outside ASCII 33–126, uppercases the
remaining characters in the POSIX locale, and produces a 32-character MD5 hex
digest. Calculate it incrementally during parsing while separately preserving
source case in stored bases. The accepted FASTA validator still rejects
unsupported symbols: the digest algorithm's broader input definition is not
permission to accept them. [SAM specification §1.3.2](https://samtools.github.io/hts-specs/SAMv1.pdf#page=5)

Use a bundle-specific application ID and explicit application schema version;
reject an unrelated database and unsupported versions before selecting it.
SQLite's header has application-ID and user-version fields, distinct from its
own schema-format version. The exact ID and supported-version policy need a
documented format contract. [SQLite database header](https://www.sqlite.org/fileformat2.html#the_database_header)

On opening, validate expected schema/metadata types, positive and bounded
lengths, checked coordinate arithmetic, and declared chunk ranges without
reading every sequence payload. On regional access, verify the required rows,
lengths, and complete interval coverage before returning bases. Query/schema
errors must fail the attempted open/load. These proposed checks implement the
accepted incremental validation boundary; they do not certify the whole file.

Do not run `integrity_check` or `quick_check` automatically on every open:
the former normally checks the entire database and the latter remains an
O(N) check. Neither constitutes biological sequence checksum verification.
Do not add custom payload checksums or scan all contigs to recalculate `M5`.
[SQLite integrity checks](https://www.sqlite.org/pragma.html#integrity_check)

## A single published file, with read-only viewing

Create a private scratch database using rollback **DELETE** journaling, commit
and close it cleanly, and publish only the complete database. Temporary journal
files during creation are compatible with a single final bundle, but must not
become dependencies of that bundle. SQLite explicitly uses temporary files
despite its single-database-file model. Do not use OFF/MEMORY journaling as a
shortcut; avoid trading creation safety for speed before measurement.
[SQLite temporary files](https://www.sqlite.org/tempfiles.html)

Avoid WAL for this document format. A WAL file can contain committed state;
separating it from the database can lose data. Read-only WAL opening may still
require existing or creatable `-wal`/`-shm` files. SQLite recommends converting
to DELETE journaling before read-only distribution. Reject externally changed
WAL-mode bundles rather than silently repairing them during viewing.
[SQLite WAL lifecycle and read-only databases](https://www.sqlite.org/wal.html#read_only_databases)

Open for viewing with `SQLITE_OPEN_READONLY` or correctly encoded `mode=ro`,
never with create-if-missing. `PRAGMA query_only` alone is not a read-only file
open. A finalized rollback-mode database should require no persistent viewing
sidecars; verify that condition in tests, including a nonwritable parent
directory. [SQLite connection opening](https://www.sqlite.org/c3ref/open.html),
[query_only semantics](https://www.sqlite.org/pragma.html#query_only)

Do **not** set `immutable=1` simply because bamdalf promises read-only viewing.
It asserts that other processes cannot change the file and disables locking
and change detection. SQLite warns of incorrect results or corruption errors
if that assertion is false. Ordinary user-owned `.bref` files do not establish
that stronger condition. [SQLite URI parameters](https://www.sqlite.org/uri.html#uriimmutable)

SQLite cannot prevent another process from overwriting an ordinary database
file. Preserve the accepted limited corruption-detection promise and reject
detected read/decode errors; do not advertise reference immutability or full
integrity certification. [SQLite corruption considerations](https://www.sqlite.org/howtocorrupt.html)

## Creation, cancellation, and publication

Proposed sequence: parse and validate source into a private scratch bundle,
check cancellation between bounded parsing/insertion batches, finalize metadata,
commit, close all handles, reopen read-only for bounded structural checks, then
publish at the chosen destination. Cancellation removes only task-owned scratch
artifacts; it must never delete or truncate a preexisting destination. Preserve
the current viewer throughout. Successful creation saves without selecting the
bundle, as already agreed.

SQLite offers a progress callback that can abort long SQL operations and an
interrupt interface with connection-lifetime requirements. Parser/hash loops
still need their own cancellation checks. Avoid promising immediate cancellation
of a blocking filesystem read. [SQLite progress callbacks](https://www.sqlite.org/c3ref/progress_handler.html),
[SQLite interrupt](https://www.sqlite.org/c3ref/interrupt.html)

Stage on the destination volume. Apple's replacement interface requires both
items on the same volume and identifies `itemReplacementDirectory` as an
appropriate staging location. Its error can identify a relocated original
through `NSFileOriginalItemLocationKey`; a thrown error is not proof that the
original remains at its original path. Publication/restore logic and failure
tests must enforce the product's stronger destination-preservation contract.
Treat atomic visibility and power-loss durability as separate engineering
questions, not guaranteed outcomes of choosing SQLite.
[Apple FileManager replacement](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:).md)

## Verification and measurement plan

1. **Correctness before timing:** independently known synthetic sequences with
   every supported ambiguity symbol and case; chunk/contig boundaries; one-base
   intervals; names/lengths/MD5; source deletion after creation; malformed schema,
   missing/oversized chunks, arithmetic overflow, and unknown format versions.
2. **File lifecycle:** ensure exactly one final `.bref` after success, no new
   viewing sidecars or changed bytes/mtime, read-only directory support, and
   refusal to replace the selected file through alternate paths. Fault-inject
   parsing, insertion, cancellation, close, rename/replacement, and restoration.
   An existing destination must retain its original bytes after failed creation.
3. **Resource experiment:** on the recorded M4/16 GiB release-build baseline,
   use a provenance-pinned representative human FASTA. Compare the two chunk
   sizes; record creation time, peak RSS, peak temporary disk usage, final size,
   open latency, first/cached regional latency, sustained-pan/drag responsiveness,
   and cancel-to-cleanup latency. Separate app-cache state from OS-cache claims.
4. **Integrated qualification:** preserve existing representative WGS criteria
   with reference/mismatch rendering, no-reference BAM viewing, and reference-only
   browsing. Archive input hashes, exact source/binary/toolchain, actual SQLite
   version/compile options, query plans, caches, and completion evidence. Do not
   set new creation/opening deadlines until the measurements are reviewed.
5. **Decision:** select SQLite only if measured behavior meets the agreed
   targets with acceptable size and implementation complexity. If not, compare
   a minimal raw indexed container under the same fixtures and protocol before
   adding compression, custom virtual filesystems, or more concurrency.

The local macOS Command Line Tools SDK contains `sqlite3.h` and `libsqlite3.tbd`
at the time of this investigation. This confirms development interfaces in this
checkout's SDK, not a successful SwiftPM link, the deployed runtime version, or
performance. Those remain verification work. Future annotation tables and
indexes are a schema-extension prospect, not part of this milestone.
