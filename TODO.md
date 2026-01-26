# Nimtalk Development TODO

This document tracks current work items, future directions, and known issues for Nimtalk development.

## Current Status Summary

**Project Structure**: ✅ Completed
- Source code under `src/` (Nim standard layout)
- Binary names: `ntalk` (interpreter/REPL), `ntalkc` (compiler)
- Build system updated with `build.nims` automation

**Core Language**: ⚡ In Progress
- ✅ Lexer and parser with data structure literal syntax
- ✅ Prototype object system with property bags
- ✅ AST interpreter core with message sending
- ✅ REPL/Interpreter with file execution support
- ⏳ Compiler infrastructure (stub implementation)

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
- [ ] Instance variable declaration syntax (`derive: #(ivar1 ivar2)`)
- [ ] Method definition syntax (`>>`) for files
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
- [ ] Better error messages and debugging support
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
- [ ] Binaries may appear in source tree (`nimtalk/repl/ntalk`) or root directory
- [ ] Clean task in `build.nims` has NimScript target restrictions
- [ ] Need consistent binary output location

### Language Implementation
- [ ] Parser edge cases with nested blocks and literals
- [ ] Memory management for circular references
- [ ] Error handling and recovery in interpreter
- [ ] Test coverage gaps in edge cases

## Documentation Needs

### User Documentation
- [ ] Complete language specification
- [ ] Tutorials and getting started guides
- [ ] API reference for built-in objects
- [ ] Examples covering all language features

### Developer Documentation
- [ ] Architecture and design documents
- [ ] Internal API documentation
- [ ] Contribution guidelines and examples
- [ ] Build and deployment instructions

## Testing & Quality

### Test Coverage
- [ ] Expand test suite for parser edge cases
- [ ] Add integration tests for complete examples
- [ ] Performance benchmarks
- [ ] Cross-platform testing

### Code Quality
- [ ] Remove unused imports and variables (current warnings)
- [ ] Fix shadowed `result` variables
- [ ] Standardize error handling patterns
- [ ] Improve code documentation coverage

## Quick Reference

### Build Commands
```bash
# Build everything
nimble build

# Build just REPL/interpreter
nim e build.nims repl

# Run tests
nimble test
nim c -r tests/test_core.nim

# Clean build artifacts
nim e build.nims clean  # (has NimScript target issues)

# Install binary
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

*Last Updated: 2026-01-26*
*Project follows Nim standard layout with `src/` directory structure.*