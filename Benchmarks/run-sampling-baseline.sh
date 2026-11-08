#!/bin/sh
# Fixed-seed comparisons on the exact previously profiled public HG002 input.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo 'usage: run-sampling-baseline.sh BAM NEW_OUTPUT_DIRECTORY [EXECUTABLE]' >&2
    exit 2
fi
bam=$1
out=$2
if [ -e "$out" ]; then
    echo 'Choose a new output directory to preserve measurement evidence.' >&2
    exit 2
fi
actual=$(shasum -a 256 "$bam" | cut -d ' ' -f 1)
if [ "$actual" != 786c9d3f66ff721d8bbb20bb62c8e055aa589f1e64f930fc8fdfc210e9b689c5 ]; then
    echo 'This runner requires the documented HG002 early regional BAM.' >&2
    exit 2
fi
if [ "$#" -eq 3 ]; then
    executable=$3
else
    executable="$(swift build -c release --show-bin-path)/VisibilityBaseline"
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
shasum -a 256 "$out/worktree.patch" Sources/BamdalfKit/*.swift Sources/CBAM/CBAM.c Sources/CBAM/include/CBAM.h Package.swift > "$out/source-sha256.txt"
shasum -a 256 "$bam" "$bam.bai" "$executable" Benchmarks/VisibilityBaseline.swift Benchmarks/run-sampling-baseline.sh Benchmarks/Data/profile-sampling.c > "$out/input-executable-sha256.txt"
python3 - "$out" <<'PY'
import pathlib,shutil,sys
snapshot=pathlib.Path(sys.argv[1])/'source-snapshot'
snapshot.mkdir()
for directory in ['Sources','Benchmarks']:
    shutil.copytree(directory,snapshot/directory)
shutil.copyfile('Package.swift',snapshot/'Package.swift')
PY
xcrun clang -O2 -I .build/htslib/include Benchmarks/Data/profile-sampling.c .build/htslib/lib/libhts.a -lz -o "$out/profile-sampling"
for region in ordinary deeper; do
    case "$region" in
        ordinary) center=10025000 ;;
        deeper) center=29892600 ;;
    esac
    for width in 1000 10000; do
        start=$((center - width / 2 + 1))
        end=$((start + width - 1))
        "$out/profile-sampling" "$bam" "chr20:$start-$end" > "$out/$region-$width.tsv" 2> "$out/$region-$width.counts.txt"
        for budget in 500 1000 2000 5000 9223372036854775807; do
            for repetition in 1 2 3; do
                prefix="$out/$region-$width-b$budget-r$repetition"
                echo "$region width=$width budget=$budget repetition=$repetition"
                /usr/bin/time -l "$executable" "$bam" "chr20:$start-$end" "$prefix" "$budget" \
                    > "$prefix.stdout.json" 2> "$prefix.time.txt"
            done
        done
    done
done
python3 - "$out" <<'PY'
import collections,csv,json,pathlib,re,statistics,sys
root=pathlib.Path(sys.argv[1])
profiles={}
for path in sorted(root.glob('*.tsv')):
    records=[line.split('\t') for line in path.read_text().splitlines()]
    # Exact pinned input has only named records with absent RG; reject drift.
    if any(record[0]!='<absent>' or record[1]=='*' for record in records):
        raise SystemExit('Unexpected profile identity namespace: '+str(path))
    counts=dict(line.split() for line in path.with_suffix('.counts.txt').read_text().splitlines())
    profiles[path.stem]={'decoded_records':int(counts['decoded_records']),
                         'candidate_records':len(records),
                         'candidate_groups':len({(record[0],record[1]) for record in records})}
rows=[]
for path in sorted(root.glob('*-r[123].json')):
    result=json.loads(path.read_text())
    region,width,budget,repetition=path.stem.split('-')
    match=re.search(r'^\s*(\d+)\s+maximum resident set size\s*$',path.with_suffix('.time.txt').read_text(),re.MULTILINE)
    if not match:
        raise SystemExit('Missing peak RSS: '+str(path))
    profile=profiles[f'{region}-{width}']
    if result['queried_eligible_records']!=profile['candidate_records'] or result['regional_query_calls']!=1:
        raise SystemExit('Incomplete or unexpected query work: '+str(path))
    if result['retained_groups']!=min(result['sampling_group_budget'],profile['candidate_groups']):
        raise SystemExit('Incorrect retained group cardinality: '+str(path))
    result.update(region=region,repetition=int(repetition[1:]),peak_rss_bytes=int(match.group(1)),**profile)
    path.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    rows.append(result)
fields=['region','width_bases','sampling_group_budget','repetition','interval',
        'decoded_records','candidate_records','candidate_groups','retained_groups','alignments','rows',
        'is_downsampled','regional_query_calls','queried_eligible_records','regional_query_wall_ms',
        'query_pack_native_layout_wall_ms','query_pack_native_layout_cpu_ms',
        'renderer_draw_wall_mean_ms','renderer_draw_cpu_mean_ms','peak_rss_bytes',
        'viewport_width_points','viewport_height_points','backing_scale','sampling_seed']
with (root/'results.csv').open('w',newline='') as file:
    writer=csv.DictWriter(file,fieldnames=fields,extrasaction='ignore');writer.writeheader();writer.writerows(rows)
summary=[]
for key in sorted({(row['region'],row['width_bases'],row['sampling_group_budget']) for row in rows}):
    group=[row for row in rows if (row['region'],row['width_bases'],row['sampling_group_budget'])==key]
    entry=dict(region=key[0],width_bases=key[1],sampling_group_budget=key[2],repetitions=len(group))
    for field in ['query_pack_native_layout_wall_ms','regional_query_wall_ms','renderer_draw_cpu_mean_ms','peak_rss_bytes','rows','alignments','retained_groups']:
        values=[row[field] for row in group]
        entry[field+'_median']=statistics.median(values)
        entry[field+'_min']=min(values)
        entry[field+'_max']=max(values)
    summary.append(entry)
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(root/'profile.json').write_text(json.dumps(profiles,indent=2)+'\n')
print('Wrote',len(rows),'measurements to',root/'results.csv')
PY
