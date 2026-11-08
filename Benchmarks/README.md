# Native alignment visibility baseline

`VisibilityBaseline` measures the actual viewer session, window controller, and alignment `NSView` using a local indexed BAM. It is a measurement executable, not a renderer implementation or a correctness test. It sets the session's visibility limit to `Int64.max` so candidate widths remain measurable after the application default is selected. Its three-argument form also explicitly disables sampling with an unlimited group budget, preserving the original visibility comparison after the app's sampling default is selected.

Build and run from repository root, with the project HTSlib bootstrap already completed:

```sh
swift build -c release --product VisibilityBaseline
sh Benchmarks/run-visibility-baseline.sh \
  .local/measurements/issue-5/data/HG002.GRCh38.regions.bam \
  .local/measurements/issue-5/native-baseline
```

The runner's coordinates are intentionally specific to the public regional HG002 fixture. The self-contained [data acquisition recipe](Data/README.md) provides checked-in extraction/profile scripts, public source/reference provenance, complete intervals, expected counts, and digests. Prepare it with `sh Benchmarks/Data/acquire.sh .local/measurements/issue-5/data` before running the benchmark; choose a fresh output directory when preserving an existing acquisition. The ordinary center is chr20:10,025,000, with widths 150, 500, 1,000, 5,000, 10,000, and 50,000 bases. The deeper center is chr20:29,892,600, with the same widths through 10,000 only. Each of these 11 cases runs in three separate processes. Do not use the runner with another BAM without adapting and documenting the loci.

The executable opens a real 1,100 × 720 point light-appearance window for each process. Run it in an interactive macOS session, separately from native UI tests or other work that manipulates these windows. No screen recording permissions or external UI-control binding are required. A single-case smoke run is:

```sh
binary_dir=$(swift build -c release --show-bin-path)
"$binary_dir/VisibilityBaseline" \
  .local/measurements/issue-5/data/HG002.GRCh38.regions.bam \
  chr20:10024501-10025500 \
  .local/measurements/issue-5/smoke/ordinary-1000
```

## Measurements and boundaries

- File-open wall time is separate from interval loading.
- Query/packing/native-layout wall and process-CPU times start immediately before `session.submitInterval()` and end after its returned task completes and the actual content view lays out. The controller subscribes through the ordinary presentation callback. These measurements include synchronous presentation and layout work; they do not isolate HTSlib I/O from Swift record construction or packing.
- The actual renderer is obtained through the window's public `NSScrollView.documentView`. Its `draw(_:)` method is called five times into a bitmap of the visible viewport at the window's real backing scale. Per-draw CPU and wall times include rasterization and context flushing; allocation, PNG encoding, full-content caching, compositor presentation, and frame scheduling are excluded. Each process records all five values and their mean, so first-draw effects remain visible.
- Peak RSS comes from macOS `/usr/bin/time -l` and is recorded in **bytes**. It is the whole process maximum, including startup, file open, loading, rendering, and both image exports. It is not incremental BAM memory or a renderer-only peak.
- Every case starts with a new process/session and has no application cache or prior successful view. OS filesystem caches are uncontrolled: this is not a cold-disk benchmark. Cases run sequentially in a fixed order and are not statistically independent machine-performance samples.
- With three arguments, no sampling is performed. An optional fourth positive integer sets a measurement-only group budget; all comparisons use seed 42 and the actual session sampler. Only the top visible rows are rasterized. Full-depth inspection requires vertical scrolling and is not timed here.

## Sampling-budget comparison

The [sampling runner](run-sampling-baseline.sh) compares budgets 500, 1,000, 2,000, 5,000, and unlimited at both public loci with 1 kb and 10 kb targets. It requires the exact documented HG002 regional BAM digest, writes to a new output directory, and runs three fresh processes per combination (60 total). Run it separately from tests, builds, and other native-window work:

```sh
swift build -c release --product VisibilityBaseline
sh Benchmarks/run-sampling-baseline.sh \
  .local/measurements/issue-5/data/HG002.GRCh38.regions.bam \
  .local/measurements/issue-7/sampling-baseline
```

The independent [HTSlib profiler](Data/profile-sampling.c) enumerates complete indexed candidates before timing. It records decoded and eligible record counts; the runner counts exact RG/QNAME groups and rejects unexpected identity namespaces in this fixed input. The actual session query closure records query calls, eligible records returned, and reader elapsed time. Those counts must match the profile, and retained groups must equal `min(B, N)`, before results are summarized. This is measurement validation on these data, not a substitute for identity/selection tests.

JSON and CSV retain complete candidate/retained counts, query work, downsampling state, rows, native load/draw timings, and process peak RSS. The sampler still retrieves complete candidates. Neither the group budget nor reduced retained counts imply a bound on decoding work or total memory. The source is the early documented 300× input, not the final approximately 100× qualification panel. See the [initial sampling measurements](../docs/performance/sampling-2026-11-08.md) for the resulting default and its limits.

Per-run JSON records coordinates, counts, row count, timings, viewport size, scale, points per base, median drawn extent, image paths, and basic machine details. The runner retains process output and `time` logs, adds peak RSS to the primary JSON, and writes `results.csv` and `summary.json` with median/minimum/maximum across the three processes. `environment.txt`, `worktree.patch`, and input/executable/source SHA-256 values identify the run's code and environment. An error or suppressed/empty alignment result stops the runner instead of silently becoming a fast measurement.

## Native readability evidence

The primary `.alignments.png` file is produced directly by the actual alignment view's drawing method, preserving its real geometry, colors, symbols, clipping, and viewport scale. Inspect representative ordinary and deeper images at all candidate widths before deciding readability. Record visual findings separately from timing measurements: point/base scale alone does not establish legibility.

The supplementary `.content.png` is an AppKit `cacheDisplay` capture of the complete window content. Some AppKit configurations can omit static or layer-backed content in this capture. Inspect it before treating it as a complete window screenshot; the reliable renderer-only capture and separate native field/ruler checks provide the baseline if full content is incomplete. Neither image is a compositor-level screenshot.

This harness does not establish final 100× WGS qualification, all-contig retrieval completeness, navigation continuity, scrolling frame rates, energy usage, or comparative performance against another genome viewer. The HG002 early fixture has documented 300× source coverage and substantially different observed local depths. Interpret results within its recorded profile and regional limits.
