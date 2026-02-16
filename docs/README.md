# Harding Documentation

This directory contains documentation for the Harding programming language.

## User Documentation

These are the primary documents for learning and using Harding:

| Document | Description | Audience |
|----------|-------------|----------|
| [MANUAL.md](MANUAL.md) | Complete language reference manual | All users |
| [QUICKREF.md](QUICKREF.md) | Quick syntax cheat sheet | Quick lookup |
| [GTK.md](GTK.md) | GTK bridge and GUI development | GUI developers |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | VM internals and architecture | Contributors |
| [bootstrap.md](bootstrap.md) | Foundation and architecture of the VM bootstrap | Contributors |
| [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) | Tool usage (`harding`, `granite`) and debugging | All users |
| [FUTURE.md](FUTURE.md) | Future plans and roadmap | Contributors |
| [VSCODE.md](VSCODE.md) | VSCode syntax highlighting extension | VSCode users |

## Getting Started

New to Harding? Start with these documents in order:

1. [MANUAL.md](MANUAL.md) - Complete language manual
2. [QUICKREF.md](QUICKREF.md) - Quick reference when you're coding
3. [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - How to use `harding` and `granite`

## Specialized Topics

| Topic | Document |
|-------|----------|
| GUI Development | [GTK.md](GTK.md) |
| Contributing | [IMPLEMENTATION.md](IMPLEMENTATION.md) |
| Future Roadmap | [FUTURE.md](FUTURE.md) |

## Design Documents

The [`design/`](design/) directory contains architecture documents for major subsystems:

| Document | Description |
|----------|-------------|
| [COMPILATION_PIPELINE.md](design/COMPILATION_PIPELINE.md) | Granite compiler architecture and pipeline |

## Historical and Research Documents

The [`research/`](research/) directory contains historical design documents, implementation plans, and proposals. These documents are kept for reference but may not reflect the current implementation.

When in doubt, consult the user documentation above rather than research documents.

## Contributing to Documentation

- Keep user-facing documentation current with implementation changes
- Add research documents to `research/` subdirectory
- Follow the style guidelines in [../CLAUDE.md](../CLAUDE.md)
