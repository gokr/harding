# Example Compilation Test Matrix

## Snapshot (2026-02-27)

Tested with `./granite run` on the current `main` worktree.

## Verified Results

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | ✅ | Basic output path works. |
| `control_flow` | ✅ | Conditionals, loops, `to:do:`, and boolean logic produce expected output. |
| `fibonacci` | ✅ | Compiled method + loop behavior working; expected sequence prints. |
| `inheritance` | ✅ | `super` dispatch and `isKindOf:` hierarchy checks working. |
| `harding_main` | ✅ | `Harding compile:` + `Harding main:` split works as intended. |
| `collections` | ✅ | Array/Table creation, mutation, reads, and reductions produce expected values. |

## Key Behavior Confirmed

- `Harding compile:` executes compile-time setup/definitions in Granite.
- `Harding main:` becomes runtime executable code in generated `main()`.
- Interpreter supports both `Harding compile:` and `Harding main:` as normal block evaluation on the `Harding` global.
- Compiled method registration and argument passing are active.
- `super` sends in compiled methods use runtime superclass lookup.

## Open Gaps

1. Generated-file cleanup (remove currently unused imports in module header).
2. Add targeted regression tests for runtime selectors added in this phase (`new`, `add:`, `at:put:`, `inject:into:`, `to:do:`, boolean selectors).

## Useful Commands

```bash
./granite run examples/inheritance.hrd
./granite run examples/fibonacci.hrd
./granite run examples/harding_main.hrd
./granite run examples/control_flow.hrd
./granite run examples/collections.hrd
```
