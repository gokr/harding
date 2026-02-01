# Nimtalk Documentation

This directory contains documentation for the Nimtalk programming language.

## Structure

### User Documentation (Current)

These documents describe the current implementation and are kept up to date:

- **[VSCODE.md](VSCODE.md)** - VSCode syntax highlighting extension
- **[NEWLINE_RULES.md](NEWLINE_RULES.md)** - Newline handling and statement separation rules
- **[SYNTAX-QUICKREF-updated.md](SYNTAX-QUICKREF-updated.md)** - Quick reference for Nimtalk syntax
- **[SYNTAX-REALITY.md](SYNTAX-REALITY.md)** - Current implemented syntax details
- **[SPECIFICATION.md](SPECIFICATION.md)** - Language specification
- **[GRAMMAR.md](GRAMMAR.md)** - Formal BNF grammar for the language
- **[INHERITANCE.md](INHERITANCE.md)** - Multiple inheritance and conflict resolution
- **[TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md)** - Guide for using ntalk and ntalkc tools
- **[GREENTHREADS.md](GREENTHREADS.md)** - Green threads implementation and API
- **[CONCURRENCY.md](CONCURRENCY.md)** - Concurrency design and comparisons
- **[PRIMITIVES.md](PRIMITIVES.md)** - Primitive syntax and direct invocation
- **[PERFORM.md](PERFORM.md)** - Dynamic message sending with perform:
- **[closures.md](closures.md)** - Documentation of closure implementation
- **[NIMTALK_FOR_SMALLTALKERS.md](NIMTALK_FOR_SMALLTALKERS.md)** - Guide for Smalltalk developers

### Research and Historical Documents

The [`research/`](research/) subdirectory contains historical design documents, implementation plans, and proposals. These are kept for reference but may not reflect the current state of the implementation:

- Design proposals for the object model
- Implementation plans (marked as complete)
- Decision records from early development

When in doubt, consult the user documentation above rather than research documents.

## Quick Start

New to Nimtalk? Start with:

1. The [main README](../README.md) for an overview
2. [NEWLINE_RULES.md](NEWLINE_RULES.md) for understanding newline behavior
3. [SYNTAX-QUICKREF-updated.md](SYNTAX-QUICKREF-updated.md) for syntax reference
4. [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) for using the tools

## Contributing to Documentation

- Keep user-facing docs current with implementation changes
- Add research documents to `research/` subdirectory
- Follow the style guidelines in [CLAUDE.md](../CLAUDE.md)
