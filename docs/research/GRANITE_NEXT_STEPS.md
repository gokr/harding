# Granite Compiler Next Steps

## Context

This plan replaces the older external Granite notes with a repo-local status and execution order based on the current tree.

**Status Update (2026-03-15)**: Granite Phases 0-7 are now complete. The compiler supports exception handling codegen, remaining node types, and direct slot access. The main compiler priority remains parity for block-heavy programs, especially captured blocks and compiled non-local returns. Items now done include compiled inheritance examples, `super` sends, `Harding compile:` / `Harding main:` split behavior, and exception handling.

## Current Snapshot

### Completed Phases (0-7)

**Phase 0-4 (2026-03-10)**: Foundation and core compilation
- Basic expression and statement compilation
- Method generation with arguments
- Inline control flow (`ifTrue:`, `whileTrue:`, `timesRepeat:`)
- Class and slot access compilation

**Phase 5 (2026-03-12)**: Exception handling codegen
- `on:do:` exception handler compilation
- Handler actions: `resume`, `resume:`, `retry`, `pass`, `return:`
- Exception signal point preservation
- `ensure:` cleanup blocks

**Phase 6-7 (2026-03-15)**: Remaining node types and optimizations
- Direct slot access code generation
- Remaining AST node type coverage
- Inherited slot access in compiled code

### Already Confirmed

- `examples/inheritance.hrd` works in Granite.
- `examples/harding_main.hrd` works in Granite.
- `super` dispatch is present in generated code and runtime fallback.
- Compiled method registration with arguments is active.
- Collection and boolean runtime support has been expanded in compiled mode.
- Exception handling works in compiled code.
- Direct slot access generates efficient Nim code.

References:

- `docs/research/EXAMPLE_MATRIX.md`
- `docs/research/COMPILER-PLAN.md`
- `docs/ROADMAP.md`

### Main Remaining Gaps

1. Captured blocks in expression position still generate invalid Nim.
2. Compiled non-local returns use a broad exception catch and do not yet target the correct compiled home method precisely.
3. Compiler parity tests for blocks are still mostly scaffolding and do not run the generated code.
4. Remaining runtime selector gaps should be driven by example parity failures, not guessed in advance.

## Recommended Work Order

### Phase 0: Establish a Repeatable Parity Baseline

Add and use a script that:

- runs each supported example through `./harding`
- runs the same example through `./granite run`
- captures stdout/stderr and exit status for both
- reports pass, fail, or skip
- stores diffs for failing examples

This gives a current truth source for Granite progress and makes `docs/research/EXAMPLE_MATRIX.md` easy to refresh.

### Phase 1: Fix Captured Blocks in Expression Context

The code generator already calls out this problem directly in `src/harding/codegen/expression.nim`.

Current issue:

- `genExpression` emits `createBlockWithEnv(...)` for captured blocks
- the generated path assumes statement-level setup
- Nim rejects this when the block appears inside an expression

Implementation direction:

- lower captured block creation in expression position into a Nim `(block: ... )` expression or equivalent helper
- keep environment initialization statement-safe while still returning a `NodeValue`
- cover nested captured block creation as a regression case

Expected impact:

- unblocks block-heavy examples first
- reduces divergence between statement and expression block codegen

### Phase 2: Tighten Compiled Non-Local Return Semantics

Granite currently handles block `^` by raising `NonLocalReturnException` and catching it at the enclosing compiled method boundary.

Current issue:

- block code raises `NonLocalReturnException(value: ..., targetId: 0)`
- compiled methods catch any `NonLocalReturnException` and return its value
- this is good enough as a bootstrap path, but it is broader than the interpreter's home-activation semantics

Implementation direction:

- assign stable ids to compiled method activation targets
- emit the correct target id in compiled block returns
- only consume matching non-local returns in the intended home method
- let non-matching returns continue unwinding

Expected impact:

- better semantics for nested compiled blocks
- cleaner path for future mixed-mode interaction
- smaller semantic gap versus the VM

### Phase 3: Turn Block Parity Tests into Real Compiler Tests

`tests/test_compiler_block_parity.nim` currently parses and generates code, but does not compile and run it.

Implementation direction:

- wire `compileAndRun` into the real Granite pipeline
- execute generated programs in a temporary build directory
- compare compiled results against interpreter behavior

Priority regression cases:

- captured block in assignment
- captured block in expression position
- nested captured blocks
- non-local return from a block
- nested non-local return through control flow

### Phase 4: Fill Runtime Selector Gaps from Measured Failures

After the harness and block fixes are in place, rerun the example sweep and only then add runtime or codegen behavior for selectors that still fail.

Likely targets include:

- string convenience selectors
- numeric helpers
- collection iteration helpers not already covered by inline codegen

Rule:

- drive selector work from parity failures in examples or tests
- avoid broad speculative runtime expansion

### Phase 5: Cleanup and Drift Reduction

After parity improves:

- trim generated-module unused imports and warnings
- add focused tests for `Harding compile:` / `Harding main:`
- add focused tests for `super` dispatch and specialized `if` / `while` codegen
- refresh `docs/research/EXAMPLE_MATRIX.md`

## Near-Term Milestone

The next meaningful Granite milestone is:

> Block-heavy examples compile and run with parity, backed by an automated example harness and real compiler parity tests.

## Concrete First Tasks

1. Add `scripts/test_granite_examples.sh`.
2. Run the harness to capture the current baseline.
3. Fix captured-block expression codegen.
4. Add real execution to `tests/test_compiler_block_parity.nim`.
5. Implement targeted compiled non-local return matching.
