# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Harding is a prototype-based Smalltalk dialect that compiles to Nim. It provides:
- Smalltalk-like object system with prototype inheritance
- Nim compilation backend
- REPL for interactive development
- FFI integration for calling Nim code

**Current Status**: Early prototype with basic parsing, evaluation, and object system.

## Build Commands

```bash
nimble harding           # Build harding REPL in repo root (debug)
nimble harding_release   # Build harding REPL in repo root (release)
nimble bona              # Build bona IDE in repo root (debug)
nimble bona_release      # Build bona IDE in repo root (release)
nimble build             # Build all binaries (in subdirectories only)
nimble test              # Run all tests (automatic discovery via testament)
nimble clean             # Clean build artifacts and binaries
nimble install_harding   # Install harding binary to ~/.local/bin/
```

**IMPORTANT**: Use `nimble harding` to build the REPL and `nimble bona` to build the IDE. These commands place binaries in the root directory for easy access. Using `nimble build` alone will NOT update the root directory binaries.

### Convenience Tasks

The following nimble tasks provide convenient shortcuts for common development tasks:

- **`nimble harding`**: Build the `harding` REPL binary in the root directory
- **`nimble harding_release`**: Build the `harding` REPL with release optimizations
- **`nimble bona`**: Build the `bona` IDE binary in the root directory
- **`nimble bona_release`**: Build the `bona` IDE with release optimizations
- **`nimble clean`**: Removes build artifacts including nimcache, build directories, and binaries from all locations
- **`nimble install_harding`**: Copies the `harding` binary to `~/.local/bin` (Unix/Linux/macOS) or appropriate Windows location
- **`nimble install_bona`**: Installs the `bona` binary and desktop integration (.desktop file and icon)
- **`nimble harding_bitbarrel`**: Build REPL with BitBarrel database support (requires BitBarrel server)

These tasks match the functionality previously only available through `nim e build.nims <task>`.

## Testing

Tests use Nim's built-in unittest framework. Run tests with:

```bash
nim c -r tests/test_core.nim
```

## Logging and Debugging

Both `harding` and `granite` support a `--loglevel` option to control logging output. This is useful for debugging execution flow and tracing interpreter behavior.

### Available Log Levels

- `DEBUG` - Detailed tracing of execution flow, message sends, variable lookups
- `INFO` - General information about operations being performed
- `WARN` - Warning messages for potentially problematic situations
- `ERROR` - Error messages (default level)
- `FATAL` - Fatal error messages only

### Using Logging

**For the REPL (harding):**
```bash
# Start REPL with debug logging
harding --loglevel DEBUG

# Run a script with debug logging
harding --loglevel DEBUG myprogram.harding

# Evaluate expression with info logging
harding --loglevel INFO -e "3 + 4"
```

**For the compiler (granite):**
```bash
# Compile with debug logging
granite compile myprogram.harding --loglevel DEBUG

# Build with info logging
granite build myprogram.harding --loglevel INFO

# Run with debug logging
granite run myprogram.harding --loglevel DEBUG
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

Both `harding` and `granite` support an `--ast` flag to dump the Abstract Syntax Tree after parsing. This is useful for understanding how your Harding code is being parsed before execution or compilation.

**For the REPL (harding):**
```bash
# Show AST for a script and then execute it
harding --ast examples/demo.harding

# Show AST for an expression and show result
harding --ast -e "3 + 4"

# Combine with debug logging for full visibility
harding --ast --loglevel DEBUG script.harding
```

**For the compiler (granite):**
```bash
# Show AST before compiling
granite compile myprog.harding --ast

# Show AST with debug logging
granite compile myprog.harding --ast --loglevel DEBUG
```

The AST output shows the hierarchical structure of parsed expressions, making it easier to understand how messages, literals, and other constructs are represented.

## Debugging and Development

### Building for Debugging

For debugging sessions, you need to build Harding with debug symbols and debug information. The key is to add debug flags to your build commands:

**Debug Build with GDB/LDB Support:**
```bash
# Build Harding with debug symbols for use with GDB or LLDB
nim c -d:debug --debuginfo --debugger:native -o:harding_debug src/harding/repl/harding.nim

# Alternative with additional debug info
nim c -d:debug --debugger:native -d:nimDebugDlOpen --stackTrace:on --lineDir:on -o:harding_debug src/harding/repl/harding.nim
```

**Common Debug Build Options:**
```bash
# With maximum debug information
nim c -d:debug \
  --debugger:native \
  -d:nimDebugDlOpen \
  --lineDir:on \
  --stackTrace:on \
  --stackTraceMsgs:on \
  -d:nimStackTrace \
  -o:harding_debug src/harding/repl/harding.nim
```

**Nimble Task for Debug Builds:**
Add to your `harding.nimble`:
```nim
task debug, "Build with debug symbols":
  exec "nim c -d:debug --debugger:native --debuginfo --lineDir:on --stackTrace:on -o:harding_debug src/harding/repl/harding.nim"
  exec "nim c -d:debug --debugger:native -o:granite_debug src/harding/compiler/granite.nim"
```

### Debugger Integration

#### With GDB/LLDB:
```bash
# Build debug version
nim c -d:debug --debugger:native --stackTrace:on -o:harding_debug src/harding/repl/harding.nim

# Debug with GDB
gdb --args ./harding_debug examples/demo.harding

# Or with LLDB (macOS)
lldb ./harding_debug examples/demo.harding
```

#### VS Code Debugging
Create `.vscode/launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Harding REPL",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/harding_debug",
      "args": ["examples/test.harding"],
      "stopAtEntry": false,
      "cwd": "${workspaceFolder}",
      "externalConsole": false,
      "MIMode": "gdb",
      "setupCommands": [
        {
          "description": "Enable pretty-printing for gdb",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ],
      "logging": {
        "trace": true,
        "traceResponse": true
      }
    }
  ]
}
```

#### Nim's Built-in Debugger
Enable Nim's internal debugger with `--debugger:on`:
```bash
nim c -d:debug --debugger:on --debugger:native -o:harding_debug src/harding/repl/harding.nim
```

### Using GDB for Debugging
```bash
# Start GDB with Harding
gdb --args harding_debug script.harding

# Common GDB commands for Harding:
# (gdb) break nkCall
# (gdb) break evaluateExpression
# (gdb) run
```

### Memory Debugging
For memory-related issues:
```bash
# Build with memory debugging
nim c -d:useMalloc -d:debug --debugger:native --lineDir:on --stackTrace:on \
  -o:harding_memdebug src/harding/repl/harding.nim
```

### VS Code Configuration
1. Install the "C/C++", "Nim", and "CodeLLDB" VS Code extensions
2. Add to `.vscode/launch.json` for Nim debugging with CodeLLDB:
```json
{
    "name": "Debug Harding",
    "type": "lldb",
    "request": "launch",
    "program": "${workspaceFolder}/harding_debug",
    "args": ["${input:scriptPath}"],
    "cwd": "${workspaceFolder}",
    "preLaunchTask": "nim-build-debug"
}
```

### Claude Code and Debugging
While Claude Code cannot directly attach to debuggers, it can help:
- Generate debug configurations
- Suggest breakpoint locations based on stack traces
- Explain debugging session output
- Help add debug logging to code

For Nim debugging, Claude can't directly:
- Set or modify breakpoints at runtime
- Evaluate variables in running debugger
- Pause or step through code
- Start/stop debug sessions

Use VS Code's debugger or terminal-based debuggers (gdb/lldb) for interactive debugging sessions. Claude Code can, however, help you craft the correct debug flags, explain error messages, and suggest debug logging locations.

### Performance Debugging
For performance issues:
```bash
# Profile with debug symbols for better call stack
nim c -d:debug -d:nimprof --debugger:native -o:harding_profile src/harding/repl/harding.nim
```

### Testing with Debug Info
For debugging failing tests:
```bash
# Run specific test with debug output
NIM_DEBUG=1 nim c -d:debug -r tests/test_parser.nim
```

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

## Stackless VM Design

Harding uses a **stackless virtual machine** design where execution is driven by a work queue rather than the native call stack. This is critical for supporting green threads and continuations.

### Key Principles

**All control flow must go through the work queue.** The VM maintains:
- `workQueue`: A queue of `WorkFrame` objects representing pending work
- `evalStack`: A stack for expression evaluation results
- `activationStack`: The logical activation record stack

**Never use Nim's try/finally or exception handling** in VM primitives. This would break the stackless design because:
- Nim's try/finally unwinds the native call stack
- But the VM's work queue state would be inconsistent
- Green thread switching happens at the VM level, not the native level

### Correct Pattern: Work Queue Integration

Instead of:
```nim
# WRONG - breaks stackless design
try:
  result = evalBlock(...)  # May suspend and resume!
finally:
  cleanup()  # Runs at wrong time!
```

Use:
```nim
# CORRECT - maintains stackless design
interp.pushWorkFrame(newCleanupFrame())  # Schedule cleanup
interp.pushWorkFrame(newEvalFrame(block))  # Schedule evaluation
# Return and let VM process work queue
```

### When Writing VM Primitives

- Primitives schedule work frames, they don't execute directly
- The VM loop (`processWorkFrame`) processes frames from the queue
- Green threads yield by returning control to the VM loop
- Exception handling uses the `exceptionHandlers` stack, not Nim exceptions

See `src/harding/interpreter/vm.nim` for the work queue implementation.

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
harding/
├── core/           # Core types and object system
├── parser/         # Lexer and parser
├── interpreter/    # Evaluation and activation
├── compiler/       # Nim code generation
├── repl/           # Read-Eval-Print Loop
├── ffi/            # Foreign Function Interface
└── docs/           # Documentation
    ├── research/   # Historical design docs and proposals
```

### Documentation Organization

The `docs/` directory contains project documentation:

- **Root docs (`docs/*.md`)**: Current user guides, syntax references, and specifications
- **`docs/research/`**: Historical design documents, implementation plans, and research notes. These are kept for historical context but may not reflect the current implementation. Key documents include:
  - Object model design proposals and implementation plans
  - Historical decision records
  - Research notes on language features

When working with documentation, prefer the root-level user guides over research documents for understanding current behavior.

## File Naming Conventions

- Source files use `.nim` extension
- Test files use `test_*.nim` pattern
- Example files use `.harding` extension (Harding source)

## Harding Language Syntax

### Comments

Harding uses `#` for comments (different from Nim's documentation comments):

```harding
# This is a comment in Harding
# Comments use hash symbol followed by a space

# You can also have inline comments
window title: "Hello"  # Set the window title
```

**Important**: Do NOT use `"..."` (double quotes) for comments in Harding - these are strings. Always use `#` for comments.

### Literals

**Strings**: Double quotes only
```harding
"Hello, World!"
"String with #{interpolation}"    # Variable interpolation
"Line 1\nLine 2"                  # Escape sequences
```

**Symbols**: Hash followed by identifier or string
```harding
#mySymbol        # Simple symbol
#"a symbol"      # Symbol with spaces or special chars
#'another'      # Alternative quote style
```

**Numbers**:
```harding
42          # Integer
3.14        # Float
0xFF        # Hexadecimal (integer only)
```

**Booleans and nil**:
```harding
true
false
nil
```

**Arrays**: Literal syntax with `#(...)`
```harding
#(1 2 3)                    # Array of integers
#("a" "b" "c")             # Array of strings
#(1 'two' 3.0)              # Mixed types
```

**Tables** (dictionaries): Literal syntax with `#{...}`
```harding
#{#key -> "value"}          # Table with symbol key
#{"name" -> "Alice"}        # Table with string key
```

### Common Syntax Patterns

**Class definition with slots:**
```harding
MyClass := Object derive: #(slot1 slot2 slot3)

# With automatic accessors (getters and setters)
Point := Object deriveWithAccessors: #(x y)
```

**Method definition:**
```harding
MyClass>>methodName: arg1 with: arg2 [
    | localVar |
    localVar := arg1 + arg2.
    ^localVar    # Return value using ^
]

# Class method
MyClass class>>new [
    ^ super new initialize
]
```

**Block closures:**
```harding
# Block with parameter
[:param | param + 1]

# Block with multiple parameters
[:a :b | a + b]

# Block with no parameters
[Transcript showCr: "Hello"]

# Block with early return
[:val |
    val < 0 ifTrue: [^ 0].    # Early return from block
    val * 2
]
```

**Conditionals:**
```harding
condition ifTrue: [
    # do something
].

condition ifFalse: [
    # do something else
].

condition ifTrue: [...] ifFalse: [...]

# While loops
[condition] whileTrue: [body].
[condition] whileFalse: [body].

# Times repeat
5 timesRepeat: [Transcript showCr: "Hello!"].
```

### Primitive Syntax

Primitives declare methods implemented in Nim. They provide access to low-level operations and VM functionality.

**Declarative syntax** (recommended for simple methods):
```harding
# Method that directly calls a primitive
Class>>method: arg <primitive primitiveSelector: arg>

# Examples from core library
Table>>at: key <primitive primitiveTableAt: key>
Table>>at: key put: value <primitive primitiveTableAt: key put: value>
Array>>size <primitive primitiveArraySize>
```

**Inline syntax** (for use inside method bodies):
```harding
Class>>method [
    | temp |
    temp := self setup.
    ^ <primitive primitiveDoSomething: temp>
]

# Examples
MyClass>>clone [
    ^ <primitive primitiveClone>
]
```

**Primitive syntax rules:**
1. **Declarative form**: `Class>>selector <primitive primName: arg1 ...>`
   - Placed directly after the method signature
   - Arguments must match the method parameter names
   - No method body (brackets) when using declarative form

2. **Inline form**: `^ <primitive primName: expr>`
   - Used inside method body with brackets `[...]`
   - Arguments can be any expression
   - Typically used with `^` (return) to return the primitive result

3. **Argument matching**: In declarative form, primitive argument names must match method parameters:
   ```harding
   # Correct: 'key' in primitive matches 'key' parameter
   Table>>at: key <primitive primitiveTableAt: key>

   # Error: 'x' does not match parameter 'key'
   Table>>at: key <primitive primitiveTableAt: x>
   ```

4. **Colon count**: The number of colons in the primitive selector must match the number of arguments:
   ```harding
   # Correct: 2 colons, 2 arguments
   Table>>at: key put: value <primitive primitiveTableAt: key put: value>

   # Error: primitiveTableAt: takes 1 argument, but 2 provided
   Table>>at: key put: value <primitive primitiveTableAt: key put: value>
   ```

**Common methods:**
- `isEmpty` / `isEmpty not` - Check if string/collection is empty (use `isEmpty not` instead of `notEmpty`)
- `notNil` - Check if object is not nil
- `class` - Get the class of an object
- `derive:` - Create a new class with slots
- `at:` / `at:put:` - Dictionary-style property access
- `clone` - Create a shallow copy of an object
- `perform:` / `perform:with:` - Dynamic message sending

## BitBarrel Integration

BitBarrel is a high-performance Bitcask-style key-value storage engine that has been integrated into Harding to provide first-class persistent collections.

### Building with BitBarrel Support

To enable BitBarrel support, build with the `-d:bitbarrel` flag:

```bash
nimble harding_bitbarrel          # Build REPL with BitBarrel
nimble harding_bitbarrel_release  # Build release version
```

Or manually:
```bash
nim c -d:bitbarrel -o:harding src/harding/repl/harding.nim
```

This requires the `whisky` WebSocket library which will be automatically installed.

### Available Classes

**Barrel** - Connection to BitBarrel server:
```harding
# Connect to default localhost:9876
barrel := Barrel new.

# Connect to specific host
barrel := Barrel open: "192.168.1.100:9876".

# Create and use barrels
barrel create: "mydata" mode: 'hash'.
barrel use: "mydata".
barrel close.
```

**BarrelTable** - Hash-based persistent key-value storage:
```harding
# Create new hash-based table
users := BarrelTable create: "users".

# Or open existing
users := BarrelTable open: "users".

# Basic operations
users at: 'user:1' put: 'Alice'.
name := users at: 'user:1'.
users includesKey: 'user:1'.  # true
users removeKey: 'user:1'.

# Collection protocol
users do: [:key :value | Transcript showCr: key + " => " + value].
users keys.     # Array of all keys
users size.     # Number of entries
users isEmpty.  # Check if empty

# Higher-order methods (return in-memory Tables)
adults := users select: [:key :user | (user at: 'age') >= 18].
names := users collect: [:key :user | user at: 'name'].
```

**BarrelSortedTable** - Ordered persistent storage with range queries:
```harding
# Create new ordered table (uses critbit index)
logs := BarrelSortedTable create: "logs".

# Same basic operations as BarrelTable
logs at: '2024-01-01:001' put: 'System started'.

# Range queries (returns in-memory Table)
janLogs := logs rangeFrom: '2024-01-01' to: '2024-02-01'.
day1Logs := logs prefix: '2024-01-01:'.

# Ordered access
logs first.   # First entry {key. value}
logs last.    # Last entry
logs keys.    # Keys in sorted order
```

### Loading BitBarrel in Harding

In the REPL or scripts:
```harding
# Load all BitBarrel classes
load: "lib/harding/bitbarrel/Bootstrap.hrd".

# Or individual files
load: "lib/harding/bitbarrel/Barrel.hrd".
load: "lib/harding/bitbarrel/BarrelTable.hrd".
load: "lib/harding/bitbarrel/BarrelSortedTable.hrd".
```

### Architecture

The BitBarrel integration follows the same pattern as GTK integration:

```
┌─────────────────────────────────────────────────────────┐
│              Harding Level (Smalltalk)                   │
│         Barrel, BarrelTable, BarrelSortedTable          │
├─────────────────────────────────────────────────────────┤
│              Nim Bridge Layer (FFI)                    │
│    barrel.nim, barrel_table.nim, barrel_sorted_table.nim │
├─────────────────────────────────────────────────────────┤
│         BitBarrel Client Library (Nim)                 │
│              WebSocket protocol via whisky             │
├─────────────────────────────────────────────────────────┤
│               BitBarrel Server                         │
│         Bitcask-style key-value storage                │
└─────────────────────────────────────────────────────────┘
```

The native methods are conditionally compiled with `when defined(bitbarrel):` so Harding builds without BitBarrel support will still work (just without the BitBarrel classes).

### Future Directions

Potential enhancements:
1. Implement barrel literals in the language syntax
2. Provide transparent persistence for Harding objects
3. Add transaction support
4. Implement distributed/barrel sharding features