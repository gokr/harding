# Benchmarks

How Harding is measured against other engines, what the recorded numbers are,
and how to reproduce them.

Numbers in this file are dated and revision-pinned on purpose. **Read the
revision before quoting any figure.** A number without its revision is not a
result.

## What is measured

| Runner | Workloads | Engines | Script |
|---|---|---|---|
| Practical cross-engine | Richards, DeltaBlue, Queens | Granite, CPython, GNU Smalltalk, native Nim | `scripts/bench_compare_practical.py` |
| Dispatch and object-graph | shapes, tree | Granite, CPython, native Nim | `scripts/profile_granite.py` |
| AWFY | Bounce, Json, Havlak (upstream's own sources) | Granite, CPython, GNU Smalltalk | `scripts/bench_compare_awfy.py` |
| AWFY on Smalltalk VMs | Bounce, Json, Havlak | Cog, Oil (Squeak) | `scripts/bench_compare_oil.py` |
| Sieve | trial division to 5000 | C, Go, Node, Ruby, Python, Nim, Granite, interpreter | `scripts/bench_sieve_languages.py` |

Algorithm and performance workloads live in `benchmark/`, not in `examples/`,
and are not part of the example audit.

Why `shapes` and `tree` exist, and what each one exercises, is in
[BENCHMARK_COVERAGE.md](BENCHMARK_COVERAGE.md). The classic three workloads
measured 0% improvement on several optimisation slices that were worth 28-84% on
their own receiver shape.

### Method, common to all runners

- Answer-checked. Every timed run must print its expected result; a run that
  exits non-zero, writes to stderr, or fails verification is a hard failure and
  is never recorded as a score. GNU Smalltalk in particular can print an
  exception on stdout and still exit zero, so exit status alone is not trusted.
- Startup subtracted. The zero-work baseline is the same program with the driver
  loop bounded at zero, so process start and class initialization are measured
  and removed rather than estimated. A baseline that prints anything fails.
- Paired, alternating. One warm-up is discarded, then engine order and
  zero-work/work order alternate per trial; the reported figure is a median of
  per-trial paired differences, in milliseconds per pass.
- Repetition counts differ per engine because constant factors differ by orders
  of magnitude. Timing is always reported per pass, so the counts do not affect
  the unit. Raw totals across engines are **not** comparable.
- Compilation is excluded.
- The host is not isolated. Host load is recorded in `results.json` and belongs
  in any report; small differences are ties.

## Most recent practical comparison

Revision `61e18c3`. CPython 3.12.3, GNU Smalltalk 3.2.5 (non-JIT), Nim
2.2.12/GCC 13.3.0 release ARC, Intel Core Ultra 7 165U. Five measured trials
plus a discarded warm-up. Milliseconds per checked pass, startup baseline
removed:

| Workload | Granite | CPython | GNU Smalltalk | Native Nim |
|---|---:|---:|---:|---:|
| Richards | 33.845 | 4.773 | 2.728 | 0.168 |
| DeltaBlue | 60.013 | 6.929 | 7.837 | 0.165 |
| Queens | 111.412 | 13.824 | 9.308 | 0.276 |

Granite is ~7.1–8.7x slower than this CPython port, ~7.7–12.4x slower than GNU
Smalltalk, and ~202–403x slower than the explicit native Nim representation.
These are workload results, not language-wide rankings. **Being compiled via Nim
does not currently imply Python-level performance.**

Evidence: `build/bench-compare-practical/run-gne5ie02/results.json` (build
artifact, not committed). A confirmation run `run-k1c801uk` gave the same
ordering with Granite ~8.1–8.8x slower than CPython.

### What each port actually is

A matched port, not a maximally idiomatic rewrite, and not a message-send
interpreter for the non-Smalltalk engines.

- **Richards** — 1,000 idle iterations, six task priorities, packet order and the
  `xor16` helper retained; verification requires 2,322 queued and 928 held
  packets per pass.
- **DeltaBlue** — chain/projection size 100, LIFO worklists, the pinned Octane
  strength mapping (including required → weakest), ten plan executions per
  change, projection sum 223,305, explicit graph cleanup.
- **Queens** — exhaustive search of all 92 solutions with linked placement
  objects. The faster first-solution SOM/AWFY workload is *not* substituted.
- **Python** — emitted by a restricted source adapter into ordinary classes,
  method calls, fields and loops. Slot accessor sends remain method calls, as in
  the Cog adaptation. No NumPy, no extensions, no JIT flags.
- **GNU Smalltalk** — native methods and control structures with the same
  zero-based adapter as Cog; benchmark-only `HBObject` supplies `new →
  initialize`; no system-wide `Object` behaviour is changed.
- **Native Nim** — the implementation-headroom reference: plain refs, fields,
  calls, loops. It is not a lower bound and not a promise that Granite could
  compile to those layouts while preserving semantics.

Source licenses are retained in generated sources and copied next to run
artifacts. Native DeltaBlue is GPL-2.0-or-later and is not imported by the
Harding runtime or compiler; Richards uses the pinned V8 BSD provenance. See
[performance/RICHARDS.md](RICHARDS.md) and [performance/DELTABLUE.md](DELTABLUE.md).

## AWFY

Every port is pinned to AWFY revision
`74306fec151070fd07157cefeacf19e7e0bcdc89`. Each port's
`upstream/provenance.json` records a SHA-256 for every vendored file and the
upstream path it came from; `tests/test_awfy_compare.py` re-verifies those
digests, so a drifted vendored source fails the suite instead of silently timing
a different program.

| Case | Granite | CPython | GNU Smalltalk |
|---|---|---|---|
| Bounce | yes | yes | yes |
| Json | yes | yes | **not covered** |
| Havlak | yes | yes | **not covered** |

The two gaps are stated rather than papered over:

- **Json / GNU Smalltalk.** The fixture and checks are escape-heavy string
  literals. GST strings have no escapes at all, so receiving that data needs a
  real Harding-to-GST compiler rather than a spelling translation.
- **Havlak / GNU Smalltalk.** Havlak is written against SOM `Core` collections
  (`Vector`, `SomIdentityDictionary`, `SomIdentitySet`). The adapter does not
  translate those, and substituting Harding's `Array`/`Table` would compare a
  different data structure.

Bounce is a deliberately small workload (100 balls, 50 updates), a few
milliseconds per pass, so fixed per-pass costs dominate. A slower-than-CPython
result on Bounce means "this workload is too small to demonstrate throughput",
not "the compiler is bad". The larger cases are the honest comparators.

## Cog and Oil (Squeak)

`scripts/bench_compare_oil.py` times the same three AWFY workloads on the pinned
Cog and Oil VMs. This is a separate adapter, because Cog cannot run the Harding
ports: it loads AWFY upstream's own Smalltalk sources through upstream's own SOM
loader. The only additions are image-compatibility selectors from upstream's
`build-image-squeak.st` plus three Pharo-API replacements.

Two consequences must be stated whenever these numbers are reported:

- the workload is upstream's, not the Harding port's — upstream Json verifies its
  own fixture, so the port's `JsonChecks` assertions are not run on Cog;
- GNU Smalltalk is not covered; the comparison is Cog vs Oil on the same image.

Repetition counts are per case (Bounce 2000, Json 200, Havlak 1 — its checked
full-size graph). `tests/test_oil_benchmarks.py` re-verifies the vendored digests,
checks the driver contract, and (with local VMs) executes all three workloads at
0, 1 and 3 repetitions on both VMs plus a deliberately failing verification.

The OpenSmalltalk Oil build and verification record, including its evidence
directory, is in `research/benchmarks/OPENSMALLTALK_OIL_COMPARISON.md`.

## Sieve: arithmetic throughput

`scripts/bench_sieve_languages.py` runs `benchmark/sieve.hrd`'s algorithm (count
primes to 5000 by trial division, answer 669) in each language. It is a tight
integer loop with no message sends, closures or allocation, so it measures loop
and arithmetic throughput rather than object-model performance.

Machine: 14-core Linux x86-64, Nim 2.2.12, GCC 13.3.0, Node.js v22.23.2, Ruby
3.2.3, Python 3.12.3, Squeak 6.0 / OpenSmalltalk Cog VM (r3732).

| Engine | per sieve pass | relative |
|---|---|---|
| C (gcc -O3) | 0.193 ms | 1.0x |
| Node.js v22 | 0.204 ms | 1.1x |
| Go | 0.302 ms | 1.6x |
| Nim 2.2.12 (release) | 0.309 ms | 1.6x |
| Squeak Cog (OpenSmalltalk) | 0.448 ms | 2.3x |
| Ruby 3.2 | 3.355 ms | 17.4x |
| Python 3.12 | 4.129 ms | 21.4x |
| Granite | 7.790 ms | 40.4x |
| Interpreter (release) | 694.8 ms | 3608x |

This is the widest gap in any Harding measurement and the clearest statement of
where the compiler stands: Granite is ~40x off C on a pure arithmetic loop, while
being ~89x faster than Harding's own interpreter.

## Historical snapshots

Do not splice these into a current table. Each is superseded and kept for
traceability:

| Document | Revision | Why it is historical |
|---|---|---|
| `research/benchmarks/BENCHMARK_COMPARISON_CURRENT.md` | `18e3728` | Cog/Node comparison at that revision; engines differ from the practical runner |
| `research/benchmarks/GRANITE_BENCHMARKS.md` | pre-`61e18c3` | first cross-language baseline, before dispatch work |
| `research/performance_optimization_plan.md` | — | earlier optimisation plan |
| `research/performance_baseline.md` | — | earlier baseline note |

## Reproducing

```sh
# Practical comparison (GNU Smalltalk optional; tests skip if absent)
python3 scripts/setup_benchmark_gst.py          # local install under build/, no sudo
python3 scripts/bench_compare_practical.py --trials 5 --mm arc
nimble testBenchmarkPorts

# AWFY
python3 -B scripts/bench_compare_awfy.py --trials 7
python3 -B scripts/bench_compare_awfy.py --trials 7 --skip-gst
python3 -B scripts/bench_compare_awfy.py --trials 7 --cases json

# Cog / Oil
python3 scripts/bench_compare_oil.py bounce json havlak --trials 7

# Sieve
python3 scripts/bench_sieve_languages.py
```

`GNU Smalltalk is never silently dropped`: `--skip-gst` omits it explicitly, and
an invalid explicit `BENCHMARK_GST` path fails rather than skipping.

Artifacts land under `build/<runner>/run-*/`, with `results.json` recording raw
samples, command lines, source hashes, engine versions, dirty state and CPU
model.

## Constraints on this host

- `perf_event_paranoid=4` blocks kernel perf sampling. No privileges or kernel
  settings were changed; gprof with `-pg` release builds is used instead, and
  instrumented timings are never reported as scores.
- GNU Smalltalk is built from source under `build/gnu-smalltalk/` with a
  checksum-verified tarball, extracted dependency packages and no system
  installation. It has no JIT.

## How to read a Harding benchmark claim

1. Which runner, and was the revision recorded?
2. Was the answer checked, and was the zero-work baseline subtracted?
3. Is the workload large enough to exceed timer resolution for every engine?
4. Are the ports equally matched, or does one get a native representation the
   other cannot have?
5. Was the binary instrumented?

If any answer is missing, the number is an anecdote. Optimization work and its
measured results are indexed in
[compiler/GRANITE_PERFORMANCE.md](../compiler/GRANITE_PERFORMANCE.md); current
profiling workflow is in [performance/PERFORMANCE.md](PERFORMANCE.md).
