# Navigation regression check, 2026-11-07

The nearby-navigation change was checked with the same public GIAB subset,
M4 / 16 GiB Mac, native release harness, and two 10 kb intervals documented in
the [visibility baseline](visibility-2026-11-07.md). These are fresh loads,
not timings of cache hits or a final WGS qualification.

Initial implementation `5eb3af9` scanned every occupied range on candidate rows.
Three repetitions exposed a substantial regression. Sorted interval lookup now
checks neighboring ranges, while fresh layouts retain the simpler final-endpoint
algorithm. Identity deduplication preserves input order, avoiding a shuffle of
coordinate-ordered BAM results before packing. Retained-row correctness remains
covered separately by deterministic session and native tests.

| Region | Initial navigation implementation, median ms | Corrected implementation, median ms | Prior visibility baseline, median ms |
| --- | ---: | ---: | ---: |
| Ordinary 10 kb | 1,261.88 | 148.08 | 133.54 |
| Deeper 10 kb | 5,819.43 | 446.17 | 443.44 |

Each phase used three separate process runs per interval. The corrected ordinary
range was 142–162 ms and the deeper range 444–462 ms. Other builds and CPU-heavy
tests were paused for the accepted repeat measurements. One attempt overlapped
a build and was excluded. The unchanged harness drew the actual native view;
record and row counts stayed at 20,942 / 430 and 47,160 / 2,251 respectively.

[Per-run data and final source hashes](data/navigation-2026-11-07.json) preserve
the evidence. This check isolates a detected packing regression; it does not
establish a hard latency or memory target, qualify all depths, or measure a
performance advantage over another viewer. The 10,000-base cutoff is unchanged.
