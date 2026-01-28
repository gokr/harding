# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nimtalk is a prototype-based Smalltalk dialect that compiles to Nim. It provides:
- Smalltalk-like object system with prototype inheritance
- Nim compilation backend
- REPL for interactive development
- FFI integration for calling Nim code

**Current Status**: Early prototype with basic parsing, evaluation, and object system.

## Build Commands

```bash
nimble build             # Build the REPL and compiler (binaries in subdirectories)
nimble local             # Build and copy binaries to root directory for convenience
nimble test              # Run all tests (automatic discovery via testament)
nimble clean             # Clean build artifacts and binaries
nimble install           # Install ntalk binary to ~/.local/bin/
```

### Convenience Tasks

The following nimble tasks provide convenient shortcuts for common development tasks:

- **`nimble local`**: Builds the project using `nimble build` and copies the `ntalk` and `ntalkc` binaries to the root directory for easy access
- **`nimble clean`**: Removes build artifacts including nimcache, build directories, and binaries from all locations
- **`nimble install`**: Copies the `ntalk` binary to `~/.local/bin` (Unix/Linux/macOS) or appropriate Windows location

These tasks match the functionality previously only available through `nim e build.nims <task>`.

## Testing

Tests use Nim's built-in unittest framework. Run tests with:

```bash
nim c -r tests/test_core.nim
```

## Logging and Debugging

Both `ntalk` and `ntalkc` support a `--loglevel` option to control logging output. This is useful for debugging execution flow and tracing interpreter behavior.

### Available Log Levels

- `DEBUG` - Detailed tracing of execution flow, message sends, variable lookups
- `INFO` - General information about operations being performed
- `WARN` - Warning messages for potentially problematic situations
- `ERROR` - Error messages (default level)
- `FATAL` - Fatal error messages only

### Using Logging

**For the REPL (ntalk):**
```bash
# Start REPL with debug logging
ntalk --loglevel DEBUG

# Run a script with debug logging
ntalk --loglevel DEBUG myprogram.nt

# Evaluate expression with info logging
ntalk --loglevel INFO -e "3 + 4"
```

**For the compiler (ntalkc):**
```bash
# Compile with debug logging
ntalkc compile myprogram.nt --loglevel DEBUG

# Build with info logging
ntalkc build myprogram.nt --loglevel INFO

# Run with debug logging
ntalkc run myprogram.nt --loglevel DEBUG
```

### Debug Logging Output

When using `DEBUG` level, you'll see:
- Each AST node being evaluated and its type
- Message sends with receiver and selector
- Method lookups and execution
- Variable assignments and lookups
- Activation stack push/pop operations
- Method entry/exit with return values

Example debug output:
```
Evaluating node: nkMessage
Message send: +
Message receiver: 3
Looking up method: +
Found method, executing
Executing method with 1 arguments
Pushing activation, stack depth: 1
Evaluating node: nkLiteral
Returning from method: 7
Popping activation, stack depth: 0
```

### Adding Debug Logging

When modifying the evaluator or other core components, use the `debug` macro:

```nim
import std/logging

# In evaluation code
debug("Message send: ", selector)
debug("Variable lookup: ", name, " = ", value.toString())
```

The `debug` statements are only active when the log level is set to DEBUG or lower.

### AST Debugging

Both `ntalk` and `ntalkc` support an `--ast` flag to dump the Abstract Syntax Tree after parsing. This is useful for understanding how your Nimtalk code is being parsed before execution or compilation.

**For the REPL (ntalk):**
```bash
# Show AST for a script and then execute it
ntalk --ast examples/demo.nt

# Show AST for an expression and show result
ntalk --ast -e "3 + 4"

# Combine with debug logging for full visibility
ntalk --ast --loglevel DEBUG script.nt
```

**For the compiler (ntalkc):**
```bash
# Show AST before compiling
ntalkc compile myprog.nt --ast

# Show AST with debug logging
ntalkc compile myprog.nt --ast --loglevel DEBUG
```

The AST output shows the hierarchical structure of parsed expressions, making it easier to understand how messages, literals, and other constructs are represented.

## Nim Coding Guidelines

### Code Style and Conventions
- Use camelCase, not snake_case (avoid `_` in naming)
- Do not shadow the local `result` variable (Nim built-in). Nim provides an implicit `result` variable that holds the return value; declaring a local variable named `result` shadows it and causes warnings.
- Doc comments: `##` below proc signature
- Prefer generics or object variants over methods and type inheritance
- Use `return expression` for early exits
- Prefer direct field access over getters/setters
- **NO `asyncdispatch`** - use threads or taskpools for concurrency
- Remove old code during refactoring
- Import full modules, not selected symbols
- Use `*` to export fields that should be publicly accessible
- When using fmt **ALWAYS** write it as `fmt("...")` not `fmt"..."` (escaped characters)

### Memory Management: var, ref, and ptr

**Nim is Value-Based**: Understanding Nim's value semantics is critical for memory safety.

#### var (Value Types)
- Creates stack-allocated values with copy-on-assignment semantics
- `var x = y` creates a copy of `y` (except for ref/ptr types)
- Use for objects that don't need shared ownership or heap allocation
- Default for most types - safer and more efficient

#### ref (Traced References)
- Garbage-collected heap references (preferred for shared objects)
- Use `new()` to allocate: `var obj = new(MyType)`
- Assignment copies the reference, not the object
- Automatically managed by Nim's garbage collector
- Use when you need shared ownership or want to avoid copying

#### ptr (Untraced Pointers)
- Manually managed memory (unsafe)
- Use with `alloc()`/`dealloc()`: must manage lifetime yourself
- Required for FFI or low-level system programming
- Must call `reset()` on GC objects before deallocating to prevent leaks
- Avoid unless absolutely necessary

#### Common Pitfalls

**NEVER take address of temporary copies:**
```nim
# DANGEROUS - undefined behavior!
proc badExample(): ptr int =
  var x = 42
  var table = {"key": x}
  result = addr table["key"]  # Points to temporary copy!
```

**SAFE patterns:**
```nim
# Store refs directly in containers when sharing is needed
type
  MyStruct = ref object
    data: int

proc safeExample(): Table[string, MyStruct] =
  result = {"key": MyStruct(data: 42)}  # Store ref, not value
```

#### ref Objects Design Pattern

For objects that will frequently be shared or passed around, consider defining them as `ref object` from the start:

```nim
# Good: Natural reference semantics
type
  DataFile = ref object
    handle: File
    size: uint64
    lock: Lock

  # Usage: no wrapping needed
  proc createDataFile(): DataFile =
    result = DataFile(handle: open(...), size: 0)
```

This provides a more Java-esque mental model where objects are naturally heap-allocated and shared via references. Benefits:
- No need to wrap value types in `ref` everywhere
- Cleaner API without constant `[]` dereferencing
- Natural shared ownership semantics
- Less error-prone than manual `ref` wrapping

**Rule of Thumb:**
- Use `var` for stack-local and simple values
- Use `ref object` for types intended to be shared (data structures, files, network connections)
- Use `ref` wrapping only when retrofitting existing value types
- Use `ptr` only for FFI or when you specifically need manual memory management
- Never use `addr` and `cast` to create refs from value types in containers

### Function and Return Style
- **Single-line functions**: Use direct expression without `result =` or `return`
- **Multi-line functions**: Use `result =` assignment and `return` for clarity
- **Early exits**: Use `return value` instead of `result = value; return`
- **Exception handlers**: Use `return expression` for error cases

### Comments and Documentation
- Do not add comments talking about how good something is
- Do not add comments that reflect what has changed (use git)
- Do not add unnecessary commentary or explain self-explanatory code

### Refactoring
- Remove old unused code during refactoring
- Delete deprecated methods, unused types, and obsolete code paths immediately
- Keep the codebase lean and focused

## Thread Safety

**Important**: Do not use asyncdispatch. Use regular threading or taskpools for concurrency.

### Lock-Protected Data Structures
- Use `Lock` for concurrent access to shared data structures
- Use condition variables for coordination when needed

### GC Safety Pattern
For threaded code that accesses shared state, use `{.gcsafe.}` blocks:

```nim
proc someThreadedProc*() {.gcsafe.} =
  {.gcsafe.}:
    # Access to shared state that is actually thread-safe
    # but can't be proven so by the compiler
    withLock(keydir.lock):
      keydir.entries[key] = entry
```

Use `{.gcsafe.}:` blocks only when certain the code is actually thread-safe (e.g., lock-protected access).

## Documentation Guidelines

### Nim Doc Comment Guidelines

#### Basic Syntax

**Documentation comments** use double hash (`##`):
```nim
## This is a documentation comment - will appear in generated docs
```

**Regular comments** use single hash (`#`):
```nim
# This is a regular comment - will NOT appear in generated docs
```

#### Placement

- **Module docs**: At the top of the file, before imports
- **Type docs**: After the type definition
- **Proc docs**: After the proc signature
- **Field docs**: Using `##` after each field in type definitions

#### Important Rule: Exports

**Documentation will only be generated for exported types/procedures/etc.**

Use `*` following the name to export:
```nim
type Record* = object    ## Will generate docs for Record (exported)
type Person = object     ## Will NOT generate docs for Person (not exported)

proc open*(path: string): DataFile =  ## Will generate docs (exported)
proc close(path: string) =            ## Will NOT generate docs (not exported)
```

#### Standard Sections

**Description**: First line or first paragraph
```nim
proc len*(keyDir: var KeyDir): int =
  ## Get the number of entries in the KeyDir
```

**Parameters**: Inline format (Nim stdlib style)
```nim
## limit: Maximum number of items to return (default: 1000)
## cursor: Last key from previous page (empty string for first page)
```

**Returns**: Inline description
```nim
## Returns the number of records recovered
```

**Or explicit Returns section**:
```nim
## Returns: (live_records, total_records, fragmentation_ratio)
```

**Code Examples**: Using `**Example:**` with code blocks
```nim
## **Example:**
## ```nim
## var t = {"name": "John", "city": "Monaco"}.newStringTable
## doAssert t.len == 2
## ```
```

**Raises**: Can be inline or in pragmas
```nim
## If key is not in t, the KeyError exception is raised
```

**See also**: For related documentation
```nim
## See also:
## *   `hasKey proc`
## *   `items proc`
```

**Deprecated**: Using pragma
```nim
proc oldApi*() {.deprecated: "Use newApi instead".} = ...
```

#### Formatting

**Backticks for code identifiers**:
```nim
## Use `open` to create a new data file
```

**Double backticks for format specs**:
```nim
## Returns: ``(items: seq[(string, string)], nextCursor: string, hasMore: bool)``
## Format: ``[timestamp:8][keyLen:4][key][valLen:4][flags:1][algorithm:1][value]``
```

#### Best Practices

1. **Add exactly one space after `##`**:
```nim
## Good: One space after hash marks
##Bad: No space after hash marks
```

2. **Always include code examples for key public APIs**:
```nim
proc set*(barrel: Barrel, key, value: string): bool =
  ## Store a key-value pair
  ##
  ## **Example:**
  ## ```nim
  ## let barrel = openBarrel("data.db")
  ## barrel.set("user:1", "Alice")
  ## barrel.close()
  ## ```
```

3. **Document all export parameters**:
```nim
proc itemsInRange*(barrel: Barrel, startKey: string, endKey: string,
                   limit: int = 1000, cursor: string = ""): (seq[(string, string)], string, bool) =
  ## Get key-value pairs in range [startKey, endKey)
  ## limit: Maximum number of items to return (default: 1000)
  ## cursor: Last key from previous page (empty string for first page)
```

4. **Document return types**:
```nim
## Returns: ``(items: seq[(string, string)], nextCursor: string, hasMore: bool)``
```

5. **Use enum inline comments for clarity**:
```nim
type
  SyncMode* = enum
    None = "none"       # No sync (fastest, risk of data loss)
    Sync = "sync"       # Sync to OS buffer
    Fsync = "fsync"     # Sync to disk (safest)
```

#### What NOT to Do

- **Don't use `#` for documentation** - it won't appear in generated docs
- **Don't omit exports** - non-exported items won't generate documentation
- **Don't skip parameter docs** - users need to know what each parameter does
- **Don't forget code examples** - they're the most helpful part of documentation

### Writing Style
- Use neutral, factual language
- Avoid superlatives and hype words
- Describe features without marketing language
- Focus on implementation details and behavior

### Do's and Don'ts
- Do: "Fast recovery"
- Don't: "Ultra-fast recovery"
- Do: "Provides good performance"
- Don't: "Optimal performance", "Maximum performance"
- Do: "Buffer size 64KB-256KB (recommended)"
- Don't: "Optimal buffer size", "Perfect for X"

### Performance
- Use "~" for approximate values: "~250K ops/sec"
- Include measurement context implicitly or explicitly
- Use "fast" sparingly, only when justified
- Avoid "extremely", "incredibly", "amazingly"

### General Tone
- Professional but understated
- Technical, not promotional
- Helpful without exaggeration
- Clear and direct

## Code Quality and Testing

### Maintaining Clean Code
Always check for and remove compiler warnings:
- **Unused imports**: Remove imports that are not used (e.g., `Warning: imported and not used`)
- **Unused variables**: Remove variables declared but never used (e.g., `Hint: 'foo' is declared but not used`)
- **Unused parameters**: Use `_` prefix or `_` to indicate intentionally unused variables
- Run tests frequently to catch warnings early

### Test Quality Standards
- **All tests must pass**: Green tests are non-negotiable
- **No warnings in test compilation**: Test code should compile without warnings
- **Tests should run quickly**: Keep tests focused and fast
- **Test names should be descriptive**: Clearly state what is being tested
- **Clean up test data**: Tests should remove temporary files/directories
- **Avoid flaky tests**: Tests should be deterministic and reliable

### When to Ignore Warnings
- Some warnings from dependencies (like Mummy) are unavoidable
- ORC-related crashes during thread shutdown are a known Nim issue
- Document known issues in code comments or CLAUDE.md

## Known Issues

**ORC Crash in Some Threading Tests**: Some network tests may show ORC crash during thread cleanup due to Nim issue #25253. This is NOT a code issue - it's a confirmed Nim compiler bug.

**Root Cause**: Nim's ORC garbage collector can crash when cleaning up objects with circular references across thread boundaries. The crash happens in `orc.nim:unregisterCycle()` during thread shutdown.

### ORC Crash Prevention with {.acyclic.} and Closure Elimination

The compaction system uses two approaches to prevent ORC cycle detection crashes:

#### 1. Mark types as {.acyclic.}

Use `{.acyclic.}` on types that participate in cross-thread references:
```nim
BarrelObj {.acyclic.} = object
  # ... fields including compactController: CompactController

CompactControllerObj {.acyclic.} = object
  # ... raw pointers instead of closures
```

#### 2. Eliminate closures in cross-thread code (critical!)

**Problem**: Closures create GC-managed environments that ORC tracks. When objects are destroyed across thread boundaries (e.g., in Mummy's WebSocket worker pool), ORC can crash during cycle detection.

**Solution**: Store raw pointers directly instead of closures:
```nim
# BAD - closures cause ORC crashes in threaded code
proc newCompactController(keyDir: ptr KeyDir): CompactController =
  proc updateCallback(key: string, entry: KeyDirEntry) {.gcsafe.} =
    keyDir[].add(key, entry)  # Closure captures keyDir
  result.updateEntry = updateCallback  # ORC tracks closure environment

# GOOD - direct pointer storage, no closures
type
  IndexMode = enum
    imNone, imKeyDir, imCritBit

  CompactControllerObj = object
    indexMode: IndexMode
    keyDirPtr: pointer    # Raw pointer, not tracked by ORC
    critBitPtr: pointer

proc updateIndex(controller: CompactController, key: string, entry: KeyDirEntry) =
  case controller.indexMode
  of imKeyDir:
    cast[ptr KeyDir](controller.keyDirPtr)[].add(key, entry)
  # ...
```

#### Additional safeguards

**Cleanup order matters**: Shutdown controllers BEFORE deinitializing resources:
```nim
proc close*(barrel: Barrel) =
  # Wait for threads to complete
  while barrel.compactionState.inProgress:
    sleep(10)
  barrel.joinCompactionThread()

  # Shutdown controller BEFORE deinit - it holds pointers to these
  if barrel.compactController != nil:
    barrel.compactController.shutdown()
    barrel.compactController = nil

  # Now safe to deinit
  barrel.keyDir.deinit()
```

#### When to apply these patterns

- **Use {.acyclic.}**: On ref object types involved in cross-thread patterns
- **Eliminate closures**: When callbacks/procs need to access data across threads
- **Use raw pointers**: Instead of closures that capture references

## Project Structure

```
nimtalk/
├── core/           # Core types and object system
├── parser/         # Lexer and parser
├── interpreter/    # Evaluation and activation
├── compiler/       # Nim code generation
├── repl/           # Read-Eval-Print Loop
└── ffi/            # Foreign Function Interface
```

## File Naming Conventions

- Source files use `.nim` extension
- Test files use `test_*.nim` pattern
- Example files use `.nt` extension (Nimtalk source)

## Future Directions

### BitBarrel Integration
Consider integrating BitBarrel (the high-performance Bitcask-style key-value storage engine from ../bitbarrel) as a core part of Nimtalk. This would provide:
- First-class barrel objects in Nimtalk
- Built-in persistence model similar to Gemstone and original OODBs
- High-performance storage with O(1) reads via in-memory hash index
- Crash recovery with hint files for fast startup
- Background compaction

Potential integration approaches:
1. Expose BitBarrel API as Nimtalk objects and methods
2. Implement barrel literals in the language syntax
3. Provide transparent persistence for Nimtalk objects
4. Use FFI to call BitBarrel C API or directly link the Nim library

This would give Nimtalk a powerful persistence layer built into the language.