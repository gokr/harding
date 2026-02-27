# Performance Baseline Measurements

## Environment
- Date: $(date)
- Branch: perf/work-frame-pooling (merged with main)

## Benchmark Results

### Sieve (n=500, expected: 95 primes)
| Build | Run 1 | Run 2 | Run 3 | Avg |
|-------|-------|-------|-------|-----|
| Debug | 3.14s | 3.11s | 2.79s | ~3.0s |
| Release (original) | 0.34s | 0.44s | 0.49s | ~0.4s |
| Release (with frame pooling) | 0.24s | 0.23s | 0.36s | ~0.28s |

### Queens (expected: true)
| Build | Run 1 | Run 2 | Run 3 | Avg |
|-------|-------|-------|-------|-----|
| Debug | 1.08s | 0.84s | 1.07s | ~1.0s |
| Release (original) | 0.13s | 0.16s | 0.12s | ~0.14s |
| Release (with frame pooling) | 0.19s | 0.13s | 0.10s | ~0.14s |

## Summary

| Build | Sieve | Queens | Improvement |
|-------|-------|--------|-------------|
| Debug | ~3.0s | ~1.0s | baseline |
| Release (original) | ~0.4s | ~0.14s | baseline |
| Release (optimized) | ~0.28s | ~0.14s | 30% / 0% |

## Optimizations Applied

1. **JavaScript Support Removal** (~600 lines removed)
2. **Lazy Method Table Rebuilding** (defer rebuild until lookup)
3. **Slot Access Rewriter** (O(1) index instead of string lookup)
4. **Float Fast Path** (direct float operations)
5. **WorkFrame Pooling** (reuse frames, reduce GC pressure)

## Test Status

All tests passing:
- ✅ test_core.nim (22 tests)
- ✅ test_primitives.nim (13 tests)
- ✅ test_exception_handling.nim (8 tests)
- ✅ test_website_features.nim (20 tests)
