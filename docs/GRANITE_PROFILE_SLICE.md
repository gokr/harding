# Granite profiling: bounded instance-method resolution cache

Baseline runtime revision: `732716d`. Scope: a single runtime optimization;
no benchmark-specific specialization or language-semantic changes.

## Profiles

`perf` could not access even `task-clock` with this host's
`perf_event_paranoid=4`. No kernel settings or privileges were changed. Release
ARC binaries were built with GCC `-pg` and inspected with `gprof`; uninstrumented
release binaries were retained separately for timing.

Thirty verified repetitions of Richards, DeltaBlue and exhaustive Queens show
allocation, string hashing, hierarchy traversal and dynamic dispatch as material
costs. Baseline flat profiles put string hashing at ~7–9% self samples and raw
allocation at ~7–10%. This is sampling evidence, not precise attribution:
profiling instrumentation changes runtime costs, allocator counts include
runtime temporaries, and gprof's inferred inclusive costs are not independent
measurements.

## Change

Native instance-method resolution now uses a thread-local table keyed by
`(lookup start class name, selector)`:

- Positive and negative results are reused by generic instance dispatch,
  method-existence checks, and monomorphic send-cache misses.
- A mismatch with `compiledClassDispatchVersion` clears the table before lookup.
  Supported method/class/hierarchy registration paths already increment it.
- The table clears at 4,096 entries, preventing arbitrary selector traffic from
  growing it without bound. It retains names/procedure values, not receivers.
- Live interpreted lookup still occurs before cached native dispatch. Warm native
  entries do not mask interpreted replacement or runtime-subclass overrides.
- Lookup start class remains part of the key, preserving explicit super sends,
  multiple-parent declaration order and cyclic-graph termination.
- Class-side method resolution is unchanged. No thread-safety promise is added
  for concurrent mutation of the existing process-global registries. Direct
  writes to exported registry tables bypassing registration/versioning remain
  unsupported, as they were for the pre-existing monomorphic send caches.

The cache trades additional hash lookups and a bounded table for fewer hierarchy
walks and temporary allocations. Profiled counts before/after, thirty repetitions:

| Workload | Hierarchy walks before | After | Raw allocator calls before | After |
|---|---:|---:|---:|---:|
| Richards | 8,199,792 | 2,982,341 | 66,668,391 | 46,682,638 |
| DeltaBlue | 12,584,668 | 4,299,795 | 98,468,749 | 63,399,751 |
| Queens | 28,806,365 | 10,398,524 | 215,086,482 | 144,377,631 |

Hierarchy walks drop ~64–66%, allocator calls ~30–36%. Hash calls increase
slightly; this is not an elimination of hashing or allocation overhead.

## Paired uninstrumented measurements

Same generated Nim source and build flags for each before/after pair:
Nim 2.2.12, GCC 13.3.0, `-d:release --mm:arc`, Intel Core Ultra 7 165U, Linux
x86-64. Seven measured alternating trials, thirty passes per process; one checked
warm-up per variant discarded. Output and stderr were checked every run. Process
wall-time medians divided by 30 (no startup subtraction):

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 84.499 | 69.744 | 1.212x | ~17.5% |
| DeltaBlue | 119.871 | 97.629 | 1.228x | ~18.6% |
| Queens | 231.525 | 194.961 | 1.188x | ~15.8% |

Host load was not isolated. Before/after ranges overlap (Richards before
~70–134 ms, after ~61–93 ms); these are initial paired observations, not exact
portable speedups. All seven Queens and DeltaBlue paired observations improved;
Richards improved in six of seven. Do not compare their absolute times directly
with the earlier Cog table from another run. This reduces part of the measured
cost, but the large Cog gap remains.

Evidence under `build/granite-profile-slice/`: `manifest.json` (source hashes and
baseline revision), per-case `before`/`after` binaries, `gprof.stdout`,
`after-gprof.stdout`, generated Nim, checked outputs and `paired-results.json`.
Scratch drivers: `build/profile_granite_slice.py`,
`build/measure_resolution_cache.py`, `build/profile_resolution_after.py`.

Reusable runner for future slices:

```sh
# Before editing runtime code; retains uninstrumented baseline and optional gprof:
python3 scripts/profile_granite.py --profile --mm arc
# After editing; supply the printed previous artifact directory:
python3 scripts/profile_granite.py --compare build/granite-profiles/run-BASE --mm arc
```

The reusable runner snapshots sources, checks retained binary hashes, records
revision/toolchain/dirty state, and alternates timing order. Profile and timing
binaries are separate. It is not a benchmark score or a permission workaround.
The runner's profile and comparison modes were exercised with checked one-pass
smoke runs (`run-lfep6w7d`, `run-pc4b990g`). Their short, noisy timings are not
used as optimization evidence; the table above uses the retained thirty-pass
before/after binaries.

## Validation and remaining work

Focused runtime tests exercise late method installation after a negative lookup,
method replacement, parent-order changes, explicit-super starts, cycles,
capacity clearing, initializer installation after a cached miss, nil results,
reentrancy and evaluation-once behavior. Existing engine-boundary suites check
interpreted replacements and subclass overrides after native cache warming.
Runtime/support/boundary/reentrant-return/block-lifetime/base-allocation suites
pass under ARC and ORC (40/10/34/16/15/2 tests respectively).
Richards and DeltaBlue both-engine ARC/ORC conformance tasks pass, as do thirteen
focused executed parity cases. Four real GTK accessibility acceptances also
pass (both engines under ARC/ORC), alongside backend cleanup/package checks.
This is not a complete suite pass.

The first freeze conformance sweep encountered a shared default Nim-cache linker
collision on `class_factory` while another parity sweep built the same module
name. Its log records undefined type-info symbols, not a Harding result mismatch.
The diagnosed rerun uses isolated per-invocation Nim caches; evidence is recorded
under `build/resolution-frozen-isolated.log` (12/12 declared conformance cases
passed) and `build/resolution-frozen-build-isolated.log` (separate build tests).
Do not infer freeze success from the failed initial gate. The wider parity
sweep runs in batches with progress recorded in
`build/resolution-parity-batches.json`; the log, not a task exit alone, determines
which cases completed.

The next slice should re-profile before choosing another target. Remaining
hashing, slot-access lookup and allocation are visible candidates, not yet
measured optimization results. Keep bound host lookup and live-layout checks;
do not remove them merely because pure-native benchmarks do not use them.
