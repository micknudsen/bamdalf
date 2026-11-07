#!/bin/sh
# One subprocess per interval/repetition keeps peak RSS attributable to one load.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo 'usage: run-visibility-baseline.sh BAM OUTPUT_DIRECTORY [EXECUTABLE]' >&2
    exit 2
fi
bam=$1
out=$2
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
shasum -a 256 "$bam" "$executable" Benchmarks/VisibilityBaseline.swift Benchmarks/run-visibility-baseline.sh > "$out/input-executable-sha256.txt"
for region in ordinary deeper; do
    case "$region" in
        ordinary) center=10025000; widths='150 500 1000 5000 10000 50000' ;;
        deeper) center=29892600; widths='150 500 1000 5000 10000' ;;
    esac
    for width in $widths; do
        start=$((center - width / 2 + 1))
        end=$((start + width - 1))
        for repetition in 1 2 3; do
            prefix="$out/$region-$width-r$repetition"
            echo "$region width=$width repetition=$repetition chr20:$start-$end"
            /usr/bin/time -l "$executable" "$bam" "chr20:$start-$end" "$prefix" \
                > "$prefix.stdout.json" 2> "$prefix.time.txt"
        done
    done
done
python3 - "$out" <<'PY'
import csv,json,pathlib,re,statistics,sys
root=pathlib.Path(sys.argv[1])
rows=[]
for p in sorted(root.glob('*-r[123].json')):
    result=json.loads(p.read_text())
    region,width,repetition=p.stem.split('-')
    text=p.with_suffix('.time.txt').read_text()
    match=re.search(r'^\s*(\d+)\s+maximum resident set size\s*$',text,re.MULTILINE)
    if not match:
        raise SystemExit('Missing macOS peak-RSS value: '+str(p))
    result.update(region=region,repetition=int(repetition[1:]),peak_rss_bytes=int(match.group(1)))
    p.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    rows.append(result)
fields=['region','width_bases','repetition','interval','alignments','rows',
        'file_open_wall_ms','query_pack_native_layout_wall_ms','query_pack_native_layout_cpu_ms',
        'renderer_draw_wall_mean_ms','renderer_draw_cpu_mean_ms','peak_rss_bytes',
        'viewport_width_points','viewport_height_points','backing_scale','points_per_base',
        'median_drawn_span_bases','renderer_png']
with (root/'results.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');writer.writeheader();writer.writerows(rows)
summary=[]
for region in ['ordinary','deeper']:
    for width in sorted({x['width_bases'] for x in rows if x['region']==region}):
        group=[x for x in rows if x['region']==region and x['width_bases']==width]
        entry=dict(region=region,width_bases=width,repetitions=len(group))
        for field in ['query_pack_native_layout_wall_ms','renderer_draw_wall_mean_ms','renderer_draw_cpu_mean_ms','peak_rss_bytes']:
            values=[x[field] for x in group]
            entry[field+'_median']=statistics.median(values)
            entry[field+'_min']=min(values)
            entry[field+'_max']=max(values)
        summary.append(entry)
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Wrote',len(rows),'measurements to',root/'results.csv')
PY
