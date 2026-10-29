# Current cross-engine benchmark comparison

Revision: `18e3728` (`granite-completeness`). Fresh release Harding/Granite builds,
Nim 2.2.12, GCC 13.3.0, Linux x86-64, Intel Core Ultra 7 165U. ARC is selected for
Harding, Granite and native Nim. Cog: Squeak 6.0 image, OpenSmalltalk production
Spur/Cog x86-64 VM `202312181441`, VM commit `cc2dd90` (December 2023).
These results describe this available Cog installation, not the latest Cog VM.

## Method

```sh
python3 scripts/bench_compare.py --trials 5 --mm arc
python3 scripts/bench_compare_classic.py --trials 5 --mm arc
```

Both runners build release Harding/Granite before timing, use a disposable copy
of the Squeak image, and never save benchmark changes into the supplied image.
Every observation's output and process status is checked. One checked warm-up
pair is discarded; five process pairs are measured, alternating engine order
and work/baseline order. Reported values are medians of paired
`(work wall time - zero-work wall time) / repetitions`. Raw process totals,
baselines, versions, commands and source hashes are in each `results.json`.

Different repetition counts keep measured work above startup costs. These are
process measurements with approximate baseline subtraction, not pure steady-state
VM-internal timings. JIT warm-up within a process remains included. Cog's zero-work
baseline compiles the same benchmark methods but executes zero passes; Harding's
loads the same class definitions. Cog uses the default GC; ARC is not a claim
that its memory-management policy matches Cog's tracing collector.

The host is not isolated from other activity. Small differences are not
significant, and results are not directly comparable with older measurements
from a different run/host load. No system priority or desktop settings were
changed. Cog's heartbeat-priority warning is retained in stderr logs, not hidden
or treated as benchmark output.

## Matched sieve and object workloads

The existing misleadingly named "sieve" workload counts primes <= 5000 by trial
division (669), not an Eratosthenes sieve. Queens exhaustively counts all eight
queens solutions (92), allocating linked placements. Towers moves 13 linked disks
between three pegs (8191 moves), checks every move and final peg contents.
Explicit Cog implementations match those algorithms; image-provided benchmark
methods are not used. Native Nim uses equivalent linked ref objects with ARC.

Milliseconds per pass, paired startup baseline removed:

| Workload | Harding interpreter | Granite | Cog | Native Nim |
|---|---:|---:|---:|---:|
| Trial division | 407.586 | 3.730 | 0.224 | 0.134 |
| Queens, all solutions | 1,826.588 | 223.348 | 1.990 | 0.301 |
| Towers, 13 disks | 268.965 | 57.600 | 0.162 | 0.148 |

Granite is ~109x faster than the interpreter on trial division, ~8.2x on queens,
and ~4.7x on towers. Cog is ~17x, ~112x and ~355x faster than Granite respectively
in this run. These are workload-specific ratios, not general language rankings.
Granite's dynamic object representation, sends and allocation remain substantial
costs; the tight integer loop and object workloads must not be conflated.

The trial-division comparison also includes:

| Engine | ms/pass |
|---|---:|
| C (`gcc -O3`) | 0.086 |
| Node.js 22.23.4 | 0.096 |
| Go 1.27.1 | 0.131 |
| Nim release ARC | 0.134 |
| Cog | 0.224 |
| Ruby 3.2.3 | 1.696 |
| Python 3.12.3 | 2.140 |
| Granite release ARC | 3.730 |
| Harding release ARC | 407.586 |

Repetitions: trial division interpreter 10, Granite 500, Nim/Cog/C/Go/Node 10000,
Ruby/Python 1000; object workloads interpreter 3, Granite 20, Nim/Cog 1000.
Evidence: `build/bench-compare/run-x1qtsi5c/results.json`.
Native/Cog towers is short and particularly noisy: Cog net samples range
~0.108–0.177 ms/pass, Nim ~0.124–0.163; do not rank them from their medians.
Granite queens ranged ~205–246 ms/pass and interpreter queens ~1701–2119.

## Richards and DeltaBlue

`bench_compare_classic.py` mechanically adapts the checked Harding class/method
sources into Smalltalk syntax. It does not use Squeak's unrelated built-in
Richards/DeltaBlue variants. The adaptation retains Richards' arithmetic bit
helpers, task priorities, packet ordering and verification; DeltaBlue retains
its pinned reference's LIFO worklists, strength mapping and planner behavior.
Both retain explicit graph teardown. Cog collection indexing goes through a
zero-based `HBArray` adapter backed by `OrderedCollection` (including fixed-size
packet arrays), which introduces extra dispatch/storage overhead compared with
an idiomatic Smalltalk port. These Cog results are therefore **adapted-port
comparisons**, not peak native-bitwise Richards or idiomatic DeltaBlue scores.

Node runs hash-checked Chromium Octane sources at commit
`570ad1ccfe86e3eecba0636c8f932ac08edec517`, without the Octane scoring harness.
Its native bit operations and lack of explicit ownership teardown differ from
the Harding/Cog adaptations. Node numbers are reference context, not exact port
parity. Benchmarks verify their results on every pass. Generated DeltaBlue
sources retain GPL-2.0-or-later notices and copied license files.

Milliseconds per standard pass, paired startup baseline removed:

| Workload | Harding interpreter | Granite | Cog adapted port | Node reference |
|---|---:|---:|---:|---:|
| Richards, 1,000 idle iterations | 624.363 | 87.450 | 0.565 | 0.120 |
| DeltaBlue, chain/projection 100 | 440.508 | 112.835 | 0.659 | 0.165 |

Repetitions: interpreter 5, Granite 20, adapted Cog/Node 300. Node runs all
repetitions in a single compiled function with stub benchmark-harness registration
and throwing `alert`, not repeated host-to-VM evaluation calls. No Octane suite
scores or calibration loops are used.

Granite is ~7.1x/~3.9x faster than the interpreter for Richards/DeltaBlue, while
adapted Cog is ~155x/~171x faster than Granite. The magnitude merits profiling
Granite's boxed value, dynamic dispatch and allocation paths; these measurements
do not isolate which component dominates. Do not infer that Cog is slower than
Node by these ratios on an idiomatic Smalltalk benchmark: the port adaptations,
array wrapper and reference cleanup policies differ.

Evidence: `build/bench-compare-classic/run-pqj7sq0s/results.json`. The earlier
`run-vp4yyqq0` used a Node `vm` context wrapper and is superseded for comparison.
Both current runners measured runtime revision `18e3728`; only runner/documentation
files were uncommitted. There were no runtime changes between the two runs.
The supplied Squeak image hash matches the recorded disposable copy's initial
hash after testing; no image snapshot was saved.

## Limits and follow-up

This run uses current release ARC builds; it does not repeat all comparisons
under ORC. Both runners accept `--mm orc` for that separate experiment. Full
language-suite correctness is not established by benchmark results. The source
adapter is intentionally restricted to these checked benchmark files, not a
general Harding-to-Smalltalk compiler. Cog/Node smoke runs and seven Python
source-generation regressions accompany the checked timing runs.

For a more precise optimization study, use an otherwise idle host, longer Cog
object batches, a saved benchmark-only Cog image, explicit in-process warm-up,
and retained before/after Granite binaries on the same source. Keep raw startup
and total times: subtraction can amplify noise for short workloads.
