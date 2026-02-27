# Granite Compiler Improvement Plan

## Current Status (2026-02-27)

Granite now compiles and runs inheritance and fibonacci examples with compiled methods, superclass lookup, and `super` sends working in the generated runtime path.

### Completed in this phase

- Restored `Harding` semantics as a normal global object (not a parser pseudo-var hack).
- Added interpreter-side `Harding compile:` and `Harding main:` methods on `GlobalTable`.
- Split Granite behavior clearly:
  - `Harding compile:` executes at compile time for setup/definitions.
  - `Harding main:` compiles into runtime `main()` and is not executed during compile.
- Improved class graph and superclass registration (including `Object` chain registration).
- Added compiled method dispatch with argument support `(self, args)` and updated runtime registration.
- Added `sendSuperMessage` support in runtime and generated code for `nkSuperSend`.
- Improved method slot read/write codegen in method context to use generated accessors.
- Added direct handling for `nkWhile` and `nkIf` in statement generation.
- Fixed generated-code ordering so compiled methods are emitted after operator helpers, avoiding undeclared `nt_*` calls.
- Cleaned a few warnings from recent changes (`result` shadowing and unused locals).

## Verified Examples

Validated with `./granite run`:

- `examples/inheritance.hrd` ✅
- `examples/fibonacci.hrd` ✅
- `examples/harding_main.hrd` ✅
- `examples/control_flow.hrd` ✅ (core control flow works; boolean logical operator behavior still partial)
- `examples/collections.hrd` ⚠️ (builds/runs, many operations still resolve to `nil`)

## Remaining Work

### High priority

1. Improve collection primitives/interpreter fallback in compiled mode so `size`, `at:`, `keys`, and iteration produce values in `collections.hrd`.
2. Complete boolean/logical operator support in compiled runtime (`and:`, `or:`, `&`, `|`, `not`) to match interpreter semantics.

### Medium priority

1. Reduce generated-file warnings by trimming unused imports in module header.
2. Add/expand compiler behavioral tests for:
   - `Harding compile:`/`Harding main:` split semantics
   - `super` dispatch in compiled methods
   - while/if specialized AST node codegen

## Next Steps

1. Fix `collections.hrd` behavior by tracing message fallback for Array/Table operations in compiled runtime.
2. Implement missing boolean primitive paths and rerun `control_flow.hrd`.
3. Run wider example sweep and refresh `EXAMPLE_MATRIX.md` with final pass/fail notes.
