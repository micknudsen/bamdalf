"""Single-file SQLite storage experiment. The app does not import this module."""

from contextlib import closing
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import re
import sqlite3
import tempfile

APPLICATION_ID = 0x42524546  # BREF
MAX_CONTIGS = 100_000
MAX_NAME_BYTES = 4096
MAX_DICTIONARY_BYTES = 16 * 1024 * 1024
ALPHABET = b"ACGTRYSWKMBDHVNacgtryswkmbdhvn"
SCHEMA = """
CREATE TABLE metadata (id INTEGER PRIMARY KEY, source_name TEXT NOT NULL,
    creator TEXT NOT NULL, created_utc TEXT NOT NULL, chunk_bytes INTEGER NOT NULL);
CREATE TABLE contigs (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE BINARY,
    length INTEGER NOT NULL, m5 TEXT NOT NULL, first_chunk INTEGER NOT NULL);
CREATE TABLE chunks (id INTEGER PRIMARY KEY, bases BLOB NOT NULL);
"""
REGIONAL_QUERY = """
SELECT id, typeof(bases), length(bases), substr(bases, 1, ?)
FROM chunks WHERE id BETWEEN ? AND ? ORDER BY id
"""


def write_sequences(db, source, chunk_bytes):
    """Stream input, even if a chromosome occupies one unwrapped line."""
    number = 0
    name_bytes = 0
    next_chunk = 1
    name = None
    pending = bytearray()

    def write_chunk(bases):
        nonlocal next_chunk, length
        if bases.translate(None, ALPHABET):
            raise ValueError(f"Unsupported sequence character in {name}")
        digest.update(bases.upper())
        length += len(bases)
        db.execute("INSERT INTO chunks VALUES (?, ?)", (next_chunk, bases))
        next_chunk += 1

    def finish_record():
        if pending:
            write_chunk(pending)
            pending.clear()
        if not length:
            raise ValueError(f"Empty sequence for {name}")
        db.execute("INSERT INTO contigs VALUES (?, ?, ?, ?, ?)",
                   (number, name, length, digest.hexdigest(), first_chunk))

    with source.open("rb") as fasta:
        at_start = True
        while True:
            piece = fasta.readline(65536)
            if not piece:
                break
            is_header = at_start and piece.startswith(b">")
            at_start = piece.endswith(b"\n")
            if is_header:
                if name is not None:
                    finish_record()
                fields = piece[1:].split(None, 1)
                if not fields or (len(piece) == 65536 and not at_start and len(fields) == 1):
                    raise ValueError("Missing or oversized FASTA name")
                name_bytes += len(fields[0])
                if (number >= MAX_CONTIGS or len(fields[0]) > MAX_NAME_BYTES
                        or name_bytes > MAX_DICTIONARY_BYTES):
                    raise ValueError("Contig dictionary exceeds format bounds")
                name = fields[0].decode("utf-8")
                # Continuations of a long description are not sequence.
                while not at_start and piece:
                    piece = fasta.readline(65536)
                    at_start = piece.endswith(b"\n")
                number += 1
                length = 0
                digest = hashlib.md5()
                first_chunk = next_chunk
            else:
                bases = piece.removesuffix(b"\n")
                if at_start or (piece.endswith(b"\r") and fasta.peek(1)[:1] == b"\n"):
                    bases = bases.removesuffix(b"\r")
                if bases and name is None:
                    raise ValueError("Sequence before first FASTA header")
                pending.extend(bases)
                if len(pending) >= chunk_bytes:
                    write_chunk(pending[:chunk_bytes])
                    del pending[:chunk_bytes]
    if name is None:
        raise ValueError("No FASTA records")
    finish_record()


def create(source, destination, chunk_bytes):
    if chunk_bytes not in (65536, 262144):
        raise ValueError("Unknown experimental chunk size")
    with tempfile.TemporaryDirectory(dir=destination.parent) as scratch:
        staged = Path(scratch) / "candidate.bref"
        with closing(sqlite3.connect(staged)) as db:
            db.execute("PRAGMA journal_mode=DELETE")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("PRAGMA page_size=4096")
            db.execute("PRAGMA cache_size=-4096")
            db.execute("PRAGMA mmap_size=0")
            db.execute(f"PRAGMA application_id={APPLICATION_ID}")
            db.execute("PRAGMA user_version=1")
            db.executescript(SCHEMA)
            db.execute("INSERT INTO metadata VALUES (1, ?, ?, ?, ?)",
                       (source.name, "bamdalf-storage-experiment/1",
                        datetime.now(timezone.utc).isoformat(), chunk_bytes))
            write_sequences(db, source, chunk_bytes)
            db.commit()
        with Bundle(staged):
            pass
        os.link(staged, destination)  # Experiment only publishes to a fresh name.


class Bundle:
    def __init__(self, path):
        with path.open("rb") as stream:
            header = stream.read(20)
        if header[:16] != b"SQLite format 3\0" or header[18:] != b"\1\1":
            raise ValueError("Expected a rollback-journal SQLite bundle")
        self.db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
        try:
            self.db.execute("PRAGMA trusted_schema=OFF")
            self.db.execute("PRAGMA mmap_size=0")
            self.db.execute("PRAGMA cache_size=-4096")
            if (self.db.execute("PRAGMA application_id").fetchone() != (APPLICATION_ID,)
                    or self.db.execute("PRAGMA user_version").fetchone() != (1,)):
                raise ValueError("Unsupported bundle identity or version")
            tables = dict(self.db.execute(
                "SELECT name, type FROM sqlite_schema WHERE name IN ('metadata','contigs','chunks')"))
            if tables != {name: "table" for name in ("metadata", "contigs", "chunks")}:
                raise ValueError("Missing required table")
            layouts = {"metadata": ("id", "source_name", "creator", "created_utc", "chunk_bytes"),
                       "contigs": ("id", "name", "length", "m5", "first_chunk"),
                       "chunks": ("id", "bases")}
            for table, columns in layouts.items():
                info = list(self.db.execute(f"PRAGMA table_info({table})"))
                if (tuple(row[1] for row in info) != columns
                        or (info[0][2].upper(), info[0][5]) != ("INTEGER", 1)):
                    raise ValueError("Unexpected core table layout")
            metadata = list(self.db.execute("SELECT * FROM metadata LIMIT 2"))
            if len(metadata) != 1:
                raise ValueError("Expected one metadata record")
            key, source, creator, created, self.chunk_bytes = metadata[0]
            if (key != 1 or not all(isinstance(s, str) and s for s in (source, creator, created))
                    or self.chunk_bytes not in (65536, 262144)):
                raise ValueError("Invalid metadata")
            self.dictionary = {}
            self.first_chunk = {}
            next_chunk = 1
            total_name_bytes = 0
            for idx, name, length, m5, first in self.db.execute("SELECT * FROM contigs ORDER BY id"):
                if (idx != len(self.dictionary) + 1 or not isinstance(name, str) or not name
                        or name in self.dictionary or type(length) is not int or length <= 0
                        or not isinstance(m5, str) or not re.fullmatch("[0-9a-f]{32}", m5)
                        or type(first) is not int or first != next_chunk):
                    raise ValueError("Invalid contig dictionary or chunk range")
                name_size = len(name.encode("utf-8"))
                total_name_bytes += name_size
                if (idx > MAX_CONTIGS or name_size > MAX_NAME_BYTES
                        or total_name_bytes > MAX_DICTIONARY_BYTES):
                    raise ValueError("Oversized contig dictionary")
                self.dictionary[name] = (length, m5)
                self.first_chunk[name] = first
                next_chunk += (length - 1) // self.chunk_bytes + 1
            ends = [self.db.execute("SELECT min(id) FROM chunks").fetchone()[0],
                    self.db.execute("SELECT max(id) FROM chunks").fetchone()[0]]
            if not self.dictionary or ends != [1, next_chunk - 1]:
                raise ValueError("Invalid payload index bounds")
        except BaseException:
            self.db.close()
            raise
        self.payload_bytes = 0
        self.payload_rows = 0

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.db.close()

    def read(self, name, start, stop):
        length, _ = self.dictionary[name]
        if not 0 <= start < stop <= length:
            raise ValueError("Interval outside contig")
        size = self.chunk_bytes
        base = self.first_chunk[name]
        expected_id = base + start // size
        last = base + (stop - 1) // size
        result = bytearray()
        for key, kind, count, bases in self.db.execute(REGIONAL_QUERY, (size, expected_id, last)):
            offset = (key - base) * size
            if (key != expected_id or kind != "blob" or count != min(size, length - offset)
                    or bases.translate(None, ALPHABET)):
                raise ValueError("Invalid sequence chunk")
            self.payload_bytes += count
            self.payload_rows += 1
            result.extend(bases[max(0, start - offset):min(count, stop - offset)])
            expected_id += 1
        if expected_id != last + 1 or len(result) != stop - start:
            raise ValueError("Incomplete interval")
        return bytes(result)
