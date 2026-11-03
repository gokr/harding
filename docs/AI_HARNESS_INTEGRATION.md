# Harding and AI coding harnesses

## Scope and status

This note records what Harding currently offers an LLM or an AI coding harness,
what it is structurally good at, and where the gaps are. It is a **capability
review**, not a design commitment, and it is not a claim that the authoring story
is finished.

Findings were checked against `main` at `5ff020b` with a locally built
`./harding`. Claims that rest on source reading name the file. As with
`LANGUAGE_COMPARISON.md`, the probes were ad hoc rather than a test suite, and
several should become tests.

Two related documents cover adjacent ground and are not duplicated here:
`BONA_ASSESSMENT.md` audits the IDE (including the state of BonaMCP) and
`LANGUAGE_COMPARISON.md` covers the language-design view.

## Summary

Harding's advantage for agents is **structural, not syntactic**: a program is a
set of named, independently replaceable method units, and the same source has two
independent engines that can be diffed. That combination gives an agent a precise
edit surface and a semantic self-check.

The thesis below is assembly. No individual item is unique to Harding; the
combination -- Smalltalk semantics, one source, two engines, unit-level editing --
is unusual.

## What exists today, verified

### Structured, isolated evaluation

`Object evaluate:` answers a table rather than raising:

```harding
Object evaluate: "3 + 4"   # => #{"ok" -> true, "value" -> 7, "error" -> ""}
Object evaluate: "1 / 0"   # => ok = false, error = "Runtime error: DivisionByZero: ..."
Object evaluate: "x := "    # => ok = false, error = "Parse error at line 1, col 6: ..."
```

`evaluateIsolated` (`src/harding/interpreter/vm.nim:391`) runs the evaluation with
its own VM stacks while sharing globals, source index and scheduler ownership, and
sets `suppressUncaughtExit`. Consequence, verified: after a failing evaluation the
session remains usable and later evaluations still succeed. A bad expression
therefore does not wedge the process.

Error strings carry a class and a position for parse failures
(`Parse error at line 1, col 6: ...`) and a signal name for runtime failures.
They are strings, not structured frames -- see *Gaps*.

### Validation without execution

`src/harding/interpreter/source_editor.nim` validates a replacement definition
through the real parser **without evaluating it**, then writes atomically, and the
language exposes it as
`Harding editSourceFile:owner:selector:replacement:delete:`. This is the primitive
that makes unit-level editing safe rather than blind patching.

### A callable compiler

`Granite class>>compile: sourceString` (`lib/granite/Granite.hrd`) returns
generated Nim source as a string. Combined with the interpreter, this is the basis
of the differential oracle described below.

### Reflection, partially

Working: `class`, `className`, `name`, `superclassNames`, `isKindOf:`,
`respondsTo:`, `perform:`/`perform:with:`, runtime `removeMethod:`, and runtime
class redefinition (verified: existing instances keep their layout, new instances
get the new one).

Not working: `methods`, `allSlotNames`, `allInstances`. A harness therefore cannot
enumerate a class's surface from inside the language.

### MCP: present, but not yet usable end to end

Two separate paths exist, and neither is a working agent entry point today.

- `src/harding/web/mcp_bridge.nim` -- a built-in bridge over MummyX, imported by
  `vm.nim`. `tests/test_mcp_bridge.nim` has 15 tests, but three of them are
  explicit `skip()` placeholders for integration, and the HTTP path is untested.
- `lib/gui/bona/BonaMCP.hrd` -- the NimCP-backed server, registering eight tools
  (`bona_ping`, `bona_eval`, `bona_transcript_tail`, `bona_list_libraries`,
  `bona_list_classes`, `bona_list_methods`, `bona_get_method_source`,
  `bona_load_file`). The tool surface is written and is a good sketch of what an
  agent needs.

  **It does not start.** The worker bridge still embeds `"NimCP tool error: " ,
  ex printString` (`external/nimcp/src/nimcp/harding_integration.nim:160`). That
  is comma concatenation, which Harding removed in favour of `&`, so the worker
  source fails to parse. This is the defect recorded in `BONA_ASSESSMENT.md` and
  is unchanged at this revision.

So: the *shape* of an agent tool surface exists and is worth building on, but the
authoring story is not deliverable today. Treat everything under *What I would
build* as work, not inventory.

## The three structural advantages

### 1. Unit-level editing instead of text patching

LLMs are weakest at exactly what Python, Go and Rust demand: emitting a valid
textual diff with correct indentation and no collateral edits. Harding's
one-method-per-unit model maps onto tool calls without ambiguity:

```
get method source        -> exact text of Class>>selector
replace method           -> parser-validated, atomically written
```

The agent never supplies a line range or a context window, which removes the
"wrong hunk", "dropped brace" and "reformatted neighbours" failure modes by
construction. Where a harness does need to write whole files, the same validator
applies before anything reaches disk.

### 2. Two engines as a differential oracle

The same source runs on the interpreter and compiles through Granite. Comparing
the two answers is a semantic check that requires no test to be written:

```
verify(source) -> {same: bool, interpreted: ..., compiled: ..., diff: ...}
```

`scripts/test_granite_parity.py` already does exactly this for 105 cases, and the
example audit does it for 81 programs. Exposing the same mechanism as a tool turns
an existing harness into an agent primitive, so an agent can answer "did my
refactor change behaviour?" by construction rather than by guesswork.

**Caveat.** The oracle is only as good as parity coverage. Two of 81 example
programs already fail to run natively (`examples/language/multiple_inheritance.hrd`
and `examples/compiler/harding_main.hrd`, both pre-existing at this revision). A
`verify` tool must distinguish "the engines disagree" from "Granite does not
support this yet", or it will emit false failures and the agent will learn to
ignore it.

### 3. The image is a disposable workspace

Live class redefinition plus isolated evaluation means an agent can define a
scratch class, exercise it, redefine it, and discard it, in-process, without
touching the filesystem. Combined with `respondsTo:` this supports exploratory
work that would otherwise need throwaway files.

## Why source, not AST

A natural proposal is to have the model emit an AST: "the parser adds nothing, so
skip it". Measured on this implementation, that is a net loss.

**The parser adds little.** Harding has 17 node kinds and 2,544 lines of
lexer+parser. Two of the node kinds (`nkIf`, `nkWhile`) are produced by the parser
from `ifTrue:`/`whileTrue:` sugar, which is to say the AST is source-shaped rather
than a canonical core.

**Wrong indices are not caught, and one class of them is silent.** Corrupting a
correctly parsed method to simulate model-invented indices:

- `localIndex` 2 -> 999: still answers correctly. `resolveLocalIndices`
  (`src/harding/core/types.nim:636`) falls back to name-based lookup.
- slot index 0 -> 1 in `K>>read [ ^ v ]`: **silently answers `9`**, the value of
  the next slot. No error, no diagnostic.

For locals the information is recoverable, so the AST carries no advantage. For
slots the AST is strictly *more* dangerous than source, because `^ v` cannot be
misread as `w` whereas `slotIndex: 1` compiles and lies.

**It costs an order of magnitude more tokens.**

| Representation | Chars | ~Tokens |
|---|---:|---:|
| Source: `Array>>includes: element [...]` | 155 | ~38 |
| Equivalent JSON AST | 1,498 | ~374 |

About 9.7x. A real `--ast` dump shows the same direction: 59 bytes of source
becomes 301 bytes of debug output. Less familiar syntax costs *more* tokens,
because a JSON AST reifies every node kind explicitly.

**The infrastructure is absent.** There is no AST JSON codec, no AST-to-source
printer (so no round-trip), no builder API, the `--ast` printer elides method
bodies (`Literal(<block>)`), and `executeMethod` is not exported.

**AST also skips parser-stage rewrites** that a model emitting raw AST would
bypass, notably `rewriteNodeForSlotAccess`, which resolves slot references against
the defining class at method-install time -- globally when `self` is global,
lexically when a local shadows the slot.

Where structure does pay: **querying**, not generating. "Which methods send
`foo:`?" or "does this class assign a slot it does not declare?" is far easier
over a typed AST than over text, and needs no model output.

If model-generated AST is ever wanted, the safe design is the inverse of raw AST:
a **name-based builder** in which the host, not the model, resolves locals and
slots. But given the token cost and the silent-slot-index hazard, source plus
honest tooling is the better trade.

## Why Harding is comparatively easy to author

The small grammar matters less than the structure:

- **One method, one unit.** Edit by `Class>>selector`, validated and written
  atomically. No line ranges or brace matching.
- **No precedence table to mislearn.** Binary is strictly left-to-right:
  `2 + 3 * 4` is `20`, not `14`. One genuine trap: keyword messages bind *loosest*,
  so `2 * 3 max: 4` is `6` while `2 * (3 max: 4)` is `8`. This differs from
  Smalltalk-80 and is undocumented; an agent will get it wrong.
- **Consequences do the semantic work.** `ifTrue:`, `whileTrue:`, `do:` are
  ordinary sends, so a wrong selector yields `MessageNotUnderstood` rather than a
  mis-parse.

## Gaps, in the order they hurt

1. **No semantic feedback while editing.** The LSP server is a stub: hover returns
   the raw source line, completion is a hardcoded list of 29 selectors,
   `referencesProvider` and `renameProvider` are `false`, and there is no
   `publishDiagnostics` at all. An agent editing `.hrd` gets *less* feedback than
   for Python. Most of the necessary inputs already exist (source index, slot
   contracts, parser diagnostics) and simply are not exposed.
2. **Evaluation is not cancellable.** Recorded as an open item in `AGENTS.md`. A
   runaway loop wedges the session, which is disqualifying for unattended use.
3. **Errors are strings.** No codes, spans or structured frames; stack traces are
   text on stderr.
4. **Reflection cannot enumerate a class.** No `methods`, no `allSlotNames`.
5. **`--ast` is a debug dump,** not machine-consumable JSON, and it elides method
   bodies.
6. **No host-level linting.** Runtime misuse of slots is silent (see the slot-index
   finding above); a checked builder or a static pass would surface it.
7. **MCP is not runnable** (see above).

## What I would build

Ordered by value per unit of work, all of it unstarted unless noted.

1. **Expose the existing structural-edit surface headlessly.** `get`/`set` method
   source over a plain protocol, reusing `source_editor.nim`. The validation and
   atomic write already exist; this is plumbing. Today it is GUI-only.
2. **Make the LSP real.** Hover from the definition plus slot contract,
   completion from actual method tables, diagnostics from the parser and
   `scope_validation.nim`. Every AI harness speaks LSP, so this is the highest
   leverage item.
3. **The parity oracle as a tool** (`verify(source)`), needing only
   `Object evaluate:` plus `Granite compile:` that already exist, and a clear
   "unsupported" outcome distinct from "disagrees".
4. **Cancellable `evaluate:`** -- the pre-existing open item.
5. **Class signatures for context budgeting**, e.g. `Class>>signatureSummary`, so
   an agent can survey a 200-method class without ingesting the bodies.
6. **Record and replay an evaluation session**, turning an agent's exploration into
   a reproducible regression case for free.
7. **Fix BonaMCP startup** (one-line syntax correction plus the ownership work
   `BONA_ASSESSMENT.md` already specifies) if the MCP route is wanted.

## Risks

- **Training data.** Harding is effectively absent from model corpora, so raw code
  generation will be weaker than for Python. The structural tools compensate,
  because they move work from the model to the host; but expect an agent to be
  productive fastest via get/edit/verify rather than by writing large files blind.
- **Documentation is the agent's only source of truth.** The `<<` mutation
  divergence and the missing `identityHash` behind `Comparable` (both recorded in
  `LANGUAGE_COMPARISON.md`) are exactly the kind of thing an agent will discover
  the hard way and then mistrust.
- **Silent wrong answers are worse than errors.** The slot-index result above is
  the canonical example: a harness must not let an agent emit anything that can
  address a field it did not mean to address.

## Revisit checklist

- Confirm the revision: `git log --oneline -1` (this reflects `5ff020b`).
- Re-verify the MCP claim before repeating it:
  `grep -n 'NimCP tool error' external/nimcp/src/nimcp/harding_integration.nim`
  should show `&` rather than `,` once fixed.
- Re-check the LSP: `grep -n 'publishDiagnostics' src/harding/lsp/server.nim`
  (absent at this revision) and the hover body in `handleTextDocumentHover`.
- Re-measure the token ratio with `build/`-style probe scripts if the AST story is
  revisited; the 9.7x figure came from a hand-written JSON encoding and a tuned
  positional encoding would narrow it.
- Re-run the parity suite for the oracle caveat: two pre-existing native failures
  are expected at `5ff020b`.
