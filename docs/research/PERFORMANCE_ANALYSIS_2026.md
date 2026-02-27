# Performance Analysis & Recommendations (Feb 2026)

## Profiling Results

**Benchmark**: Sieve of Eratosthenes (primeCount to 5000)
**Tool**: Nim built-in profiler (`--profiler:on`)
**Result**: 357 samples, 242 unique stack traces

### Top Hotspots

| Function | % Samples | Issue |
|----------|-----------|-------|
| `rebuildAllTables` | 89.08% | Method table rebuilding too eager |
| `rebuildAllDescendants` | 89.08% | Recursive rebuild of entire hierarchies |
| `hashFarm`/`rawGet`/`hasKey` | 26-37% | Hash table overhead |
| `lookupClassMethod` | 42.58% | Called during every lookup |
| `evalWithVM` | 91.60% | Main interpreter loop |
| `executeMethod` | 89.92% | Method execution overhead |

### Root Cause Analysis

**1. Method Table Rebuilding (CRITICAL - 89% of samples)**

The lazy rebuild optimization is being triggered far too frequently:

```nim
# In objects.nim:lookupMethod()
if cls.methodsDirty:
  rebuildAllDescendants(cls)  # Rebuilds EVERY descendant!
  cls.methodsDirty = false
```

**Problem**: 
- Every method addition marks the class AND all descendants as dirty
- Every lookup on a dirty class triggers full rebuild
- `rebuildAllDescendants` recursively walks the entire subclass tree
- Each rebuild calls `initTable` and repopulates via hash table operations

**Evidence from profile**:
- `rebuildAllTables` appears in 318/357 samples (89%)
- `initTable` appears repeatedly
- `rawGet`, `hasKey`, `enlarge` from hash operations dominate

**Solution**:
1. **Defer rebuilds during batch loading** - Already have `methodTableDeferRebuild` flag but not used aggressively enough
2. **Rebuild only on cache miss** - Don't rebuild in `lookupMethod`, only when MIC/PIC actually miss
3. **Incremental rebuild** - Only rebuild the class itself, not all descendants
4. **Use flat arrays for small method sets** - Avoid hash tables for <16 methods

---

**2. Hash Table Overhead (HIGH - 26-37% of samples)**

Nim's `Table` is used everywhere:
- Method tables (`methods`, `allMethods`, `classMethods`, `allClassMethods`)
- Slot tables (`slots`)
- Globals
- Activation locals
- Captured variables

**Profile evidence**:
- `hashFarm`: 94/357 (26%)
- `rawGet`: 133/357 (37%)
- `hasKey`: 73/357 (20%)
- `enlarge`: 35/357 (10%)

**Solution**:
1. **Pre-size tables** - Most method tables are small (<16 entries)
2. **Use open-addressing** - Better cache locality than chaining
3. **Flat arrays for hot paths** - Method lookup for common selectors
4. **String interning for selectors** - Compare pointers, not strings

---

**3. No AST Specialization for Control Flow (MEDIUM)**

The sieve benchmark uses `whileTrue:` heavily:

```harding
[ i <= 5000 ] whileTrue: [
  # body
]
```

**Current**: Full message send machinery
1. Evaluate receiver block
2. Evaluate argument block
3. Send `whileTrue:` message
4. Lookup method
5. Execute method
6. Evaluate blocks repeatedly

**Profile**: `evalWithVM` in 91.6% of samples, `executeMethod` in 89.9%

**Solution**: Recognize at parse time and generate specialized nodes:

```nim
# In parser.nim: detect whileTrue:/whileFalse: patterns
if msg.selector in ["whileTrue:", "whileFalse:"] and
   msg.arguments.len == 1 and
   msg.arguments[0].kind == nkBlock:
  return WhileNode(
    condition: msg.receiver,
    body: msg.arguments[0],
    isWhileTrue: msg.selector == "whileTrue:"
  )
```

Then in `evalWithVM`:
```nim
of nkWhile:
  let whileNode = cast[WhileNode](node)
  # Direct loop without message send overhead
  while true:
    let condResult = evalBlock(..., whileNode.condition)
    let isTrue = condResult.kind == vkBool and condResult.boolVal
    if (whileNode.isWhileTrue and not isTrue) or
       (not whileNode.isWhileTrue and isTrue):
      break
    evalBlock(..., whileNode.body)
  return nilValue()
```

**Expected**: 5-10x speedup for tight loops

---

**4. Missing Direct Threading (MEDIUM)**

**Current**: Work queue processing via `case` statement

**Solution**: Use GCC's `&&label` extension:

```nim
when defined(gcc):
  var labels: array[WorkFrameKind, pointer]
  labels = [
    wfEvalNode: addr evalNodeHandler,
    wfSendMessage: addr sendMessageHandler,
    # ...
  ]

template dispatch() =
  goto labels[frame.kind]

evalNodeHandler:
  # ...
  dispatch()

sendMessageHandler:
  # ...
  dispatch()
```

**Expected**: 2-3x dispatch speedup

---

**5. Block Allocation Overhead (LOW-MEDIUM)**

Every block execution creates an activation:
- `newActivation` calls `acquireActivation` from pool
- Still has initialization overhead
- Tables cleared every time

**Solution**:
1. **Inline clean blocks** - Blocks without captures can be singletons
2. **Stack allocation** - Non-escaping blocks use stack space
3. **Better pooling** - Reuse activations more aggressively

---

## Implementation Priority

### Phase 1: Fix Method Table Rebuilding (1-2 days)
**Impact**: Expected 5-10x speedup

1. Change `rebuildAllDescendants` to only rebuild the class itself
2. Only rebuild on actual MIC/PIC miss, not every lookup
3. Add `methodTableDeferRebuild` usage in `loadStdlib`
4. Pre-size method tables based on expected size

**Files to modify**:
- `src/harding/interpreter/objects.nim` (rebuild logic)
- `src/harding/interpreter/vm.nim` (lookup methods)
- `src/harding/core/types.nim` (add pre-sizing)

### Phase 2: AST Specialization (2-3 days)
**Impact**: Expected 2-5x speedup for compute-heavy code

1. Add `IfNode` and `WhileNode` to parser
2. Add specialization in `evalWithVM`
3. Extend to `to:do:`, `timesRepeat:`, `and:`, `or:`

**Files to modify**:
- `src/harding/parser/parser.nim`
- `src/harding/interpreter/vm.nim`
- `src/harding/core/types.nim` (new node types)

### Phase 3: Hash Table Optimization (1-2 days)
**Impact**: Expected 20-30% speedup

1. Pre-size all method tables
2. Use `initTable[size]` with expected capacity
3. Consider custom open-addressing table for hot paths

**Files to modify**:
- `src/harding/interpreter/objects.nim`
- `src/harding/core/types.nim`

### Phase 4: Direct Threading (2-3 days)
**Impact**: Expected 2-3x dispatch speedup

1. Add `when defined(gcc)` direct threading
2. Migrate work frame handlers to labels
3. Test on Linux/macOS (GCC/Clang)

**Files to modify**:
- `src/harding/interpreter/vm.nim`

---

## Expected Combined Impact

| Optimization | Sieve | Queens | Towers |
|--------------|-------|--------|--------|
| Baseline (debug) | ~3.0s | ~1.0s | N/A |
| Baseline (release) | ~0.4s | ~0.14s | N/A |
| Phase 1 only | ~0.08s | ~0.03s | N/A |
| Phase 1+2 | ~0.04s | ~0.02s | N/A |
| Phase 1+2+3 | ~0.03s | ~0.015s | N/A |
| All phases | ~0.02s | ~0.01s | N/A |

**Total expected**: 10-20x speedup over current release build

---

## Measurement Protocol

After each phase:
```bash
# Rebuild
nimble harding_release

# Run benchmarks
time ./harding benchmark/sieve.hrd
time ./harding benchmark/queens.hrd
time ./harding benchmark/towers.hrd

# Profile
nimble profile_nimprof
cat profile_results.txt | head -50
```

Compare to baseline:
- Sieve: 0.4s → target 0.02s (20x)
- Queens: 0.14s → target 0.01s (14x)

---

## Additional Optimizations (Future)

### Tagged Value Extension
- Currently only integers use tagged values
- Extend to floats, characters, small strings
- **Impact**: 10-20% for float-heavy code

### Frame Pooling Enhancement
- WorkFrame is `ref object` - heap allocated
- Pool or use value types
- **Impact**: 10-15% (reduces GC pressure)

### Megamorphic Handler Optimization
- When PIC > 4 entries, use direct lookup
- Skip cache probing overhead
- **Impact**: 5-10% for polymorphic sends

### Selector Interning
- Intern all selectors at parse time
- Compare pointers instead of strings
- **Impact**: 10-15% in method lookup

### Write Barrier Optimization
- Skip barrier for immediate (tagged) values
- **Impact**: 5-10% for object-heavy code

---

## Conclusion

The profiling clearly identifies **method table rebuilding** as the dominant bottleneck (89% of samples). This is a classic case of an optimization (lazy rebuilding) that's being triggered far too frequently.

**Immediate action**: Fix Phase 1 (method table rebuilding) for 5-10x speedup.

**Medium-term**: Implement AST specialization and hash table optimization for additional 2-3x.

**Long-term**: Direct threading and other optimizations for compiler-level performance.

The interpreter architecture is sound - these are implementation refinements, not architectural changes.
