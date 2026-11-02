# Bound-host lookup memo

## Change

`boundClassFor` finds the interpreter host for a receiver by walking live class
identity (`findBoundClass`), which allocates a `visited: seq[Class]` on every call.
It is reached from `boundInterpretedSend`, i.e. once per dynamic send **when an
interpreter is bound** (embedded hosts: GTK applications, the IDE).

The answer is now memoized per receiver `Class`, invalidated whenever a binding is
added or removed. Negatives are cached too, and must be: binding an ancestor gives
every subclass below it a host, so a cached "no host" answer for a subclass would
otherwise survive the bind.

All four mutation sites invalidate — shim binding, instance binding (both paths)
and unbind.

## Measured effect: none on the benchmark suite

Same-core paired trials, `build/granite-profiles/run-y5nfbout` →
`run-tfz09epn`:

| Workload | Ratio |
|---|---:|
| Richards | 1.007x |
| DeltaBlue | 0.998x |
| Queens | 0.981x |

That is noise, and it is expected: `boundCompiledClasses` is empty in a standalone
compiled program, so `boundClassFor` returns at the `len == 0` check before ever
reaching the walk. `boundClassFor` does not appear in the gprof output at all.

This is therefore a **mixed-mode optimization with no benchmark claim**. It is kept
because it removes one `seq` allocation per dynamic send in embedded hosts and
costs nothing when unbound (the same single length check, inlined). If we want
evidence rather than reasoning, it needs a mixed-mode benchmark, which does not
exist yet.

## Validation

- `test_engine_boundary` 36 tests (was 35), ARC and ORC, 0 failures.
- New test: a leaf class under a future host class caches a negative answer while
  detached, must reach the host after binding the ancestor, must stop reaching it
  after unbind, and must reach it again after rebinding.
- Negative control: disabling `invalidateBoundClassMemo` makes the suite fail,
  so the invalidation is load-bearing and the test would catch a regression.

Logs: `build/memo7-*`, `build/memo-negative.log`.
