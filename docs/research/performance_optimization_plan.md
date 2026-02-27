# Performance Optimization Plan

## Branch Setup
- **Branch**: `perf/work-frame-pooling`
- **Worktree**: `../harding-perf` (separate checkout for performance work)

## Benchmarks

### Primary Benchmarks

| Benchmark | Expected | Description | Why It Matters |
|-----------|----------|-------------|----------------|
| `sieve.hrd` | 95 | Prime counting (n=500) | Heavy integer arithmetic, loops |
| `queens.hrd` | true | N-Queens solver | Method calls, object creation |
| `towers.hrd` | true | Towers of Hanoi (13 disks) | Recursion, method dispatch |

### Build Configurations
- `nimble harding` (debug)
- `nimble harding_release` (-d:release)
- Manual: `nim c -d:danger --opt:speed` (maximum optimization)

## Optimization 4: Extend Tagged Value Usage

### Current State
- Integers use tagged values for fast arithmetic path
- Floats and special values go through full instance path

### Implementation Plan
1. **Phase 1**: Add float support to tagged value operations in `wfSendMessage`
2. **Phase 2**: Special-case common float operations (+, -, *, /)
3. **Phase 3**: Extend to other value types if beneficial

### Measurement
- Baseline: Run benchmarks with current code
- Expected impact: Modest (10-20%) for float-heavy code
- Sieve benchmark doesn't use floats, so may not show improvement

## Optimization 5: Work Frame Pooling

### Problem
- `WorkFrame` is `ref object` - heap allocated for every operation
- Creates GC pressure during heavy computation

### Current Design
```nim
WorkFrame* {.acyclic.} = ref object
  kind*: WorkFrameKind
  # ... 20+ fields
```

### Proposed Changes

#### Option A: Object Pool (Recommended)
```nim
type
  WorkFramePool = object
    frames: seq[WorkFrame]
    available: seq[int]  # indices of available frames

proc acquireFrame(pool: var WorkFramePool): WorkFrame
proc releaseFrame(pool: var WorkFramePool, frame: WorkFrame)
```

#### Option B: Value Type (More Aggressive)
Change `WorkFrame` from `ref object` to `object`:
- Store in stack-allocated seq
- Requires restructuring how frames are passed
- Higher risk of breaking changes

### Implementation Steps

1. **Create WorkFramePool type** in new file `src/harding/interpreter/frame_pool.nim`
2. **Modify Interpreter** to use pool
3. **Update push/pop** work frame operations
4. **Measure impact** on benchmarks

### Expected Impact
- Sieve: High (many iterations = many work frames)
- Queens: Medium (object creation + method calls)
- Towers: High (recursive calls = many frames)

## Measurement Protocol

### Baseline Collection
```bash
# For each benchmark
for build in debug release danger; do
  for run in 1 2 3; do
    time ./harding benchmark/sieve.hrd
  done
done
```

### Metrics
- Wall clock time
- User CPU time
- Memory usage (peak RSS)
- GC collections (if measurable)

### Success Criteria
- 20%+ improvement on sieve
- No regressions in other benchmarks
- All existing tests still pass

## Implementation Order

1. ✅ Baseline measurements (all builds)
2. Work frame pooling implementation
3. Tagged value extension
4. Final measurements
5. Merge if criteria met

## Notes

- Keep changes isolated to perf branch until validated
- Document any breaking changes
- Consider adding micro-benchmarks for specific operations
