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
- Added runtime selector support for compiled mode collection/boolean paths (`new`, `add:`, `at:`, `at:put:`, `size`, `keys`, `inject:into:`, `to:do:`, boolean selectors).
- Added statement write-back for mutating collection messages (`add:`, `at:put:`) so local/slot receivers retain updates.
- Fixed slot ordering in `getAllSlots` to keep parent slots first, preventing bad casts in superclass method execution.

## Verified Examples

Validated with `./granite run`:

- `examples/inheritance.hrd` ✅
- `examples/fibonacci.hrd` ✅
- `examples/harding_main.hrd` ✅
- `examples/control_flow.hrd` ✅
- `examples/collections.hrd` ✅

## Remaining Work

### High priority

1. Add regression tests covering new compiled runtime selector behavior (collections + boolean logic + `to:do:`).
2. Review semantics compatibility against interpreter for edge cases (e.g., selector return-value conventions on mutating collection messages).

### Medium priority

1. Reduce generated-file warnings by trimming unused imports in module header.
2. Add/expand compiler behavioral tests for:
   - `Harding compile:`/`Harding main:` split semantics
   - `super` dispatch in compiled methods
   - while/if specialized AST node codegen

## Next Steps

1. Add focused tests for `control_flow.hrd` and `collections.hrd` behavior in the compiler test suite.
2. Reduce generated-module import warnings (`sequtils`, `objects`, `activation`).
3. Run wider example sweep and refresh `EXAMPLE_MATRIX.md` after test additions.
