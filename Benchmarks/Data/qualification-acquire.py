#!/usr/bin/env python3
"""Prepare the fixed approximately 100x qualification panel, never overwrite it."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import acquire

REGIONS = [(9830400, 10354688), (19988480, 20119552), (29818880, 30081024)]
SEED = 20261108
THRESHOLD = (1 << 64) // 3
MAX_TRANSFER = 300000000
SOURCE_OUTPUT = 'HG002.GRCh38.qualification-source.bam'
OUTPUT = 'HG002.GRCh38.qualification-100x.bam'


def identity(record, source_offset):
    """Use exact RG/QNAME bytes, retaining every record in a named fragment."""
    name_length = record[12]
    cigar_count = struct.unpack_from('<I', record, 16)[0] & 65535
    sequence_length = struct.unpack_from('<i', record, 20)[0]
    qname = record[36:36 + name_length - 1]
    acquire.require(record[36 + name_length - 1] == 0, 'Unterminated QNAME')
    if qname == b'*':
        return b'\x00' + source_offset.to_bytes(8, 'big')
    cursor = 36 + name_length + cigar_count * 4 + (sequence_length + 1) // 2 + sequence_length
    rg = None
    while cursor < len(record):
        acquire.require(cursor + 3 <= len(record), 'Truncated auxiliary tag')
        tag, kind = record[cursor:cursor + 2], chr(record[cursor + 2])
        cursor += 3
        if kind in 'ZH':
            end = record.index(b'\0', cursor)
            value = record[cursor:end]
            cursor = end + 1
        elif kind in 'AcCsSiIfd':
            size = {'A': 1, 'c': 1, 'C': 1, 's': 2, 'S': 2, 'i': 4, 'I': 4, 'f': 4, 'd': 8}[kind]
            value = record[cursor:cursor + size]
            cursor += size
        elif kind == 'B':
            acquire.require(cursor + 5 <= len(record), 'Truncated auxiliary array')
            subtype = chr(record[cursor])
            count = struct.unpack_from('<I', record, cursor + 1)[0]
            size = {'c': 1, 'C': 1, 's': 2, 'S': 2, 'i': 4, 'I': 4, 'f': 4}[subtype]
            value = None
            cursor += 5 + count * size
        else:
            raise ValueError(f'Unknown auxiliary type {kind}')
        acquire.require(cursor <= len(record), 'Truncated auxiliary value')
        if tag == b'RG':
            acquire.require(kind == 'Z' and rg is None, 'Invalid or duplicate RG')
            rg = value
    name = len(qname).to_bytes(8, 'big') + qname
    return b'\x01' + name if rg is None else b'\x02' + len(rg).to_bytes(8, 'big') + rg + name


def extract(chunks, blocks, reference_id):
    """Retain original source offsets while deduplicating overlapping chunks."""
    records = {}
    candidates = 0
    for first, last in chunks:
        first_block, last_block = first >> 16, last >> 16
        offsets = [offset for offset in sorted(blocks) if first_block <= offset <= last_block]
        acquire.require(offsets and offsets[0] == first_block, 'Missing starting BGZF block')
        data = b''.join(blocks[offset] for offset in offsets)
        cursor = first & 65535
        stop = sum(len(blocks[offset]) for offset in offsets if offset < last_block) + (last & 65535)
        block_index, uncompressed_offset = 0, 0
        while cursor < stop:
            size = struct.unpack_from('<i', data, cursor)[0] + 4
            record = data[cursor:cursor + size]
            acquire.require(size >= 36 and len(record) == size, 'Truncated BAM record')
            tid, position, bin_mapq_name, flags_cigar = struct.unpack_from('<iiII', record, 4)
            cigar = struct.unpack_from('<' + 'I' * (flags_cigar & 65535), record, 36 + (bin_mapq_name & 255))
            end = position + sum(op >> 4 for op in cigar if (op & 15) in (0, 2, 3, 7, 8))
            if tid == reference_id and any(position < high and max(position + 1, end) > low for low, high in REGIONS):
                while uncompressed_offset + len(blocks[offsets[block_index]]) <= cursor:
                    uncompressed_offset += len(blocks[offsets[block_index]])
                    block_index += 1
                source_offset = (offsets[block_index] << 16) + cursor - uncompressed_offset
                records[source_offset] = (position, record)
            cursor += size
            candidates += 1
        acquire.require(cursor == stop, 'BAI chunk ended inside a BAM record')
    return sorted(((offset, position, record) for offset, (position, record) in records.items()), key=lambda x: (x[1], x[0])), candidates


def write_bam(path, header, dictionary, records):
    buffer = bytearray(b'BAM\1' + struct.pack('<i', len(header)) + header + dictionary)
    with path.open('xb') as stream:
        for record in records:
            buffer.extend(record)
            while len(buffer) >= 64000:
                stream.write(acquire.encode_bgzf(buffer[:64000]))
                del buffer[:64000]
        if buffer:
            stream.write(acquire.encode_bgzf(buffer))
        stream.write(acquire.encode_bgzf(b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--plan', action='store_true')
    arguments = parser.parse_args()
    directory = arguments.output_directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    acquire.require(arguments.plan or not any((directory / name).exists() for name in [SOURCE_OUTPUT, OUTPUT]),
                    'Choose a new output directory; original BAMs must be preserved')
    initial = [
        ('source.bam.bai', acquire.SOURCE_URL + '.bai', 267072, '942df9668bc25daccf78ec8a0922f742f1e587622272d6801121fcd1631e091b'),
        ('source-README.txt', acquire.BASE_URL + '/README_NHGRI_Novoalign_bams', 1347, '95db9a8a7b7ef5476d4794bce3423d6d7da65f5d9672deb0893c69cd537eca34'),
        ('header.bgzf', acquire.SOURCE_URL, 262144, '8671667598b5c05ee2db751ff539c0c898c3d0b3f8ffb60cfa74fbb18903f15d'),
    ]
    for name, url, size, digest in initial:
        is_header = name == 'header.bgzf'
        acquire.download(directory / name, url, size, arguments.offline,
                         (0, size - 1) if is_header else None,
                         directory / 'source-header-http.txt' if is_header else None)
        acquire.verify_digest(directory / name, digest)
    header, dictionary, references = acquire.read_header(directory / 'header.bgzf')
    (directory / 'source-header.sam').write_bytes(header)
    tid = [name for name, _ in references].index('chr20')
    bins, linear = acquire.read_reference_index(directory / 'source.bam.bai', tid)
    acquire.REGIONS = REGIONS
    chunks = acquire.selected_chunks(bins, linear)
    ranges = acquire.byte_ranges(chunks)
    transfer = sum(end - start + 1 for start, end in ranges) + sum(item[2] for item in initial)
    acquire.require(transfer < MAX_TRANSFER, 'Planned transfer exceeds 300 MB cap')
    plan = {'regions_0based_halfopen': REGIONS, 'ranges': ranges, 'planned_body_bytes': transfer,
            'transfer_cap_bytes': MAX_TRANSFER, 'preparation_seed': SEED, 'threshold_u64_exclusive': THRESHOLD}
    (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    print(json.dumps(plan), flush=True)
    if arguments.plan:
        return
    blocks, checksums = {}, {}
    for index, (start, end) in enumerate(ranges):
        path = directory / f'range-{index}.bgzf'
        headers = directory / f'range-{index}.http.txt'
        acquire.download(path, acquire.SOURCE_URL, end - start + 1, arguments.offline, (start, end), headers)
        acquire.require(path.stat().st_size == end - start + 1, 'Incorrect range size')
        response = headers.read_text().lower()
        acquire.require(f'content-range: bytes {start}-{end}/{acquire.SOURCE_SIZE}' in response, 'Wrong Content-Range')
        acquire.require(f'etag: "{acquire.SOURCE_ETAG}"' in response, 'Source ETag changed')
        checksums[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        blocks.update(acquire.bgzf_blocks(path.read_bytes(), start))
    records, candidates = extract(chunks, blocks, tid)
    del blocks
    keep, groups = [], {}
    seed = SEED.to_bytes(8, 'big')
    with (directory / 'source-offsets.txt').open('x') as offsets:
        for offset, _, record in records:
            key = identity(record, offset)
            selected = int.from_bytes(hashlib.sha256(seed + key).digest()[:8], 'big') < THRESHOLD
            previous = groups.setdefault(key, [selected, 0])
            acquire.require(previous[0] == selected, 'Inconsistent fragment selection')
            previous[1] += 1
            keep.append(selected)
            offsets.write(f'{offset}\n')
    header = header.replace(b'@HD\tVN:1.0\tSO:unsorted', b'@HD\tVN:1.0\tSO:coordinate')
    source_header = header + b'@PG\tID:bamdalf-qualification-source\tPN:qualification-acquire.py\tVN:1\tDS:Bounded complete regional extraction; no filtering.\n'
    derived_header = source_header + f'@PG\tID:bamdalf-qualification-100x\tPN:qualification-acquire.py\tVN:1\tDS:SHA256 fragment retention below floor(2^64/3); preparation seed {SEED}.\n'.encode()
    write_bam(directory / SOURCE_OUTPUT, source_header, dictionary, (item[2] for item in records))
    write_bam(directory / OUTPUT, derived_header, dictionary, (item[2] for item, selected in zip(records, keep) if selected))
    for name in [SOURCE_OUTPUT, OUTPUT, 'source-offsets.txt', 'source-header.sam', 'plan.json'] + [item[0] for item in initial]:
        checksums[name] = hashlib.sha256((directory / name).read_bytes()).hexdigest()
    manifest = dict(plan, source_url=acquire.SOURCE_URL, source_size=acquire.SOURCE_SIZE, source_etag=acquire.SOURCE_ETAG,
                    source_profile='HG002 Illumina HiSeq 300x; 2x148bp; Novoalign3.02.07; GRCh38 no-alt plus hs38d1',
                    reference_contigs=len(references), reference_dictionary_sha256=hashlib.sha256(dictionary).hexdigest(),
                    source_records=len(records), decoded_candidate_records=candidates, retained_records=sum(keep),
                    source_groups=len(groups), retained_groups=sum(value[0] for value in groups.values()),
                    max_source_group_records=max(value[1] for value in groups.values()),
                    max_retained_group_records=max(value[1] for value in groups.values() if value[0]),
                    unnamed_source_records=sum(key[0] == 0 for key in groups), sha256=checksums)
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({key: value for key, value in manifest.items() if key not in ['ranges', 'sha256']}), flush=True)


if __name__ == '__main__':
    main()
