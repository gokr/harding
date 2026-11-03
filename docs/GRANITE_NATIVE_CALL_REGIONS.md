# Native Integer call regions (prototype)

The compiler plans pure expression methods with explicit returns, Integer
parameters, literals and `+`, `-`, `*`. It builds plans in dependency order so a
method can call a previously planned method through lexical `self`, keeping both
parameters and returns as Nim `int` across that call. No benchmark names or
selectors are special-cased. Regions also support Integer temporaries, comparisons,
`ifTrue:ifFalse:`, and `whileTrue:`/`whileFalse:` lowered to native Nim control
structures. Definite initialization is tracked: both branches must initialize a
new local, and a possibly empty loop cannot establish initialization afterward.
Methods with fallthrough, heap/parameter mutation, slots, callbacks, recursion,
division or real closures are not planned yet.

For example:

```smalltalk
Calc>>outer: n [ ^(self inner: n) * 3 ].
Calc>>inner: n [ ^n + 1 ].
```

produces the equivalent of:

```nim
proc inner_native(n: int): int = n + 1
proc outer_native(n: int): int = inner_native(n) * 3
```

There is no `NodeValue`, argument sequence or dynamic send *inside* this region.
A boxed adapter at its external boundary checks all input tags, exact receiver
class identity and the current registered procedure for every transitive method
dependency before entering it. Bound interpreters disable the native path. All
operands arrive evaluated before guards run, so argument-side method replacement
cannot select a stale body. Class/subclass mismatch, Float arguments, changed
methods and nil-returning replacements retain ordinary dispatch.

Selectors must be unique within the module for this first routing implementation.
This is a conservative candidate filter, not a claim that the world is closed.
No source declaration or training profile is needed for these pure regions.
Observed slot contracts can support later extensions, but this prototype does not
yet propagate slot values into regions.

## Validation so far

- `tests/test_native_call_regions.py`: generated native chain, warmed calls,
  Float fallback, transitive method replacement, replacement during a once-only
  operand callback, subclass override, top-level replacement and nil results;
  executed under ARC and ORC.
- Compiler basic: 99 checks under ARC and ORC.
- Generated host fixture: the `answer` class-side test fails under both this
  prototype and the retained pre-prototype compiler; recorded in
  `build/native-region-host.log` and `build/native-region-baseline-host.log`.
  It remains an unresolved baseline failure, not a passing gate.
- Final broader parity sweep: **105 passed, 0 failed**
  (`build/native-region-parity-final.log`, `build/parity/run-ac6a2xkx`). The first
  sweep caught an over-broad forward declaration for an uncompiled Array method;
  declarations now cover only emitted region candidates. The failing
  SortedCollection case passes after the fix.
- The focused fixture also binds an interpreter, replaces the transitive callee
  there, detaches, and checks native dispatch resumes. It verifies callbacks,
  recursion, division and implicit-return bodies are not planned.

The locals/control-flow extension passes eight definite-initialization planner
checks under ARC and ORC and the expanded generated-host fixture (including
callee replacement inside a loop). Its full parity sweep also passes **105/105**
(`build/native-loop-parity.log`, `build/parity/run-9id5654b`).

### `main()` consultation (top-level sends)

Top-level statements used the per-site send cache and never consulted the
adapters, so a script whose hot loop sat at top level gained nothing (the first
measurement of this slice silently compared the same boxed path twice). `main()`
now receives the candidate table like method bodies do, and a generation test
asserts the adapter call appears inside `main()`.

Measured against `dc97e2a`, release ARC, CPU 2, exact stdout checked on every run:

| Workload | Before | After | Marginal speedup |
|---|---:|---:|---:|
| Top-level 100k→4M loop, 3 native calls per iteration | 146.4 ns/iter | 1.2 ns/iter | **126×** |
| Richards (30 passes) | 20.385 ms | 20.407 ms | 0.999× |
| DeltaBlue (30 passes) | 33.210 ms | 32.952 ms | 1.008× |
| Queens (30 passes) | 37.196 ms | 36.785 ms | 1.011× |

Per-iteration costs use a least-squares fit over 200k/1M/4M iterations, because
process startup (~25 ms) dominates fixed-N timings. The emitted C still contains
the real `while` loop, so this is not closed-form folding. Interpreter and
compiled output agree at limits 0, 1, 2, 3, 7, 11 and 100
(`build/toplevel-differential/`). Full parity: **105/105**
(`build/parity/run-o4mxd82e`).

**No main-workload gain yet.** Richards/DeltaBlue/Queens do not contain loops
that qualify (their hot methods touch slots, send to other receivers, or use
division), so the boxes they pay are elsewhere. The next lever is not more
region shapes but slot-backed regions, which is where those workloads spend
their time.
