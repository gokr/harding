# Harding Roadmap

This document is the active roadmap for Harding. It summarizes current priorities and expected next milestones.

Historical planning notes are preserved in `docs/research/`.

## Current Focus

### Compiler (Granite)

- ✅ Completed Phases 0-7: exception handling, remaining node types, direct slot access.
- Complete first-class block compilation with captures.
- Implement non-local return support in compiled blocks.
- Improve class/method compilation from in-VM code paths.
- Continue reducing divergence between CLI and in-VM compilation flows.

### Runtime and VM

- Keep exception semantics stable (`resume`, `resume:`, `retry`, `pass`, `return:`).
- Continue stackless VM cleanup and simplification where behavior is unchanged.
- Improve diagnostics and error messages in parser/runtime hot paths.
- Follow up indexed-locals fast paths so captured-cell writes stay coherent without dropping back to slow-path assignment.

### FFI and Ecosystem

- Expand Nim interop/type marshaling support.
- Improve stability and usability of external integration workflows.

### Tooling

- Refine REPL ergonomics (history/completion and workflow polish).
- Continue VSCode/LSP/DAP quality improvements.
- Keep Bona IDE workflows aligned with the language/runtime behavior.

### Documentation and Examples

- Keep `MANUAL.md` as the primary language reference.
- Keep `QUICKREF.md` concise and syntax-oriented.
- Expand tutorials and example-driven learning material.

## Near-Term Milestones

1. Compiler parity improvements for block-heavy programs.
2. Better runtime error reporting and debugging clarity.
3. Additional FFI coverage for common Nim integration scenarios.
4. Documentation pass for contributor and user onboarding.

## Deferred / Longer-Term

- Deeper compiled-code optimization passes.
- Additional standard library expansion areas (networking, richer utilities).
- Optional advanced static analysis/type-checking explorations.

## Related Historical Documents

- `docs/research/TODO.md`
- `docs/research/IMPROVEMENTS.md`
- `docs/research/COMPILER-PLAN.md`
- `docs/research/EXAMPLE_MATRIX.md`
