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

## Open questions for you

1. Is a two-step "run, then rebuild with feedback" workflow acceptable, or must
   a single build stand alone? This decides whether (3) is in scope at all.
2. Should feedback come from the interpreter, an instrumented binary, or both?
3. For uncovered slots: guards (safe, some cost) or stay dynamic (no cost, no
   gain)?
4. Where should a profile file live and how should it be invalidated — follow the
   existing frozen-receipt pattern?
