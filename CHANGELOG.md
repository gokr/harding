# Changelog

All notable changes to Harding are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added
- External Harding library management (`library` command) for installing and managing third-party Harding packages.
- External BitBarrel library published as `bitbarrel` with registry support and package installation flow.
- Optional MummyX HTTP server integration documentation, including build tasks for both `harding` and `bona`.
- A Harding htmx-style web component layer, DaisyUI-backed Todo app example, and Bona workflow notes for live-editable MummyX web experiments.
- Block-aware cached Html templates and buffer-backed component rendering for reusable static markup with dynamic slots.
- Granite compiler Phases 0-7: exception handling codegen, remaining node types, and direct slot access compilation.
- VM optimization for declarative primitives eliminating dispatch overhead.
- **Prefix literal syntax** with `json{...}` for creating JSON strings directly. Pluggable design allows any class to implement `parseLiteral:` for custom `{...}` syntax. Case-insensitive prefix normalization (json, Json, JSON all work). Includes `Json parse:` and `Json stringify:` for bidirectional conversion.
- **`String class>>withCapacity:`** - Create pre-allocated mutable strings for efficient building.
- **`String>><<`** operator - In-place string appending that returns self for chaining. Uses Nim's efficient `add()` with automatic capacity doubling.
- **Constant literal optimization** - Array and Table literals with only constant elements (literals, no variables or message sends) are evaluated at parse time and cached. Interpreter uses pre-computed values, Granite generates compile-time Nim constants. Nested collections not yet optimized.
- Triple-quoted multiline string literals (`"""..."""`) for raw multi-line text with embedded `"` characters.
- Compiled JSON object serialization with class-side configuration (`jsonExclude:`, `jsonOnly:`, `jsonRename:`, `jsonOmitNil:`, `jsonOmitEmpty:`, `jsonFormat:`, `jsonFieldOrder:`, `jsonReset`) and `Object>>toJson`.
- JSON serialization benchmarks for nested Table/Array payloads and ordinary Harding object graphs.

### Changed
- Bona workspace artifacts are no longer tracked in git (added to .gitignore).
- Class definitions in core libraries now include class-specific comments.
- BitBarrel support now ships as an external library instead of built-in Harding source and build flags.
- MummyX request handling now runs through scheduler-backed green worker processes instead of executing on the socket thread.
- Granite block/codegen parity now covers captured block expressions, top-level block returns, 0-based collection access, and more runtime selector coverage.
- MummyX routes can now be cleared and rebuilt, and URL-encoded form data is exposed on `HttpRequest`.
- Bona now pumps scheduler work from the GTK main loop, refreshes open Browsers after successful Workspace evaluations, and documents the web stack through `Web` and `WebTodo` library bootstraps.
- **Removed Buffer class** - String now has `withCapacity:` and `<<` operator, making Buffer redundant. Use `(String withCapacity: 100) << "text"` instead of `Buffer withCapacity: 100` + `<<` + `contents`.
- `Json stringify:` now serializes ordinary Harding objects through compiled slot plans, supports primitive-only formatters (`#string`, `#rawJson`, `#symbolName`, `#className`), and falls back to `jsonRepresentation` when a class needs custom structure.

### Fixed
- Hardened browser dialogs and class reflection in Bona IDE.
- Fixed source tracking temp file cleanup in tests.
- External library builds now resolve transitive Nimble dependency paths needed by installed packages.
- MummyX request handlers now resume correctly after blocking native receives in the stackless VM.
- Interpreter native-value dispatch now marks interpreter-aware wrappers correctly, fixing crashes in collection iteration and block benchmark examples.
- Interpreter `print` and `println` now render arrays and tables using their actual Harding string forms.
- **Fixed VM eval stack underflow** with nested HtmlTemplates using dynamic content blocks (`textWith:`, `attrWith:`, `fragmentWith:`). Root cause was BlockNode AST mutation during non-local returns corrupting the target activation. Fixed by copying block nodes before mutation.
- JSON table-key serialization now rejects unsupported key types explicitly and detects cycles in slot-based and `jsonRepresentation`-based object serialization.

## [0.8.0] - 2026-03-09

### Added
- MummyX HTTP server support for building web applications and REST APIs.
- Application Builder tool for visual Granite compiler workflow.
- Canonical class derivation APIs: `derivePublic:`, `derive:read:write:`, and `derive:read:write:superclasses:`.
- `::` named access syntax for direct readable/writable slot access plus `Table`/`Library` binding access.
- Multiple-inheritance conflict reflection via `conflictSelectors` and `classConflictSelectors`.
- Source indexing for Browser method and class-definition lookups, including `<classDefinition>` pseudo-entries.
- `startsWith:` and `endsWith:` methods for `String`.

### Changed
- Multiple inheritance now uses first-parent-wins lookup order instead of failing on direct-parent selector conflicts.
- System Browser shows class definitions when selecting a class and refreshes source locations before save/delete.
- Browser-generated class definitions now use canonical `derive: ... read: ... write: ... superclasses: ...` form.
- Library restructure: reorganized into layered directories (core, stdlib, etc).
- Improved GTK callback stability and closure capture handling.

### Fixed
- Source location tracking now reparses files after edits so method offsets follow line-count changes.
- GUI/browser editing paths no longer depend solely on stale cached line ranges.
- Closure capture in IfNode/WhileNode control flow blocks.
- Array sorting and collection method improvements.
- Exception handling and block unwind cleanup fixes.
- Builder heightRequest and compilation fixes.

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

[Unreleased]: https://github.com/gokr/harding/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/gokr/harding/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/gokr/harding/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/gokr/harding/compare/v0.6.0...v0.7.0
