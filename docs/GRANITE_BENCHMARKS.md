# Granite benchmark: cross-language baseline

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

- One microbenchmark cannot characterize a language. Object allocation, message
  sends, closures and exceptions are not exercised here; `benchmark/towers.hrd`
  and `benchmark/queens.hrd` are candidates for those, but neither is verified in
  both engines yet.
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
