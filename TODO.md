# Nimtalk Development TODO

This document tracks current work items and future directions for Nimtalk development.

## Current Status

**Core Language**: The interpreter is fully functional with:
- Lexer, parser, AST interpreter
- **Class-based object system with inheritance and merged method tables** ✅
- REPL with file execution
- **Block closures with full lexical scoping, environment capture, and non-local returns** ✅
- **Closure variable isolation and sibling block sharing** ✅
- Method definition syntax (`>>`) with multi-character binary operator support
- `self` and `super` support (unqualified and qualified `super<Parent>`)
- Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`, `&`, `|`) ✅
- Enhanced comment handling (`#` followed by special chars) ✅
- Standard library (Object, Boolean, Block, Number, Collections, String, FileStream, Exception, TestCase) ✅
- Smalltalk-style temporary variables in blocks (`| temp |`) ✅
- Multiline keyword message support (no `.` needed between lines) ✅
- **All stdlib files load successfully** ✅
- **asSelfDo:** for self-rebinding blocks ✅
- **extend:** for extending objects with methods ✅
- **extendClass:** for class-side method definition ✅
- **derive:methods:** for combined class creation ✅
- **perform:** family for dynamic message sending ✅

**Not Yet Implemented**: Compiler (ntalkc is stub), FFI, advanced standard library.

## High Priority

### Compiler
- [ ] Method compilation from AST to Nim procedures
- [ ] Nim type definitions for Class and Instance
- [ ] Symbol export for compiled methods
- [ ] Working `ntalkc` (currently stub)

### FFI Integration
- [ ] Nim type marshaling
- [ ] FFI bridge for calling Nim functions
- [ ] Nim module imports
- [ ] Type conversion utilities

## Medium Priority

### Standard Library
- [x] Number objects with arithmetic helpers (abs, even, odd, max:, min:, to:do:, etc.)
- [ ] Enhanced string manipulation
- [ ] More collection methods (inject:into:, detect:, anySatisfy:, allSatisfy:, etc.)
- [ ] File I/O primitives
- [ ] Exception handling primitives

### Performance
- [ ] Method caching
- [ ] AST optimization passes
- [ ] Memory management improvements

### Tooling
- [ ] REPL history and completion
- [x] Editor syntax highlighting definitions (VSCode extension)
- [ ] Build system refinements

## Future Directions

### BitBarrel Integration
- [ ] First-class barrel objects
- [ ] Transparent persistence
- [ ] Crash recovery support

### Language Evolution
- [ ] Multiple inheritance syntax (`withParents:`) - first parent defines "kind", additional parents are mixins
- [ ] Optional static type checking
- [ ] Module/namespace system
- [ ] Concurrency model
- [ ] Metaprogramming APIs

## Known Issues

- ~~Parser edge cases with nested blocks~~ ✅ Fixed
- ~~Closure variable isolation~~ ✅ Fixed
- ~~Non-local return implementation~~ ✅ Fixed
- ~~Multi-character binary operators~~ ✅ Fixed
- ~~Comment handling for `#====`~~ ✅ Fixed
- ~~Temporary variables in blocks~~ ✅ Fixed
- ~~Multiline keyword messages~~ ✅ Fixed
- ~~asSelfDo: for self-rebinding~~ ✅ Implemented
- ~~extend: for instance method batching~~ ✅ Implemented
- ~~extendClass: for class-side methods~~ ✅ Implemented
- ~~derive:methods: combined class creation~~ ✅ Implemented
- ~~perform: family for dynamic dispatch~~ ✅ Implemented
- ~~Green threads core scheduler~~ ✅ Implemented
- ~~Process forking and yielding~~ ✅ Implemented
- ~~Shared globals between processes~~ ✅ Implemented
- Monitors and SharedQueues (in progress)
- Memory management for circular references
- Error handling improvements needed
- Compiler implementation (ntalkc is stub)

## Documentation Needs

- [x] Newline handling documentation (docs/NEWLINE_RULES.md)
- [ ] Tutorials and comprehensive examples
- [ ] API reference for built-in objects
- [ ] Internal API documentation
- [ ] Help text improvements

## Build Quick Reference

```bash
nimble build       # Build ntalk and ntalkc
nimble local       # Build and copy to root
nimble test        # Run tests
nimble clean       # Clean artifacts
```

## Recent Completed Work (2026-01-30)

### Parser & Lexer Fixes
- Fixed multi-character binary operators (`==`, `===`, `//`, `\\`, `<=`, `>=`, `~=`) to match multi-char before single-char fallback
- Fixed comment handling for `#====` and similar section headers (no space needed after `#`)
- Added Smalltalk-style temporary variables in blocks: `[ | temp1 temp2 | ... ]`
- Multi-character method selectors now supported (e.g., `Object>>~~ other [...]`)
- Added `parsePrimaryUnaryOnly` for parsing keyword arguments that allow unary messages
- Fixed keyword messages to span multiple lines (newline-aware parsing)

### Object Model & Runtime Fixes
- Fixed array indexing to use 1-based indexing (Smalltalk compatible)
- Added `selectorPutImpl` for proper method storage on runtime objects with slots
- Added slot variable access in methods (lookup and assignment)
- Fixed array literal evaluation to handle pseudo-variables (true, false, nil)
- Added `add:` alias for `primitiveAdd:` on arrays

### Testing Framework
- Created TestCase class in stdlib with assertion methods
- Support for `assert:`, `assert:equals:`, `fail:` methods
- Test lifecycle methods (initialize, setUp, tearDown)
- Example tests in examples/test_example.nt

### Documentation
- Created docs/NEWLINE_RULES.md documenting newline behavior
- Updated all docs to reflect double-quoted strings only
- Reserved single quotes for future use in lexer

## Recent Completed Work (2026-01-31)

### Self-Rebinding and Method Batching
- Implemented `asSelfDo:` primitive for evaluating blocks with rebound self
- Added `extend:` for batching instance method definitions
- Added `extendClass:` for class-side (factory) method definitions
- Added `derive:methods:` for combined class creation with methods
- Implemented `perform:`, `perform:with:`, `perform:with:with:` for dynamic dispatch
- All `perform:` calls now use symbols (`#selector`) instead of strings
- Updated `doesNotUnderstand:` to accept selector with optional arguments

### Green Threads (Cooperative Processes)
- Implemented core scheduler in `nimtalk/core/process.nim`
- Added `SchedulerContext` for interpreter integration
- Each process has its own interpreter with isolated activation stack
- Shared globals and rootObject between all processes
- Round-robin scheduling with explicit yields
- Process states: ready, running, blocked, suspended, terminated
- `Processor` global object with `yield`, `fork:`, `current` methods
- Process forking from Nimtalk blocks
- Test suite for scheduler and process lifecycle

---

## Recent Completed Work (2026-01-31)

### Boolean and Number Class Hierarchies
- Created Boolean as parent class for True and False
- Created Number as parent class for Integer and Float
- Updated stdlib to use new hierarchies

### Block Self Resolution Fix
- Fixed self resolution in blocks to use homeActivation.receiver
- Blocks now correctly refer to their creating object's self

### New Binary Operators
- Added & and | as binary operators (logical AND/OR)
- Added support for & and | as method selectors (True>>& other, True>>| other)

### Negative Number Literals
- Added support for negative number literals using Spry-style lexer approach
- Numbers like -5 are now parsed as single negative literals

### Missing Wrap Functions
- Added wrapBlockAsObject for block method support
- Added wrapStringAsObject, wrapArrayAsObject, wrapTableAsObject, wrapFloatAsObject

---

## Recent Completed Work (2026-02-01)

### VSCode Extension
- Added comprehensive VSCode syntax highlighting for `.nt` files
- Created TextMate grammar (.vscode/syntaxes/nt.tmLanguage.json)
- Added language configuration (.vscode/language-configuration.json)
- Added extension manifest (package.json)
- Created `.vscodeignore` for smaller extension packages
- Added VSCODE.md documentation
- Extension packaged as .vsix (~276KB)

### Documentation Updates
- Fixed string literal syntax in documentation (use double quotes, not single quotes)
- Fixed comment syntax (use # for comments)
- Updated docs/README.md with new documentation files
- Updated docs/NEWLINE_RULES.md
- Updated docs/SPECIFICATION.md
- Updated docs/SYNTAX-QUICKREF-updated.md
- Updated TODO.md with VSCode extension completion

---

*Last Updated: 2026-02-01*

## Recent Completed Work (2026-02-01)

### Multiple Inheritance Conflict Detection and addParent:

- Added conflict detection for slot names in multiple parent classes
- Added conflict detection for method selectors in multiple parent classes
  - Only checks directly-defined methods, not inherited ones
- Implemented `addParent:` class message to add parents after class creation
  - Allows resolving conflicts by overriding methods first, then adding parents
- Conflict detection provides clear error messages with guidance
- Added example tests demonstrating conflict detection and resolution

---

*Last Updated: 2026-02-01*
