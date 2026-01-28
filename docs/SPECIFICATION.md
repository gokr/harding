# Nimtalk Language Specification

*This file is a placeholder. The full language specification will be documented here.*

## Overview

Nimtalk is a prototype-based Smalltalk dialect that compiles to Nim code. This document specifies the complete language syntax, semantics, and behavior.

## Current Status

The language specification is being developed alongside the implementation. Key design decisions are documented in other files in the `docs/` directory.

## Related Documentation

- `SYNTAX-QUICKREF-updated.md` - Syntax quick reference
- `NIMTALK-NEW-OBJECT-MODEL.md` - Object model design
- `IMPLEMENTATION-PLAN.md` - Implementation roadmap
- `CLASSES-AND-INSTANCES.md` - Class-based design exploration
- `TOOLS_AND_DEBUGGING.md` - Debugging and tooling guide

## Language Features

### Core Syntax
- Prototype-based object system with Object and Dictionary prototypes
- Message passing semantics
- Block closures with lexical scoping
- Data structure literals (`#()`, `#{}`, `{|}`)
- Method tables using canonical Symbols for identity-based lookup
- String concatenation with comma operator (`'Hello' , ' World'`)
- Collection access with `at:` method (works on arrays and tables)

### Execution Models
- AST interpreter for development and REPL
- Nim compiler backend for production

### Nim Integration
- FFI for calling Nim code
- Type marshaling between Nimtalk and Nim
- Direct Nim module imports

## Tooling

### Command-Line Tools

**ntalk** - Interactive REPL and interpreter
- `ntalk` - Start REPL
- `ntalk file.nt` - Run script
- `ntalk -e "code"` - Evaluate expression
- `ntalk --ast` - Show AST
- `ntalk --loglevel DEBUG|INFO|WARN|ERROR` - Set verbosity

**ntalkc** - Compiler to Nim
- `ntalkc compile file.nt` - Compile to Nim source
- `ntalkc build file.nt` - Compile and build
- `ntalkc run file.nt` - Compile, build, and run

### Logging

Both ntalk and ntalkc support `--loglevel` for controlling output verbosity:
- `DEBUG` - Detailed execution trace
- `INFO` - General information
- `WARN` - Warnings only
- `ERROR` - Errors only (default)

For programmatic control in tests or embedded usage:
```nim
import nimtalk/core/types
configureLogging(lvlError)  # Suppress debug output
setLogLevel(lvlDebug)       # Enable debug output
```

*Last updated: 2026-01-28 (updated with comma operator and collection access documentation)*