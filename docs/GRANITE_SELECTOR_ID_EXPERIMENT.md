# Rejected: per-site selector ids and class density ids

## What was tried

`resolveCompiledMethod` hashed two strings on every resolution — the class name and
the selector — through `internDispatchName` + `getOrDefault`. Both are avoidable:

- The receiver class is a live `Class` object, so a lazily assigned `dispatchId`
  field removes the class-name hash.
- The selector is a compile-time constant at each generated call site, so a
  `dispatchSelectorId(selector)` template assigning a `{.global, threadvar.}` id
  per expanded site removes the selector hash, hashing once per site instead.

Both were implemented, correct, and passed all gates:
`test_compiler_basic` 99, `test_compiled_runtime` 43, `test_engine_boundary` 36,
`test_compiled_support` 11 — ARC and ORC, zero failures. Queens still printed 92.

## Measured effect: none

Same-core paired trials, `build/granite-profiles/run-2bmhoact` →
`run-1db6m0mb`:

| Workload | Ratio |
|---|---:|
| Richards | 1.007x |
| DeltaBlue | 0.989x |
| Queens | 0.999x |

Counts per verified pass, before → after:

| Workload | `getOrDefault` | `hash` |
|---|---:|---:|
| Richards | 49,996 → 29 | 93,421 → 43,501 |
| DeltaBlue | 139,425 → 47,968 | 452,237 → 456,699 |
| Queens | 207,171 → 2,057 | 211,290 → 10,289 |

The hashing is gone — Queens' `getOrDefault` fell by two orders of magnitude — and
nothing measurable changed.

## Why it was reverted

Two reasons, in this order.

1. **No payoff.** The theory was that ~11% of Queens' samples were resolution
   hashing. The call counts confirmed the work existed and the change removed it,
   and wall time did not move. So `hash`/`getOrDefault` were attributed to
   `resolveCompiledMethod` by the call graph but are not where the samples are.
   The instrumented profile misled us about their cost; only the paired timing
   settles it.

2. **It added real complexity and risk for nothing.** A `Class.dispatchId` field
   assigned lazily from a global counter, a second id space threaded through
   `CompiledSendCache`, and a per-site `{.global, threadvar.}` in generated code
   that is only correct because the interner clears the resolution cache before
   recycling ids. Every one of those is a place a future change can produce a
   wrong-method dispatch. That is a bad trade against 0%.

## What this teaches

Before this slice, two of the changes in this session that *did* pay off
(operand bindings, per-site cache) were found by reading generated code and by
diffing call counts *against wall time*. The two that did not (the
`compiledInstanceSelectors` gate, and this) were both cases of trusting a
profile's self-time attribution after the profile had already been perturbed by
gprof instrumentation.

Rule for the next slice: a call-count reduction is only evidence if paired wall
time moves with it. Otherwise revert, however clean the mechanism.

## Where the remaining time actually is

From the same profile used here, Queens spends 29% in `canPlaceRow` itself (the
algorithm), 9% in `sendMessageCached`, and 3.8% each in `eqdestroy`, `nimSetMem`
and `rawAlloc`. `nt_pipe` and `nt_eq` are 3.8% each. That points at argument
sequences and `NodeValue` traffic on ordinary sends — the cached small-arity ABI —
rather than at resolution, and specifically it predicts Richards will not improve,
since its hot path is object dispatch and allocation.
