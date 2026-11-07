#!/usr/bin/env python3
"""Extract two real GIAB regions using bounded BAI-directed HTTP byte ranges.

The source records remain byte-for-byte unchanged. Only the BAM header's sort
order and extraction provenance are updated before deterministic recompression.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib

BASE_URL = (
    'https://giab.s3.amazonaws.com/data/AshkenazimTrio/HG002_NA24385_son/'
    'NIST_HiSeq_HG002_Homogeneity-10953946/'
    'NHGRI_Illumina300X_AJtrio_novoalign_bams'
)
SOURCE_NAME = 'HG002.GRCh38.300x_chr20.bam'
SOURCE_URL = BASE_URL + '/' + SOURCE_NAME
SOURCE_SIZE = 12100052820
SOURCE_ETAG = 'cf5c661b132e291c32be4c3805be3f60-91'
REGIONS = [(9994240, 10059776), (29884416, 29900800)]  # zero-based, half-open
MAX_TRANSFER = 30000000
OUTPUT_NAME = 'HG002.GRCh38.regions.bam'
PROVENANCE = (
    b'@PG\tID:bamdalf-regional-extract\tPN:acquire.py\tVN:1\tDS:'
    b'Bounded HTTP-range extraction; sorted by reference position and source offset; '
    b'no record filtering or downsampling.\n'
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def download(path, url, maximum_size, offline, byte_range=None, headers=None):
    if path.exists():
        return
    if offline:
        raise FileNotFoundError(f'Offline cache is missing {path}')
    command = ['curl', '-fsSL', '--max-time', '90', '--max-filesize', str(maximum_size)]
    if byte_range is not None:
        command += ['--range', f'{byte_range[0]}-{byte_range[1]}']
    if headers is not None:
        command += ['-D', str(headers)]
    # Partial responses never become reusable cache files after a failed request.
    temporary = path.with_name(path.name + '.partial')
    subprocess.run(command + [url, '-o', str(temporary)], check=True)
    temporary.replace(path)


def verify_digest(path, expected):
    observed = hashlib.sha256(path.read_bytes()).hexdigest()
    require(observed == expected, f'Source digest mismatch: {path}')


def bgzf_blocks(data, base_offset=0):
    """Yield complete BGZF blocks; a range may end with a partial padded block."""
    offset = 0
    while offset + 18 <= len(data):
        block_size = struct.unpack_from('<H', data, offset + 16)[0] + 1
        if offset + block_size > len(data):
            break
        yield base_offset + offset, zlib.decompress(data[offset:offset + block_size], 31)
        offset += block_size


def read_header(path):
    raw = b''.join(block for _, block in bgzf_blocks(path.read_bytes()))
    require(raw[:4] == b'BAM\1', 'Invalid BAM header magic')
    text_length = struct.unpack_from('<i', raw, 4)[0]
    header = raw[8:8 + text_length]
    offset = dictionary_start = 8 + text_length
    reference_count = struct.unpack_from('<i', raw, offset)[0]
    offset += 4
    references = []
    for _ in range(reference_count):
        name_length = struct.unpack_from('<i', raw, offset)[0]
        offset += 4
        name = raw[offset:offset + name_length - 1].decode()
        offset += name_length
        length = struct.unpack_from('<i', raw, offset)[0]
        offset += 4
        references.append((name, length))
    return header, raw[dictionary_start:offset], references


def read_reference_index(path, wanted_reference):
    data = path.read_bytes()
    require(data[:4] == b'BAI\1', 'Invalid BAI magic')
    offset = 8
    for reference in range(struct.unpack_from('<i', data, 4)[0]):
        bin_count = struct.unpack_from('<i', data, offset)[0]
        offset += 4
        bins = {}
        for _ in range(bin_count):
            bin_number, chunk_count = struct.unpack_from('<Ii', data, offset)
            offset += 8
            bins[bin_number] = [struct.unpack_from('<QQ', data, offset + 16 * i)
                                for i in range(chunk_count)]
            offset += 16 * chunk_count
        interval_count = struct.unpack_from('<i', data, offset)[0]
        offset += 4
        linear = struct.unpack_from('<' + 'Q' * interval_count, data, offset)
        offset += 8 * interval_count
        if reference == wanted_reference:
            return bins, linear
    raise ValueError('Reference is missing from BAI')


def overlapping_bins(start, end):
    """BAI reg2bins from the SAM/BAM specification; end is exclusive."""
    end -= 1
    bins = [0]
    for first_bin, shift in [(1, 26), (9, 23), (73, 20), (585, 17), (4681, 14)]:
        bins.extend(range(first_bin + (start >> shift), first_bin + (end >> shift) + 1))
    return bins


def selected_chunks(bins, linear):
    chunks = []
    for start, end in REGIONS:
        minimum_offset = linear[min(start >> 14, len(linear) - 1)]
        for bin_number in overlapping_bins(start, end):
            chunks.extend((max(first, minimum_offset), last)
                          for first, last in bins.get(bin_number, []) if last > minimum_offset)
    merged = []
    for first, last in sorted(chunks):
        if merged and first <= merged[-1][1]:
            merged[-1][1] = max(last, merged[-1][1])
        else:
            merged.append([first, last])
    return merged


def byte_ranges(chunks):
    ranges = []
    for first, last in chunks:
        start, end = first >> 16, (last >> 16) + 65535
        if ranges and start <= ranges[-1][1] + 1:
            ranges[-1][1] = max(end, ranges[-1][1])
        else:
            ranges.append([start, end])
    return ranges


def extract_records(chunks, blocks, reference_id):
    records = {}
    candidates = 0
    for first, last in chunks:
        first_block, last_block = first >> 16, last >> 16
        offsets = [offset for offset in sorted(blocks) if first_block <= offset <= last_block]
        require(offsets and offsets[0] == first_block, 'Missing starting BGZF block')
        data = b''.join(blocks[offset] for offset in offsets)
        cursor = first & 65535
        stop = sum(len(blocks[offset]) for offset in offsets if offset < last_block) + (last & 65535)
        while cursor < stop:
            record_size = struct.unpack_from('<i', data, cursor)[0] + 4
            record = data[cursor:cursor + record_size]
            require(record_size >= 36 and len(record) == record_size, 'Truncated BAM record')
            record_reference, position, bin_mapq_name, flags_cigar = struct.unpack_from('<iiII', record, 4)
            cigar_count, name_length = flags_cigar & 65535, bin_mapq_name & 255
            cigar = struct.unpack_from('<' + 'I' * cigar_count, record, 36 + name_length)
            reference_end = position + sum(operation >> 4 for operation in cigar
                                           if (operation & 15) in (0, 2, 3, 7, 8))
            if record_reference == reference_id and any(
                position < end and max(position + 1, reference_end) > start
                for start, end in REGIONS
            ):
                # Deduplicate overlapping index chunks by source virtual offset,
                # never by read name or bytes: identical distinct records survive.
                uncompressed_offset = 0
                for block_offset in offsets:
                    if uncompressed_offset + len(blocks[block_offset]) > cursor:
                        virtual_offset = (block_offset << 16) + cursor - uncompressed_offset
                        records[virtual_offset] = (position, record)
                        break
                    uncompressed_offset += len(blocks[block_offset])
            cursor += record_size
            candidates += 1
        require(cursor == stop, 'BAI chunk ended inside a BAM record')
    ordered = [value[1] for _, value in sorted(records.items(), key=lambda item: (item[1][0], item[0]))]
    return ordered, candidates


def encode_bgzf(data):
    compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
    payload = compressor.compress(data) + compressor.flush()
    block_size = 18 + len(payload) + 8
    require(block_size <= 65536, 'BGZF output block is too large')
    return (bytes.fromhex('1f8b08040000000000ff060042430200')
            + struct.pack('<H', block_size - 1) + payload
            + struct.pack('<II', zlib.crc32(data), len(data)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--offline', action='store_true', help='Require all source range files in the output cache')
    parser.add_argument('--plan', action='store_true', help='Read metadata/index and print the bounded range plan only')
    arguments = parser.parse_args()
    directory = arguments.output_directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    output = directory / OUTPUT_NAME
    require(arguments.plan or not output.exists(), 'Output BAM already exists; choose a new directory to preserve it')
    initial_files = [
        ('source.bam.bai', SOURCE_URL + '.bai', 267072,
         '942df9668bc25daccf78ec8a0922f742f1e587622272d6801121fcd1631e091b'),
        ('source-README.txt', BASE_URL + '/README_NHGRI_Novoalign_bams', 1347,
         '95db9a8a7b7ef5476d4794bce3423d6d7da65f5d9672deb0893c69cd537eca34'),
        ('header.bgzf', SOURCE_URL, 262144,
         '8671667598b5c05ee2db751ff539c0c898c3d0b3f8ffb60cfa74fbb18903f15d'),
    ]
    for name, url, size, digest in initial_files:
        is_header = name == 'header.bgzf'
        download(directory / name, url, size, arguments.offline,
                 (0, size - 1) if is_header else None,
                 directory / 'source-header-http.txt' if is_header else None)
        verify_digest(directory / name, digest)
    header, dictionary, references = read_header(directory / 'header.bgzf')
    (directory / 'source-header.sam').write_bytes(header)
    reference_id = [name for name, _ in references].index('chr20')
    bins, linear = read_reference_index(directory / 'source.bam.bai', reference_id)
    chunks = selected_chunks(bins, linear)
    ranges = byte_ranges(chunks)
    transfer_bytes = sum(end - start + 1 for start, end in ranges)
    require(transfer_bytes + sum(item[2] for item in initial_files) < MAX_TRANSFER,
            'Refusing planned transfer above 30 MB cap')
    print(json.dumps({'regions_0based': REGIONS, 'chunks': len(chunks), 'ranges': ranges,
                      'planned_range_bytes': transfer_bytes}), flush=True)
    if arguments.plan:
        return
    blocks = {}
    for index, (start, end) in enumerate(ranges):
        path = directory / f'range-{index}.bgzf'
        headers = directory / f'range-{index}.http.txt'
        download(path, SOURCE_URL, end - start + 1, arguments.offline, (start, end), headers)
        require(path.stat().st_size == end - start + 1, 'Incorrect byte-range response size')
        response = headers.read_text().lower()
        require(f'content-range: bytes {start}-{end}/{SOURCE_SIZE}' in response,
                'HTTP server did not return the requested range')
        require(f'etag: "{SOURCE_ETAG}"' in response, 'Source ETag changed')
        blocks.update(bgzf_blocks(path.read_bytes(), start))
    records, candidates = extract_records(chunks, blocks, reference_id)
    header = header.replace(b'@HD\tVN:1.0\tSO:unsorted', b'@HD\tVN:1.0\tSO:coordinate') + PROVENANCE
    uncompressed = b'BAM\1' + struct.pack('<i', len(header)) + header + dictionary + b''.join(records)
    with output.open('wb') as stream:
        for offset in range(0, len(uncompressed), 64000):
            stream.write(encode_bgzf(uncompressed[offset:offset + 64000]))
        stream.write(encode_bgzf(b''))
    manifest = {
        'source_url': SOURCE_URL,
        'source_profile': 'HG002 GRCh38 300x chr20, Illumina HiSeq 2x148 bp, Novoalign 3.02.07',
        'reference_contigs': len(references),
        'reference_dictionary_sha256': hashlib.sha256(dictionary).hexdigest(),
        'regions_0based_halfopen': REGIONS,
        'downloaded_range_bytes': transfer_bytes,
        'extracted_records': len(records), 'candidate_records': candidates,
        'source_ranges': ranges,
        'subset_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'subset_bytes': output.stat().st_size,
    }
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest), flush=True)


if __name__ == '__main__':
    main()
