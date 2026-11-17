# Small native call entries: rejected experiment

## Attempted change

Give one- and two-argument instance methods a direct native entry
`proc(self, arg0, arg1: NodeValue)` plus a sequence-compatibility wrapper, and
route compiled one/two-argument sends through a per-site cache that dispatches
to the direct entry when arity and method version match. The intent was to remove
per-call `seq[NodeValue]` construction from ordinary compiled calls.

## Why it was reverted

Correctness was fine. Measured performance was not:

| Workload | Before ms/pass | After ms/pass | Change |
|---|---:|---:|---:|
| Richards | 32.66 | 32.47 | ~0.6% faster (noise) |
| DeltaBlue | 51.92 | 53.33 | ~2.7% slower |
| Queens | 99.68 | 105.05 | ~5.1% slower |

Method: retained release-ARC binaries, 12 measured alternating trials after one
warm-up, 30 verified passes per invocation, both binaries pinned to the same
performance core (CPU 2). Same baseline as
`build/granite-profiles/run-mzpeuqfx`. Evidence:
`build/small-calls-pinned.log`.

A first unpinned run also showed no gain and looked worse on DeltaBlue/Queens
(`build/arity-profile.log`). The prototype is not kept in the tree.

## Why it did not help

- The per-site cache added a comparison chain plus a cache-fill path on every
  one/two-argument send, paid even when the direct entry is hit.
- Calls that reach interpreted code, class-side methods, builtins or a host-bound
  owner must build a sequence anyway, so they paid both paths.
- `seq[NodeValue]` for one or two elements is a single small allocation whose
  cost is apparently below the added indirection on these workloads.
- Richards/Queens spend most time in dispatch, allocation and value copying around
  sends, not in building the argument buffer alone.

This does not disprove a calling-convention change. It disproves *this* shape of
it: a dynamic-arity cache lookup in front of the call. A viable next attempt would
need compile-time-known targets (static class, or a guarded monomorphic site whose
guard is cheaper than a cache probe) so no per-call resolution happens at all.

## Consequence for the plan

The recommendation in `GRANITE_LUAJIT_NOTES.md` and
`BENCHMARK_PRACTICAL_BASELINES.md` is refined: do not pursue argument-sequence
removal through runtime arity dispatch. Prioritise guarded receiver-send
specialization and typed value propagation, where the guard replaces a dispatch
instead of being added to one, and re-profile before committing to a calling
convention redesign.
