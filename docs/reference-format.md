# Reference bundle format v2

A closed `.bref` is one SQLite database. Version 2 stores sequences as
case-preserving ASCII in 65,536-byte chunks. This format was selected from the
[whole-human-reference measurements](performance/reference-storage-2026-11-18.md)
for [issue #49](https://github.com/micknudsen/bamdalf/issues/49).

Version 2 adds the required stored bundle name. Version 1 bundles must be
regenerated from their FASTA; there is no migration or filename fallback.
Bundle versions are independent of application release versions.

## Core tables and identity

Use the SQLite application ID `0x42524546` (ASCII BREF), `user_version=2`,
UTF-8 text and ordinary rowid tables. The required columns, in order, are shown
below. Every field after the primary key is required (`NOT NULL`).

| Table | Columns and rules |
| --- | --- |
| `metadata` | `id INTEGER PRIMARY KEY` with exactly one row numbered 1, `source_name TEXT` (source basename), `creator TEXT` (application and version), `created_utc TEXT` (ISO 8601 UTC timestamp), `chunk_bytes INTEGER` (65536), `bundle_name TEXT` (trimmed display name) |
| `contigs` | `id INTEGER PRIMARY KEY` from 1 in source order, `name TEXT UNIQUE COLLATE BINARY`, `length INTEGER` in bases, `m5 TEXT` (32 lowercase hex digits), `first_chunk INTEGER` (inclusive positive chunk ID) |
| `chunks` | `id INTEGER PRIMARY KEY`, `bases BLOB` (raw ASCII) |

Use an extended ISO 8601 UTC timestamp with calendar date, time through seconds,
an optional fractional second, and either `Z` or `+00:00`. For example,
`2026-11-18T06:15:30Z` and `2026-11-18T06:15:30.123456+00:00` are valid.

Store only the source basename, creator and time for provenance. Do not read
a source path during opening or use it as sequence identity. Contig names
are nonempty UTF-8, matched by their exact bytes. No normalization or
case folding applies. The v2 dictionary bounds are 100,000 contigs, 4,096
UTF-8 bytes per name and 16 MiB of name bytes in total. Limit each provenance
field to 4,096 UTF-8 bytes. The measured assembly uses 2,580 contigs. A writer
diagnoses unsupported input before publication.

Trim surrounding whitespace and newlines from the supplied bundle name. Require
a nonblank UTF-8 name of at most 4,096 bytes after trimming. Opening requires
that same bound, valid UTF-8 text and an already-trimmed nonblank name. Preserve
its characters, including slashes and `.bref`; it is a display label, not a
pathname or a sequence compatibility key. Renaming or moving the file does not
change the stored name. The source basename remains separate provenance.

Each contig owns consecutive chunk IDs in source order. The first begins at 1.
A length `L > 0` needs `1 + (L - 1) / 65536` chunks (integer division).
The next contig starts immediately after that range. Positive coordinates,
lengths, and row IDs fit signed 64-bit integers. Check additions and
conversions before use. Each chunk contains exactly 65,536 bases, except
that a contig's last chunk may be shorter. No chunk spans two contigs.

Use the first whitespace-delimited identifier of a FASTA header. Keep bases
from the ASCII DNA alphabet `ACGTRYSWKMBDHVN` and its lowercase equivalents.
Reject an absent name, duplicate name, missing sequence or invalid character.
Support wrapped lines, LF, CRLF and an unterminated final sequence line.
Calculate M5 incrementally over the uppercase sequence alone. For this
validated alphabet this is SAM sequence normalization. Source wrapping,
descriptions, and case do not affect the digest. Payloads retain the original
case. [SAM specification, section 1.3.2](https://samtools.github.io/hts-specs/SAMv1.pdf)

## Opening and reading

Open the file in ordinary SQLite read-only mode. Reject a foreign application
ID, unsupported user version, non-rollback header, incomplete core schema or
invalid metadata. Obsolete or unsupported versions and invalid name metadata
include guidance to regenerate the bundle. Never create or repair a database while viewing. Validate
the required table/column types and integer primary keys. Bound SQLite row
and metadata allocations *before* materializing field values. Check dictionary
order, unique names, positive lengths, M5 syntax, consecutive declared chunk
ranges, and the first and last IDs in the payload index. Query indexed extrema
separately to avoid a full-table scan. Leave individual chunk checks to reads.
Apply SQL limits to untrusted metadata and reject invalid storage classes.
Declared SQLite column types alone do not enforce the required value types.

For a nonempty 0-based half-open interval `[s, e)`, require
`0 <= s < e <= length`. Find chunk IDs `first_chunk + s / 65536` through
`first_chunk + (e - 1) / 65536`. Retrieve these rows by integer primary key
in ascending order. Validate each requested row's ID, BLOB type, length,
and DNA alphabet. Slice to the specified range. A missing row or short read
fails the request. Do not return a partial interval. At most two boundary
chunks contain bases outside the request. The measured implementation uses
a 4 MiB SQLite page cache, disabled mmap and no application chunk cache.
A page-cache setting is separate from total process RSS.

Opening checks structure and index bounds. Regional reads check the data
they touch. A whole-file scan, digest recomputation and custom block
checksums are outside the milestone.

## Publication and future extensions

Use a private staging directory on the destination volume. Select DELETE
rollback journaling. Finish the transaction, close every writer handle, and
reopen read-only for structural validation before publishing the single file.
Keep task-owned journals in staging. Cancellation, parse/read errors or
publication failure preserve an existing destination and clear only task-owned
files. The production workflow protects the active file's identity through
aliases and uses the platform's confirmed replacement flow. For an existing
destination, a coordinated write rechecks the device and inode before the
atomic rename. Coordinated writers serialize this final step. A writer that
bypasses macOS file coordination can still rename a path between the identity
check and the rename. For a fresh destination, exclusive rename rejects any
file that appeared during the import. Readers must work
in a nonwritable directory, without WAL, SHM, an external index or extraction.

A v2 reader may ignore additional ordinary tables with no role in core
interpretation. Future annotation tables can refer to the contig primary key
within this bundle and record their own provenance. Changed sequence encoding,
chunk sizing, coordinate semantics, new required structures, or changed
interpretation of existing fields requires a new user version. Reject that
version before selecting it. A new schema must preserve core meaning to remain
readable as v2. The production [reference-bundle interface](../Sources/BamdalfKit/ReferenceBundle.swift)
uses 1-based inclusive genomic intervals and converts to the file coordinates above.
