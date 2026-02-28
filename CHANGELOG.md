# Changelog

All notable changes to Harding are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added
- `System` stdlib class with `arguments`, `cwd`, and stdio accessors (`stdin`, `stdout`, `stderr`).
- `File` stdlib convenience class (`readAll:`, `write:to:`, `append:to:`, `exists:`).
- Package API for embedding Harding sources with Nim primitives (`src/harding/packages/package_api.nim`) and package-loading tutorial (`docs/NIM_PACKAGE_TUTORIAL.md`).

### Changed
- `FileStream` now uses native file primitives (`primitiveFileOpen:mode:`, `primitiveFileReadAll`, etc.) and exposes `Stdin`, `Stdout`, and `Stderr` globals.
- CLI parsing now supports script/runtime args after `--`, and passes them into interpreter `System arguments`.
- `load:` for `Harding` and `Library` now resolves both filesystem paths and embedded package sources.
- Granite Application builds now inject command-line args into `main: args` via generated runtime setup.

### Tests
- Added stdlib/package coverage for system arguments, stream globals, file I/O convenience methods, and embedded package loading.
- Added end-to-end CLI coverage verifying `--` argument forwarding for script mode and `-e` mode.

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

[Unreleased]: https://github.com/gokr/harding/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/gokr/harding/compare/v0.6.0...v0.7.0
