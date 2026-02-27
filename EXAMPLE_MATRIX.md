# Example Compilation Test Matrix

## Snapshot (2026-02-27)

Tested with `./granite run` on the current `compiler-next` worktree.

## Verified Results

| Example | Status | Notes |
|---------|--------|-------|
| `hello` | ✅ | Basic output path works. |
| `control_flow` | ⚠️ | `if`/`while`/`timesRepeat:` work; boolean logical operators still return `nil` in this path. |
| `fibonacci` | ✅ | Compiled method + loop behavior working; expected sequence prints. |
| `inheritance` | ✅ | `super` dispatch and `isKindOf:` hierarchy checks working. |
| `harding_main` | ✅ | `Harding compile:` + `Harding main:` split works as intended. |
| `collections` | ⚠️ | Builds/runs, but collection operations still return many `nil` values. |

## Key Behavior Confirmed

- `Harding compile:` executes compile-time setup/definitions in Granite.
- `Harding main:` becomes runtime executable code in generated `main()`.
- Interpreter supports both `Harding compile:` and `Harding main:` as normal block evaluation on the `Harding` global.
- Compiled method registration and argument passing are active.
- `super` sends in compiled methods use runtime superclass lookup.

## Open Gaps

1. Collection operations in compiled mode (`Array`/`Table` usage in `collections.hrd`).
2. Boolean/logical operator behavior in compiled mode (`and:`, `or:`, `&`, `|`, `not`).
3. Generated-file cleanup (remove currently unused imports in module header).

## Useful Commands

```bash
./granite run examples/inheritance.hrd
./granite run examples/fibonacci.hrd
./granite run examples/harding_main.hrd
./granite run examples/control_flow.hrd
./granite run examples/collections.hrd
```
