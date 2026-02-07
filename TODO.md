# Harding Development TODO

This document tracks current work items and future directions for Harding development.

## Current Status

**Core Language**: The interpreter is fully functional with:
- Lexer, parser, AST interpreter
- **Class-based object system with inheritance and merged method tables** ✅
- **Multiple inheritance with conflict detection** ✅
- **addParent: for adding parents after class creation** ✅
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
- **Process introspection (pid, name, state)** ✅
- **Process control (suspend, resume, terminate)** ✅
- **Green threads with Processor fork: and Processor yield** ✅
- **Harding load: method for loading .harding files** ✅
- **--home and --bootstrap CLI options** ✅
- **Script files auto-wrapped in [ ... ] blocks** ✅
- **Temporary variable declarations in scripts: | var1 var2 |** ✅
- **Scripts execute with self = nil (Smalltalk workspace convention)** ✅
- **DEBUG echo statements converted to proper debug() logging** ✅

**Still Needed**: Compiler (granite is stub), FFI to Nim, standard library expansion.

## High Priority

### Compiler
- [ ] Method compilation from AST to Nim procedures
- [ ] Nim type definitions for Class and Instance
- [ ] Symbol export for compiled methods
- [ ] Working `granite` (currently stub)

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
- [ ] Method caching (beyond current allMethods table)
- [ ] AST optimization passes
- [ ] Memory management improvements for circular references

### Tooling
- [ ] REPL history and completion
- [x] Editor syntax highlighting definitions (VSCode extension)
- [ ] Build system refinements
- [ ] Better error messages

### Green Threads
- [ ] Monitor synchronization primitive
- [ ] SharedQueue for producer-consumer patterns
- [ ] Semaphore for counting/binary locks

## Low Priority

### BitBarrel Integration
- [ ] First-class barrel objects
- [ ] Transparent persistence
- [ ] Crash recovery support

### Language Evolution
- [x] Multiple inheritance syntax (implemented via `addParent:`)
- [ ] Optional static type checking
- [ ] Module/namespace system
- [ ] Metaprogramming APIs

## Known Issues

- Block body corruption in forked processes when running in test suite (works in isolation)
- Memory management for circular references
- Error handling improvements needed
- Compiler implementation (granite is stub)

## Documentation Needs

- [x] Quick Reference (docs/QUICKREF.md)
- [x] Language Manual (docs/MANUAL.md)
- [x] Implementation docs (docs/IMPLEMENTATION.md)
- [x] Tools & Debugging docs (docs/TOOLS_AND_DEBUGGING.md)
- [ ] Tutorials and comprehensive examples
- [ ] API reference for built-in objects
- [ ] Help text improvements

## Build Quick Reference

```bash
nimble local       # Build and copy binaries to root directory (recommended)
nimble build       # Build harding and granite
nimble test        # Run tests
nimble clean       # Clean artifacts
nimble install     # Install harding to ~/.local/bin/
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

## Recent Completed Work

### Automatic Accessor Generation (2025-02-07)
- `deriveWithAccessors:` - Creates class with auto-generated getters and setters for all slots
- `derive:getters:setters:` - Creates class with selective accessor generation
- Getters use O(1) SlotAccessNode for fast direct slot access
- Setters use O(1) SlotAccessNode for fast direct slot assignment
- Added comprehensive tests in test_stdlib.nim
- Updated documentation in MANUAL.md and QUICKREF.md

### Script Files and Temporary Variables (2025-02-07)
- Script files auto-wrapped in `[ ... ]` blocks before parsing
- Temporary variables can be declared at file level: `| var1 var2 |`
- Scripts execute with `self = nil` (Smalltalk workspace convention)
- No need for uppercase globals in simple scripts
- Shebang support for executable scripts: `#!/usr/bin/env harding`
- evalScriptBlock implementation in VM
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

*Last Updated: 2025-02-08*
