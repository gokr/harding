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

## Constant Literal Optimization

Harding automatically optimizes constant Array and Table literals at parse time:

### What Gets Optimized

- `#(1, 2, 3)` - Flat arrays with literal elements
- `#("a", "b", "c")` - Arrays with string literals
- `#{"key" -> 1}` - Tables with literal keys and values
- `#()` - Empty arrays
- `#{}` - Empty tables

### How It Works

1. **Parse time**: Parser analyzes literals and determines if all elements are constants (no message sends, no variables)
2. **Caching**: Constant values are pre-computed and stored in the AST node's `cachedValue` field
3. **Fast path**: Interpreter uses cached value directly instead of evaluating elements at runtime
4. **Granite**: Compiler generates compile-time Nim constants

### Performance Impact

| Scenario | Before | After |
|----------|--------|-------|
| `#(1, 2, 3)` | N work frames + build operation | Single push of cached value |
| `#{"a" -> 1}` | 2N work frames + build operation | Single push of cached value |

### Limitations

- Nested arrays/tables are not cached (e.g., `#(#(1, 2))` evaluates at runtime)
- Arrays/tables containing variables or message sends are not cached
- Conservative approach avoids type mismatch between cached values and runtime instances

For full implementation details, see `docs/plans/CONSTANT_LITERAL_OPTIMIZATION.md`.

## Historical Performance Notes

- `docs/research/PERFORMANCE_ANALYSIS_2026.md`
- `docs/research/performance_baseline.md`
- `docs/research/performance_optimization_plan.md`
- `docs/research/OPTIMIZE.md`
