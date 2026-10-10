# AGENTS.md

This file provides guidance to AI coding agents (Claude Code and similar tools) working in this repository.

## Project Overview

Harding is a class-based Smalltalk dialect that compiles to Nim. It provides a Smalltalk-like object system, stackless AST interpreter, Nim compilation backend (Granite), REPL, GTK4 IDE (Bona), VSCode extension (LSP/DAP), optional MummyX HTTP server integration, and an external library system (`harding lib`).

**Current Status**: v0.8.0 - Functional interpreter with green threads, MIC/PIC caching, Smalltalk-style resumable exceptions, GTK4 IDE, VSCode extension, Granite compiler for native binary compilation, MummyX web server support, and installable external libraries (BitBarrel, MySQL, SQLite, JWT, etc.). FFI to Nim is still in progress.

## Build Commands

```bash
nimble harding           # Build harding REPL in repo root (debug)
nimble harding_release   # Build harding REPL in repo root (release)
nimble bona              # Build bona IDE in repo root (debug)
nimble bona_release      # Build bona IDE in repo root (release)
nimble test              # Run all tests (incl. external library tests)
nimble testCore          # Run core VM/language tests only
nimble testStdlib        # Run stdlib tests only
nimble testOther         # Run compiler/IDE/integration tests only
nimble clean             # Clean build artifacts and binaries
nimble discover          # Scan external/ and regenerate external_libs_generated.nim
nimble harding_lsp       # Build the LSP server
nimble install_harding   # Install harding binary to ~/.local/bin/
nimble install_bona      # Install bona binary and desktop integration
nimble vsix              # Build the VSCode extension package
```

**IMPORTANT**: Use `nimble harding` / `nimble bona` to build. These place binaries in the root directory. `nimble build` alone will NOT update root directory binaries.

Granite has no nimble task; build it directly:

```bash
nim c -p:external -o:granite src/harding/compiler/granite.nim
```

After installing/removing external libraries (`./harding lib install <name>`), run `nimble discover` and rebuild with `nimble harding` so the generated external library integration picks up the change.

## Testing

Tests use Nim's unittest framework, run via testament: `nimble test` runs all tests in `tests/test_*.nim` plus installed external library tests (`<externalLib>/tests/test_*.nim`). Individual tests: `nim c -r tests/test_interpreter_core.nim`. Test files follow `test_*.nim` pattern covering core interpreter, object model, parser, exceptions, concurrency, stdlib, compiler, and integration. ARC and ORC are supported validation targets; verify actual results rather than assuming the suite is green.

## Bona Production Hardening

The active goal is a reliable Smalltalk environment: Workspace, Browser, Inspector, Transcript, and Builder. See `docs/BONA_ASSESSMENT.md` for reproduced defects and evidence; keep this section current as fixes land.

### Phases and scope

1. Fix confirmed defects, starting with source loss, bootstrap initialization, GTK dialog ABI, MCP startup/ownership, dirty-editor refresh, and shutdown. Add a focused regression with each fix; do not defer safety tests until phase 2.
2. Exercise every existing tool through deterministic model/integration tests and black-box GTK acceptance tests. Cover save/reload, errors and recovery, dialogs/cancellation, repeated open/close, and preservation of unsaved edits.
3. Make creating GTK apps in Harding straightforward and make Builder produce a single executable that embeds the application sources and the Harding interpreter, with a defined system dependency contract (GTK4, GtkSourceView 5, VTE for the IDE, MummyX/NimCP for web/MCP builds). The embedded-interpreter target is agreed and is the first packaging mode; Granite compilation remains a separate backend that Builder can select later. A packaged app must run without the source tree and without a separate `harding` binary.

Granite compiler development is separate (including `worktrees/granite-completeness`); do not modify that worktree or expand this effort into compiler parity work without agreement. Preserve unrelated/uncommitted changes, including installed external-library changes.

### Current progress

- Implemented: Granite bootstrap initialization and invalid dependency-array syntax; GTK4 dialog ABI/literal messages/cancellation cleanup; targeted atomic Browser source writes; dirty-editor refresh deferral; bounded Transcript history, close/reopen retention, and class-side `contents` delegation.
- Language/runtime contracts agreed and implemented: failed loads signal `LoadError` (new `lib/core/LoadError.hrd`) for both `Harding load:` and `Library load:`, and `Object evaluate:` returns a structured `ok`/`value`/`error` table. `Object eval:` keeps its plain-value/error-string behavior for compatibility. `evaluate:` shares globals, source indexing and scheduler ownership with the caller, making it safe for Bona tools and MCP dispatch.
- Bona tools migrated to the structured contract: Workspace, Inspector, Browser, Builder, Transcript, and BonaMCP no longer classify results by error-message prefixes. Workspace Do It now reports its result to Transcript, matching documented behavior.
- Verified through gnome-ui-mcp: Workspace opening/text insertion/Print It and Builder New creating `MyApp` after the bootstrap fix. This is not yet a complete acceptance suite.
- Outstanding: safe source reflection/display/reload, scheduler-bound BonaMCP startup and lifecycle, coordinated shutdown, the embedded-interpreter packaging path, and complete tool acceptance coverage. Builder persistence and source-backed editing are implemented and covered by tests.
- Focused logs live in `build/bona-hardening/`. Tests include `test_source_editor`, `test_load_and_eval`, Bona models, GUI automation, and interpreter core; do not claim the complete test suite has passed from these alone.

### Interpreter and language discussion gate

Bring interpreter/language defects to the user with a minimal reproduction, expected versus actual behavior, affected workflows, and proposed choices. Do not silently adapt language semantics to work around IDE bugs. Straightforward bootstrap/FFI/UI fixes that preserve semantics can proceed with regressions.

Load failure and structured evaluation were explicitly agreed and are implemented: `LoadError` is signaled instead of printing and returning nil, and `Object evaluate:` returns `{ok, value, error}` while `Object eval:` stays unchanged. New Bona code should use `Object evaluate:`.

Still open for discussion: `Object eval:` scheduler ownership for long-running work was partly addressed by `evaluateIsolated`, but suspension/cancellation of an in-flight evaluation is not implemented; do not claim interruptibility until it is.

`::` on ordinary Bona tool instances produced `Message not understood: at:` in regression setup; use explicit accessors for now and investigate named-access dispatch with a minimal interpreter test before changing its contract. Transcript had an instance `contents` method but no class-side delegation despite BonaMCP calling `Transcript contents`; the delegation is now explicit.

`Library load:` and `Harding load:` signal `LoadError` on missing files, parse errors, and load-time failures; globals and library bindings are left unchanged on failure. Do not reintroduce silent nil returns in load paths.

Source reflection is currently line-based and counts brackets without respecting strings/comments. Do not treat it as a safe general-purpose source rewriter. Targeted writes use `src/harding/interpreter/source_editor.nim` and `Harding editSourceFile:owner:selector:replacement:delete:`; this validates parser-delimited definitions without evaluating proposed code. Browser saves/deletes must preserve unrelated classes, statements, comments, class-side methods, and formatting; validate before writing and use atomic replacement. Do not test destructive editing on repository sources.

### GUI automation: gnome-ui-mcp

A local `gnome-ui` MCP server is registered with Niffler, using `gnome-ui-mcp` 0.5.0 from commit `b11ec2f63ee712a0a78b40a93a7add2b89e96bef`. Its disposable checkout is `build/gnome-ui-mcp/repo`, environment `build/gnome-ui-mcp/venv`. Recreate locally without Docker or global Python changes:

```bash
uv venv --python /usr/bin/python3 --system-site-packages build/gnome-ui-mcp/venv
uv pip install --python build/gnome-ui-mcp/venv/bin/python ./build/gnome-ui-mcp/repo
build/gnome-ui-mcp/venv/bin/gnome-ui-mcp --help
```

The system Python supplies PyGObject/AT-SPI. The server needs the same GNOME Wayland session environment: `DBUS_SESSION_BUS_ADDRESS`, `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, `DISPLAY`, and `XDG_SESSION_TYPE`. Registration enables only accessibility, navigation, window, state, and waiting categories; calls are serial. Discover `mcp-gnome-ui` tools in the harness.

- Launch Bona with `GTK_A11Y=atspi`; keep it alive using the harness background-process facility, not an unowned `&` child of a short tool call.
- Set `set_boundaries(app_name="bona", allow_global_keys=[])` before interacting. This is name-based, not a sandbox: avoid multiple Bona instances and verify the process/window being tested.
- Scope discovery to Bona. Use `list_windows`, then a window-scoped snapshot or `find_elements` with role/name. Re-discover after changes; numeric AT-SPI paths and snapshot UIDs are not durable.
- `activate_element` with action `click` and `set_element_text` work on the tested GTK4 surface without mouse coordinates. Prefer these over input injection or desktop-wide permission/configuration changes.
- `get_element_text` returned empty text despite nonzero character counts in the initial trial. Cross-check with `Atspi.Text.get_text(accessible, 0, -1)` using system Python; do not report successful UI behavior solely from an action's `success` flag.
- The initial Print It trial produced editor text `3 + 47` (six characters), not a spaced result; verify selection behavior and record this as a workflow issue, not an arithmetic failure.
- Test sessions must use disposable working directories or non-colliding workspace IDs: Workspace reads/writes `workspace-<id>.hrd` in the current directory and can delete empty workspace files on save/close. Do not overwrite a developer's existing workspace. Redirect it with `Workspace filePath: <abs path>` rather than relying on the default; the GUI automation tests do this and assert the repo root stays clean.
- Do not operate on unrelated applications, capture the whole desktop unnecessarily, or relax a boundary after a failed call. Shut down only test processes owned by this task.
- Do not run a suite that writes or deletes tracked repository files without checking afterwards; `test_badminton_buddy` previously deleted `badminton-buddy/badminton.db` (now fixed). Run `git status` after long sweeps and restore accidental deletions.

### Validation and known dependencies

```bash
nimble bona
nim c -r --out:build/test_bona_models tests/test_bona_models.nim
nim c -r --out:build/test_source_editor tests/test_source_editor.nim
nim c -r --out:build/test_load_and_eval tests/test_load_and_eval.nim
nim c -r --out:build/test_gui_automation tests/test_gui_automation.nim
```

Bona needs GTK4, GtkSourceView 5, and **GTK4** VTE (`libvte-2.91-gtk4.so.0`); GTK3 VTE is not compatible. On the assessed Ubuntu host GTK4 VTE was missing. A runtime package was extracted locally under `build/bona-assessment/deps`; use its `usr/lib/x86_64-linux-gnu` in `LIBRARY_PATH` for linking and `LD_LIBRARY_PATH` for running, or explicitly arrange installation. Do not substitute the GTK3 library.

The full `tests/test_*.nim` sweep is not green: `test_badminton_buddy` fails at `BadmintonRepository open:` (SQLite repository path; unrelated to Bona work) and its HTTP tests depend on an external server. Treat those as known, separate issues.

The existing nimble test tasks mask failures with `|| true`; inspect actual test results or use direct `nim c -r` for focused validation. A green task exit alone is not proof of passing tests. Headless tests and direct GTK signal tests do not replace real event-loop/AT-SPI acceptance tests. Validate ARC and ORC when touching proxy lifetime, callbacks, or cross-thread services. Logs and scratch work belong under `build/`, not `/tmp`.

## Logging and Debugging

See `docs/TOOLS_AND_DEBUGGING.md` for full details (VS Code configs, GDB usage, debug build variants).

Both `harding` and `granite` support `--loglevel DEBUG|INFO|WARN|ERROR|FATAL` and `--ast` to dump the AST after parsing.

```bash
harding --loglevel DEBUG myprogram.hrd    # Debug logging
harding --ast -e "3 + 4"                  # Show AST
```

Use the `debug` macro from `std/logging` in evaluation code:
```nim
debug("Message send: ", selector)
```

### Debug/Profile Builds

```bash
nimble harding_debug    # REPL with debugger support (--debugger-port 9877)
nimble harding_perf     # Release + debuginfo for perf/FlameGraph profiling
nimble harding_nimprof  # Built-in Nim profiler (writes profile_results.txt)
nimble profile_nimprof  # Build and run nimprof on benchmark/sieve.hrd
nimble profile_perf     # Build and run perf on benchmark/sieve.hrd
```

## Nim Coding Guidelines

### Code Style
- Use camelCase, not snake_case
- Do not shadow the local `result` variable (Nim built-in)
- Doc comments: `##` below proc signature
- Prefer generics or object variants over methods and type inheritance
- Use `return expression` for early exits; prefer direct field access
- **NO `asyncdispatch`** - use threads or taskpools
- Import full modules, not selected symbols
- Use `*` to export public fields
- **ALWAYS** write fmt as `fmt("...")` not `fmt"..."`
- Remove old code during refactoring; keep codebase lean

### Function and Return Style
- **Single-line**: Direct expression without `result =` or `return`
- **Multi-line**: Use `result =` assignment
- **Early exits**: Use `return value`

### Comments
- No comments about how good something is
- No comments reflecting what changed (use git)
- No unnecessary commentary on self-explanatory code

### Memory Management

- **var**: Stack-allocated, copy-on-assignment. Default for most types.
- **ref**: GC-managed heap references. Use for shared objects, `ref object` for types intended to be shared.
- **ptr**: Manual memory (unsafe). Only for FFI. Avoid otherwise.
- Never take address of temporary copies. Never use `addr`/`cast` to create refs from value types in containers.

### ARC/ORC Pointer Safety: Keep-Alive Registries

When storing a Nim `ref` object in `Instance.nimValue` as a raw `pointer`, ARC loses track and may collect it prematurely. Solution: register in a keep-alive seq first.

```nim
registerBlockNode(receiverVal.blockVal)  # Keep alive for ARC
instance.nimValue = cast[pointer](receiverVal.blockVal)  # Now safe
```

Existing registries: `blockNodeRegistry` (src/harding/core/types.nim), `processProxies`/`schedulerProxies`/`monitorProxies`/`sharedQueueProxies`/`semaphoreProxies` (src/harding/core/scheduler.nim), `globalTableProxies` (src/harding/interpreter/vm.nim).

**Rule**: When adding new pointer storage to `nimValue`, always register in the appropriate keep-alive registry first. C/FFI pointers (GTK widgets, file handles) don't need registries.

## Thread Safety

- No asyncdispatch. Use regular threading or taskpools.
- Use `Lock` for concurrent access to shared data structures.
- Use `{.gcsafe.}:` blocks only when code is actually thread-safe (e.g., lock-protected).

### ORC Crash Prevention

Nim ORC can crash with cross-thread circular references (Nim issue #25253). Mitigations:
- Mark types with `{.acyclic.}` for cross-thread ref objects
- Eliminate closures in cross-thread code; use raw pointers instead
- Shutdown controllers BEFORE deinitializing resources they reference

## Stackless VM Design

Harding uses a **stackless VM** driven by a work queue, not the native call stack. This enables green threads and continuations.

The VM maintains: `workQueue` (pending WorkFrames), `evalStack` (expression results), `activationStack` (activation records).

**Key rules for VM primitives:**
- **Never use Nim's try/finally or exception handling** - breaks stackless design
- Primitives schedule work frames, they don't execute directly
- The VM loop (`processWorkFrame`) processes frames from the queue
- Green threads yield by returning control to the VM loop
- Exception handling uses `exceptionHandlers` stack, not Nim exceptions

```nim
# WRONG - breaks stackless design
try:
  result = evalBlock(...)
finally:
  cleanup()

# CORRECT - schedule work frames
interp.pushWorkFrame(newCleanupFrame())
interp.pushWorkFrame(newEvalFrame(block))
```

See `src/harding/interpreter/vm.nim` for implementation and `docs/IMPLEMENTATION.md` for architecture details.

## Exception Handling

See `docs/research/ExceptionHandling.md` for full details. Harding uses **Smalltalk-style resumable exceptions** on top of the stackless VM.

1. `on:do:` schedules three work frames: `[pushHandler][evalBlock][popHandler]`
2. Handler installation saves VM depths (stack, work queue, eval stack)
3. `signal` creates an `ExceptionContext` preserving the signal point, truncates VM state to handler checkpoint
4. Handler block executes with exception as argument

Handler actions: `resume` (restore signal point, return nil), `resume: value`, `retry` (re-execute protected block), `pass` (delegate to outer handler), `return: value`.

Division by zero catches Nim `DivByZeroDefect` and converts to Harding `DivisionByZero` via `signalExceptionByName`. Exception classes are looked up in imported libraries, not just globals.

## Project Structure

```
src/harding/
├── core/           # Core types, scheduler, processes, tagged values
├── parser/         # Lexer and parser
├── interpreter/    # Stackless VM, activation records, evaluator, frame pools
├── compiler/       # Granite: Nim code generation
├── codegen/        # Shared codegen helpers (blocks, expressions, modules, slots)
├── repl/           # CLI, REPL, script execution
├── gui/            # Bona GTK4 IDE
├── lsp/            # Language server for VSCode
├── debugger/       # Breakpoints, debug protocol (HDP), DAP bridge
├── packages/       # External library installer (`harding lib`)
├── external/       # Generated external library integration (auto-generated, do not edit)
├── runtime/        # Compiled runtime support
└── web/            # MummyX and MCP bridges
lib/                # Harding stdlib (.hrd), layered: core, standard, syntax, gui, web, granite, mummyx, reactive, process, mysql, corral
external/           # Installed external libraries (bitbarrel, mysql, sqlite, jwt, nimcp, ...)
docs/               # Documentation
    ├── research/   # Historical design docs (may be outdated)
examples/           # Example .hrd scripts
tests/              # Nim unittest files (test_*.nim)
```

- Source files: `.nim`, test files: `test_*.nim`, Harding source: `.hrd`
- Prefer root-level docs over `docs/research/` for current behavior
- `src/harding/external/external_libs_generated.nim` is auto-generated by `nimble discover`; do not edit by hand

### Changelog Maintenance

Keep `CHANGELOG.md` current. Use Keep a Changelog style sections. Add entries under `## [Unreleased]` during development. When bumping version in `harding.nimble`, update changelog in the same change set.

## Documentation Style

- Use `##` for Nim doc comments (after proc signature). Only exported (`*`) items generate docs.
- Use neutral, factual language. No superlatives or marketing language.
- Use "~" for approximate values. Avoid "extremely", "incredibly", etc.

## Code Quality

- Remove compiler warnings: unused imports, variables, parameters
- All tests must pass; test code should compile without warnings
- Tests should be fast, deterministic, and clean up after themselves

## Harding Language Syntax

See `docs/QUICKREF.md` for full syntax reference and `docs/MANUAL.md` for the complete language manual.

### Basics

```harding
# Comments use hash
"Strings use double quotes"
"String with #{interpolation}"
#mySymbol                          # Symbols
#(1 2 3)                           # Arrays (0-based indexing)
#{"name" -> "Alice"}               # Tables
json{...}                          # Prefix literal syntax for JSON strings
true false nil                     # Booleans and nil
42  3.14  0xFF                     # Numbers
```

### Classes and Methods

```harding
MyClass := Object derive: #(slot1 slot2)
Point := Object derivePublic: #(x y)

MyClass>>methodName: arg1 with: arg2 [
    | localVar |
    localVar := arg1 + arg2.
    ^localVar
]

MyClass class>>new [
    ^ super new initialize
]
```

### Blocks and Control Flow

```harding
[:param | param + 1]                          # Block with parameter
[:a :b | a + b]                               # Multiple parameters
condition ifTrue: [...] ifFalse: [...]        # Conditionals
[condition] whileTrue: [body].                # While loop
5 timesRepeat: [Transcript showCr: "Hello!"]. # Times repeat
```

### Primitives

```harding
# Declarative form (no method body)
Table>>at: key <primitive primitiveTableAt: key>
Array>>size <primitive primitiveArraySize>

# Inline form (inside method body)
MyClass>>clone [
    ^ <primitive primitiveClone>
]
```

Declarative form: arguments must match method parameter names. Inline form: arguments can be any expression.

### Common Methods

`isEmpty` / `isEmpty not`, `notNil`, `class`, `derive:`, `derivePublic:`, `at:` / `at:put:`, `clone`, `perform:` / `perform:with:`

### Defining Primitives (Nim-backed methods)

The primitive name in the `.hrd` file and the registration key in Nim must match (parameter names are stripped; the colon count must match the method arity). Two conventions are used:

1. **Class-prefixed names** (see `external/mysql`, `docs/NIM_PACKAGE_TUTORIAL.md`):
   ```harding
   MyClass>>connect: host <primitive primitiveMyClassConnect:>
   ```
   ```nim
   let method = createCoreMethod("primitiveMyClassConnect:")
   method.setNativeImpl(myConnectImpl)
   cls.methods["primitiveMyClassConnect:"] = method
   cls.allMethods["primitiveMyClassConnect:"] = method
   ```

2. **Library-prefixed names + `addMethodToClass` helper** (see `external/bitbarrel`):
   ```harding
   Barrel>>connect: host <primitive barrelConnect: host>
   ```
   ```nim
   let method = createCoreMethod("connect:")
   method.setNativeImpl(barrelConnectImpl)
   method.hasInterpreterParam = true
   addMethodToClass(barrelClass, "barrelConnect:", method)
   ```

Key rules:
- Class methods go in `classMethods` / `allClassMethods` tables
- Instance methods go in `methods` / `allMethods` tables
- Use `setNativeImpl()` not direct assignment for native implementation
- The primitive selector in `.hrd` is parsed to extract just the keyword parts (parameter names are stripped)

## BitBarrel Integration

BitBarrel is available as an external Harding library. Install it with `./harding lib install bitbarrel`, then rebuild with `nimble harding`. Classes are embedded in the binary and registered automatically at VM startup, so no manual `load:` is needed.

Classes: `Barrel` (connection), `BarrelTable` (hash-based persistent storage), `BarrelSortedTable` (ordered storage with range queries). Sources live under `external/bitbarrel/lib/bitbarrel/`.

External BitBarrel builds are compiled with the generated `-d:harding_bitbarrel` flag.
