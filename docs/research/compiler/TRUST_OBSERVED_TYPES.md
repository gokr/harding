# Opt-in observed slot contracts

Default compilation is unchanged: observations confirm or reject static numeric
candidates, but do not narrow undeclared storage. To explicitly specialize an
artifact to the types seen in a training run:

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
./harding --type-feedback build/profile.json benchmark/richards.hrd
./granite build benchmark/richards.hrd --dir:build/trained \
  --type-feedback:build/profile.json --trust-observed-types \
  --inference-report:build/trained/report.json
```

`--trust-observed-types` requires validated feedback and native compilation;
`--mixed` is refused. Source fingerprints must still match. Single observed
primitive write kinds (Integer, Float, Boolean, String, Symbol) become native
fields, including when static inference was inconclusive. Confirmed static
candidates with observations are eligible too. Explicit source declarations win.
Conflicting kinds, Integer/Float mixtures, nil writes and missing observations do
not become inferred contracts. Object/collection narrowing is not implemented.

## This deliberately changes the artifact's contract

This is not a semantics-preserving profile hint. A narrowed Integer slot has an
`int` field and the same checked setters as a declared Integer slot. Wrong-kind
or nil writes fail without overwriting the previous value. No deoptimization or
automatic recompilation is provided. Recollect feedback and recompile when the
input population changes.

Allocation also uses declared-type defaults (Integer zero, Float zero, Boolean
false, empty String/Symbol), **not nil**. Training's `initial:Nil` allocation tags
are not explicit nil writes. Consequently, reading before initialization can
answer differently in this mode; use the conservative default when that matters.
An explicit `nil` assignment in `initialize` is still a real write and excludes
the slot from narrowing.

In Richards, `currentId := nil` occurs in `RichardsScheduler>>initialize`; it is
not a loop sentinel. The schedule loop writes an identity before using it, but
that does not authorize dropping the initialization write. `currentId` therefore
remains dynamic. `control` and `count` receive Integer observations and can narrow.

## Scope and validation

The class model passed to code generation carries the chosen contracts rather
than rebuilding them away. Inherited layouts use the parent's narrowed fields.
Default compilation keeps the existing reflected-model path unchanged.

`tests/test_trusted_feedback.py` executes collection, default and opt-in code
generation, source-drift rejection, flag validation, native inherited layouts,
and checked setters under ARC and ORC. Existing feedback tests remain unchanged.
Focused suites pass under ARC/ORC: compiler basic 99, slot inference 32, slot
diagnostics 11, compiled runtime 43. This is not a full-suite claim.

No performance score is claimed yet. The initial hand-run timing omitted the
flag from its supposed aggressive variant and is invalid. Native parameters and
returns across call boundaries remain subsequent work; this flag establishes the
storage contract they can use.
