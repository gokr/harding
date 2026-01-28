# Nimtalk Development TODO

This document tracks current work items, future directions, and known issues for Nimtalk development.

## Current Status Summary

**Project Structure**: ✅ Completed
- Source code under `src/` (Nim standard layout)
- Binary names: `ntalk` (interpreter/REPL), `ntalkc` (compiler)
- Build system updated with `build.nims` automation

**Core Language**: ✅ **Mostly Complete!**
- ✅ Lexer and parser with data structure literal syntax
- ✅ Prototype object system with property bags and prototype chains
- ✅ AST interpreter core with message sending and block evaluation
- ✅ REPL/Interpreter with file execution and interactive mode
- ✅ Slot-based instance variable system (**fully implemented, 149x performance improvement**)
- ✅ Native method dispatch from Nimtalk code
- ✅ Base library with core objects and collections
- ✅ Lexical closures with comprehensive test coverage
- ✅ Cascade syntax (`;` operator) for multiple messages to same receiver
- ⏳ Compiler infrastructure (stub implementation - next major priority)

## High Priority Tasks

### 1. Compiler Implementation
- [ ] Complete method compilation from AST to Nim procedures
- [ ] Generate proper Nim type definitions for ProtoObject
- [ ] Implement symbol export for compiled methods
- [ ] Create actual `ntalkc` functionality (currently stub)

### 2. FFI Integration
- [ ] Implement Nim type marshaling system
- [ ] Create FFI bridge for calling Nim functions from Nimtalk
- [ ] Support Nim module imports in Nimtalk
- [ ] Type conversion utilities (`asNim:`, `fromNim:`)

### 3. Language Features
- [x] Instance variable type system and core implementation (types.nim, objects.nim)
- [x] Instance variable declaration syntax (`derive: #(#ivar1 #ivar2)` - implemented as message)
- [x] Instance variable access via automatic getters/setters (automatically generated)
- [x] Lexical closures with variable capture and non-local returns
- [x] Cascade syntax (`;` operator) for multiple messages to same receiver
- [ ] Method definition syntax (`>>`) for files (parser support pending)
- [ ] `super` support for calling parent methods
- [ ] Enhanced control flow (loops, conditionals)

## Medium Priority Tasks

### 4. Standard Library Objects
- [ ] Basic collection types (Array, Dictionary equivalents)
- [ ] Number objects with arithmetic operations
- [ ] String objects with manipulation methods
- [ ] Boolean objects with conditional logic

### 5. Performance Optimization
- [ ] Method caching for faster message lookup
- [ ] AST optimization passes
- [ ] Compiler optimizations for generated Nim code
- [ ] Memory management improvements

### 6. Tooling Enhancement
- [ ] Enhanced REPL with history and completion
- [x] Better error messages and debugging support
- [x] AST inspection with `--ast` flag
- [x] Execution tracing with `--loglevel DEBUG`
- [x] Programmatic logging control (`configureLogging()`, `setLogLevel()`)
- [ ] Syntax highlighting definitions for editors
- [ ] Build system improvements

## Future Directions

### 7. BitBarrel Integration
- [ ] First-class barrel objects in language
- [ ] Transparent persistence for Nimtalk objects
- [ ] Integration with existing BitBarrel Nim library
- [ ] Crash recovery and compaction support

### 8. Language Evolution
- [ ] Optional static type checking
- [ ] Module and namespace system
- [ ] Concurrency model using Nim's threading
- [ ] Metaprogramming and reflection APIs

## Known Issues & Bugs

### Build System
- [x] Binaries may appear in source tree (`nimtalk/repl/ntalk`) or root directory (both locations supported)
- [x] Clean task in `build.nims` uses shell commands to avoid NimScript restrictions
- [x] `nim e build.nims repl` copies binaries to root directory for convenience
- [ ] Need consistent binary output location (Nimble default behavior)

### Language Implementation
- [ ] Parser edge cases with nested blocks and literals
- [ ] Memory management for circular references
- [ ] Error handling and recovery in interpreter
- [ ] Test coverage gaps in edge cases

## Documentation Needs

### User Documentation
- [x] README.md with getting started guide and examples (updated)
- [x] Design documents for slot-based instance variable system (docs/)
- [x] Debugging and tools documentation (docs/TOOLS_AND_DEBUGGING.md)
- [ ] Complete language specification (SPECIFICATION.md missing)
- [ ] Tutorials and comprehensive examples
- [ ] API reference for built-in objects
- [ ] Help text improvements (ntalk and ntalkc)

### Developer Documentation
- [x] Architecture and design documents (docs/IMPLEMENTATION-PLAN.md, docs/NIMTALK-NEW-OBJECT-MODEL.md)
- [x] Contribution guidelines (CONTRIBUTING.md)
- [x] Build and deployment instructions (README.md, build.nims)
- [ ] Internal API documentation
- [ ] Code documentation coverage

## Testing & Quality

### Test Coverage
- [x] Expand test suite for parser edge cases
- [x] Add integration tests for complete examples (test_derive_from_nimtalk.nim)
- [x] Add comprehensive evaluator tests (test_evaluator.nim - 23KB test suite)
- [x] Performance benchmarks (benchmark_slots.nim - 149x speedup)
- [x] Cross-platform testing (basic Nim portability tests)

### Code Quality
- [ ] Remove unused imports and variables (current warnings)
- [ ] Fix shadowed `result` variables
- [ ] Standardize error handling patterns
- [ ] Improve code documentation coverage

## Quick Reference

### Build Commands
```bash
# Build everything using Nimble (binaries in nimtalk/repl/, nimtalk/compiler/)
nimble build

# Build using build script (copies binaries to root directory)
nim e build.nims repl

# Run tests
nim e build.nims test
nimble test
nim c -r tests/test_core.nim

# Clean build artifacts
nim e build.nims clean

# Install binary to ~/.local/bin/ (Unix/Linux/macOS)
nim e build.nims install
```

### Project Structure
```
nimtalk/
├── src/                    # Source code (Nim standard layout)
│   └── nimtalk/
│       ├── core/          # Core types (types.nim)
│       ├── parser/        # Lexer and parser
│       ├── interpreter/   # Evaluator, objects, activation
│       ├── compiler/      # Code generation (ntalkc.nim)
│       └── repl/          # REPL implementation (ntalk.nim)
├── examples/              # Example .nt files
├── tests/                 # Test suite
└── build.nims            # Build automation
```

### Binary Usage
```bash
# Run script
ntalk hello.nt

# Evaluate expression
ntalk -e "3 + 4"

# Start interactive REPL
ntalk

# Compile (stub)
ntalkc hello.nt
```

---

*Last Updated: 2026-01-28 (Logging system implemented with programmatic control, all tests passing)*
*Project follows Nim standard layout with `src/` directory structure.*