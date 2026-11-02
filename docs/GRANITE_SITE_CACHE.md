# Per-site send cache in method bodies

## Change

Codegen already had a per-site cache (`cachedSend` → `sendMessageCached`, a
`{.global, threadvar.}` `CompiledSendCache` per expanded send site), but it was
only emitted for **top-level script code**. Every send inside a compiled *method*
took the generic `sendMessageBound` path — and in the benchmarks, essentially all
hot sends are method bodies: the generated Richards had 88 `sendMessageBound`
sites and zero cache sites.

Two changes:

1. Method bodies now emit `cachedSendBound(owner, receiver, selector, args)`. Its
   helper keeps the owner-based host routing (`hostedBuiltin`) for VM-owned
   receivers when an interpreter is bound, then defers to `sendMessageCached`.
   With no bound classes it is a single length check, inlined away.

2. `sendMessageCached` now also caches **negative** results. Before, a miss
   resolved the pair, found nothing, and fell through to `sendMessage`, which
   resolved the *same* pair a second time. Polymorphic sites (one site, many
   receiver classes) hit that path constantly.

To make (2) possible without duplicating 460 lines, the builtin selector chain
moved out of `sendMessage` into `dispatchBuiltin(runtime, receiver, selector,
args, receiverClassName)`. `sendMessage` still computes `receiverClassName` and
resolves compiled methods first, then calls `dispatchBuiltin`; `sendMessageCached`
calls `dispatchBuiltin` directly on a cached negative. Behaviour is unchanged in
both paths — the chain body was moved verbatim.

## Measured effect

Same-core (CPU 2) paired trials, `build/granite-profiles/run-tfz09epn` (runtime
`f8e2f2a`) → `run-inkadz7s`, 30 verified passes per process, twelve measured
alternating trials after one warm-up:

| Workload | Trial 1 | Trial 2 |
|---|---:|---:|
| Richards | **1.154x** | **1.173x** |
| DeltaBlue | **1.190x** | **1.190x** |
| Queens | 0.990x | 0.995x |

Counts per verified pass, before → after:

| Workload | `resolveCompiledMethod` | `hash` | `rawAlloc` |
|---|---:|---:|---:|
| Richards | 63,678 → 24,997 | 298,092 → 93,421 | 301,812 → 206,598 |
| DeltaBlue | 106,325 → 69,711 | 650,554 → 452,237 | 447,225 → 262,570 |
| Queens | 103,586 → 103,585 | 414,350 → 211,290 | 244,797 → 224,963 |

Queens is neutral: its sites are polymorphic, so each site caches one class and
misses on the other rows. It still halves string hashing (414k -> 211k) but the
miss path now falls back to `sendMessage`, which re-resolves.

### What a negative answer may not skip

The first version of this change dispatched straight to `dispatchBuiltin` on any
cached negative. Two parity cases caught that this is wrong: `sendMessage` runs
ordered steps *before* its builtin chain, and both are answerable without a
compiled method.

- `perform:` / `perform:with:` / `perform:with:with:` convey a selector taken
  from an argument; skipping straight to the chain lost the conveyance.
- The exception protocol answers `message`, `message:`, `signal`, `retry`,
  `pass`, `defaultAction` and `printString` for exception instances.

A negative is now cached and dispatched only for selectors in
`negativeCacheSafeSelectors`, which excludes those families. Everything else falls
through to the generic path and re-resolves — correct, and the reason Queens does
not improve. Widening that list needs evidence that a selector truly has no
pre-chain step.

An earlier intermediate version — per-site cache but *without* negative caching —
was measured and regressed Queens (0.892x, then 0.977x) because the miss path
resolved twice. The negative gate is therefore needed just to reach neutral on
polymorphic workloads; the gain comes from Richards and DeltaBlue.

## Validation

ARC and ORC, zero failures: `test_compiler_basic` 88, `test_compiled_runtime` 43,
`test_engine_boundary` 36. Three compiler tests that asserted the old
`sendMessageBound` spelling were updated to `cachedSendBound`.

Full parity sweep: **102 passed, 0 failed** (`build/parity/run-9g37dbej`), after
the `negativeCacheSafeSelectors` gate above. The intermediate version failed
`custom_exception_hierarchy` and `equality_dynamic_dispatch`; those two are worth
re-running specifically when touching this path.

## Caveat on host load

These numbers were taken while other work was running on the machine; load
average ranged 1.8–6.0. Both trials agree closely and the instruction-count
changes confirm the mechanism, but the absolute timings are higher than earlier
sessions and the ratios should be re-taken on a quiet machine before quoting
them anywhere external.
