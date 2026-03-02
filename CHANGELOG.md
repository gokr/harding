# Changelog

All notable changes to Harding are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

## [0.7.1] - 2026-03-02

### Added
- IDE Inspector rewritten with tree view and embedded workspace support.
- System Browser context menus with method deletion capability.
- GTK widget support: `GtkListBox`, `GtkPaned`, and separator support in `ContextMenu`.
- `startsWith:` and `endsWith:` methods for `String` (implemented as Nim primitives).
- Alert dialog integration and GTK automation hooks for IDE.
- Comprehensive compiler block parity test suite.

### Changed
- Replaced button-based BrowserPane with `GtkListBox` for improved UX.
- Browser save/reload workflow improvements with keyboard shortcuts.
- `printIt` now inserts at cursor position and selects inserted text.
- Improved debug/warn templates and removed unused logging imports.

### Fixed
- Compiler nested block compilation with proper registry sharing and forward declarations.
- Block compilation with captures and environment structs.
- Recursive non-local return detection in blocks.
- Preserved captured variable writes in indexed assignment fast path.

### Performance
- VM optimizations: indexed locals, frame pooling, and logging improvements.

## [0.7.0] - 2026-02-27

### Added
- Mixed-mode compilation fallback to interpreter runtime (`--mixed`) and supporting runtime integration.
- Native Nim class generation support in the compiler, plus Harding-side `compile:` / `main:` workflow improvements.
- Exception signal-point capture and restoration (`ExceptionContext`, `resume`, `resume:`), including `Notification` resumable behavior.
- Slot reflection and improved native type conversion pathways (`toValue`, `classRef` support).

### Changed
- Merged major development lines from `compiler-next` and `fix-exceptions` into `main`.
- Strengthened stackless VM control flow around returns, activation cleanup, and work-queue handling.
- Tightened boolean semantics for conditional evaluation to align with Smalltalk-style true/false logic.
- Updated standard library behavior for arrays, intervals, sorted collections, symbols, and strings to match current runtime semantics.

### Fixed
- Exception control-flow correctness for handler actions (`pass`, `return:`, uncaught default action, resume continuation behavior).
- Closure isolation and receiver/home-activation edge cases in block evaluation.
- Release-build safety issue in `println` (memory safety fix).
- Parser/operator consistency issues and several method dispatch/lookup edge cases.
- Multiple stdlib and website example regressions uncovered during merge stabilization.

### Performance
- Method-table lazy rebuild optimization (significant speedup in lookup-heavy paths).
- Activation/frame pooling and follow-up VM optimization phases.
- Compiler-side optimization passes and block/codegen improvements.

### Tests
- Expanded and stabilized tests for exceptions, stdlib, parser precedence, dynamic dispatch, and website examples.
- Split large stdlib coverage into focused suites for faster diagnostics.

[Unreleased]: https://github.com/gokr/harding/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/gokr/harding/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/gokr/harding/compare/v0.6.0...v0.7.0
