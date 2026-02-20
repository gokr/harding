# Harding Development TODO

This document tracks current work items and future directions for Harding development.

## Current Status

**Core Language**: The interpreter is fully functional with:
- Lexer, parser, stackless AST interpreter (recursive evaluator removed)
- **Class-based object system with inheritance and merged method tables** ✅
- **Multiple inheritance with conflict detection** ✅
- **addSuperclass: for adding parents after class creation** ✅
- REPL with file execution
- **Block closures with full lexical scoping, environment capture, and non-local returns** ✅
- **Closure variable isolation and sibling block sharing** ✅
- Method definition syntax (`>>`) with multi-character binary operator support
- `self` and `super` support (unqualified and qualified `super<Parent>`)
- Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`, `&`, `|`) ✅
- Enhanced comment handling (`#` followed by special chars) ✅
- Standard library (Object, Boolean, Block, Number, Collections, String, FileStream, Exception, TestCase) ✅
- **Exception handling via on:do:** ✅
- **Exception class hierarchy (Error, MessageNotUnderstood, SubscriptOutOfBounds, DivisionByZero)** ✅
- **nil as singleton UndefinedObject instance** ✅
- **Stdout global for console output** ✅
- Smalltalk-style temporary variables in blocks (`| temp |`) ✅
- Multiline keyword message support (no `.` needed between lines) ✅
- **All stdlib files load successfully** ✅
- **asSelfDo:** for self-rebinding blocks ✅
- **extend:** for extending objects with methods ✅
- **extendClass:** for class-side method definition ✅
- **derive:methods:** for combined class creation ✅
- **deriveWithAccessors:** for automatic getter/setter generation ✅
- **derive:getters:setters:** for selective accessor generation ✅
- **perform:** family for dynamic message sending ✅
- **Process, Scheduler, and GlobalTable as Harding-side objects** ✅
- **Harding global for accessing global namespace** ✅
- **Interval for numeric range iteration** ✅
- **SortedCollection for ordered collections** ✅
- **Monitor, SharedQueue, Semaphore synchronization primitives** ✅
- **Process introspection (pid, name, state)** ✅
- **Process control (suspend, resume, terminate)** ✅
- **Green threads with Processor fork: and Processor yield** ✅
- **Harding load: method for loading .harding files** ✅
- **--home and --bootstrap CLI options** ✅
- **Script files auto-wrapped in [ ... ] blocks** ✅
- **Temporary variable declarations in scripts: | var1 var2 |** ✅
- **Scripts execute with self = nil (Smalltalk workspace convention)** ✅
- **DEBUG echo statements converted to proper debug() logging** ✅

**Granite Compiler**: Standalone `.hrd` script compilation to native binaries works with inline control flow (ifTrue:, whileTrue:, timesRepeat:, etc.). Compiled code runs 30-200x faster than interpreted.

**Still Needed**: First-class block compilation with captures, non-local returns, class/method compilation from in-VM code, FFI to Nim, standard library expansion.

## High Priority

### Compiler
- [x] Application class for structured builds
- [x] Granite compiler primitives (`compile:`, `build:`)
- [x] Transitive class collection
- [x] Application binary generation
- [x] Method compilation from AST to Nim procedures
- [x] Nim type definitions for Harding classes
- [x] Basic runtime helpers (println, arithmetic operators)
- [x] Monomorphic Inline Cache (MIC) for message sends
- [x] Standalone `.hrd` script compilation via CLI granite
- [x] Inline control flow (ifTrue:, ifFalse:, whileTrue:, whileFalse:, timesRepeat:)
- [x] Block registry and procedure generation infrastructure
- [x] Statement and expression context for inline control flow
- [ ] First-class block compilation with captures
- [ ] Non-local return from blocks via exceptions
- [ ] Class/method compilation from in-VM code
- [ ] Unboxed arithmetic optimization
- [ ] Symbol export for compiled methods
- [ ] Dead code elimination
- [x] PIC (Polymorphic Inline Cache) - multi-type caching with version-based invalidation

### FFI Integration
- [ ] Nim type marshaling
- [ ] FFI bridge for calling Nim functions
- [ ] Nim module imports
- [ ] Type conversion utilities

## Medium Priority

### Standard Library Expansion
- [ ] More collection methods
- [ ] Regular expression support
- [ ] Date/time handling
- [ ] Additional file I/O capabilities
- [ ] Networking primitives

### Performance
- [x] MIC/PIC inline caching with version-based invalidation
- [ ] AST optimization passes
- [ ] Memory management improvements for circular references

### Tooling
- [ ] REPL history and completion
- [x] Editor syntax highlighting definitions (VSCode extension)
- [x] Language Server Protocol (LSP) implementation
- [x] Debug Adapter Protocol (DAP) implementation
- [x] VSCode extension with full IDE support
- [ ] Build system refinements
- [ ] Better error messages

### Green Threads
- [x] Monitor synchronization primitive
- [x] SharedQueue for producer-consumer patterns
- [x] Semaphore for counting/binary locks

## Completed

### VSCode Extension with LSP and DAP (2026-02-13)
- [x] Harding Debug Protocol (HDP) server with TCP socket
- [x] Breakpoint management (set, remove, clear, conditional)
- [x] Stepping support (step over, step into, step out)
- [x] Stack frame inspection
- [x] Variable inspection (locals, arguments, self)
- [x] Language Server Protocol (LSP) implementation
- [x] LSP features: completions, hover, document symbols, workspace symbols
- [x] Debug Adapter Protocol (DAP) TypeScript implementation
- [x] VSCode extension packaging with `nimble vsix`
- [x] Extension includes syntax highlighting, LSP client, and DAP adapter

### BitBarrel Integration (2026-02-13)
- [x] First-class barrel objects (`Barrel`, `BarrelTable`, `BarrelSortedTable`)
- [x] WebSocket client for BitBarrel server communication
- [x] Hash-based persistent storage (`BarrelTable`)
- [x] Ordered persistent storage with range queries (`BarrelSortedTable`)
- [x] Collection protocol support (do:, select:, collect:, keys, size)
- [x] Conditional compilation with `-d:bitbarrel` flag
- [x] Harding-side class definitions in `lib/harding/bitbarrel/`

### Code Cleanup - JS Support Removal (2026-02-16)
- [x] Removed all 9 `when defined(js)` conditionals from core files
- [x] types.nim: Removed JS conditional from `CompiledMethod.nativeAddr`
- [x] types.nim: Removed JS conditional from `NimValueDefault` helper
- [x] types.nim: Removed JS conditional from Boolean instance creation
- [x] parser.nim: Removed JS conditional from `BlockNode.nativeImpl`
- [x] objects.nim: Removed JS conditional from `writeImpl` and `writelineImpl`
- [x] objects.nim: Removed JS conditional from `createGetterMethod` and `createSetterMethod`
- [x] Moved `docs/JAVASCRIPT.md` to `docs/research/` as historical documentation
- [x] Updated documentation references (README.md, docs/README.md)

### Language Evolution
- [x] Multiple inheritance syntax (implemented via `addParent:`)
- [ ] Optional static type checking
- [ ] Module/namespace system
- [ ] Metaprogramming APIs

## Known Issues

- Memory management for circular references
- Error handling improvements needed

## Documentation Needs

- [x] Quick Reference (docs/QUICKREF.md)
- [x] Language Manual (docs/MANUAL.md)
- [x] Implementation docs (docs/IMPLEMENTATION.md)
- [x] Tools & Debugging docs (docs/TOOLS_AND_DEBUGGING.md)
- [x] GtkSourceView syntax highlighting (docs/GTKSOURCEVIEW.md)
- [ ] Tutorials and comprehensive examples
- [ ] API reference for built-in objects
- [ ] Help text improvements

## Build Quick Reference

```bash
nimble harding     # Build harding REPL in repo root (recommended)
nimble bona        # Build bona IDE in repo root
nimble test        # Run tests
nimble clean       # Clean artifacts
nimble install_harding  # Install harding to ~/.local/bin/
```

### Debug Builds

```bash
# Build with debug symbols
nim c -d:debug --debugger:native -o:harding_debug src/harding/repl/harding.nim

# Debug with GDB
gdb --args ./harding_debug script.harding
```

### Logging Options

```bash
harding --loglevel DEBUG script.harding    # Verbose tracing
harding --loglevel INFO script.harding     # General information
harding --loglevel WARN script.harding     # Warnings only
harding --loglevel ERROR script.harding    # Errors only (default)
```

### GTK IDE Improvements and Print It (2026-02-08)
  - Fixed calling convention mismatch in GTK native methods (segmentation fault fix)
  - Added {.nimcall.} pragma to all GTK native method implementations
  - Fixed GtkTextIter storage with proper buffer allocation (256-byte opaque struct buffers)
  - Added text manipulation methods to TextView/SourceView:
    - `insertText:at:` - Insert text at position offset
    - `selectRangeFrom:to:` - Select text range
    - `insertTextAtSelectedEnd:` - Insert text after selection
    - `getSelectionEnd` - Get selection end position
  - Implemented Smalltalk-style Print It in Workspace
  - Print It now inserts result in editor (after selection) and selects it for easy deletion
  - GtkSourceView now inherits from GtkTextView for method sharing
  - Added FFI bindings for gtkTextBufferInsert and gtkTextBufferSelectRange

### Test Coverage Improvements (2025-02-08)
- Fixed all disabled tests in test_evaluator.nim (10 tests rewritten using class-based model)
- Fixed skipped tests in test_super.nim for qualified super sends
- Added test_perform.nim for dynamic message sending (6 tests)
- Added test_exception_handling.nim documenting exception handling (primitives not yet implemented)
- Added test_extend.nim documenting method batching (known limitation with asSelfDo:)
- Added string concatenation tests with auto-conversion to test_stdlib.nim
- 15 of 17 test files now passing (2 document known limitations)

### String Concatenation with Auto-Conversion (2025-02-08)
- `,` operator now auto-converts arguments using `toString`
- Supports numbers, objects, and any type with string representation
- Example: `"Value: " , 42` produces `"Value: 42"`

### Complete Stackless VM Migration (2025-02-08)
- Removed the old recursive evaluator (`evalOld`, ~1200 lines deleted)
- All execution now goes through the stackless VM work queue
- Re-entrant evaluation via `evalWithVM` for native methods that need to call Harding code
- Control flow primitives (`ifTrue:`, `ifFalse:`, `whileTrue:`, `whileFalse:`, block `value:`) handled by VM work frames
- Fixed captured variable propagation through nested blocks (MutableCell sharing)
- Fixed non-local returns from deeply nested blocks (`homeActivation` walks to enclosing method)
- Fixed `doesNotUnderstand:` fallback in VM dispatch
- Fixed escaped blocks with non-local returns to exited activations
- Renamed entry points: `doitStackless` -> `doit`, `evalStatementsStackless` -> `evalStatements`
- All 14 tests pass

### Automatic Accessor Generation (2025-02-07)
- `deriveWithAccessors:` - Creates class with auto-generated getters and setters for all slots
- `derive:getters:setters:` - Creates class with selective accessor generation
- Getters use O(1) SlotAccessNode for fast direct slot access
- Setters use O(1) SlotAccessNode for fast direct slot assignment
- Added comprehensive tests in test_stdlib.nim

## Granite Compiler Implementation (In Progress)

### Current Status (2026-02-10)

**Completed:**
- ✅ Application base class (lib/core/Application.hrd)
  - `name` and `libraries` slots
  - `main: args` entry point method
  - `build` method that calls `Granite build: self`
- ✅ Granite compiler class (lib/core/Granite.hrd)
  - `compile:` primitive - generates Nim code from Harding source
  - `build:` primitive - fully functional application building
  - Helper methods for transitive class collection
- ✅ Primitive registration infrastructure
  - `src/harding/interpreter/compiler_primitives.nim` with primitive implementations
  - Registration in vm.nim when `-d:granite` is defined
  - Build with: `nim c -d:granite -o:harding_granite src/harding/repl/harding.nim`
- ✅ Transitive class collection
  - Collects all classes reachable from Application
  - Follows superclass chains
  - Includes library-specified classes
- ✅ Nim code generation for Application
  - Generates main() procedure
  - Creates build directory and writes .nim file
  - Compiles with Nim to binary
- ✅ Method compilation from AST
  - Compiles Harding method bodies to Nim procedures
  - Generates class type definitions with slots
  - Supports basic expressions (literals, arithmetic, message sends)
  - Runtime helper functions (nt_println, nt_plus, etc.)

**Working Example:**
```bash
# Build with granite support
nim c -d:granite -o:harding_granite src/harding/repl/harding.nim

# Compile Harding to Nim
./harding_granite -e 'Granite compile: "3 + 4"'

# Build Application with method compilation
./harding_granite -e '
MyApp := Application derive: #().
MyApp>>main: args [
  Stdout writeLine: "Hello from compiled Harding!".
  Stdout writeLine: ("2 + 3 = ", (2 + 3) asString).
  ^0
].
app := MyApp new.
app name: "myapp".
Granite build: app
'
# Output: Build successful: build/myapp

# Run compiled binary
./build/myapp
# Output:
# Application: myapp
# Hello from compiled Harding!
# 2 + 3 = 5
```

**Note on Command-Line Arguments:**
The `main: args` method signature accepts an array of arguments, but currently the compiler passes an empty array. Full command-line argument passing from the host OS is not yet implemented.

**Next Steps (Priority Order):**

#### 1. Transitive Class Collection
Implement `collectFilesFor:` in `compiler_primitives.nim`:
```nim
proc collectTransitiveClasses*(app: Instance, interp: Interpreter): seq[ClassInfo]
```
- Start from Application's class
- Follow superclass chain
- Parse method bodies to find class references (e.g., `Array new`, `Set new`)
- Collect all transitively referenced classes
- Return as sequence of ClassInfo objects

**Files to modify:**
- `src/harding/interpreter/compiler_primitives.nim` - add class collection logic
- `src/harding/compiler/analysis.nim` - add AST analysis for class references

#### 2. Library Scoping
When Application specifies `libraries: #(Core Collections)`:
- Only include classes from those libraries
- Filter out classes from other libraries
- Core classes (Object, Integer, etc.) always included

**Implementation approach:**
```nim
proc filterByLibraries*(classes: seq[ClassInfo],
                       libraries: seq[string],
                       interp: Interpreter): seq[ClassInfo]
```

#### 3. Dead Code Elimination (Optional)
When no libraries specified, analyze message sends:
```nim
proc analyzeMessageSends*(classes: seq[ClassInfo]): HashSet[string]
proc pruneUnusedMethods*(classes: seq[ClassInfo],
                        usedSelectors: HashSet[string]): seq[ClassInfo]
```
- Walk all method bodies
- Collect all message selectors sent
- Keep only methods that are actually called
- Mark entry point methods (`main:`) as always kept

#### 4. Nim Code Generation for Application
Extend `genModule` in `src/harding/codegen/module.nim`:
- Generate a Nim `main()` procedure
- Create Application instance
- Call `main:` with command-line args
- Include all collected class definitions
- Generate method dispatch tables

**Key design decisions:**
- Each Harding class becomes a Nim type
- Methods become Nim procedures with mangled names
- Message dispatch via method table lookup
- Native methods call existing interpreter primitives

#### 5. Binary Compilation
Implement full `graniteBuildImpl`:
```nim
proc graniteBuildImpl*(self: Instance, args: seq[NodeValue]): NodeValue
```
- Get Application instance from args
- Extract `name` and `libraries` slots
- Collect transitive classes
- Apply library filter or dead code elimination
- Generate Nim module
- Write to `build/{appName}.nim`
- Invoke `nim c` to compile to binary
- Return path to binary or error message

**Command sequence:**
```harding
# From Harding REPL
app := MyApplication new.
app name: "myapp".
app libraries: #(Core Collections).
Granite build: app.  # Creates build/myapp binary
```

#### 6. PIC (Polymorphic Inline Cache) - Future Enhancement
After basic build works:
- Add PIC data structures to runtime
- Generate PIC-aware message sends
- Cache method lookups at call sites
- Measure performance improvement

#### 7. Type Specialization - Future Enhancement
- Analyze method return types
- Generate type-specialized method variants
- Call direct type-specific versions when types known

### Implementation Order

1. **Transitive class collection** - Required for build
2. **Library scoping** - Required for library-based filtering
3. **Nim code generation** - Required for output
4. **Binary compilation** - Required for end-to-end build
5. **Dead code elimination** - Optional optimization
6. **PIC** - Performance optimization
7. **Type specialization** - Advanced optimization

### Testing Plan

```bash
# Build with granite
nim c -d:granite -o:harding_granite src/harding/repl/harding.nim

# Test compile:
./harding_granite -e 'Granite compile: "3 + 4"'

# Test Application class
./harding_granite -e 'Application class'

# Create test application
cat > TestApp.hrd << 'EOF'
TestApp := Application derive: #().
TestApp>>initialize [
  super initialize.
  self name: "testapp".
  self libraries: #(Core).
].
TestApp>>main: args [
  Transcript showCr: "Hello from TestApp!".
  ^0
].
EOF

# Build application
./harding_granite -e '
  (File read: "TestApp.hrd") value.
  app := TestApp new.
  Granite build: app
'

# Run compiled binary
./build/testapp
```

### Architecture Notes

**Single Runtime Approach:**
- Granite uses existing interpreter runtime
- No need to bootstrap separate interpreter
- Classes already loaded and available
- Direct access to method tables and class hierarchy

**Primitive-Based Design:**
- Compiler exposed as Harding primitives
- Harding code can compile Harding code
- Smalltalk-style `Smalltalk compiler evaluate:`
- No external `granite` process needed for IDE integration

**Conditional Compilation:**
- `-d:granite` flag enables compiler primitives
- Regular `harding` binary doesn't include compiler
- Separate `harding_granite` for compilation support
- Smaller binary size when compiler not needed
- Updated documentation in MANUAL.md and QUICKREF.md

### Script Files and Temporary Variables (2025-02-07)
- Script files auto-wrapped in `[ ... ]` blocks before parsing
- Temporary variables can be declared at file level: `| var1 var2 |`
- Scripts execute with `self = nil` (Smalltalk workspace convention)
- No need for uppercase globals in simple scripts
- Shebang support for executable scripts: `#!/usr/bin/env harding`
- evalScriptBlock implementation in stackless VM
- Documentation updates for script execution in MANUAL.md and QUICKREF.md

### Debug Logging Improvements (2025-02-07)
- Converted DEBUG echo statements to proper debug() logging calls
- Debug output now respects --loglevel option
- Cleaner normal script execution (no unwanted debug prints)
- Logging updates across VM and codebase

### Documentation and Cleanup (2025-02-06)
- Updated README.md with concise example and proper documentation links
- Fixed all example files to use `new` for instance creation (not `derive`)
- Fixed all example files to use double quotes for strings (not single quotes)
- Updated all documentation to match current syntax
- Renamed .nemo files to .hrd extension throughout codebase
- Fixed QUICKREF.md title (was "N Syntax")
- Fixed VSCODE.md to reference correct grammar file (harding.tmLanguage.json)
- Updated README to use `granite` consistently (was `granite`)
- Updated all shebang lines from `nemo` to `harding`
- Fixed examples/README.md with correct binary and extension names

### Exception Handling (2025-02-03)
- Implemented exception handling via `on:do:` mechanism
- Created Exception class hierarchy (Error, MessageNotUnderstood, SubscriptOutOfBounds, DivisionByZero)
- Errors in Harding code now use Nim exceptions with stack traces
- Exception support in TestCase for test assertion failures

### Harding Object System Updates (2025-02-03)
- `nil` as singleton UndefinedObject instance (not primitive)
- Stdout global for console output
- String `repeat:` and Array `join:` methods
- Class introspection: `className`, `slotNames`, `superclassNames`
- Fixed class-side method definition via `extendClass:`

### Process, Scheduler, GlobalTable (2025-02-03)
- Process class as Harding-side object with pid, name, state methods
- Process control: suspend, resume, terminate
- Scheduler class with process introspection
- GlobalTable class and Harding global for namespace access
- All processes share globals via `Harding`

### Multiple Inheritance (2025-02-01)
- Conflict detection for slot names in multiple parent classes
- Conflict detection for method selectors in multiple parent classes
- `addParent:` message for adding parents after class creation
- Override methods in child to resolve conflicts

### Green Threads (2025-01-31)
- Core scheduler with round-robin scheduling
- Process forking with `Processor fork:`
- Each process has isolated activation stack
- Shared globals between all processes
- Process states: ready, running, blocked, suspended, terminated

### Method Definition Enhancements (2025-01-31)
- `asSelfDo:` for self-rebinding blocks
- `extend:` for batching instance methods
- `extendClass:` for class-side (factory) methods
- `derive:methods:` for combined class creation
- `perform:` family for dynamic message sending

### Parser and Syntax (2025-01-30)
- Multi-character binary operators (`==`, `//`, `<=`, `>=`, `~=`, `~~`, `&`, `|`)
- Smalltalk-style temporaries in blocks: `[ | temp1 temp2 | ... ]`
- Multiline keyword messages (newline-aware)
- `#====` section header comments
- 1-based array indexing (Smalltalk compatible)

### VSCode Extension (2025-02-01)
- Comprehensive syntax highlighting for `.harding` files
- TextMate grammar with language configuration
- Packaged as .vsix extension

---

### Performance Optimizations (2026-02-10)
- Implemented Monomorphic Inline Cache (MIC) for message sends
- Tagged value representation for integers, booleans, and nil
- Fast path for integer arithmetic with automatic overflow to heap
- Computed goto dispatch for VM execution loop
- Conditional debug template to eliminate debug overhead in release builds

### Bona Desktop Integration (2026-02-11)
- Fixed dock and Alt-Tab switcher icon display
- Created `GtkApplication` with application ID `org.harding-lang.bona`
- Added `bona.desktop` file with `StartupWMClass` matching application ID
- Added `nimble install_bona` task for desktop integration
- Restructured GTK4 flow to use `activate` signal for window creation
- Windows now created via `gtk_application_window_new()` for proper app association

### GTK IDE Fixes (2026-02-10)
- Fixed Print It - no longer prints to Transcript (only inserts in editor)
- Keyboard shortcuts now stop event propagation
- Fixed toolbar button vertical stretching in Launcher
- Added window icon support for GTK4

### Synchronization Primitives Fix (2026-02-09)
- Fixed blocking/unblocking in Monitor, Semaphore, and SharedQueue
- Processes now properly yield when blocking on synchronization primitives
- PC decrement on block ensures statements re-execute correctly when unblocked
- Fixed runToCompletion to handle blocked processes properly
- Added comprehensive multi-process tests (test_sync_primitives.nim)
- Removed "Block body corruption" from known issues (fixed)

### Variable Resolution Fix (2026-02-11)
- Fixed critical bug in `lookupVariable` where parent activation locals were checked before slots
- Methods can no longer see calling method's locals (proper Smalltalk scoping)
- Slot access now takes precedence over globals (consistent Smalltalk semantics)
- Fixed `Exception>>message` to use direct slot access instead of `getSlot:`
- Added test cases to verify correct variable resolution order

### IDE Improvements (2026-02-11)
- Added Inspector tool for object introspection (`Object>>inspect`)
- Workspace now has "Inspect It" button and Ctrl+I keyboard shortcut
- Fixed Transcript integration - output now goes to correct window
- Added window icon support via icon themes for GTK4

### Granite Standalone Script Compilation (2026-02-13)
- CLI granite (`granite compile/build/run`) now compiles standalone `.hrd` scripts
- Inline control flow compilation: ifTrue:, ifFalse:, ifTrue:ifFalse:, whileTrue:, whileFalse:, timesRepeat:
- Both statement context (no value needed) and expression context (value required) handled
- Block registry infrastructure for non-inline blocks (procedure generation, capture analysis stubs)
- `indentBlock` helper for correct nested code indentation
- Runtime helpers: `isTruthy`, `toInt`, arithmetic operators (`nt_plus`, `nt_minus`, etc.)
- Verified with sieve of Eratosthenes benchmark (correct results, 30-200x faster than interpreted)
- Benchmark results (primes up to 5000): interpreter debug ~23s, interpreter release ~2.3s, compiled release ~0.01s

### Stdlib Refactoring (2026-02-12)
- Moved core method definitions from Nim native code to `.hrd` stdlib files
- Updated IDE Browser, Libraries, and Workspace components
- Simplified blocked process handling in scheduler

### MIC/PIC Inline Caching and VM Fixes (2026-02-16)
- Polymorphic Inline Cache (PIC): up to 4 class/method entries per call site
- Version-based cache invalidation: class version counters detect stale entries
- LRU promotion: PIC hits swap to MIC for fast repeated access
- Megamorphic flag: skip caching at highly polymorphic sites
- Fixed exception handling: proper VM state unwinding (work queue, eval stack, activation stack)
- Fixed Library primitive syntax: declarative form for class>>new and bindings
- Fixed SortedCollection: use basicNew instead of non-existent newInstance
- Registered derive:getters:setters: class method on Object
- Moved ifError: from Object to Block
- Lazy method table rebuilding with methodsDirty flag
- Enabled 15 previously skipped tests; all 26 test files pass

### Smalltalk-style Resumable Exceptions (2026-02-20)

- [x] ExceptionContext preserves full activation stack and work queue at signal point
- [x] Exception>>signal no longer truncates activation stack (proper Smalltalk-style)
- [x] Exception>>resume - resume execution from signal point (signal returns nil)
- [x] Exception>>resume: - resume from signal point returning a value
- [x] Exception>>retry - re-execute the protected block
- [x] Exception>>pass - delegate to next outer matching handler
- [x] Exception>>return: - return value from the on:do: expression
- [x] Exception>>signalContext - access full call stack at signal point
- [x] Exception>>signaler - the object that signaled the exception
- [x] Exception>>signalActivationDepth - activation stack depth at signal point
- [x] Notification class as resumable exception subclass
- [x] Comprehensive test suite in test_signal_point_debugging.nim

*Last Updated: 2026-02-20*
