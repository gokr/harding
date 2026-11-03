# Harding Documentation

This directory contains documentation for the Harding programming language.

## Canonical Documents

These are the active, maintained documents:

| Document | Purpose | Audience |
|----------|---------|----------|
| [MANUAL.md](MANUAL.md) | Complete language and runtime reference | All users |
| [QUICKREF.md](QUICKREF.md) | Syntax and common idioms cheat sheet | Daily reference |
| [LANGUAGE_COMPARISON.md](LANGUAGE_COMPARISON.md) | Language-design review against Smalltalk-80, Python, Ruby and Go; distinctive features, simplifications and known shortcomings | Users and contributors |
| [AI_HARNESS_INTEGRATION.md](AI_HARNESS_INTEGRATION.md) | What Harding offers LLM/agent harnesses, why source beats AST generation, and the gaps to close | Contributors |
| [NIL_AND_ABSENCE.md](NIL_AND_ABSENCE.md) | Findings on nil/absence: why removing nameable nil was rejected, measured nil-usage audit, decided fixes (lookup signals, `isNil` primitive, `Root`) | Contributors |
| [MUMMYX.md](MUMMYX.md) | Optional HTTP server integration | Users and contributors |
| [API_SERVER_TUTORIAL.md](API_SERVER_TUTORIAL.md) | Build a plain JSON API server with MummyX and BitBarrel | Users |
| [NIM_PACKAGE_TUTORIAL.md](NIM_PACKAGE_TUTORIAL.md) | Packaging Nim primitives with Harding code | Contributors |
| [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) | CLI tools, workflows, and debugging | Users and contributors |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | VM/runtime architecture details | Contributors |
| [BOOTSTRAP.md](BOOTSTRAP.md) | Bootstrap architecture and stdlib loading | Contributors |
| [COMPILATION_PIPELINE.md](COMPILATION_PIPELINE.md) | Granite compiler pipeline | Contributors |
| [ROADMAP.md](ROADMAP.md) | Active development priorities | Contributors |
| [PERFORMANCE.md](PERFORMANCE.md) | Performance workflow and current priorities | Contributors |
| [VSCODE.md](VSCODE.md) | VSCode extension usage | VSCode users |
| [GTK.md](GTK.md) | GTK bridge and GUI development | GUI developers |
| [GTKSOURCEVIEW.md](GTKSOURCEVIEW.md) | GtkSourceView syntax highlighting | GNOME/GtkSourceView users |
| [FUTURE.md](FUTURE.md) | Longer-term plans and directions | Contributors |

## Getting Started

New to Harding? Start with these documents in order:

1. [MANUAL.md](MANUAL.md) - Complete language manual
2. [QUICKREF.md](QUICKREF.md) - Quick reference when you're coding
3. [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - How to use `harding` and `granite`

## Historical and Research Documents

The [`research/`](research/) directory contains historical design notes, implementation plans, archived optimization proposals, and earlier roadmap material.

These files are preserved for context and traceability, but may not match current behavior.

When in doubt, prefer the canonical documents listed above.

## Contributing to Documentation

- Keep user-facing documentation current with implementation changes
- Add research documents to `research/` subdirectory
- Follow the style guidelines in [../AGENTS.md](../AGENTS.md)
