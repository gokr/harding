# Richards: reference, conformance and measurements

## Reference and port

`benchmark/richards.hrd` ports Chromium Octane's `richards.js` at commit
`570ad1ccfe86e3eecba0636c8f932ac08edec517`:

https://github.com/chromium/octane/blob/570ad1ccfe86e3eecba0636c8f932ac08edec517/richards.js

Reference source SHA-256:
`1246a64a24b931158bf01c24640343259fa74b0226e73bad630bd1f686aa0fa7`.
The source-file BSD-3-Clause notice is retained in
`benchmark/licenses/RICHARDS.txt`; include that notice when distributing the
benchmark or its binaries. The reference credits Martin Richards' BCPL benchmark.
This is not a translation of the differently licensed AWFY/Sun implementation.

The port preserves:

- Six tasks and IDs: idle (0), worker (1), handlers (2/3), devices (4/5).
- Priorities 0, 1000, 2000, 3000, 4000, 5000; priority-driven dispatch.
- Two initial work packets and three packets per device; four-word payloads.
- Linked FIFO packet queues, packet identity rewrites and task state transitions.
- Alternating worker destinations, payload values 1–26 and idle control seed 1.
- The standard Octane workload: 1,000 idle iterations, 2,322 queues and 928 holds.

No precomputed results replace task execution. Harding currently lacks integer
bitwise methods, so benchmark-local arithmetic implements state-bit operations
and 16-bit XOR with 53256. These helpers run in both engines and their cost is
included. This changes instruction mix relative to JavaScript/native-bitwise
ports; timings must not be presented as Octane scores or direct cross-language
Richards comparisons. This benchmark simulates dispatch itself, not Harding's
green-thread scheduler.

Class names are prefixed with `Richards`. `dispose` breaks task-to-scheduler
cycles after each verified sample (also on verification failure), outside the
scheduler algorithm but inside the measured workload. Method arguments avoid
slot shadowing; receiver slot reads use ordinary Harding lexical semantics.

## Run and validate

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
./harding benchmark/richards.hrd
./granite build --release benchmark/richards.hrd \
  --dir:build/richards -o:build/richards/richards
./build/richards/richards
# Three independent verified runs:
./harding benchmark/richards.hrd -- 3
./build/richards/richards 3
nimble testRichards
python3 scripts/audit_examples.py benchmark-richards --strict --timeout 180
```

The optional argument is a nonnegative number of complete benchmark repetitions,
not an idle-iteration count. Every repetition verifies the standard counters;
stdout reports their sums. Zero repetitions provides a startup/source-loading
baseline. Negative or nonnumeric arguments fail explicitly.

`testRichards` builds release ARC and ORC interpreters and native binaries, then
executes the same `tests/richards_checks.hrd` in both engines. It checks all eight
task states, FIFO append/priority behavior, XOR helper vectors, repeated runs and
cleanup, verification failure, default/repeated/zero driver behavior and invalid
arguments. Nonstandard idle workloads have independently checked reference
counters obtained by executing the pinned JavaScript in Node (not by copying
results from Harding):

| Idle iterations | Queued packets | Holds |
|---:|---:|---:|
| 1 | 8 | 3 |
| 2 | 12 | 4 |
| 10 | 31 | 12 |
| 100 | 239 | 95 |
| 1,000 | 2,322 | 928 |
| 10,000 | 23,246 | 9,297 |

## Release measurements

```sh
python3 scripts/bench_richards.py --mm arc --repetitions 10 --trials 5
python3 scripts/bench_richards.py --mm orc --repetitions 10 --trials 5
```

The runner builds release interpreter/compiler/native binaries before timing,
snapshots application source, verifies stdout/stderr on every observation, checks
and excludes one warm-up pair, and alternates engine/work/baseline order.
Each observation is a fresh process. It records raw wall-clock samples, medians,
source/binary hashes, revision/dirty state, build commands, CPU/OS and compiler
versions in `build/richards-bench/run-*/results.json`. No performance threshold is
used. Run on an otherwise idle host; compiler execution is not timed.

Initial local observations (Intel Core Ultra 7 165U, Linux x86-64, Nim 2.2.12,
GCC 13.3.0, `-d:release`, five measured pairs of ten standard repetitions):

| Memory manager / engine | Median total, 10 runs | Median zero-run baseline | Median paired net per run |
|---|---:|---:|---:|
| ARC interpreter | 8,720.491 ms | 185.919 ms | 853.457 ms |
| ARC Granite | 1,398.375 ms | 1.396 ms | 139.695 ms |
| ORC interpreter | 8,149.601 ms | 190.344 ms | 791.673 ms |
| ORC Granite | 1,355.704 ms | 1.927 ms | 135.378 ms |

Artifacts: `run-t3t9wivu` (ARC), `run-he1wr8uv` (ORC). Toolchain parent revision:
`88ba4ad`; the report records the then-uncommitted Richards files and their hashes.
These samples are noisy: ARC native totals ranged from ~1,035 to ~1,849 ms;
ORC native totals from ~1,019 to ~1,565 ms. Treat them as initial local baselines,
not a stable ranking of memory managers. Startup subtraction is approximate;
paired net medians need not equal the difference of the two separate medians.
Raw totals include process startup and, for the interpreter, bootstrap and source
loading. Native execution needs no source files or separate Harding executable.
