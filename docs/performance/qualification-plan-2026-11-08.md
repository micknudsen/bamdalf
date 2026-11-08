# MVP qualification plan — 2026-11-08

Accepted by the user in Q103–Q110 and confirmed as a whole on 2026-11-08.
This plan resolves D4. Data preparation, the detailed protocol, and qualification
execution remain work for [issue #11](https://github.com/micknudsen/bamdalf/issues/11),
after its implementation predecessors are complete. No qualification results are
claimed here.

## Machine and build

Qualify on the Apple M4 Mac with 16 GiB RAM used for the
[initial measurements](visibility-2026-11-07.md). Use a release build, record
hardware, exact OS, toolchain, dependency versions, revision, and window/viewport
size, and avoid competing builds/tests during measurement. This baseline does
not promise identical performance on every supported Mac.

## Data preparation

Use a reproducible regional panel derived from the public GIAB HG002 300× source
documented in the [acquisition recipe](../../Benchmarks/Data/README.md): Illumina
HiSeq paired 148-base reads, Novoalign 3.02.07, GRCh38 no-alt plus hs38d1
(`GCA_000001405.15_GRCh38_no_alt_plus_hs38d1_analysis_set.fna.gz`).

Retain approximately one third of fragments using a fixed preparation seed,
keeping related records together. Preparation sampling is separate from runtime
display sampling. Label the result **derived approximately 100× data**; measure
actual resulting regional depths rather than assuming every region is 100×.
Keep the original 300× dense slices as additional stress cases.

A full whole-genome BAM download is not required. Acquire a broader panel with
ordinary and locally dense regions and long contiguous stretches for sustained
panning, cache eviction, and revisits. The original two small slices alone are
insufficient. Preserve source/reference/contig provenance, extraction boundaries,
preparation commands and seed, and checksums. Verify completeness inside the
selected spans; do not interpret unextracted space as empty source data.

## Provisional targets

| Case | Initial target |
| --- | --- |
| Ordinary app-uncached navigation, alignment-visible span up to 10 kb | At least 95% ready and drawn within 500 ms |
| Designated dense stress app-uncached navigation, span up to 10 kb | At least 95% ready and drawn within 1 second |
| Navigation requiring no BAM query | At least 95% complete within 100 ms |
| Horizontal drag previews and vertical scrolling | At least 95% of visual updates within 33 ms |
| Ten-minute navigation run | Peak process memory below 2 GiB |

Fresh-load time includes query, decoding, sampling, layout, and native drawing.
App-uncached means absent from Bamdalf's cache; record OS file-cache conditions
separately. Cached-navigation time includes layout and drawing. Continuous
interaction includes input handling and native drawing in ordinary and sampled
dense views. CPU drawing cost alone does not establish compositor presentation
or actual display frame rate; report the measurement boundary honestly.

The ten-minute run covers ordinary/dense regions, repeated visits, eviction, and
reloading. Retain a memory trace to expose continuing growth and define the exact
process-memory metric consistently in the protocol. The budget is a qualification
target, not permission to silently discard records or change accepted sampling,
geometry, or continuity behavior.

## Delegated protocol and revisions

The implementing agent chooses and documents exact regions, extraction recipe,
navigation route, repetition counts, and measurement tools within these
conditions. Fix the protocol before collecting qualification results. Include
cold/warm loads, toolbar/mouse navigation, sampled/unsampled/wide transitions,
large groups, and sustained navigation. Report each benchmark case separately;
easy cases must not hide dense-region failures. Choose the numerical sampling
budget and refine the visibility cutoff through measured tuning, preserving
accepted behavior and keeping correctness tests separate from timing checks.

The targets are provisional. The user explicitly authorized trying them and
adjusting them if evidence shows they are inappropriate. Preserve original
targets/results, explain revisions, and report against the target version used.
This supersedes the original prohibition on adjusting goals after seeing
results; silent failure relabeling is not permitted. Do not claim qualification
complete with unmet applicable goals or missing required measurements.

## Recorded execution — 2026-11-08

The [completed qualification report](qualification-2026-11-08.md) records the
broader independently reproduced panel, fixed protocol and its reviewed
scrolling correction, dense-drag optimization, all 27 completed cases, and the
612.701-second memory route at `micknudsen/bamdalf@01d3d95`. It supersedes the
unperformed-execution status above without changing this plan's numerical
targets. Its machine, CPU-drawing boundary, and memory-growth limitations remain
part of the result; supported-toolchain CI is a separate delivery gate.
