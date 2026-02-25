# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Harding is a prototype-based Smalltalk dialect that compiles to Nim. It provides:
- Smalltalk-like object system with prototype inheritance
- Nim compilation backend
- REPL for interactive development
- FFI integration for calling Nim code

**Current Status**: v0.6.0 - Functional interpreter with green threads, MIC/PIC caching, Smalltalk-style resumable exceptions, GTK IDE, VSCode extension, and Granite compiler for native binary compilation.

## Quick Reference

### Build Commands

```bash
nimble harding           # Build harding REPL in repo root (debug)
nimble harding_release   # Build harding REPL in repo root (release)
nimble bona              # Build bona IDE in repo root (debug)
nimble bona_release      # Build bona IDE in repo root (release)
nimble test              # Run all tests
nimble clean             # Clean build artifacts
nimble install_harding   # Install harding binary to ~/.local/bin/
```

**IMPORTANT**: Use `nimble harding` to build the REPL and `nimble bona` to build the IDE. These commands place binaries in the root directory for easy access. Using `nimble build` alone will NOT update the root directory binaries.

See [TOOLS_AND_DEBUGGING.md](docs/TOOLS_AND_DEBUGGING.md) for additional build tasks (debugger, profiler, LSP, etc.).

### Testing

```bash
nimble test              # Run all tests
```

Tests use Nim's built-in unittest framework. Key test areas:
- Core interpreter: message dispatch, method execution, closures, control flow
- Object model: class creation, inheritance, slots
- Exception handling: on:do:, signal, resume, retry
- Concurrency: green threads, scheduler, sync primitives
- Standard library: primitives, perform

### Debugging

```bash
# Debug logging
harding --loglevel DEBUG script.harding

# Show AST
harding --ast script.harding

# REPL mode
harding
```

See [TOOLS_AND_DEBUGGING.md](docs/TOOLS_AND_DEBUGGING.md) for comprehensive debugging documentation.

## Project Structure

```
harding/
├── src/
│   ├── harding/
│   │   ├── core/           # Core types (Node, Instance, Class)
│   │   ├── parser/         # Lexer and parser
│   │   ├── interpreter/    # VM, objects, activation
│   │   ├── codegen/        # Nim code generation
│   │   ├── compiler/       # Granite compiler
│   │   ├── repl/           # REPL and interactive mode
│   │   ├── ffi/            # Foreign Function Interface
│   │   └── gui/            # GTK IDE
│   └── granite.nim         # Compiler entry point
├── lib/harding/            # Standard library (.hrd files)
├── tests/                  # Test suite
├── docs/                   # Documentation
│   ├── IMPLEMENTATION.md   # Architecture and internals
│   ├── TOOLS_AND_DEBUGGING.md  # Tools and debugging
│   ├── MANUAL.md           # Language manual
│   ├── GTK.md              # GTK integration
│   ├── VSCODE.md           # VSCode extension
│   └── research/           # Historical design docs
└── harding.nimble          # Build configuration
```

## Key Documentation

| Document | Purpose |
|----------|---------|
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | Architecture, VM internals, coding guidelines |
| [TOOLS_AND_DEBUGGING.md](docs/TOOLS_AND_DEBUGGING.md) | Tools usage, debugging, profiling |
| [MANUAL.md](docs/MANUAL.md) | Language syntax and semantics |
| [bootstrap.md](docs/bootstrap.md) | Bootstrap architecture details |
| [FUTURE.md](docs/FUTURE.md) | Future development plans |

## Nim Coding Guidelines (Summary)

### Code Style

- **camelCase**, not snake_case
- Do not shadow the implicit `result` variable
- Prefer `return expression` for early exits
- Doc comments use `##` placed **after** proc signature
- Use `fmt("...")` not `fmt"..."` (escaped characters)
- Import full modules, not selected symbols
- Export with `*` suffix

### Memory Management

- **var**: Stack-allocated, copy-on-assignment (default for most types)
- **ref**: GC heap references, use `new()` to allocate
- **ptr**: Manually managed, use with `alloc()`/`dealloc()` only when necessary

When storing Nim `ref` objects as raw `pointer` in `Instance.nimValue`, you **must** register them in keep-alive registries to prevent ARC/ORC from collecting them. See [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for details.

### Critical Rules

1. **No `asyncdispatch`**: Use threads or taskpools for concurrency
2. **No `try/finally` in VM primitives**: Breaks stackless design
3. **Remove old code during refactoring**: Don't leave commented-out code
4. **Don't shadow `result`**: Nim's implicit return variable

### Thread Safety

Use `{.gcsafe.}` blocks for accessing shared state from threads:

```nim
proc someProc() {.gcsafe.} =
  {.gcsafe.}:
    withLock(someLock):
      # access shared data
```

See [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for comprehensive Nim coding guidelines, memory management details, and thread safety patterns.

## Stackless VM Design

Harding uses a **stackless virtual machine** design where execution is driven by a work queue rather than the native call stack. This is critical for supporting green threads and continuations.

**Key Principle**: All control flow must go through the work queue. Never use Nim's `try/finally` or exception handling in VM primitives.

**Work Queue Pattern**:
```nim
# WRONG - breaks stackless design
try:
  result = evalBlock(...)  # May suspend!
finally:
  cleanup()  # Runs at wrong time!

# CORRECT - maintains stackless design
interp.pushWorkFrame(newCleanupFrame())
interp.pushWorkFrame(newEvalFrame(block))
# Return and let VM process work queue
```

See [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for complete VM architecture documentation.

## Exception Handling

Harding uses Smalltalk-style resumable exceptions with signal point preservation:

- **`on:do:`** - Install exception handler
- **`signal:`** - Signal exception (preserves signal point)
- **`resume`** / **`resume:`** - Resume from signal point with optional value
- **`retry`** - Re-execute protected block
- **`pass`** - Delegate to next handler
- **`return:`** - Return value from on:do: expression

The signal point is preserved via `ExceptionContext` which captures full VM state at the signal point, enabling resumable behavior in a stackless VM.

See [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for complete exception handling documentation.

## Language Syntax Quick Reference

### Class Definition
```harding
Point := Object derive: #(x y).
Point := Object deriveWithAccessors: #(x y).  # With auto-generated getters/setters
```

### Method Definition
```harding
Point>>distanceTo: otherPoint [
    | dx dy |
    dx := (otherPoint x) - (self x).
    dy := (otherPoint y) - (self y).
    ^ ((dx squared) + (dy squared)) sqrt  # Return with ^
]
```

### Primitives (Nim integration)
```harding
# Declarative form
Integer>>+ other <primitive primitivePlus: other>

# Inline form
MyClass>>clone [
    ^ <primitive primitiveClone>
]
```

### Blocks (Closures)
```harding
[:param | param + 1]                    # Block with parameter
[:a :b | a + b]                         # Multiple parameters
[Transcript showCr: "Hello"]            # No parameters
```

### Conditionals and Loops
```harding
condition ifTrue: [...] ifFalse: [...].
[condition] whileTrue: [body].
n timesRepeat: [body].
```

See [MANUAL.md](docs/MANUAL.md) for complete language documentation.

## Where to Find Things

| What you're looking for | Where to look |
|------------------------|---------------|
| How to build/test | [Build Commands](#build-commands) above |
| How to debug | [TOOLS_AND_DEBUGGING.md](docs/TOOLS_AND_DEBUGGING.md) |
| VM architecture | [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) |
| Language syntax | [MANUAL.md](docs/MANUAL.md) |
| Nim coding standards | [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) |
| GTK integration | [GTK.md](docs/GTK.md) |
| VSCode extension | [VSCODE.md](docs/VSCODE.md) |
| Historical designs | [docs/research/](docs/research/) |

## Known Issues

**ORC Crash in Some Threading Tests**: Some network tests may show ORC crash during thread cleanup due to Nim issue #25253. This is a confirmed Nim compiler bug, not a code issue.

Workaround: Use `{.acyclic.}` pragma on types with cross-thread references and avoid closures in cross-thread code (use raw pointers instead).

See [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for complete ORC crash prevention patterns.

## Code Quality

- All tests must pass
- No compiler warnings in test code
- Remove unused imports and variables
- Keep code clean and focused

---

For detailed implementation information, see [IMPLEMENTATION.md](docs/IMPLEMENTATION.md).
For tool usage and debugging, see [TOOLS_AND_DEBUGGING.md](docs/TOOLS_AND_DEBUGGING.md).
