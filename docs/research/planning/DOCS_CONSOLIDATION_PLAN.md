# Documentation consolidation plan

Inventory and disposition for every Markdown file that was under `docs/`. This
is a record of completed work; it is kept with the other archived planning notes
because it holds the disposition table for all 74 original files.

## Status: executed and committed

All waves landed as separate commits. `docs/` went from 74 flat files to 14, with
the rest in purpose-named subdirectories. Six consolidated documents replaced
their sources.

`scripts/docgraph.py` walks the whole tree recursively and reports **0 broken
links**. Its orphan list is empty except for the two `docs/evidence/oil/`
`README.md` files, which are reached as directories from the Oil record rather
than as files; that is intended.

Follow-ups closed after the moves:

- Regenerated `website/dist/docs.html` now uses the moved paths; `dist/` is
  generated output that is committed, so it has to be repaired with the sources.
- `benchmark/deltablue.hrd` and `benchmark/licenses/DELTABLUE.txt` pointed at
  `docs/DELTABLUE.md`; both name the new path.
- `scripts/docgraph.py` had been an `os.listdir` scan of `docs/` and
  `docs/research/`, so it could not see the new subdirectories and its "no
  orphan and no broken link" result described only the old flat tree. It now
  walks recursively and ignores links inside code fences.
- `docs/research/README.md` listed its entries as code spans, leaving 43 archived
  documents with no inbound link. They are links now.

Still true, deliberately:

- `CHANGELOG.md` keeps pre-move paths in its older entries. They name the tree as
  it was at that release and are not rewritten.
- `docs/research/TODO.md` records a historical move of `docs/JAVASCRIPT.md`; its
  path text is historical too.
- `docs/research/gui/GTK_SUPPORT.md` is a dated audit. `docs/gtk/GTK.md` now says
  its "Missing" column predates the entry, list and text-view additions.

## Problem

`docs/` holds 74 files and `docs/research/` holds 51. Roughly 40 of the top-level
files are engineering logs of one optimisation slice, audits taken at a specific
commit, or plans for work that is already merged. Thirty-two top-level documents
have no inbound link at all, so the directory no longer tells a reader what is
current, and several documents describe themselves as historical while sitting
next to the reference manual.

Measured with a one-off link inventory (the origin of `scripts/docgraph.py`):

- 32 top-level `docs/*.md` with zero inbound links, including 15 `GRANITE_*`
  slice write-ups, `APPLICATION_STRUCTURE.md`, `NIMONY_ASSESSMENT.md`,
  `NIM_2_4_EVALUATION.md`, `REACTIVE_WEB_RENDERING.md`.
- `docs/README.md` is itself unlinked, and its "canonical" table lists 24 of 74
  files.
- 8 real broken links (rest of the checker's hits are Nim code samples and
  website router paths): `PLAN.md` → `GRANITE_BENCHMARKS.md`,
  `research/PRIMITIVES.md` → `RUNTIME.md`, `research/SPECIFICATION.md` →
  `VSCODE.md`, `research/SYNTAX-QUICKREF-updated.md` → `TOOLS_AND_DEBUGGING.md`.
- All nine evidence paths cited by `OPENSMALLTALK_OIL_COMPARISON.md` exist under
  `docs/evidence/oil/`; the evidence directory moves with that record.

## Rules applied

1. **`docs/` describes what the code does today.** Reference, guides, contracts,
   current semantics, current performance numbers, comparisons against other
   Smalltalks and languages.
2. **`docs/research/` holds history.** Dated audits, superseded plans, rejected
   experiments, measurement snapshots, investigation records. A research
   document states its baseline revision in its first paragraph.
3. **Plans live outside `docs/`.** `PLAN.md` at the root keeps its job; working
   checklists (roadmaps, defect lists, feature targets) move to `docs/plans/`,
   which is explicitly exempt from the "describes today" rule.
4. **One document per question.** Where three files answer the same question,
   one consolidated document is written and the originals move to
   `docs/research/` under a purpose-named subdirectory, with their content
   intact rather than deleted.
5. **Paths in `CHANGELOG.md` are historical** and are not rewritten; they name
   the tree as it was at that release.

## Target tree

```
docs/
├── README.md                  index: what to read, in what order
├── MANUAL.md                  language and runtime reference
├── QUICKREF.md                syntax cheat sheet
├── COMPARISONS.md             Smalltalk-80, Python, Ruby, Go, Cog, GNU Smalltalk
├── AI_HARNESS_INTEGRATION.md  what Harding offers LLM/agent harnesses
├── IMPLEMENTATION.md          VM, scheduler, dispatch, activation internals
├── BOOTSTRAP.md               VM bootstrap and stdlib loading
├── COMPILATION_PIPELINE.md    Granite pipeline and engine boundary
├── EXCEPTION_MODEL.md         accepted exception contract
├── DECLARED_SLOTS.md          declared slot contract and numeric checks
├── TOOLS_AND_DEBUGGING.md     CLI tools, REPL, debug builds, profiling workflow
├── VSCODE.md                  extension, LSP and DAP
├── APPLICATION_STRUCTURE.md   how to structure and build an application
├── NIM_PACKAGE_TUTORIAL.md    shipping Nim primitives with .hrd sources
├── compiler/
│   ├── GRANITE.md             current compiler capability and known gaps
│   ├── GRANITE_RUNTIME.md     compiled representation contracts (collections/JSON)
│   └── GRANITE_PERFORMANCE.md dispatch/optimisation design + slice index
├── gtk/
│   ├── GTK.md                 entry point, two bridges, known gaps
│   ├── GTK_APPLICATIONS.md    standalone GTK4 applications
│   ├── BONA.md                IDE: tools, workflows, open defects
│   └── GTKSOURCEVIEW.md       syntax highlighting install
├── web/
│   ├── MUMMYX.md              HTTP server integration and concurrency model
│   ├── HTML.md                Html DSL and render caching
│   └── API_SERVER_TUTORIAL.md JSON API server walkthrough
├── performance/
│   ├── PERFORMANCE.md         profiling workflow and current priorities
│   ├── BENCHMARKS.md          current cross-engine numbers and how to reproduce
│   ├── RICHARDS.md            port provenance and conformance
│   └── DELTABLUE.md           port provenance and conformance
├── plans/                     explicitly not "current capabilities"
│   ├── ROADMAP.md             active priorities
│   ├── FIXES.md               confirmed defects and Smalltalk alignment list
│   ├── PRIMITIVE_TYPES_ROADMAP.md
│   └── GRANITE_TYPED_MEMBERS_DESIGN.md
├── research/                  history, one level of purpose subdirectories
│   ├── README.md
│   ├── compiler/ benchmarks/ language/ planning/ gui/ web/ toolchain/
└── (research/evidence/oil/ stays where the analysis refers to it)
```

## Classification of `docs/*.md`

Legend: **Keep** = stays, content is current (wording fixed if needed);
**Merge** = content folded into a named document, original archived;
**Research** = moves to `docs/research/<subdir>/` unchanged;
**Plan** = moves to `docs/plans/`.

| File | What it is | Disposition |
|---|---|---|
| `MANUAL.md` | language reference | Keep |
| `QUICKREF.md` | syntax reference | Keep; move status prose into `EXCEPTION_MODEL.md` link |
| `IMPLEMENTATION.md` | VM internals | Keep; refresh against current VM |
| `BOOTSTRAP.md` | bootstrap architecture | Keep |
| `COMPILATION_PIPELINE.md` | Granite pipeline | Keep |
| `EXCEPTION_MODEL.md` | accepted contract | Keep; drop "branch, not a claim" status |
| `DECLARED_SLOTS.md` | slot contract | Keep; absorb `NUMERIC_SLOT_POLICY.md` |
| `TOOLS_AND_DEBUGGING.md` | tools guide | Keep |
| `VSCODE.md` | editor support | Keep |
| `APPLICATION_STRUCTURE.md` | application guide | Keep; link from index |
| `NIM_PACKAGE_TUTORIAL.md` | packaging tutorial | Keep |
| `AI_HARNESS_INTEGRATION.md` | capability review | Keep; move to `COMPARISONS.md` only if it grows |
| `LANGUAGE_COMPARISON.md` | comparison | Merge → `COMPARISONS.md` |
| `HARDING_VS_SMALLTALK80.md` | comparison | Merge → `COMPARISONS.md` |
| `COLLECTION_PROTOCOL_AUDIT.md` | collection comparison | Merge → `COMPARISONS.md` §collections |
| `FIXES.md` | defect/alignment work list | Plan → `plans/FIXES.md` |
| `ROADMAP.md` | priorities | Plan → `plans/ROADMAP.md` |
| `FUTURE.md` | long-range intentions | Merge → `plans/ROADMAP.md` §long-term; archive |
| `PRIMITIVE_TYPES_ROADMAP.md` | agreed target representation | Plan → `plans/` |
| `GRANITE_TYPED_MEMBERS_DESIGN.md` | proposal, no code | Plan → `plans/` |
| `GRANITE_SLOT_TYPE_INFERENCE.md` | measured feasibility study | Research → `research/compiler/` |
| `TYPE_INFERENCE_FEEDBACK.md` | implemented advisory inference | Merge → `compiler/GRANITE.md` §inference |
| `TRUST_OBSERVED_TYPES.md` | opt-in flag for the above | Merge → `compiler/GRANITE.md` §inference |
| `NUMERIC_SLOT_POLICY.md` | slot check policy | Merge → `DECLARED_SLOTS.md` |
| `GRANITE_STATUS.md` | merged work record + capability | Merge → `compiler/GRANITE.md` (current view) |
| `GRANITE_STDLIB_COMPILATION.md` | stdlib compilation design | Merge → `compiler/GRANITE.md`; archive |
| `GRANITE_EXAMPLE_AUDIT.md` | example coverage report | Merge → `compiler/GRANITE.md` §coverage; archive |
| `GRANITE_COLLECTIONS_AND_JSON.md` | representation contract | Keep → `compiler/GRANITE_RUNTIME.md` |
| `GRANITE_AUDIT.md` | exception migration evidence | Research → `research/compiler/` |
| `LEGACY_GRANITE_AUDIT.md` | branch salvage audit | Research → `research/compiler/` |
| `GRANITE_SITE_CACHE.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_SEND_RESOLUTION.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_DIRECT_SENDS.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_DIRECT_SLOTS.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_OPERAND_BINDINGS.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_CACHE_LIFETIME.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_COLLECTION_VIEWS.md` | defect analysis | Research → `research/compiler/` |
| `GRANITE_PROFILE_SLICE.md` | profiling slice | Research → `research/compiler/` |
| `GRANITE_BOOLEAN_PRIMITIVES.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_NATIVE_CALL_REGIONS.md` | prototype record | Research → `research/compiler/` |
| `GRANITE_BOUND_CLASS_MEMO.md` | optimisation slice | Research → `research/compiler/` |
| `GRANITE_SELECTOR_ID_EXPERIMENT.md` | rejected experiment | Research → `research/compiler/` |
| `GRANITE_SMALL_CALL_EXPERIMENT.md` | rejected experiment | Research → `research/compiler/` |
| `GRANITE_SPECIALIZATION_PROBE.md` | measurement probe | Research → `research/compiler/` |
| `GRANITE_LUAJIT_NOTES.md` | external-compiler reading notes | Research → `research/compiler/` |
| `GRANITE_PORTFOLIO_EXAMPLE.md` | example walkthrough | Research → `research/compiler/` (examples manifest is the live record) |
| `GRANITE_BENCHMARKS.md` | historical baseline | Research → `research/benchmarks/` |
| `BENCHMARK_COMPARISON_CURRENT.md` | historical (`18e3728`) | Research → `research/benchmarks/` |
| `BENCHMARK_PRACTICAL_BASELINES.md` | current numbers (`61e18c3`) | Merge → `performance/BENCHMARKS.md` |
| `AWFY_COMPARISON.md` | current AWFY methodology | Merge → `performance/BENCHMARKS.md` §AWFY |
| `AWFY_STDLIB_AUDIT.md` | SOM stdlib audit | Research → `research/benchmarks/` |
| `OPENSMALLTALK_OIL_COMPARISON.md` | Oil verification record | Research → `research/benchmarks/`; fix missing evidence paths |
| `RICHARDS.md` | port provenance | Keep → `performance/` |
| `DELTABLUE.md` | port provenance | Keep → `performance/` |
| `PERFORMANCE.md` | workflow and priorities | Keep → `performance/` |
| `GTK.md` | GTK entry point | Keep → `gtk/` |
| `GTK_APPLICATIONS.md` | application protocol | Keep → `gtk/` |
| `GTKSOURCEVIEW.md` | highlighting | Keep → `gtk/` |
| `GTK_SUPPORT.md` | coverage audit + gaps | Merge gaps → `gtk/GTK.md`; archive → `research/gui/` |
| `BONA_ASSESSMENT.md` | assessment + hardening log | Merge current state → `gtk/BONA.md`; archive → `research/gui/` |
| `BONA_WEB_TODO.md` | Bona + MummyX walkthrough | Keep → `gtk/BONA.md` §live-editing walkthrough |
| `MUMMYX.md` | server integration | Keep → `web/` |
| `API_SERVER_TUTORIAL.md` | tutorial | Keep → `web/` |
| `REACTIVE_WEB_RENDERING.md` | current web direction | Merge → `web/HTML.md` |
| `HTML_CANVAS_STATUS.md` | DSL status snapshot | Merge current → `web/HTML.md`; archive |
| `NIL_AND_ABSENCE.md` | investigation + decision | Merge decision → `MANUAL.md` §nil; archive → `research/language/` |
| `NIM_2_4_EVALUATION.md` | toolchain evaluation | Research → `research/toolchain/` |
| `NIMONY_ASSESSMENT.md` | migration assessment | Research → `research/toolchain/` |

`docs/evidence/oil/` stays under `docs/research/benchmarks/evidence/` only if the
paths are updated in the Oil record; otherwise keep it at `docs/evidence/`. The
record's claims are what depend on it, so the move follows the record.

## Waves

Each wave is one commit that leaves links working.

**W1 — mechanical moves.** Create `docs/{compiler,gtk,web,performance,plans}` and
`docs/research/{compiler,benchmarks,language,planning,gui,web,toolchain}`. Move
the files classified Research and Plan. Rewrite links repo-wide for moved paths,
including `tests/test_oil_benchmarks.py` and the `docs/FIXES.md` comment in
`tests/test_smalltalk_alignment.nim`. Verify with `scripts/docgraph.py`: no new
broken links, no file referenced by a path that no longer exists.

**W2 — comparisons.** Write `COMPARISONS.md` from `LANGUAGE_COMPARISON.md`,
`HARDING_VS_SMALLTALK80.md` and `COLLECTION_PROTOCOL_AUDIT.md`: feature table,
distinctive design decisions, Smalltalk-80 gaps with status, collection protocol
delta, cross-engine notes (Cog, GNU Smalltalk). Archive the three sources.

**W3 — benchmarks.** Write `performance/BENCHMARKS.md`: current numbers, method,
reproduction commands, port provenance table, which older snapshots exist and why
they are not comparable.

**W4 — compiler.** Write `compiler/GRANITE.md`: what compiles today, engine
boundary, inference, declared slots, example coverage, known gaps; plus
`compiler/GRANITE_PERFORMANCE.md` indexing each slice with its measured result and
its rejected alternatives.

**W5 — IDE and web.** Write `gtk/BONA.md` from assessment + walkthrough, add the
gap table to `gtk/GTK.md`, write `web/HTML.md` from the two Html documents.

**W6 — index and hygiene.** Rewrite `docs/README.md` and
`docs/research/README.md` to the new tree; update `AGENTS.md` paths and section
text that names moved documents; fix remaining broken links; prune wording in
`QUICKREF.md`/`EXCEPTION_MODEL.md` that still describes the work as a branch
migration.

## Verification

- `python3 scripts/docgraph.py` — recursive; no broken links, and every archived
  document is reachable from `docs/research/README.md`.
- `grep -rn 'docs/' AGENTS.md README.md CONTRIBUTING.md tests scripts` — every
  hit resolves.
- Any test that reads a document (`tests/test_oil_benchmarks.py`) passes.
- Doc-only change: no build or test suite run required beyond the reference
  check, but state that explicitly in the commit message.
