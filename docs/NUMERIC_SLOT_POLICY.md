# Numeric slot decisions in Granite

## Policy

The interpreter stays permissive: dynamic storage and Float slots accepting
Integer writes keep working, which is what makes exploratory Smalltalk pleasant.

A production build should make a decision instead. Granite therefore reports
provable numeric contradictions:

| Situation | Normal build | `--strict-slots` |
|---|---|---|
| Integer stored into a declared Float slot | warning | error |
| Float stored into a declared Integer slot | error | error |
| Anything not provable from literals/arithmetic | silent | silent |

Runtime behaviour is unchanged: a Float slot still converts Integer writes, and an
Integer slot still rejects Float with a catchable `Error`. Diagnostics are
compile-time only.

Only provable cases are reported. A warning on every arithmetic expression would
train developers to ignore the output, so a value whose numeric kind cannot be
determined from the source is deliberately not diagnosed.

## Why warning on Integer into Float

`2.5` can represent an Integer exactly only up to 2^53. A slot declared `Float`
that receives large integer identifiers silently loses precision:

```harding
Counter := Object derivePublic: #{#total -> Float}.
Counter>>add: n [ total := total + n. ^self ].   # Integer n, warned
```

The warning says so, rather than the compiler quietly choosing a representation
on the developer's behalf.

## Inference no longer widens silently

`docs/TYPE_INFERENCE_FEEDBACK.md` previously proposed Float when observations saw
both Integer and Float. That is now reported as `numeric-conflict` with the
recommendation to declare Float or Integer, because widening is exactly the
decision the developer should make consciously.

## Does any of this generate faster code?

**No.** Measured, not assumed:

```
queens:   generated Nim IDENTICAL with/without inference report
richards: generated Nim IDENTICAL with/without inference report
deltablue: generated Nim IDENTICAL with/without inference report
```

Inference and feedback currently produce a *report*. They emit no storage change,
no guard, and no specialization. That is deliberate for this stage, but it means
the answer to "does inference make Granite faster" is currently **no**.

What does produce native code today is the *declared* path from
`GRANITE_DIRECT_SLOTS.md`, and only for classes that author declarations
themselves. Note that **none of the benchmarks declare slot types**, so measured
benchmark times do not include any typed-slot benefit:

| Measurement | Before | After | Note |
|---|---:|---:|---|
| Declared-Integer counter, 500k increments | 110.2 ms | 38.2 ms | annotated microbenchmark |
| Richards, 20 runs, no declarations | 1097.2 ms | 879.4 ms | benefit is direct access, not typing |

Current release-ARC reference times for the unmodified benchmarks (single build,
5 runs, median): Queens 131.6 ms, Richards 20 runs 884.4 ms, DeltaBlue 30 runs
1591.6 ms. These are context, not an optimization claim — they are the same
generated code as before this change.

## What would actually make inference pay

1. Emit guarded native specializations for slots the report marks
   `static+observations`, keeping the dynamic path as fallback.
2. Re-measure against retained baselines with the existing paired harness.
3. Consider `Array`/`ByteArray` native element storage, which removes a
   `NodeValue` per element rather than per slot access.

Until step 1 exists, inference is a map. It tells a developer which declarations
are worth adding, and adding them is what unlocks the typed codegen path.
