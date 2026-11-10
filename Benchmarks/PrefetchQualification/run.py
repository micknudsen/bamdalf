#!/usr/bin/env python3
"""Run locked native qualification cases separately and retain complete provenance."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def archive(out, protocol, executable, plan):
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(protocol, out / 'protocol.json')
    sources = out / 'source'
    sources.mkdir()
    for directory in ['Sources', 'Benchmarks']:
        shutil.copytree(ROOT / directory, sources / directory, ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy2(ROOT / 'Package.swift', sources / 'Package.swift')
    hashes = {str(executable): digest(executable), str(protocol.relative_to(ROOT)): digest(protocol)}
    for path in sorted(sources.rglob('*')):
        if path.is_file():
            hashes[str(path.relative_to(sources))] = digest(path)
    for name in sorted({case['bam'] for case in plan['cases']}):
        path = ROOT / name
        if not path.is_file():
            raise SystemExit(f'Missing input: {path}')
        hashes[name] = digest(path)
        indexes = [index for suffix in ['.bai', '.csi'] if (index := pathlib.Path(str(path) + suffix)).exists()]
        if len(indexes) != 1:
            raise SystemExit(f'Qualification needs exactly one sibling index: {path}')
        hashes[str(indexes[0].relative_to(ROOT))] = digest(indexes[0])
    for name, expected in {**plan['inputs'], **plan['indexes']}.items():
        actual = digest(ROOT / name)
        if actual != expected:
            raise SystemExit(f'Input checksum differs: {name}')
        hashes[name] = actual
    hashes['.build/htslib/lib/libhts.a'] = digest(ROOT / '.build/htslib/lib/libhts.a')
    (out / 'sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
    (out / 'worktree.patch').write_bytes(subprocess.check_output(['git', 'diff', 'HEAD'], cwd=ROOT))
    environment = {'timestamp_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'timezone': 'Europe/Copenhagen'}
    for key, command in {
        'commit': ['git', 'rev-parse', 'HEAD'], 'status': ['git', 'status', '--short'],
        'os': ['sw_vers'], 'cpu': ['sysctl', '-n', 'machdep.cpu.brand_string'],
        'memory': ['sysctl', '-n', 'hw.memsize'], 'swift': ['swift', '--version'],
    }.items():
        environment[key] = subprocess.check_output(command, cwd=ROOT, text=True).strip()
    if environment['cpu'] != 'Apple M4' or environment['memory'] != '17179869184':
        raise SystemExit('Qualification baseline must be the recorded Apple M4 / 16 GiB')
    (out / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')


def observe(executable, protocol, case, directory):
    directory.mkdir()
    command = ['/usr/bin/time', '-l', str(executable), str(protocol), str(directory / 'native'), case['id']]
    (directory / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
    limit = max(180, float(case.get('duration_seconds', 0)) + 180)
    started = time.monotonic()
    next_progress = 60
    with (directory / 'stdout.txt').open('w') as stdout, (directory / 'time.txt').open('w') as stderr:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
        while process.poll() is None:
            elapsed = time.monotonic() - started
            if elapsed > limit:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
                raise SystemExit(f"Case exceeded {limit:g}s safety limit: {case['id']}")
            if elapsed >= next_progress:
                print(f"Running {case['id']}: {elapsed:.0f}s elapsed", flush=True)
                next_progress += 60
            time.sleep(0.25)
    if process.returncode:
        raise SystemExit(f"Case failed ({process.returncode}): {case['id']}; see {directory / 'time.txt'}")
    complete = json.loads((directory / 'native/completion.json').read_text())
    if complete.get('completed') is not True or complete.get('cases') != [case['id']]:
        raise SystemExit(f"Missing exact-case native completion: {case['id']}")
    if complete.get('protocol_sha256') != digest(protocol):
        raise SystemExit(f"Protocol changed during observation: {case['id']}")
    timing = (directory / 'time.txt').read_text()
    for label, key in [('maximum resident set size', 'external_process_peak_resident_bytes'),
                       ('block input operations', 'external_input_block_operations'),
                       ('block output operations', 'external_output_block_operations')]:
        match = re.search(r'^\s*(\d+)\s+' + re.escape(label) + r'\s*$', timing, re.MULTILINE)
        if not match:
            raise SystemExit(f'Missing process metric {label}')
        complete[key] = int(match.group(1))
    (directory / 'completion.json').write_text(json.dumps(complete, indent=2) + '\n')
    print(f"Completed {case['id']}: {time.monotonic() - started:.1f}s; peak RSS {complete['external_process_peak_resident_bytes']} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=pathlib.Path)
    parser.add_argument('protocol', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    parser.add_argument('--case', action='append', help='Run only the named case; repeat as needed')
    args = parser.parse_args()
    protocol, executable, out = args.protocol.resolve(), args.executable.resolve(), args.output.resolve()
    plan = json.loads(protocol.read_text())
    selected = [case for case in plan['cases'] if args.case is None or case['id'] in args.case]
    if not selected or (args.case and set(args.case) != {case['id'] for case in selected}):
        raise SystemExit('Unknown or empty case selection')
    audit = subprocess.check_output(['python3', str(pathlib.Path(__file__).with_name('protocol.py')), str(protocol)], cwd=ROOT)
    archive(out, protocol, executable, plan)
    (out / 'coverage-audit.json').write_bytes(audit)
    for case in selected:
        observe(executable, protocol, case, out / case['id'])
    (out / 'execution-completion.json').write_text(json.dumps({
        'completed': True, 'cases': [case['id'] for case in selected], 'protocol_sha256': digest(protocol),
        'all_protocol_cases': len(selected) == len(plan['cases']),
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
