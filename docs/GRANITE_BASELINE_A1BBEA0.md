# Granite current baseline: a1bbea0

Measured revision `a1bbea0e30767c15331cf91df85427c46d6a81b3`, clean
checkout, Linux x86-64, Intel Core Ultra 7 165U, Nim 2.2.12, GCC 13.3.0,
release ARC. This is a baseline, not a before/after performance claim. The host
was not isolated or CPU-pinned. Results, exact sources, binary hashes, compiler
logs, profiles and per-trial samples: `build/granite-profiles/run-d6ig3mm_`.

## Checked object workloads

`python3 scripts/profile_granite.py --profile --mm arc --repetitions 30
--trials 7` builds separate profiled and uninstrumented binaries, verifies every
run, discards one warmup, and reports wall time divided by 30. No startup
subtraction was applied.

| Workload | Median ms/pass | Seven-trial range ms/pass | Binary bytes |
|---|---:|---:|---:|
| Richards | 36.58 | 34.57–37.74 | 3,536,904 |
| DeltaBlue | 32.21 | 31.31–33.70 | 3,775,376 |
| Queens | 109.77 | 104.35–113.06 | 3,116,160 |

Gprof reports ~0.56/0.63/1.81 seconds of sampled self time over 30 passes;
flat percentages are coarse, instrumented observations, not wall-time attribution.
Richards shows `resolveCompiledMethod` 12.5%, string hashing 10.7%; DeltaBlue
shows `newSeqPayload` 9.5%, hashing 7.9%; Queens shows the workload's
`canPlaceRow:column:after:` 17.1%, `boundInterpretedSend` 8.8%, table lookup
7.7%, `sendMessage` 6.1% and method resolution 5.5%. Inclusive costs overlap.
Profiled calls over 30 passes include ~3.38M/2.90M/16.59M resolution calls
(Richards/DeltaBlue/Queens), ~10.22M/11.53M/26.78M raw allocations and
~6.07M/7.31M sequence payload allocations for Richards/DeltaBlue. Counts
include all runtime uses, not just dispatch.

The opt-in specialization probe was run against these same answer-checked
release binaries. Own-class dispatches with all-Integer arguments were 723,810
of 1,221,150 (59.3%) for Richards and 1,473,360 of 1,731,307 (85.1%) for
DeltaBlue; Queens had 30 of 595,020. Inherited-unique traffic includes 577,957
all-Integer calls in DeltaBlue. The probe excludes paths that bypass it, and
eligible calls are not measured savings. Logs sit beside each binary as
`specialization-probe.stderr`.

## Collection and application checks

`scripts/bench_compare_awfy.py --skip-gst --cases json --trials 3 --mm arc`
uses verified AWFY JSON checks, one warmup and alternating paired work/zero-work
processes. Granite median is 105.89 ms/pass (range 103.14–109.87); CPython
3.12.3 is 9.94 ms/pass (8.35–11.37). These are workload-specific startup-
subtracted numbers, not general language speed ratios. GST was explicitly
skipped. Artifact: `build/awfy-compare/run-w8fe35mq/results.json`.

Notebook's non-GTK model self-test was compiled with the retained release
Granite and compared byte-for-byte with a release interpreter: both matched.
Seven checked native process runs had median 1.80 ms (range 1.53–2.39), including
startup; binary size was 3,629,600 bytes. This tiny self-test is dominated by
startup/noise, not a GUI acceptance or throughput benchmark. Evidence:
`build/notebook-baseline/results.json` and `build/notebook-baseline-*.log`.

## Candidate and correctness gates

A measured candidate is reducing generic send/argument overhead. An initial
bounded experiment should target an existing common send path, keep live bound
host dispatch and registry-version invalidation, and avoid a second implementation
of any Harding method. Measure it against the retained binaries using
`python3 scripts/profile_granite.py --compare build/granite-profiles/run-d6ig3mm_`
with matching memory manager and checked results. Re-profile and attribute counts;
do not assume all sequence allocation or hashing comes from the candidate.

Separately, source-index inventory currently reports zero declared primitive gaps
for loaded core/standard, but is not an audit of selector-specific fallbacks,
optimized sends, VM-only registrations or optional libraries. Preserve source
method semantics, overrides, side effects, inheritance, error/cleanup behavior and
ARC/ORC boundary ownership when changing dispatch. Existing test-task exit codes
may mask failures; inspect focused suites and executed parity results directly.
