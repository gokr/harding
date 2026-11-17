# Granite benchmark: cross-language baseline

For the fresh current-revision comparison with Cog, including Richards and
DeltaBlue, see [current benchmark comparison](BENCHMARK_COMPARISON_CURRENT.md).
The measurements below are historical baselines; do not compare their absolute
timings across runs as if host load and runtime versions were controlled.

## Purpose

`PLAN.md` section 6 defers optimization until semantic coverage is done. This
document establishes a measured baseline before that work starts, so later
specialization, unboxing and dispatch caching have something concrete to improve
against.

The workload is the existing `benchmark/sieve.hrd`: count primes up to 5000 by
trial division, printing only the count (669). It is a tight loop and integer
arithmetic benchmark with no message sends, closures or allocation, so it
measures loop and arithmetic throughput rather than object-model performance.

## Methodology

Run with `python3 scripts/bench_sieve_languages.py`.

- The same algorithm is implemented in each language, idiomatic but without
  algorithmic changes.
- A single sieve pass is far below timer resolution for fast engines, so each
  engine runs the pass many times in one process. Repetitions are scaled per
  engine so every workload lasts several seconds.
- Each engine is timed externally. A startup-only baseline is measured and
  subtracted, which matters for Squeak's multi-hundred-millisecond image load and
  for the Harding interpreter's stdlib load.
- Five trials per engine; medians are reported, then divided by the repetition
  count to give milliseconds per single sieve pass.
- Every engine must print 669; a mismatch fails the run.
- Squeak writes results to a file because headless Squeak raises a fatal error
  dialog when writing to a closed stdout.

These are wall-clock measurements including a subtraction, not cycle-accurate
counts, and the machines' noise floor is around a few percent. Treat small
differences as ties.

## Results

Machine: 14-core Linux x86-64, Nim 2.2.12, GCC 13.3.0, Go, Node.js v22.23.2,
Ruby 3.2.3, Python 3.12.3, Squeak 6.0 / OpenSmalltalk Cog VM (r3732).

| Engine | per sieve pass | relative |
|---|---|---|
| C (gcc -O3) | 0.193 ms | 1.0x |
| Node.js v22 | 0.204 ms | 1.1x |
| Go | 0.302 ms | 1.6x |
| Nim 2.2.12 (release) | 0.309 ms | 1.6x |
| Squeak Cog (OpenSmalltalk) | 0.448 ms | 2.3x |
| Ruby 3.2 | 3.355 ms | 17.4x |
| Python 3.12 | 4.129 ms | 21.4x |
| Harding native (Granite) | 7.790 ms | 40.4x |
| Harding interpreter (release) | 694.8 ms | 3608x |

## Interpretation

The comparisons worth trusting are those between similar engine classes.

**Native compiled group.** C, Node.js, Go and Nim are within 1.6x of each other.
Node's result reflects a JIT that optimizes this integer loop well; it is not a
general claim about JavaScript performance.

**Squeak Cog is competitive here.** At 2.3x from C it is only ~1.5x slower than
Nim. Cog compiles hot methods to machine code, and `whileTrue:` with literal
blocks is inlined, so a loop with no message sends plays to its strengths. This
should not be read as Cog being roughly as fast as C on object-heavy code.

**Granite native vs the interpreter.** Native compilation is about 89x faster
than the release interpreter on this workload (7.79 ms vs 694.8 ms). That is the
headline result: compilation delivers a large, real speedup.

**Granite native vs native compilers.** Granite is ~40x slower than C and ~25x
slower than Nim on this loop. This is expected at the current stage rather than a
surprise:

- Every value is a tagged `NodeValue`, so arithmetic goes through runtime helpers
  instead of machine integers (no unboxing).
- Messages dispatch dynamically by selector string through runtime tables rather
  than to direct calls.
- Specialized codegen for literal blocks exists, but there is no cross-method
  specialization, inlining or dispatch caching.

Those are exactly the levers listed in `PLAN.md` section 6. This benchmark
therefore quantifies the current cost of the dynamic model and gives the
optimization phase a starting point.

## Caveats and limits

- Sieve does not exercise object allocation or ordinary method sends. The object
  benchmarks below provide separate coverage; these results are not interchangeable.
- Granite's compiled exception and notification support is incomplete, so this
  benchmark is not evidence of broad compiled-language coverage.
- Interpreters and VMs include different startup work, which the baseline
  subtraction reduces but does not fully remove.
- The generated native binary and the interpreter were both built from this
  branch; results are not comparable across future commits without re-running.
- Go, Node.js, Squeak and the other runtimes are whatever versions this machine
  had installed, not pinned releases.

## Reproducing

```sh
nimble harding_release
# build Granite once: nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/bench_sieve_languages.py
```

Language sources and build logs are written under `build/bench_langs/`. The Squeak
image copy lives under `build/squeak/`.

## Object benchmarks: queens and towers

Run `python3 scripts/bench_objects.py queens towers` after building the release
interpreter and Granite. The runner generates repeated drivers from the checked-in
benchmark definitions, compiles matching linked-object Nim implementations, checks
**every** trial's result, and records raw timings and logs in isolated
`build/bench_objects/run-*/` directories. Builds and executions have time limits.
Five trials are timed externally; the median zero-work startup is subtracted from
the median workload duration, then divided by repetitions. The baseline includes
class registration and solver creation. Nim uses release ARC; Granite uses the
project's default ARC. The interpreter binary must be built in release mode.

- **Queens:** exhaustive eight-queens backtracking, checking column and both
  diagonal conflicts. Each legal placement allocates a linked object. The result
  must be **92 solutions**, not merely eight occupied rows. This replaces the
  earlier simplified benchmark; it is not the SOM first-solution workload.
- **Towers:** move 13 linked disk objects between three peg objects. Every push
  checks move legality, and the final chain must contain sizes 1 through 13 with
  the other pegs empty. The result must be **8191 moves**. Each repeated run
  allocates fresh disks and pegs; moves relink existing disks.

Baseline on the same Linux x86-64 host, Nim 2.2.12 / GCC 13.3.0:

| Workload | Granite native | Release interpreter | Native Nim ARC |
|---|---:|---:|---:|
| Queens, all solutions | 185.939 ms | 4252.574 ms | 0.573 ms |
| Towers, 13 disks | 53.251 ms | 671.091 ms | 0.273 ms |

Repetitions: Granite 30, interpreter 3, Nim 1000. Raw evidence:
`build/bench_objects/run-c__8y__h/results.json` (disposable; regenerate with the
runner). Granite is ~23x/~13x faster than the interpreter, but ~325x/~195x slower
than Nim on these workloads. This measures the current dynamic representation,
dispatch and allocation costs together, not any single bottleneck. No Cog numbers
have been measured for these two algorithms; the sieve comparison cannot be
extrapolated to them. Native correctness also passes under ORC (92 and 8191).

An earlier run measured Granite at 135.331/38.154 ms and the interpreter at
3405.491/531.414 ms. Background builds and host contention were not controlled,
and capture correctness was tightened between runs. Treat these as exploratory
baselines, not evidence of a performance regression or a precise speedup target.
Re-run before/after optimization on an otherwise idle host.

These workloads exposed three correctness gaps, fixed before taking this baseline:
missing compiled nil predicates, incomplete capture traversal through specialized
control-flow nodes, and native storage reclaimed behind raw instance pointers.
Wrappers now retain their native owner directly, without a permanent keep-alive
registry. ARC does not collect arbitrary cycles; cyclic object graphs still need
separate lifetime coverage.

## Optimization A: inline-only locals

Specialized if/while blocks lowered inline no longer register as closures. This
removes unnecessary cells and home-invocation targets from ordinary accumulator
methods while retaining environments for nested escaping closures and non-local
returns. Generated-code tests assert that distinction; 46 parity cases and 29
block-codegen tests pass.

A paired comparison alternated the retained pre/post-change Granite binaries for
seven trials, each running 30 passes and checking its result:

| Workload | Before A | After A | Reduction |
|---|---:|---:|---:|
| Queens | 134.896 ms | 130.342 ms | ~3.4% |
| Towers | 41.314 ms | 38.447 ms | ~6.9% |

These are process-time medians divided by 30, without startup subtraction; both
versions have the same driver and negligible native startup relative to these
runs. Raw evidence is `build/a_paired_results.json`. Host load was not isolated.
The improvement is modest: arithmetic still operates on NodeValue and ordinary
messages still use dynamic dispatch. It does not establish a Cog performance
claim or the expected gains from B–D.

## First guarded-allocation slice

Statically named classes now bypass general dispatch for default `new` only while
a versioned guard proves no own/inherited override and an unchanged allocator.
Runtime registration changes invalidate the guard; overridden `new` stays dynamic.
All 48 parity cases pass, including inherited constructors and object benchmarks;
the repeated object workloads also return 92/8191 under ORC.

Seven alternating trials of retained before/after binaries measured queens at
182.399/166.725 ms per pass and towers at 43.513/45.865 ms. Variance was large
(queens process timings ranged ~4.7–8.7 seconds); background host load was not
controlled. This is **not evidence of a reliable speedup**, and the towers result
shows that this limited allocation shortcut is not a general dispatch optimization.
Raw timings are in `build/c_paired_results.json`. Method-call specialization and
inline caches remain separate follow-up work.

## First monomorphic send-cache slice

Generic pure compiled sends now cache positive registered instance-method targets
per send site. Receiver class, selector and registration version guard hits;
registered method/hierarchy changes invalidate them. Builtin/exception/class-side
paths still use generic dispatch. Nil is a valid method result, not a cache miss.
Runtime invalidation and evaluation-count tests pass under ARC and ORC; repeated
queens/towers workloads return 92/8191 under ORC.

An initial implementation walked exception ancestry before checking every cache
hit; it measured 239.449/78.876 ms for queens/towers. Removing that hierarchy walk
from ordinary sends (while routing exception action selectors to the original
runtime) measured 138.780/26.603 ms in a later run. These runs were not isolated,
so those numbers are diagnostic observations rather than a controlled speedup.

Seven alternating trials comparing pre-cache and revised-cache binaries gave:

| Workload | Before cache | After cache |
|---|---:|---:|
| Queens | 224.309 ms | 233.781 ms |
| Towers | 66.098 ms | 48.522 ms |

Process medians are divided by 30 passes, without startup subtraction. Raw data:
`build/d_paired_results.json`. Host contention was substantial: queens trials
ranged ~5.3–13.0 seconds. Towers suggests a gain; queens does not. Do not claim a
uniform speedup or proximity to Cog from these results. Compact class identities,
argument-allocation reduction and polymorphic cache design remain follow-up work.

## Numeric method-local unboxing

`python3 scripts/bench_numeric_methods.py --before <retained-granite> --after ./granite`
builds checked release binaries for three numeric-method loops. Each process makes
21 method calls with one million iterations per call. One warm-up and seven
alternating before/after trials check exact stdout and empty stderr. These are
whole-process medians, without startup subtraction, not per-iteration timings.
Builds are outside timing; no other agent test/build runs overlapped this timing
phase, but unrelated host/VM load was not controlled.

Before: compiler from `b89551c`. After: conservative unboxing of declared method
temporaries initialized directly to one numeric kind, with boxed parameters,
slots, captures, shadowing, type changes and division unchanged.

| Workload | Before | After | Before / after |
|---|---:|---:|---:|
| Integer accumulator, local bound | 0.977386 s | 0.189259 s | ~5.16x |
| Float accumulator, local bound | 0.978228 s | 0.185437 s | ~5.28x |
| Integer accumulator, dynamic bound parameter | 0.894023 s | 0.400281 s | ~2.23x |

Raw seven-trial measurements, generated sources, binaries and build logs:
`build/numeric-method-bench/run-ofpi3vcy/results.json` (disposable; regenerate).
Integer runs print `499999500000`, Float runs `500000.0`. The dynamic-bound case
keeps the comparison boxed because its parameter is not proven numeric.

These loops demonstrate a gain for regular numeric methods, not broad application
performance, interprocedural specialization, loop-parameter unboxing or proximity
to Cog. The generated loop still has expression boxing/unboxing at some
boundaries; this slice changes local storage and same-kind expressions, not the
calling convention. Further work should measure additional workloads and check
initialization, captures, error/overflow behavior and dynamic fallback first.
