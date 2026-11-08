# Qualification protocol v2 — 2026-11-08

This revision preserves [protocol v1](qualification-protocol-2026-11-08.md) and
its recorded measurements. The product defaults, numerical targets, hardware,
input data, fresh/cached workloads, drag cases, and ten-minute memory route are
unchanged. The exact revised plan is
[protocol v2](../../Benchmarks/qualification-protocol-v2.json).

Independent specification review of `micknudsen/bamdalf@6e992f6` found that v1's
60 consecutive 180-pixel downward scroll events could reach the bottom early.
Subsequent events would be boundary no-ops. Pooling those observations as visual
updates could hide slow actual scrolling. The in-progress v1 run was stopped
before qualification completion and before the memory case. Its raw observations
remain in `.local/measurements/issue-11/qualification-v1/`; no complete or passing
qualification is claimed for v1, and its scroll percentiles are not accepted.

V2 alternates a downward 180-pixel native wheel event and an upward 180-pixel
event, repeated 60 times per view. Every one of the 120 measured events must
change the actual session/native viewport's vertical offset, in addition to
retaining rows and making no query. A clamped no-op fails the case instead of
entering its visual-update distribution. This exercises overlapping viewport
positions near the top of each representative ordinary, sampled dense, and
10,000-record-group view; it does not claim to inspect every row or position in
the stack. The renderer still receives the entire displayed alignment set.

This is a measurement-correctness correction, not a target revision or product
behavior change. Lock and record the revised protocol and harness before
collecting v2 results. Use separate output directories and report all cases
against v2, preserving the earlier evidence and the original provisional limits.
