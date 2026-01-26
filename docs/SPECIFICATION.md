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

## Language Features

### Core Syntax
- Prototype-based object system
- Message passing semantics
- Block closures with lexical scoping
- Data structure literals (`#()`, `#{}`, `{|}`)

### Execution Models
- AST interpreter for development and REPL
- Nim compiler backend for production

### Nim Integration
- FFI for calling Nim code
- Type marshaling between Nimtalk and Nim
- Direct Nim module imports

*Last updated: 2026-01-26*