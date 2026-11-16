# AWFY cross-engine comparison

`scripts/bench_compare_awfy.py` times the AWFY ports from
`benchmark/awfy/` against CPython and, where the port translates, GNU Smalltalk.
It reports paired zero-work-subtracted milliseconds per pass, using the same
methodology as `scripts/bench_compare_practical.py` (warmup trial, alternating
engine order per trial, alternating repeats/zero order within a trial, median of
per-trial paired differences).

## The workloads are upstream's

Every port is pinned to AWFY revision `74306fec151070fd07157cefeacf19e7e0bcdc89`.
Each port's `upstream/provenance.json` records a SHA-256 for every vendored file
and the upstream path it came from; `tests/test_awfy_compare.py` re-verifies those
digests, so a drifted vendored source fails the suite instead of silently timing
a different program.

What each engine actually runs:

| Engine | Source |
|---|---|
| Granite | the port's own `.hrd` program under `benchmark/awfy/<case>/` (the same source `tests/test_awfy_<case>.py` checks) |
| CPython | upstream's own Python port (`upstream/benchmarks/Python/`), driven by a local counted loop only |
| GNU Smalltalk | a spelling translation of the same Harding program (`scripts/awfy_gst.py`) |

## What is compared, and what is not

| Case | Granite | CPython | GNU Smalltalk |
|---|---|---|---|
| Bounce | yes | yes | yes |
| Json | yes | yes | **not covered** |
| Havlak | yes | yes | **not covered** |

The two gaps are stated rather than papered over:

- **Json's GNU Smalltalk gap.** The port's fixture and checks are escape-heavy
  string literals (`\"`, `\\n`, `\\\\`). GST strings have no escapes at all, so
  receiving that data needs a real Harding-to-GST compiler rather than a spelling
  translation. Emitting an approximation risked comparing a different program, so
  it is reported as uncovered.
- **Havlak's GNU Smalltalk gap.** Havlak's algorithm is written against SOM's
  `Core` collections (`Vector`, `SomIdentityDictionary`, `SomIdentitySet`). The
  adapter does not translate those, and substituting Harding's `Array`/`Table`
  would compare a different data structure, not a different spelling.

## Honesty rules the script enforces

- A run that exits non-zero, writes to stderr, or fails verification is a hard
  failure. It is never recorded as a score, and the script aborts rather than
  publishing a partial table.
- Every timed run is answer-checked: Bounce must print `1331`, Json must print
  `AWFY Json checks passed`, Havlak's own verifier must accept the graph.
- The zero-work baseline is the same program with the driver loop bounded at
  zero, so process startup and class initialization are measured and subtracted
  rather than estimated. A baseline that prints anything fails.
- Below-timing-resolution results raise instead of producing a fake ratio.
- Host load is recorded in `results.json` at start and belongs in any report.

## Running it

```sh
python3 -B scripts/bench_compare_awfy.py --trials 7
python3 -B scripts/bench_compare_awfy.py --trials 7 --skip-gst
python3 -B scripts/bench_compare_awfy.py --trials 7 --cases json
```

GNU Smalltalk is optional; `--skip-gst` omits it explicitly (it is never silently
dropped). Artifacts land under `build/awfy-compare/run-*/`, and the summary is
written to `results.json` there.

Repetition counts live in `scripts/awfy_engines.py` and differ per engine because
constant factors differ by orders of magnitude; timing is always reported per
pass, so the counts do not affect the unit.

## Cog and Oil (Squeak) runs

`scripts/bench_compare_oil.py` also times these three workloads on the pinned
Cog and Oil VMs:

```sh
python3 scripts/bench_compare_oil.py bounce json havlak --trials 7
```

This is a separate adapter, because Cog cannot run the Harding ports: it loads
AWFY upstream's own Smalltalk sources (`benchmark/awfy/smalltalk/upstream/`,
same pinned revision, per-file SHA-256 in its `provenance.json`) through
upstream's own SOM loader (`SomLoader-Compiler.st`). The only additions are
image-compatibility selectors taken from upstream's `build-image-squeak.st`
plus three replacements for Pharo-only APIs: `SomParser textStreamCls`
(`ReadWriteStream`), a file-reading `sourceOfClassFile:`, and a
`loadFiles:` that takes an explicit file list instead of walking with
`FileReference`.

Two consequences must be stated whenever these numbers are reported:

- The workload is upstream's, not the Harding port's. Upstream Json verifies its
own fixture (an object whose `operations` array has 156 entries); the port's
`JsonChecks` parser assertions are not run on Cog.
- GNU Smalltalk is not covered here either; the comparison is Cog vs Oil on the
  same image, image adapters and repetition count.

Repetition counts are per case (`bounce` 2000, `json` 200, `havlak` 1 — its
checked full-size graph), because a single count would measure startup for one
workload and skip too little work for another. Every timed run verifies its
answer, and the zero-work baseline is the same program with a zero bound.

`tests/test_oil_benchmarks.py` re-verifies the vendored digests, checks the
driver contract, and (with local VMs) executes all three workloads at 0, 1 and 3
repetitions on both VMs plus a deliberately failing verification.

## Reading the numbers

Bounce is a deliberately small AWFY workload (100 balls, 50 updates). Its
per-pass time is a few milliseconds, which means fixed per-pass costs — object
allocation and dispatch setup — dominate. A slower-than-CPython result on Bounce
should be read as "this workload is too small to demonstrate anything about
throughput" rather than as a compiler verdict; the larger AWFY cases are the
honest comparators. Never present an instrumented or profiled build's time as a
score.
