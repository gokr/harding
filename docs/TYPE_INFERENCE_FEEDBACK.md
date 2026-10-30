# Type inference and interpreter feedback

Status: implemented as **advisory evidence**. Nothing here narrows storage,
rewrites source, or changes a program's answer.

## Static candidates

`src/harding/compiler/slot_inference.nim` combines three sources of evidence
within the analyzed module:

1. literal and `Class new` writes;
2. call-site arguments propagated into method parameters;
3. return values of `self`/`super` sends propagated into further expressions.

The fixed point runs a bounded number of iterations. An *unknown* operand does
not poison a parameter that another call site proves — otherwise nothing would
ever converge — while a known but differently-typed write does poison it.

Measured candidates from module analysis alone:

| Benchmark | Static candidates | Non-dynamic |
|---|---:|---:|
| Queens | 3 | 2 (`row`, `column` as Integer) |
| Towers | 4 | 2 |
| Richards | 29 | 10 |
| DeltaBlue | 45 | 11 |

Before parameter propagation these benchmarks produced zero usable candidates,
because real initialisers assign parameters rather than literals.

## Interpreter feedback

```sh
# Collect while running interpreted tests or a script.
./harding --type-feedback build/profile.json benchmark/deltablue.hrd

# Merge into an advisory report during compilation.
./granite compile app.hrd --dir:build/app \
    --type-feedback:build/profile.json --inference-report:build/app/report.json
```

Collection is opt-in and per-thread. The hook observes successful slot writes
(`initial`, `write`) and reads, recording only the language type name — no values,
no receivers, no call stacks. Rejected writes are never counted, and `nil` is
recorded as one type even though the runtime has two representations.

The profile is a single JSON document containing:

- a schema version and an explicit `valid` flag;
- a SHA-1 fingerprint of **every** evaluated source, including files reached
  through `Harding load:` and library loads;
- per-slot observation counts keyed `event:Type`, with concrete class names for
  object values (e.g. `write:Object:DBCollection`).

Writing is atomic. A failed run publishes nothing and removes any previous
profile, so a stale success file cannot survive an error. A source that changes
during a run marks the session invalid.

`granite` rejects a profile that is malformed, unvalidated (`valid: false`),
missing the input file, or stale against any recorded source. Stale feedback is
never partially applied.

## Reconciling the two

`inferenceReport` keeps both facts and names its evidence per slot:

| Field | Meaning |
|---|---|
| `staticCandidate` | what module analysis concluded, unchanged |
| `observations` | raw interpreter counts for that slot |
| `effectiveCandidate` | merged proposal |
| `evidence` | `static`, `static+observations`, `observations`, or `observed-proposal` |
| `effectiveReason` | why a candidate was rejected |
| `requiresGuard` | always true |
| `storageNarrowed` | always false |

Rules, in order:

- **Integer and Float observed together widen to Float**, because a Float slot
  already accepts Integer by conversion;
- nil observed at runtime rejects a non-dynamic static candidate;
- any other observed write kind that disagrees with the candidate rejects it
  (`contradicted by observations`);
- agreement is recorded as `static+observations`;
- a dynamic slot is **never** narrowed by observations alone; a single observed
  write kind is only a labelled `observed-proposal`;
- several observed kinds leave a dynamic slot dynamic.

### Numeric widening

A slot initialised to `0` and later written `2.5` is common and is not a bug in
the program; the declaration was simply too narrow. Smalltalk's numeric tower
resolves `5 + 2.5` to a Float, and our own contract already lets a Float slot
accept Integer writes. So instead of discarding such a slot as dynamic, the
report proposes **Float**:

> `Integer and Float observed; Float accepts Integer`

DeltaBlue's `DBVariable#value` is exactly this: module analysis says `skInt`,
runtime observation shows **12,932 Integer and 33 Float writes**, and the merged
report now says `skFloat` (`numeric-widening`) instead of losing the slot.

Precision caveat: a `float64` cannot represent every 64-bit Integer exactly
(beyond 2^53). Widening is safe under the type contract but is still a storage
change, which is why it is a *proposal* and not applied to untyped slots
automatically.

### Why this matters, measured

A static-only or profile-only design would have shipped `DBVariable#value` as an
Integer slot and changed the program's answers. Reconciliation caught that,
rejected the candidate, and now proposes the type that actually fits. On the same
benchmark, 10 slots are confirmed by both sources, 12 remain labelled proposals,
and one is a numeric widening.

## What is deliberately not done

- No storage is typed from inference; declared slots still require the explicit
  table form in `DECLARED_SLOTS.md`.
- No source file is rewritten with inferred declarations.
- Coverage is incomplete by construction: a profile describes the paths that ran.
- Cross-module calls, dynamic `perform:`, runtime method replacement and unknown
  receivers all remain unproven.

## Testing

`nimble testTypeFeedback` builds both engines and runs core collection/rejection
tests plus both-engine language tests under ARC and ORC. The language test asserts
that enabling collection leaves program output unchanged and that the generated
Nim is byte-identical with and without a merged report.

## Possible next steps

Only after the report shows enough confirmed candidates: emit guarded native
specializations for `static+observations` slots, measure against retained
baselines, and keep the dynamic path as the fallback. Until guards exist in
generated code, the report is a map, not an optimization.

A related language question is open, not decided: whether an explicitly declared
`Integer` slot that later holds a Float should signal an error (current approved
contract), or should widen itself to Float. The current answer keeps enforcement
strict because a silent type change is harder to debug than a rejection, while
the report steers authors toward declaring `Float` (or `0.0`) in the first place.
Changing the enforcement rule would be a language-semantics decision.
