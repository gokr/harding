# Research and historical documents

Everything here is historical or exploratory. These documents are kept for
rationale and traceability. **They may contradict current behaviour**, and a
measurement in one of them is only meaningful at the revision it names.

Current documentation is in [../README.md](../README.md). Active plans are in
[../plans/](../plans).

When a document in `docs/` is replaced by a consolidated one, the original moves
here with its content intact rather than being deleted.

## compiler/

Granite design records, engineering logs and rejection notes. Start with the
index in [../compiler/GRANITE_PERFORMANCE.md](../compiler/GRANITE_PERFORMANCE.md),
which summarises what each slice did and measured.

- **[GRANITE_STATUS.md](compiler/GRANITE_STATUS.md)** — the completeness work
  record: per-slice evidence, validation logs, coverage claims at each stage.
- **[GRANITE_STDLIB_COMPILATION.md](compiler/GRANITE_STDLIB_COMPILATION.md)** —
  why the stdlib compiles from source, what the primitive leaf means, and the
  staged plan behind it.
- **[GRANITE_EXAMPLE_AUDIT.md](compiler/GRANITE_EXAMPLE_AUDIT.md)** — example
  coverage report at its revision.
- **[TYPE_INFERENCE_FEEDBACK.md](compiler/TYPE_INFERENCE_FEEDBACK.md)**,
  **[TRUST_OBSERVED_TYPES.md](compiler/TRUST_OBSERVED_TYPES.md)** — advisory
  inference and the opt-in specialisation flag; the current summary is in
  `../compiler/GRANITE.md` §Inference.
- **[GRANITE_SLOT_TYPE_INFERENCE.md](compiler/GRANITE_SLOT_TYPE_INFERENCE.md)** —
  measured feasibility of inferring slot types; explicitly no decision to
  implement.
- **[NUMERIC_SLOT_POLICY.md](compiler/NUMERIC_SLOT_POLICY.md)** — numeric slot
  diagnostics; folded into `../DECLARED_SLOTS.md`.
- **[GRANITE_AUDIT.md](compiler/GRANITE_AUDIT.md)** — exception and
  non-local-return migration evidence.
- **[LEGACY_GRANITE_AUDIT.md](compiler/LEGACY_GRANITE_AUDIT.md)** — salvage review
  of `feature/granite-full-compilation`, including why those commits are not
  history-merged.
- **Optimisation slices** —
  [GRANITE_PROFILE_SLICE.md](compiler/GRANITE_PROFILE_SLICE.md),
  [GRANITE_SEND_RESOLUTION.md](compiler/GRANITE_SEND_RESOLUTION.md),
  [GRANITE_SITE_CACHE.md](compiler/GRANITE_SITE_CACHE.md),
  [GRANITE_CACHE_LIFETIME.md](compiler/GRANITE_CACHE_LIFETIME.md),
  [GRANITE_BOOLEAN_PRIMITIVES.md](compiler/GRANITE_BOOLEAN_PRIMITIVES.md),
  [GRANITE_OPERAND_BINDINGS.md](compiler/GRANITE_OPERAND_BINDINGS.md),
  [GRANITE_DIRECT_SENDS.md](compiler/GRANITE_DIRECT_SENDS.md),
  [GRANITE_DIRECT_SLOTS.md](compiler/GRANITE_DIRECT_SLOTS.md),
  [GRANITE_COLLECTION_VIEWS.md](compiler/GRANITE_COLLECTION_VIEWS.md),
  [GRANITE_NATIVE_CALL_REGIONS.md](compiler/GRANITE_NATIVE_CALL_REGIONS.md),
  [GRANITE_BOUND_CLASS_MEMO.md](compiler/GRANITE_BOUND_CLASS_MEMO.md).
- **Rejected experiments** —
  [GRANITE_SELECTOR_ID_EXPERIMENT.md](compiler/GRANITE_SELECTOR_ID_EXPERIMENT.md),
  [GRANITE_SMALL_CALL_EXPERIMENT.md](compiler/GRANITE_SMALL_CALL_EXPERIMENT.md).
- **Studies** —
  [GRANITE_SPECIALIZATION_PROBE.md](compiler/GRANITE_SPECIALIZATION_PROBE.md),
  [GRANITE_LUAJIT_NOTES.md](compiler/GRANITE_LUAJIT_NOTES.md),
  [GRANITE_PORTFOLIO_EXAMPLE.md](compiler/GRANITE_PORTFOLIO_EXAMPLE.md),
  [GRANITE_NATIVE_KERNEL_DEMO.md](compiler/GRANITE_NATIVE_KERNEL_DEMO.md) — a
  numeric kernel generated from Harding, with the verbatim Nim it produced.

## benchmarks/

- **[BENCHMARK_COMPARISON_CURRENT.md](benchmarks/BENCHMARK_COMPARISON_CURRENT.md)**
  — Cog/Node comparison at `18e3728`. The name is historical; read the revision.
- **[GRANITE_BENCHMARKS.md](benchmarks/GRANITE_BENCHMARKS.md)** — the first
  cross-language baseline, before the dispatch work.
- **[BENCHMARK_PRACTICAL_BASELINES.md](benchmarks/BENCHMARK_PRACTICAL_BASELINES.md)**,
  **[AWFY_COMPARISON.md](benchmarks/AWFY_COMPARISON.md)** — the sources folded
  into `../performance/BENCHMARKS.md`.
- **[AWFY_STDLIB_AUDIT.md](benchmarks/AWFY_STDLIB_AUDIT.md)** — SOM stdlib audit
  for the AWFY ports.
- **[OPENSMALLTALK_OIL_COMPARISON.md](benchmarks/OPENSMALLTALK_OIL_COMPARISON.md)**
  — the Oil/Cog build and verification record, with its evidence under
  `../evidence/oil/`.
- **[GRANITE_BASELINE_A1BBEA0.md](benchmarks/GRANITE_BASELINE_A1BBEA0.md)** —
  release profiles and verified object/JSON runs at `a1bbea0`. A baseline at that
  revision, not a before/after claim.

## language/

- **[LANGUAGE_COMPARISON.md](language/LANGUAGE_COMPARISON.md)**,
  **[HARDING_VS_SMALLTALK80.md](language/HARDING_VS_SMALLTALK80.md)**,
  **[COLLECTION_PROTOCOL_AUDIT.md](language/COLLECTION_PROTOCOL_AUDIT.md)** — the
  sources folded into `../COMPARISONS.md`.
- **[NIL_AND_ABSENCE.md](language/NIL_AND_ABSENCE.md)** — the nil investigation:
  what was measured, why removing nameable nil was rejected, and which defects
  were worth fixing anyway. Audit script: `scripts/audit_nil_usage.py`.

## gui/

- **[BONA_ASSESSMENT.md](gui/BONA_ASSESSMENT.md)** — Bona defects with
  reproductions, plus the hardening log. Current state is in `../gtk/BONA.md`.
- **[GTK_SUPPORT.md](gui/GTK_SUPPORT.md)** — GTK coverage inventory,
  shared-backend contracts and the Notebook implementation plan.

## web/

- **[REACTIVE_WEB_RENDERING.md](web/REACTIVE_WEB_RENDERING.md)** — the design note
  that introduced tracked state plus external render caching.
- **[HTML_CANVAS_STATUS.md](web/HTML_CANVAS_STATUS.md)** — the phase-1 Html DSL
  status snapshot.
- **[BONA_WEB_TODO.md](web/BONA_WEB_TODO.md)** — the first Bona live-editing
  walkthrough; the maintained version is in `../gtk/BONA.md`.

## toolchain/

- **[NIM_2_4_EVALUATION.md](toolchain/NIM_2_4_EVALUATION.md)** — Nim 2.4.0
  compatibility evaluation against the pinned 2.2.12.
- **[NIMONY_ASSESSMENT.md](toolchain/NIMONY_ASSESSMENT.md)** — Nimony migration
  assessment; an investigation, not a port.

## planning/

- **[FUTURE.md](planning/FUTURE.md)** — long-range intentions, superseded by
  `../plans/ROADMAP.md`.
- **[DOCS_CONSOLIDATION_PLAN.md](planning/DOCS_CONSOLIDATION_PLAN.md)** — the
  disposition of every original `docs/*.md` file and the waves that produced the
  current layout.

## Design and early implementation records (this directory)

- **[PROPOSAL-object-model.md](PROPOSAL-object-model.md)** — original slot-based
  object model proposal.
- **[NIMTALK-NEW-OBJECT-MODEL.md](NIMTALK-NEW-OBJECT-MODEL.md)** — object model
  design summary.
- **[CLASSES-AND-INSTANCES.md](CLASSES-AND-INSTANCES.md)** — class-like
  conventions explored during design.
- **[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)** — the 6-week implementation
  plan (all phases completed).
- **[DECISION-NEEDED.md](DECISION-NEEDED.md)** — early design decision records.
- **[SPECIFICATION.md](SPECIFICATION.md)**, **[GRAMMAR.md](GRAMMAR.md)**,
  **[SYNTAX-QUICKREF-updated.md](SYNTAX-QUICKREF-updated.md)**,
  **[SYNTAX-REALITY.md](SYNTAX-REALITY.md)**,
  **[NEWLINE_RULES.md](NEWLINE_RULES.md)** — language specification attempts.
  Current syntax is `../QUICKREF.md` and `../MANUAL.md`.
- **[SMALLTALK80.md](SMALLTALK80.md)**,
  **[NIMTALK_FOR_SMALLTALKERS.md](NIMTALK_FOR_SMALLTALKERS.md)** — earlier
  compatibility assessments and introductory material.
- **[INHERITANCE.md](INHERITANCE.md)**, **[closures.md](closures.md)**,
  **[DynamicCollectionLiterals.md](DynamicCollectionLiterals.md)**,
  **[ExceptionHandling.md](ExceptionHandling.md)**,
  **[PRIMITIVES.md](PRIMITIVES.md)**, **[PERFORM.md](PERFORM.md)** — feature
  design notes.
- **[CONCURRENCY.md](CONCURRENCY.md)**, **[GREENTHREADS.md](GREENTHREADS.md)**,
  **[GINTRO.md](GINTRO.md)** — concurrency and GTK/IDE design plans.
- **[JSON_SERIALIZATION_PLAN.md](JSON_SERIALIZATION_PLAN.md)**,
  **[JSON_SERIALIZATION_V2.md](JSON_SERIALIZATION_V2.md)**,
  **[OPENAPI_AND_API_SERVER_PLAN.md](OPENAPI_AND_API_SERVER_PLAN.md)**,
  **[MUMMYX_LIB.md](MUMMYX_LIB.md)** — JSON, API and MummyX plans.
- **[NIMTALK-TEST-FRAMEWORK-PLAN.md](NIMTALK-TEST-FRAMEWORK-PLAN.md)**,
  **[NODEVALUE_INSTANCE_UNIFICATION_PLAN.md](NODEVALUE_INSTANCE_UNIFICATION_PLAN.md)**,
  **[COMPILER-PLAN.md](COMPILER-PLAN.md)**,
  **[GRANITE_NEXT_STEPS.md](GRANITE_NEXT_STEPS.md)**,
  **[CONSTANT_LITERAL_OPTIMIZATION.md](CONSTANT_LITERAL_OPTIMIZATION.md)** —
  implementation plans.
- **[TODO.md](TODO.md)**, **[IMPROVEMENTS.md](IMPROVEMENTS.md)**,
  **[EXAMPLE_MATRIX.md](EXAMPLE_MATRIX.md)**, **[OPTIMIZE.md](OPTIMIZE.md)**,
  **[PERFORMANCE_ANALYSIS_2026.md](PERFORMANCE_ANALYSIS_2026.md)**,
  **[performance_baseline.md](performance_baseline.md)**,
  **[performance_optimization_plan.md](performance_optimization_plan.md)** —
  archived operational notes and snapshots.
- **[JAVASCRIPT.md](JAVASCRIPT.md)** — JavaScript compilation exploration.
- **[NEWNAME.md](NEWNAME.md)** — naming inspiration.
- **[BONA_MCP.md](BONA_MCP.md)** — Bona MCP protocol design and history.
- **[proposal-examples/](proposal-examples)** — example sources for the object
  model proposal.

## When to refer here

- understanding why a decision was made;
- seeing alternatives that were considered and rejected;
- recovering a measurement's method and evidence;
- historical context for current behaviour.

Prefer `../README.md` when you need to know what the code does now.
