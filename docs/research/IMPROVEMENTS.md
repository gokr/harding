# Harding Interpreter Improvements Plan

Analysis of the Harding interpreter codebase identifying areas for simplification, cleanup, and performance improvement.

## Priority 1: Unify NodeValue/Instance Dual Representation (POSTPONED)

The type system maintains two parallel representations for primitives:
- `NodeValue` variants: `vkInt`, `vkFloat`, `vkString` (fast, stack-friendly)
- `Instance` variants: `ikInt`, `ikFloat`, `ikString` (heap-allocated, carries class pointer)

This creates a wrap-unwrap cycle in the hot path:
1. Create `Instance` wrapper via `newStringInstance(cls, str)`
2. Wrap in `NodeValue(kind: vkInstance, instVal: inst)`
3. Later call `unwrap()` to re-create a primitive `NodeValue`

Every method send on primitives goes through temporary instance creation in `vm.nim:4620-4889`.

**Status**: Postponed - requires careful architectural work.

## Priority 2: Extract Duplicated VM Helpers

### 2a. Exception Handler State Restoration (6x duplication)

In `vm.nim`, activation stack restoration logic is copy-pasted across `primitiveExceptionResumeImpl`, `primitiveExceptionResumeWithValueImpl`, `primitiveExceptionReturnImpl`, `primitiveExceptionRetryImpl`, `primitiveExceptionPassImpl`. ~48 lines of duplication.

**Fix**: Extract `proc restoreVMStateToDepth(interp: var Interpreter, depth: int)`.

### 2b. Equality/Inequality Operator Duplication

`vm.nim` has identical 20-line case statements for `==` and `~=`, differing only in the boolean result.

**Fix**: Extract `proc valuesEqual(a, b: NodeValue): bool` and negate for `~=`.

### 2c. String Extraction Pattern (2x duplication)

`objects.nim` — identical 4-line pattern to extract a string from a NodeValue (checking vkString, vkSymbol, and ikString) in `primitiveAtImpl` and `primitiveAtPutImpl`.

**Fix**: Extract `proc extractStringValue(val: NodeValue): string`.

**Status**: DONE

## Priority 3: Remove Dead Code

### 3a. Unused Converter Functions

`types.nim:699-722` — Five functions never called:
- `toBlock*(val: NodeValue): BlockNode`
- `toClass*(val: NodeValue): Class`
- `toInstance*(val: NodeValue): Instance`
- `toArray*(val: NodeValue): seq[NodeValue]`
- `toTable*(val: NodeValue): Table[NodeValue, NodeValue]`

### 3b. Unused Parser Procs

- `parser.nim` — `parsePrimaryUnaryOnly` defined but never called
- `parser.nim` — `parseMethod` wraps `parseBlock()` but is never called

### 3c. Unused Import

`parser.nim` — `tables` is imported but never used.

### 3d. Redundant Instance Type Checker Helpers

`types.nim` — `isInt()`, `isFloat()`, `isString()`, `isArray()`, `isTable()`, `isObject()` are trivial wrappers around `inst.kind == ikFoo`. Only 28 total usages.

**Status**: DONE

## Priority 4: Fix toString/formatLiteral Duplication

`types.nim` — nearly identical nested `case val.kind / case val.instVal.kind` in both `toString()` and `formatLiteral()` (~60 lines duplicated). Only difference is string quoting.

**Fix**: Extract common formatting with a mode parameter.

**Status**: DONE

## Priority 5: Fix O(n^3) Method Table Rebuild

`objects.nim` — triple-nested loop in `rebuildAllTables`:
```nim
for parent in cls.superclasses:
  for c in parent.inheritanceChain():  # rebuilds seq each call
    for sel, m in c.allMethods:
```

`inheritanceChain()` recursively builds a sequence on each iteration.

**Fix**: Cache `inheritanceChain()` result.

**Status**: DONE

## Priority 6: Fix Binary Operator Token Inconsistency

`parser.nim` — local case statement missing `tkAmpersand` and `tkPipe` compared to the `BinaryOpTokens` constant. Possible bug.

**Fix**: Use the `BinaryOpTokens` constant consistently.

**Status**: DONE

## Other Noted Issues (Not Yet Prioritized)

- `isNimProxy` and `nimValue` fields on every Instance even when unused (16+ bytes waste)
- ExceptionContext captures full work queue/eval stack copies
- Parser: repeated separator skipping (~20 occurrences)
- Parser: inconsistent parse loop limits (1000 vs 100)
- Compiler: manual string parsing in analyzer instead of reusing lexer
- Compiler: O(n^2) getAllSlots
- TODOs in vm.nim exception handling (walk sender chain, check exception class, SignalContext wrapper)
