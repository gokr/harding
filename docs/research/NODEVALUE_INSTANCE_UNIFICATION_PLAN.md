# NodeValue and Instance Unification Plan

This plan describes a staged migration away from dual primitive representations.

## Problem

Harding currently carries primitive values in two forms:

- `NodeValue` immediates (`vkInt`, `vkFloat`, `vkString`, etc.)
- `Instance` wrappers (`ikInt`, `ikFloat`, `ikString`)

In hot dispatch paths, values are often converted to `Instance` for lookup and then converted back to `NodeValue` (`unwrap`). This adds branching, allocations, and ARC/ORC pressure.

## Goals

1. Use one canonical runtime value representation in execution paths.
2. Keep `Instance` for object identity, slots, and Nim proxy interop.
3. Preserve Smalltalk semantics and existing behavior during migration.
4. Reduce allocation and conversion overhead in message send hot paths.

## Non-Goals (initial phases)

- No parser/language syntax changes.
- No large primitive API rewrite in a single commit.
- No behavioral changes to exception or scheduler semantics.

## Phase Plan

### Phase 0: Guardrails and Baseline

- Add/refresh benchmarks for numeric loops and common dispatch paths.
- Lock behavior with tests for `class`, equality, nil checks, DNU, and primitive method sends.

### Phase 1: Class-First Lookup Infrastructure

- Introduce class resolution from `NodeValue` without requiring wrapper materialization.
- Introduce lookup helpers that operate on `Class` directly.
- Keep execution ABI unchanged (`self: Instance`) for compatibility.

Status:

- Added `classOfValue` in `src/harding/core/types.nim`.
- Added `lookupMethodOnClass` in `src/harding/interpreter/vm.nim`.
- Updated VM cache/lookup paths to use resolved class in more places.

### Phase 2: Receiver Materialization Deferral

- Delay `NodeValue -> Instance` conversion until method execution is actually required.
- Keep class lookup, MIC/PIC checks, and DNU class search wrapper-free.
- Materialize only when invoking native/interpreted method bodies.

### Phase 3: NodeValue-First Native ABI

- Add NodeValue-oriented native call ABI for hot primitives.
- Provide adapters for existing `self: Instance` native methods.
- Migrate arithmetic, comparisons, and string conversion first.

### Phase 4: Remove Legacy Dual Primitive Wrappers

- Remove `ikInt`/`ikFloat`/`ikString` dependence from hot dispatch paths.
- Decommission transitional helpers (`unwrap`, `valueToInstance`) once no longer needed in execution.
- Keep proxy/object representation intact.

### Phase 5: Cleanup and Validation

- Remove dead compatibility code.
- Run full tests (`nimble test`) and benchmark comparisons.
- Document final architecture in `docs/IMPLEMENTATION.md`.

## Risk Management

- Ship each phase in small, reviewable commits.
- Keep old paths available behind helper boundaries until tests pass.
- Prioritize semantic parity over aggressive optimization in early phases.

## Success Criteria

- No regressions in interpreter/compiler test suites.
- Reduced allocations in message-send-heavy benchmarks.
- Reduced time in conversion helpers and temporary wrapper creation.
