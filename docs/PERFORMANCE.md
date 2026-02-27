# Performance Guide

This document tracks current performance direction and practical profiling workflow.

For historical measurement snapshots and older optimization plans, see `docs/research/`.

## Current Priorities

- Reduce method lookup and dispatch overhead in hot interpreter paths.
- Keep method table rebuild behavior predictable and minimal.
- Maintain low allocation pressure in work-frame and activation-heavy code.
- Preserve correctness first; performance changes must keep full test coverage green.

## Benchmark Workflow

Use representative workloads and compare debug/release builds.

```bash
# Build interpreter
nimble harding
nimble harding_release

# Run sample workloads
./harding benchmark/sieve.hrd
./harding benchmark/queens.hrd
./harding benchmark/towers.hrd

./harding_release benchmark/sieve.hrd
./harding_release benchmark/queens.hrd
./harding_release benchmark/towers.hrd
```

## Profiling Workflow

For CPU hotspots:

```bash
nim c -d:debug --profiler:on -o:harding_profile src/harding/repl/harding.nim
./harding_profile benchmark/sieve.hrd
```

Interpret profile output with focus on:

- method lookup/rebuild behavior,
- work queue and continuation processing,
- hash-table-heavy operations in critical loops.

## Performance Change Checklist

- Add a short rationale for each optimization.
- Measure before/after with at least one compute-heavy benchmark.
- Confirm no regressions in test suite behavior.
- Prefer targeted simplifications over broad rewrites.

## Historical Performance Notes

- `docs/research/PERFORMANCE_ANALYSIS_2026.md`
- `docs/research/performance_baseline.md`
- `docs/research/performance_optimization_plan.md`
- `docs/research/OPTIMIZE.md`
