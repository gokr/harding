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

## Second slice: exception-class ancestry guard

Re-profiling at `d7b1328` showed the first cache had removed most hierarchy
walks, but one caller still dominated: `isCompiledExceptionClass` ran a whole
graph traversal on nearly every send, because ordinary sends reached it before
any fast rejection. On Queens it accounted for 10,398,511 of 10,398,524 walks.

Two graph-independent corrections, no semantic change:

- `signal:` is now tested before the ancestry predicate. A class can only enter
  the built-in exception protocol for `signal:`, so other selectors never pay for
  the lookup.
- The ancestry answer is cached in a bounded thread-local table keyed by class
  name and invalidated by `compiledClassDispatchVersion`, like the resolution
  cache. It stores booleans, not class or receiver references.

Profiled counts for thirty checked repetitions:

| Workload | Hierarchy walks before | After | Raw allocator calls before | After |
|---|---:|---:|---:|---:|
| Richards | 2,982,341 | 14,986 | 46,682,638 | 34,417,771 |
| DeltaBlue | 4,299,795 | 96,653 | 63,399,751 | 42,494,180 |
| Queens | 10,398,524 | 15 | 144,377,631 | 102,783,598 |

Paired uninstrumented ARC trials against retained `d7b1328` binaries, same
methodology (seven measured alternating trials, thirty checked passes each):

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 64.665 | 52.643 | 1.228x | ~18.6% |
| DeltaBlue | 94.866 | 70.212 | 1.351x | ~26.0% |
| Queens | 185.194 | 152.419 | 1.215x | ~17.7% |

The baseline in this table is the retained `run-ua7weblb` binaries, whose
medians in that run were 66.94/96.24/203.61 ms. A separate slice-one baseline
measured different absolute times; compare within a paired table only.

Evidence: `build/granite-profiles/run-ua7weblb` (baseline),
`run-21l77yc5` (paired comparison), `run-a2wno529` (post-change profiles).

Validation for this slice: `test_compiled_runtime` (42 tests, ARC and ORC),
including new cases for a cached non-exception answer that must be invalidated by
adding an `Exception` parent and for a class-side `signal:` method on an ordinary
class. Engine-boundary, reentrant-return, block-lifetime, compiled-support and
base-allocation suites run under ARC and ORC. Richards and DeltaBlue two-engine
conformance, the 102-case parity sweep, and GTK acceptance are re-run for the
combined change set.

## Third slice: closure allocation in bound-host lookup

Profiling at `d56287c` showed `boundClassFor` at ~15% of Queens time with
39,553,086 calls. Raw allocator counts had risen while hierarchy walks fell, and
Queens was allocating 102.8M objects for a benchmark that mainly builds linked
placements.

The cause was structural, not a cache miss: `boundClassFor` tested
`boundCompiledClasses.len == 0` for an early return, but defined its traversal as
a nested proc capturing `visited`. Nim therefore allocated a closure environment
on entry to every call — 39.5M allocations, all discarded unread by the early
return in a pure compiled program.

The traversal became a top-level proc taking `visited` as a `var` parameter, and
the guard is `{.inline.}`. Traversal order, the cycle guard and the early return
are unchanged; only the closure allocation is removed.

Profiled counts for thirty checked repetitions:

| Workload | Raw allocator calls before | After | `nimNewObj` before | After |
|---|---:|---:|---:|---:|
| Richards | 34,417,771 | 24,483,763 | 19,559,649 | 9,625,641 |
| DeltaBlue | 42,494,180 | 28,334,090 | 29,166,890 | 15,006,800 |
| Queens | 102,783,598 | 63,230,512 | 73,794,835 | 34,241,749 |

`boundClassFor` no longer appears in the flat profile.

Paired uninstrumented ARC trials against retained `d56287c` binaries, seven
measured alternating trials, thirty checked passes each:

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 49.273 | 45.190 | 1.090x | ~8.3% |
| DeltaBlue | 70.699 | 60.862 | 1.162x | ~13.9% |
| Queens | 153.014 | 130.311 | 1.174x | ~14.8% |

Richards gains least because its remaining cost is dominated by hashing and
allocation elsewhere, which this slice does not address.

Evidence: `build/granite-profiles/run-2obisa53` (baseline),
`run-f0lkjgd9` (paired comparison), `run-lkztylzf` (post-change profiles).

## Cumulative position

Paired measurements accumulate but are not one continuous run, and each table
uses its own baseline; do not sum the percentages. The same-session
`run-2obisa53` baseline and these post-change medians indicate roughly:

| Workload | At `732716d` | Current |
|---|---:|---:|
| Richards | ~64.7 ms | ~45.2 ms |
| DeltaBlue | ~94.9 ms | ~60.9 ms |
| Queens | ~185.2 ms | ~130.3 ms |

Order-of-magnitude gaps to Cog from the earlier comparison (roughly 0.57/0.66/
0.16 ms for adapted Richards/DeltaBlue/Towers and 1.99 ms for Queens) remain
large. Production-quality value representation (unboxing), allocation strategy
and slot dispatch are still unaddressed; they are larger, riskier changes than
the three mechanical slices above and need separate agreement.
