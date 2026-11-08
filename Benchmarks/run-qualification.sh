#!/bin/sh
# Preserve the exact input protocol, native results, source and process metadata.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo 'usage: run-qualification.sh PROTOCOL.json NEW_OUTPUT_DIRECTORY [CASE_ID]' >&2
    exit 2
fi
protocol=$1
out=$2
if [ -e "$out" ]; then
    echo 'Choose a new output directory to preserve measurement evidence.' >&2
    exit 2
fi
binary_dir=$(swift build -c release --show-bin-path)
executable="$binary_dir/Qualification"
if [ ! -x "$executable" ]; then
    echo 'Build the release Qualification product before starting a measurement.' >&2
    exit 2
fi
mkdir -p "$out"
{
    date -u '+%Y-%m-%dT%H:%M:%SZ'
    sw_vers
    uname -m
    sysctl -n machdep.cpu.brand_string
    sysctl -n hw.memsize
    swift --version
    git rev-parse HEAD
    git status --short
} > "$out/environment.txt"
git diff HEAD -- Sources Package.swift Benchmarks > "$out/worktree.patch"
shasum -a 256 "$protocol" "$executable" Sources/BamdalfKit/*.swift Sources/CBAM/CBAM.c \
    Sources/CBAM/include/CBAM.h Package.swift Benchmarks/Qualification.swift \
    Benchmarks/run-qualification.sh > "$out/source-input-executable-sha256.txt"
python3 - "$protocol" "$out" <<'PY'
import hashlib,json,pathlib,shutil,sys
protocol=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2])
plan=json.loads(protocol.read_text())
rows=[]
for bam in sorted({entry['bam'] for entry in plan['cases']}):
    for path in [pathlib.Path(bam)]+sorted(pathlib.Path(bam).parent.glob(pathlib.Path(bam).name+'.*')):
        if path.suffix not in ['.bam','.bai','.csi']: continue
        digest=hashlib.sha256()
        with path.open('rb') as file:
            for chunk in iter(lambda: file.read(1024*1024),b''): digest.update(chunk)
        digest=digest.hexdigest()
        rows.append({'path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':digest})
(root/'data-sha256.json').write_text(json.dumps(rows,indent=2)+'\n')
snapshot=root/'source-snapshot';snapshot.mkdir()
for directory in ['Sources','Benchmarks']:
    shutil.copytree(directory,snapshot/directory)
shutil.copyfile('Package.swift',snapshot/'Package.swift')
PY
if [ "$#" -eq 3 ]; then
    /usr/bin/time -l "$executable" "$protocol" "$out/native" "$3" > "$out/stdout.txt" 2> "$out/time.txt"
else
    /usr/bin/time -l "$executable" "$protocol" "$out/native" > "$out/stdout.txt" 2> "$out/time.txt"
fi
python3 - "$out" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1])
complete=json.loads((root/'native/completion.json').read_text())
if complete.get('completed') is not True: raise SystemExit('Missing native completion')
match=re.search(r'^\s*(\d+)\s+maximum resident set size\s*$',(root/'time.txt').read_text(),re.MULTILINE)
if not match: raise SystemExit('Missing process peak RSS')
complete['external_process_peak_resident_bytes']=int(match.group(1))
(root/'completion.json').write_text(json.dumps(complete,indent=2)+'\n')
print('Completed',len(complete['cases']),'cases; peak RSS',match.group(1),'bytes')
PY
