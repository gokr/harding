# Granite performance: what each optimisation slice did

Granite's optimisation history, one row per slice: what changed, what it
measured, whether it was kept. Every slice document is preserved in
`research/compiler/` with its raw evidence paths, call counts and validation
logs. This file is the index, not a replacement.

Current cross-engine numbers are in [BENCHMARKS.md](../performance/BENCHMARKS.md).
Profiling workflow is in [PERFORMANCE.md](../performance/PERFORMANCE.md).

## Reading these numbers

- **Paired ratio** — median throughput ratio of candidate to retained baseline
  from alternating same-core trials, 30 verified passes per process, warm-up
  discarded. Above 1.0 is faster.
- **Isolated experiment** — a prototype benchmarked against nothing shipped; it
  may show a large number on a synthetic loop and no gain on the workloads.
- Percentages are within-run differences, not absolute performance claims. The
  host is not isolated; small differences are ties.
- Instrumented (gprof) timings are never reported as scores. They guide
  hypotheses and give call counts.

## Kept: measured on the three object workloads

| Slice | Change | Paired ratio | Document |
|---|---|---:|---|
| Bounded resolution cache | Versioned cache for native method resolution instead of repeated hierarchy walks | 1.21x Richards, 1.23x DeltaBlue | `GRANITE_PROFILE_SLICE.md` |
| Single resolution per send | `sendMessage` no longer resolved the same `(class, selector)` twice per dynamic send | 1.15x Richards, 1.23x DeltaBlue, 1.03–1.04x Queens | `GRANITE_SEND_RESOLUTION.md` |
| Per-site send cache in method bodies | `cachedSendBound` for compiled method bodies, not just top-level script code | 1.15–1.17x Richards, 1.19x DeltaBlue, 0.99x Queens | `GRANITE_SITE_CACHE.md` |
| Cache lifetime in expression blocks | Proc-scope TLS cache address, because the generated C reset `{.global, threadvar.}` at each template expansion, so Queens' sites never warmed | Queens resolutions 2,450,880 → 1 for `notNil` | `GRANITE_CACHE_LIFETIME.md` |
| Eager Boolean primitives | `receiver \| arg` and `receiver not` answer natively for Boolean receivers, falling through otherwise | 1.23–1.25x Queens; others unchanged | `GRANITE_BOOLEAN_PRIMITIVES.md` |
| Operand bindings | Bind only operands that need binding; skip the `NodeValue` copy for bare locals, parameters and literals | 1.10–1.13x Richards, 1.02–1.04x DeltaBlue, 1.22x Queens | `GRANITE_OPERAND_BINDINGS.md` |
| Guarded unary receiver sends | Baked-in target for a unary selector with exactly one candidate method, with runtime guards | 1.18–1.20x Richards, 1.13–1.30x DeltaBlue, 1.85–1.88x Queens | `GRANITE_DIRECT_SENDS.md` |
| Guarded direct slots | Inline native slot read/write per slot, guarded by layout and registration version | ~65% on a declared-Integer counter loop; ~20% on unannotated Richards; other processes too noisy | `GRANITE_DIRECT_SLOTS.md` |
| Collection value views | Stop copying the whole collection on every `size`/query send in a loop | 1.24x DeltaBlue; Richards and Queens unaffected | `GRANITE_COLLECTION_VIEWS.md` |

## Kept: narrow or not measurable on the benchmarks

| Slice | Change | Result | Document |
|---|---|---|---|
| Bound-host lookup memo | Memoise `boundClassFor` per receiver class, invalidated on binding changes; negatives cached too | No measurable change on the suite. Kept because it removes a per-dynamic-send allocation in embedded hosts (GTK, IDE), which the benchmarks do not run. | `GRANITE_BOUND_CLASS_MEMO.md` |
| Numeric method locals | Proven single-kind method temporaries use native storage | 5.16x Integer loop, 5.28x Float loop, 2.23x with a dynamic bound; not a whole-benchmark gain | `GRANITE_STATUS.md` §Numeric specialization |
| Native Integer call regions | Pure Integer expression methods planned into native parameter/return chains | 126x on a synthetic 100k→4M loop (146.4 → 1.2 ns/iter); 0.999–1.011x on Richards/DeltaBlue/Queens | `GRANITE_NATIVE_CALL_REGIONS.md` |
| Declared-Integer slot regions | Region may read/write the receiver's declared Integer slots directly | Extension of the above; slot-backed loops become plain field access | `GRANITE_NATIVE_CALL_REGIONS.md` |

## Rejected, with the reason

These were implemented, correct, and reverted. Keeping the record is the point:
each looked like a clear win before measurement.

| Slice | Rejected because | Document |
|---|---|---|
| Per-site selector ids and class density ids | Measured **0%**. Would have added a per-class `dispatchId` field and per-site selector-id space to remove two string hashes that profiling showed were a smaller cost than the new mechanism's risk. | `GRANITE_SELECTOR_ID_EXPERIMENT.md` |
| Small native call entries | **Slower**: Richards ~0.6% (noise), DeltaBlue ~2.7%, Queens ~5.1%. Removed `seq[NodeValue]` construction per call but paid for per-site arity/version dispatch. | `GRANITE_SMALL_CALL_EXPERIMENT.md` |

The rule those produced: a mechanism that adds permanent state (a field, an id
space, a second invalidation policy) must show a measured gain on a real
workload, not on a synthetic loop and not in call counts alone.

## Probes and studies

| Document | What it answered |
|---|---|
| `GRANITE_SPECIALIZATION_PROBE.md` | How much compiled dispatch a native-parameter variant could reach: 59% of Richards' and 78% of DeltaBlue's own-class dispatches are eligible and currently un-specialized; Queens 0%. Used to decide whether interprocedural specialization is worth a slice. |
| `GRANITE_LUAJIT_NOTES.md` | What trace compilation, SSA, FFI and profiler ideas from LuaJIT imply for Granite. Design proposals, explicitly not transplant claims. |
| `GRANITE_PROFILE_SLICE.md` | The first profiling pass: allocation, string hashing, hierarchy traversal and dispatch as the four material costs, from flat profiles at `732716d`. Contains the slice that became the resolution cache. |
| `GRANITE_COLLECTION_VIEWS.md` | A worked diagnosis: a copy on every send made `size` O(n), taking AWFY Havlak to 181.6 s against CPython's 3.1 s, and what the profile actually blamed instead. |
| `GRANITE_AUDIT.md` | Exception and non-local-return migration evidence: handler cleanup across `pass`/`retry`, VM scope truncation, registration leaks. |
| `LEGACY_GRANITE_AUDIT.md` | Salvage review of branch `feature/granite-full-compilation`: what was kept, what was not, and why those commits are not history-merged. |

## Where the remaining headroom is

From the probes and profiles above, in the order the evidence supports:

1. **Slot-backed arithmetic regions.** The synthetic Integer region has enormous
   leverage but the three workloads do not contain qualifying loops; the next
   step is regions that read and write declared slots, which is where those
   workloads actually spend time.
2. **Deferred argument materialization.** `genHostedBuiltin` builds an argument
   buffer before calling `hostedBuiltin`, even when the operand is an immediate
   Integer and the helper immediately answers `handled = false`. Richards creates
   3,578,400 such payloads over 50 passes in `xor16:with:` alone. The change is
   *when* the buffer is built, not whether live host lookup happens or whether an
   operand may be evaluated twice.
3. **Specialization with source-fingerprinted feedback.** The probe shows 59–78%
   of own-class dispatches are eligible in Richards and DeltaBlue. It needs
   method/version guards and dynamic fallback, not a second semantics.

More inferred self-slot arithmetic alone did not reliably improve the three
benchmarks in earlier paired measurements, so it is not on this list.

## Reproducing a slice

Slice documents record their own commands and evidence paths. The shared
pattern:

```sh
python3 scripts/profile_granite.py        # writes build/granite-profiles/run-*/
```

Pinned to one CPU core (`taskset`), alternating trials, 30 verified passes per
process, exact stdout checked on every run. `perf` sampling is unavailable on
this host (`perf_event_paranoid=4`), so gprof with `-pg` release builds supplies
call counts and self samples.
