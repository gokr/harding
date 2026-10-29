# Granite design exploration: inferring slot types

Question raised: can Harding infer slot types rather than making the developer
declare them — including collecting types from a dynamic run and using them to
annotate slots automatically?

Constraint agreed: **Harding must not force the developer to declare slot types.**
Declaration may exist as an escape hatch, but inference must carry the workload.

This document records the measured feasibility of each approach, not a decision
to implement one. Nothing here is implemented.

## What we measured

A temporary probe recorded the runtime value kinds seen per `(class, slot)` on
every slot write in the interpreter. Working tree was restored afterwards; the
reproduction recipe is in `build/typefeedback/HOWTO.md`.

Single interpreter run per workload:

| Workload | Monomorphic slots | Polymorphic slots |
|---|---:|---:|
| Queens (all-solutions) | 3 | 0 |
| Richards | 28 | 0 |
| DeltaBlue | 33 | 1 |
| Synthetic mixed-type program | 4 | 3 |

The one DeltaBlue conflict is `DBVariable#value -> vkInt,vkFloat` — the exact
numeric case already handled by a documented tolerance in that port. The
synthetic program confirms the probe detects real polymorphism rather than always
answering "monomorphic": `balance` (Int/Float), `notes` (Array/String) and
`value` (Int/String) all reported as polymorphic.

So "95% of slots are monomorphic in practice" is supported by this evidence on
representative object-heavy code. That is the encouraging part.

## The hard constraint: AOT needs types at build time

Granite is an ahead-of-time compiler. A feedback profile can only influence a
**second** build. That is not a flaw in the idea — it is how every AOT
profile-guided system works — but it must be designed for, and it changes what
the developer experiences:

- The first build is always fully dynamic and cannot use feedback.
- Feedback must be collected from somewhere.
- The second build may apply it.

There is no way for a single AOT build to *discover* types it needs during
compilation. Any expectation of "just compile and it is typed" cannot be met.
The honest promise is "run it, then rebuild, and it is typed".

## Approaches compared

### 1. Static inference from the source (no profile)

Infer from what is written in the module: literal initialisers, consistent
assignment kinds, arithmetic usage, comparisons.

- Fits the AOT model exactly: no second build, deterministic, reproducible.
- Reuses machinery that already exists and works: `numericBindings`
  (`nrInt`/`nrFloat`/`nrBool`) already proves local arithmetic and compiles it to
  machine integers. Extending that pattern from locals to slots is the smallest
  real step.
- Conservative by necessity: any slot written from outside the module, or written
  two ways, stays dynamic.
- No developer burden at all, which matches the agreed constraint.

### 2. Static inference plus declaration escape hatch

Same as (1), but a hint is available where inference cannot conclude, for the
few genuinely ambiguous slots. `parseTypeHint`/`TypeConstraint`/`SlotDef.constraint`
already exist for this and are partly wired (the parser cannot yet read a hint —
`#(x: Int)` is a parse error in both engines today).

- Satisfies "must not force" if the hint stays optional.
- Useful for library boundaries, where the module cannot see the writes.
- Small incremental cost on top of (1).

### 3. Runtime feedback (what was proposed)

Run the dynamic program, record per-slot value kinds, emit a profile, rebuild.

- Captures what static analysis cannot: real workload behaviour across modules.
- **Coverage is the fundamental risk.** The profile only describes the paths that
  executed. A slot that was `Int` on the training run and receives a `Float` on a
  production run would silently hit a typed field. This requires either a
  guarded representation (costing most of the speedup) or a purity check.
- Where would collection hook in? Compiling *with* the probes yields an
  instrumented binary that must be built and run first — a three-step cycle
  (build instrumented → run → rebuild optimised).
- Alternatively the **interpreter** collects the profile, which needs no
  instrumented build at all: run under `harding`, record slot kinds, feed
  Granite. That is attractive because the interpreter already interprets the same
  source and we proved the probe works there. But the profile then reflects
  interpreter execution of the workloads the developer happened to run.
- Reproducibility: the build depends on a profile artifact, which must be
  versioned, invalidated when source changes, and kept out of the repository or
  treated as build input. This is the same class of problem already solved for
  the frozen-class receipt.

### 4. Speculative typing with runtime guards

Compile to typed fields but verify the kind on write/read, falling back to a
boxed path on mismatch.

- Correct under incomplete profiles, and needs no purity proof.
- The guard costs a comparison per access; the typed fast path still wins when
  it hits, but much of the benefit of unboxing is spent paying for the check.
- This is the pragmatic answer to coverage risk, and it composes with (1), (2)
  or (3) as the source of the initial guess.

### 5. Sealed / frozen classes

Classes already have a sealing concept for the native registry. For sealed
classes the layout cannot change at runtime, which makes typed inference sound
without guards.

- Strongest soundness story.
- Already partially present in the codebase.
- Only applies to the subset of classes that are sealed.

## Recommendation

Layer them, cheapest and most sound first:

1. **Static inference for slots (approach 1).** No developer burden, no second
   build, deterministic, and it reuses a pattern that already works for locals.
   This should be the default mechanism.
2. **Optional declaration (approach 2)** only as an escape hatch at boundaries.
   Never required.
3. **Runtime feedback (approach 3) as an optional accelerator**, sourced from the
   interpreter first because it needs no instrumented build, with the profile
   treated as a versioned build input and invalidated on source change.
4. **Guards (approach 4) for any typed slot whose purity is not proven**, so an
   unrepresentative profile degrades performance rather than correctness.

The key design rule regardless of source: **a typed slot must be provably
monomorphic, or guarded.** Inference that silently passes on a partial profile is
the one failure mode that would be worse than staying dynamic.

Note the measured ceiling from the typed-members design: removing slot lookup and
hashing entirely is worth roughly 5–8% on these benchmarks, and `nt_plus` is
already ~0%. Inference is worth doing because it *unblocks* unboxed fields and
cheaper allocation — not because slot access itself is the bottleneck. That
expectation should stay honest while this is scoped.


## Nil incidence, and the language-design question

Question raised: would changing Harding to reduce `nil` make native compilation
easier — e.g. requiring explicit default values for slots, or requiring
temporaries to be assigned before use?

A second probe counted per-slot nil versus non-nil writes over interpreter runs
(recipe in `build/typefeedback/NIL_HOWTO.md`).

| Workload | Slots never written nil | Slots written nil at least once |
|---|---:|---:|
| Towers (13 disks) | 5 | 2 |
| Richards | 17 | 14 |
| DeltaBlue | 21 | 16 |

No slot was nil-only. Typical nil-carrying slots are exactly the ones you would
expect: `Packet#link`, `TaskControlBlock#queue`, `Tower#heldDisk`,
`DBVariable`-style graph references and `planner` back-pointers.

**Methodological note worth keeping:** an initial version of this probe tested
`value.kind == vkNil` and reported *zero* nil writes for every workload,
including Towers, which plainly assigns `heldLink := nil`. Harding represents
nil both as `vkNil` and as a singleton `nilInstance` whose kind is `vkInstance`,
so the vkNil-only test silently missed most nil writes. The corrected probe uses
`isNilValue()`. Any future analysis of nil must do the same — and the fact that
two representations exist is itself evidence for the language point below.

### What this means for typing

Roughly **45–60% of slots in these programs are legitimately nil-bearing.**
So nil is not an edge case to be typed away; it is structural in linked
structures and back-pointers. Concretely:

- Requiring explicit non-nil defaults for every slot would force sentinel objects
  (`NoPacket`) into `link`/`queue` fields that are *designed* to be nil, or force
  `Option[...]` wrappers everywhere. Both cost performance on exactly the hot
  paths (linked traversal) that matter.
- A slot that legitimately holds `nil` or an instance cannot become a bare
  `ref T` without either a sentinel or nil being permitted — so `ref T` (which is
  nilable in Nim) is actually a fine native representation for object slots. The
  difficult case is *primitive* slots (`int`, `float64`), which cannot hold nil.
- Consequently the valuable split is not "eliminate nil" but **"distinguish
  primitive slots from reference slots"**: references map to `ref T` (nil-capable,
  already native), primitives map to `int`/`float64` only when proven never nil.

### On the two language changes proposed

**Requiring explicit default values for slot declarations** — the measurement
argues against mandating it. It would push sentinels into structurally-nilable
fields. It could be offered as an opt-in for classes that want typed primitives,
but the default-value requirement would not pay for itself.

**Requiring temporaries to be assigned before use** — this is a much better fit
and is largely orthogonal to nil. It is a *definiteness* rule, already the kind
of analysis `analyzeNumericBindings` performs for numeric locals (it rejects
reads before definite initialisation). It would:
- catch real bugs (use of uninitialised temporaries) — a genuine language win;
- let native locals be ordinary Nim `var` without a nil sentinel;
- cost nothing at runtime.

Caveat: it is a **source-compatibility break** for existing `.hrd` code, so it
needs either a deprecation cycle or a strictness mode. Worth prototyping as a
warning first and measuring how much existing code (stdlib, external libs,
Bona, examples) would violate it.

### Recommendation

Do not attempt to eliminate nil. Instead:
1. Classify each slot as **primitive or reference**. References become `ref T`
   and are already native and nil-honest.
2. Only promote a primitive slot to `int`/`float64` when the evidence shows it is
   never nil; otherwise keep `NodeValue`.
3. Treat the "temporaries must be assigned before use" rule as a separate,
   well-motivated language improvement — prototype as a warning, measure the
   fallout across existing code, then decide.


## Assessing the "eliminate nil entirely" proposal

A design discussion proposed removing nil altogether: an integer slot starts at
`0`, a string slot at `""`, an array slot at the empty array, and so on, so that
no slot ever holds nil. Two premises in that discussion are **not true of
Harding as implemented**, and correcting them changes the conclusion.

### Verified corrections

| Claim | Actual behaviour (verified) |
|---|---|
| "an uninitialized array slot defaults to `#()` rather than nil" | **False.** Uninitialized slots are nil: `C new` then `items isNil`, `name isNil`, `count isNil` all answer `true`. |
| "Array is treated as a value-like container; assignment copies a zero-length sequence header" | **False.** Harding Arrays are shared references: `b := a. b at: 0 put: 99` also changes `a`. Not Nim `seq` value semantics. |

What *is* true, and useful:

- An empty array responds to `do:` and iterates zero times without error, while
  `nil do:` raises `MessageNotUnderstood`. So "empty object over nil" does remove
  that whole class of failure.
- `#()` allocates a **fresh** array each time (identity is false, and mutating one
  does not affect another), so using `#()` as a slot default is implementable
  rather than dangerously aliasing one shared singleton. It does, however, mean
  one allocation per slot per instance.

### The decisive technical point: nil in a compiled ref is free

The performance premise behind eliminating nil does not hold for typed references.
A Nim `ref T` is a pointer; `nil` is the zero pointer. There is no `Option`
wrapper, no tag, no branch, and no boxing to test for it. So:

- **Object slot as `ref T`**: nil-capable, zero cost. Nothing to eliminate.
- **Primitive slot as `int`**: cannot be nil, and gets native arithmetic.
- **Today's `NodeValue`**: a tagged union — *this* is what costs, not nilability.

Eliminating nil therefore does **not** buy performance. Typing the slot buys
performance; nil in a typed ref is already free. This is why the object/primitive
split is the right model and full nil removal is not required for speed.

### The correctness argument against Null Object everywhere

For primitive slots, "no nil, start at 0/""" is plausible and maps directly to
Nim. For **object** slots it requires every class to nominate a neutral instance
(the Null Object pattern, enforced globally). That has a specific failure mode:

- `nil` fails **loudly** — `MessageNotUnderstood` at the point of use.
- A neutral instance fails **silently** — it answers messages, so a sentinel
  `Packet` propagates through traversal and yields a wrong answer rather than an
  exception.

Applying that to `Packet#link`, `Tower#heldDisk` or `DBVariable#planner` — the
14–16 nil-bearing slots per benchmark measured earlier — would trade a loud,
located failure for a silent, distant one. That is a worse trade than the billion
dollar mistake it aims to fix.

### Where the discussion's better ideas do apply

Two of its suggestions do not depend on removing nil and are worth keeping:

1. **Strict initialisation for temporaries.** Requiring a temporary to be assigned
   before use is a definiteness rule, orthogonal to nil, which catches real bugs
   and lets native locals be plain Nim `var`. Recommended as a separate
   prototype (warning first, since it is a source-compatibility break).
2. **Prefer explicit-fallback protocols** (`at:ifAbsent:`, `detect:ifNone:`) over
   nil-returning forms in new library code. Note this is barely exercised today:
   `ifNil:` appears 4 times and `ifNotNil:` 3 times across `lib/` and
   `benchmark/`, and `detect:ifNone:`/`at:ifAbsent:` zero times — so there is
   little legacy pressure either way, and no measurement yet showing these forms
   matter for performance.

### Conclusion

Adopt the **object slot vs primitive slot** distinction:

| Slot kind | Representation | nil | Proof needed |
|---|---|---|---|
| Object | `ref T` (T = widest static class) | native, free | no |
| Primitive | `int` / `float64` / `bool` / `string` | impossible | yes, or guarded |
| Mixed / uncertain | `NodeValue` | yes | no |

Do **not** eliminate nil. It buys no performance over a typed ref, and a global
Null Object convention would convert loud failures into silent ones. Keep strict
initialisation for temporaries as an independent proposal.

## Open questions for you

1. Is a two-step "run, then rebuild with feedback" workflow acceptable, or must
   a single build stand alone? This decides whether (3) is in scope at all.
2. Should feedback come from the interpreter, an instrumented binary, or both?
3. For uncovered slots: guards (safe, some cost) or stay dynamic (no cost, no
   gain)?
4. Where should a profile file live and how should it be invalidated — follow the
   existing frozen-receipt pattern?
