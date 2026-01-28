# Design Decisions Needed for Nimtalk

*This document tracks key design decisions that need to be made during Nimtalk development.*

## Open Decisions

### 1. String Literal Syntax
**Current State**: Both single quotes `'string'` and double quotes `"string"` are supported by lexer
**Proposal**: Standardize on double quotes `"string"` for strings, single quotes `'c'` for characters
**Decision Needed**: Should we deprecate single quotes for strings?
**Status**: Migration in progress - documentation updated to use double quotes

### 2. Instance Variable Access Syntax
**Current State**: ✅ Automatic getter/setter generation for declared ivars
**Proposal**: Add direct slot access syntax like Smalltalk (just use ivar name)
**Decision Needed**: What syntax for slot access? `person name` vs `person@name` vs keep `person at: "name"`
**Status**: ✅ Core types implemented with direct slot access, syntax design complete (automatic accessors)

### 3. Method Definition Syntax (`>>`)
**Current State**: ✅ Methods stored as properties via `at:put:` and `>>` syntax implemented
**Proposal**: `>>` syntax for method definitions in files
**Decision**: ✅ **IMPLEMENTED** - Parser supports `>>` syntax for method definitions
**Status**: ✅ Complete - Works in both REPL and file mode with full test coverage

### 4. Class-based vs Prototype-based
**Current State**: Pure prototype-based system
**Proposal**: Hybrid model with class-like behavior using slots
**Decision Needed**: How much class semantics to implement?
**Status**: Moving toward Smalltalk-like semantics while keeping prototype flexibility

### 5. Compilation Model
**Current State**: AST interpreter only, compiler stub exists
**Proposal**: Full Nim code generation
**Decision Needed**: What compilation strategy? Whole-program vs incremental?
**Status**: Early design phase

## Decided Issues

### ✅ String Literals
**Decision**: Use double quotes `"string"` for strings, single quotes `'c'` for characters
**Rationale**: Matches modern languages, distinguishes strings from characters
**Status**: Documentation updated, examples being migrated

### ✅ Build System
**Decision**: Support both Nimble defaults (binaries in subdirs) and build script (copies to root)
**Rationale**: Works with Nimble conventions while providing user convenience
**Status**: Implemented in `build.nims`

### ✅ Slot-based Instance Variables
**Decision**: Implement hybrid model supporting both property bags and slots
**Rationale**: Backwards compatibility + performance benefits (149x improvement!)
**Status**: ✅ COMPLETE - Core types implemented, parser supports `derive: #()` syntax, automatic accessor generation

## Decision Process

1. Document proposal in relevant design documents
2. Discuss in GitHub issues or discussions
3. Implement prototype if needed
4. Make decision based on implementation experience
5. Update documentation with decision

## How to Contribute

1. Read related design documents
2. Experiment with implementation options
3. Submit proposals or feedback
4. Help implement decided features

*Last updated: 2026-01-28 (Slot system complete, >> method syntax implemented, super/self support complete)*