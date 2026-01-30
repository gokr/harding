# Nimtalk Development TODO

This document tracks current work items and future directions for Nimtalk development.

## Current Status

**Core Language**: The interpreter is fully functional with:
- Lexer, parser, AST interpreter
- **Prototype object system with inheritance and merged method tables** ✅
- REPL with file execution
- **Block closures with full lexical scoping, environment capture, and non-local returns** ✅
- **Closure variable isolation and sibling block sharing** ✅
- Method definition syntax (`>>`) with multi-character binary operator support
- `self` and `super` support (unqualified and qualified `super<Parent>`)
- Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`) ✅
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
- [ ] Editor syntax highlighting definitions
- [ ] Build system refinements

## Future Directions

### BitBarrel Integration
- [ ] First-class barrel objects
- [ ] Transparent persistence
- [ ] Crash recovery support

### Language Evolution
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
- Added `selectorPutImpl` for proper method storage on ProtoObjects with slots
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

---

*Last Updated: 2026-01-31*
