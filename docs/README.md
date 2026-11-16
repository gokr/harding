# Harding documentation

Everything under `docs/` describes what the code does **today**. Historical
design notes, dated audits, superseded plans and measurement snapshots live in
[research/](research), which is explicitly not current.

Working plans — the defect list, the roadmap, agreed-but-unimplemented targets —
live in [plans/](plans). Those describe intent, not current behaviour.

`PLAN.md` in the repository root is the Granite completeness plan and is the one
plan deliberately kept outside `docs/`.

## Start here

| If you want to… | Read |
|---|---|
| learn the language | [MANUAL.md](MANUAL.md) |
| look up syntax quickly | [QUICKREF.md](QUICKREF.md) |
| see how Harding compares to Smalltalk-80, Python, Ruby, Go, Cog | [COMPARISONS.md](COMPARISONS.md) |
| use the CLI, REPL, debugger or profiler | [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) |
| write an application | [APPLICATION_STRUCTURE.md](APPLICATION_STRUCTURE.md) |
| build a GTK4 desktop app | [gtk/GTK.md](gtk/GTK.md) → [gtk/GTK_APPLICATIONS.md](gtk/GTK_APPLICATIONS.md) |
| use the Bona IDE | [gtk/BONA.md](gtk/BONA.md) |
| serve HTTP or render HTML | [web/MUMMYX.md](web/MUMMYX.md) → [web/HTML.md](web/HTML.md) |
| ship a Nim-backed library | [NIM_PACKAGE_TUTORIAL.md](NIM_PACKAGE_TUTORIAL.md) |
| understand the VM internals | [IMPLEMENTATION.md](IMPLEMENTATION.md) |
| understand the compiler | [compiler/GRANITE.md](compiler/GRANITE.md) |
| see how fast it is | [performance/BENCHMARKS.md](performance/BENCHMARKS.md) |
| use Harding from an AI coding harness | [AI_HARNESS_INTEGRATION.md](AI_HARNESS_INTEGRATION.md) |

## Language and runtime

| Document | Contents |
|---|---|
| [MANUAL.md](MANUAL.md) | complete language and runtime reference |
| [QUICKREF.md](QUICKREF.md) | syntax and common idioms |
| [COMPARISONS.md](COMPARISONS.md) | Smalltalk-80, Python, Ruby, Go, Cog, GNU Smalltalk: what is faithful, what is deliberately different, what is missing |
| [EXCEPTION_MODEL.md](EXCEPTION_MODEL.md) | the accepted exception contract both engines implement |
| [DECLARED_SLOTS.md](DECLARED_SLOTS.md) | optional slot type contracts, defaults, and the compile-time numeric policy |
| [BOOTSTRAP.md](BOOTSTRAP.md) | how the VM boots and loads the stdlib |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | stackless VM, scheduler, dispatch, activation records |
| [AI_HARNESS_INTEGRATION.md](AI_HARNESS_INTEGRATION.md) | what Harding offers an LLM or agent harness, and the gaps |

## Compiler

| Document | Contents |
|---|---|
| [compiler/GRANITE.md](compiler/GRANITE.md) | what compiles today, the engine boundary, inference, known gaps |
| [compiler/GRANITE_RUNTIME.md](compiler/GRANITE_RUNTIME.md) | compiled representation contracts for collections and object JSON |
| [compiler/GRANITE_PERFORMANCE.md](compiler/GRANITE_PERFORMANCE.md) | every optimisation slice: what changed, what it measured, what was rejected |
| [COMPILATION_PIPELINE.md](COMPILATION_PIPELINE.md) | pipeline architecture shared by CLI and in-VM compilation |

## Tools

| Document | Contents |
|---|---|
| [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) | `harding`, `granite`, `bona`, debug builds, GDB, profiling |
| [VSCODE.md](VSCODE.md) | extension, LSP and DAP |

## Desktop: GTK and Bona

| Document | Contents |
|---|---|
| [gtk/GTK.md](gtk/GTK.md) | entry point: two bridges, which one to use, what is missing |
| [gtk/GTK_APPLICATIONS.md](gtk/GTK_APPLICATIONS.md) | standalone GTK4 applications, interpreted or compiled |
| [gtk/BONA.md](gtk/BONA.md) | the IDE: tools, workflows, live web editing, known gaps |
| [gtk/GTKSOURCEVIEW.md](gtk/GTKSOURCEVIEW.md) | syntax highlighting for GNOME editors |

## Web

| Document | Contents |
|---|---|
| [web/MUMMYX.md](web/MUMMYX.md) | HTTP server integration and its concurrency model |
| [web/HTML.md](web/HTML.md) | the `Html` DSL, tracked state, component render caching |
| [web/API_SERVER_TUTORIAL.md](web/API_SERVER_TUTORIAL.md) | build a JSON API server with MummyX and BitBarrel |

## Building and performance

| Document | Contents |
|---|---|
| [APPLICATION_STRUCTURE.md](APPLICATION_STRUCTURE.md) | structuring and building Harding applications as Nim packages |
| [NIM_PACKAGE_TUTORIAL.md](NIM_PACKAGE_TUTORIAL.md) | shipping Nim primitives with embedded `.hrd` sources |
| [performance/PERFORMANCE.md](performance/PERFORMANCE.md) | profiling workflow and current priorities |
| [performance/BENCHMARKS.md](performance/BENCHMARKS.md) | current cross-engine numbers, method, reproduction |
| [performance/BENCHMARK_COVERAGE.md](performance/BENCHMARK_COVERAGE.md) | why the dispatch and object-graph workloads exist, and what each exercises |
| [performance/RICHARDS.md](performance/RICHARDS.md) | Richards port provenance and conformance |
| [performance/DELTABLUE.md](performance/DELTABLUE.md) | DeltaBlue port provenance and licensing |

## Plans

These describe intent. They are allowed to be ahead of the code.

| Document | Contents |
|---|---|
| [plans/ROADMAP.md](plans/ROADMAP.md) | active priorities and milestones |
| [plans/FIXES.md](plans/FIXES.md) | confirmed defects and cheap Smalltalk-alignment work |
| [plans/PRIMITIVE_TYPES_ROADMAP.md](plans/PRIMITIVE_TYPES_ROADMAP.md) | agreed target representation and specialised containers |
| [plans/GRANITE_TYPED_MEMBERS_DESIGN.md](plans/GRANITE_TYPED_MEMBERS_DESIGN.md) | proposal: typed native members |

## Research and history

[research/](research) holds design documents, archived plans, dated audits,
rejected experiments and measurement snapshots. They are kept for rationale and
traceability and **may contradict current behaviour**. Start at
[research/README.md](research/README.md). It is organised by area:
`compiler/`, `benchmarks/`, `language/`, `gui/`, `web/`, `toolchain/`,
`planning/`.

`docs/evidence/oil/` holds the captured evidence for the OpenSmalltalk Oil
verification record in `research/benchmarks/`.

## Contributing to documentation

- A document in `docs/` must describe behaviour you can reproduce today. Date and
  revision-pin anything that is a measurement.
- A design note, investigation record, dated audit or superseded plan belongs in
  `research/`, not here.
- An unimplemented target belongs in `plans/`, or in `PLAN.md` if it is part of
  the Granite completeness plan.
- When a document is replaced, move the original to `research/` rather than
  deleting it, and update links in the same change set.
- Follow the style rules in [../AGENTS.md](../AGENTS.md): neutral language, no
  superlatives, no comments about how good something is.
