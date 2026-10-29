# DeltaBlue Harding port

## Source and licensing

`benchmark/deltablue.hrd` adapts Chromium Octane's `deltablue.js` at commit
`570ad1ccfe86e3eecba0636c8f932ac08edec517`:

https://github.com/chromium/octane/blob/570ad1ccfe86e3eecba0636c8f932ac08edec517/deltablue.js

Reference SHA-256:
`6c4784e82f3e8f5c18306d289653d08b17b38838f1bac16b38611d7318fa5a36`.

The benchmark is **GPL-2.0-or-later**, separately from Harding's repository
default license. Copyright notices, attribution and modifications are recorded
in `benchmark/licenses/DELTABLUE.txt`; the full GPL v2 text is in
`benchmark/licenses/GPL-2.0.txt`. The source credits John Maloney, Mario Wolczko
and the V8 project authors. The conformance fixture is also GPL-2.0-or-later.
Merely including this separately licensed source does not relicense unrelated
repository files. Anyone distributing a linked benchmark binary must assess and
meet GPL corresponding-source requirements and the runtime's applicable terms;
this repository grants no special linking exception. Test binaries are built
locally under `build/`, not shipped as a release artifact.

## Algorithm and adaptations

The port retains the reference's incremental constraint graph, strength objects,
unary stay/edit constraints, binary equality/scale constraints, planner marks,
direction selection, stay optimization and extracted execution plans. The
standard run creates 100 equality constraints over 101 chain variables, executes
100 edits, then exercises a 100-pair projection with source, destination, scale
and offset changes (ten plan executions per change).

The pinned source contains unusual behavior which this port deliberately
preserves rather than silently substituting another DeltaBlue variant:

- `OrderedCollection.removeFirst` uses JavaScript `pop()`: worklists are LIFO.
- `nextWeaker` maps ranks 0..5 to 6, 5, 4, 3, 2, 0. Thus removal's initial
  required-to-weakest transition ends that resatisfaction traversal immediately.
- Binary direction selection uses consecutive conditionals, not early returns.
- The final projection checks all but the last destination; the last remains
  edit-determined at 1050 in the reference, while the other destinations become
  `index * 5 + 2000`.

Harding-specific adaptations:

- `DB`-prefixed classes and explicit per-graph planner references instead of a
  global planner; ordinary methods and inheritance, no application Nim code.
- Graph ownership registries and `dispose` break planner/constraint/variable
  reference cycles after each workload, including on errors. Cleanup is included
  in timings. Registries retain removed constraints until workload teardown.
- `Error signal:` replaces JavaScript browser `alert` failures.
- Projection checks use absolute tolerance < 0.000001, since Harding distinguishes
  Integer and Float equality whereas JavaScript uses one numeric representation.
  Division still uses `/`, including backward fractional projections.
- Identity inequality is written `(left == right) not`, using the existing
  interpreter protocol rather than inventing a selector.

This is a faithful port of the pinned Octane variant, not a claim that every
historical DeltaBlue variant shares these behaviors.

## Execution and checks

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
./harding benchmark/deltablue.hrd
./granite build --release benchmark/deltablue.hrd \
  --dir:build/deltablue -o:build/deltablue/deltablue
./build/deltablue/deltablue
nimble testDeltaBlue
python3 scripts/audit_examples.py benchmark-deltablue --strict --timeout 180
```

An optional nonnegative argument selects complete standard repetitions (default
1). Every run verifies chain/projection results; stdout says `DeltaBlue runs=N
verified`. Zero is a startup/source-loading baseline; negative/nonnumeric inputs
fail. No solver work is replaced by precomputed answers.

The shared `tests/deltablue_checks.hrd` fixture executes in release interpreter
and Granite binaries under ARC and ORC. It checks collection identity/removal,
reference strength transitions, extracted plans, reverse propagation, constraint
removal, fractional reverse projection, required-constraint and cycle rejection,
graph cleanup, chain sizes 0/1/2/10/100,
projection sizes 1/2/10/100 and repeated standard runs. Expected projection sums
are 1050, 3050, 19230 and 223305 respectively. These expectations were checked by
executing the pinned JavaScript in Node, not inferred from the Harding result.
Driver checks exercise default/zero/repeated runs and rejected arguments.

## Performance measurements

```sh
python3 scripts/bench_deltablue.py --mm arc --repetitions 10 --trials 5
python3 scripts/bench_deltablue.py --mm orc --repetitions 10 --trials 5
```

This entry uses the same checked release-engine harness as Richards. It builds
release engines before timing, snapshots application source, records CPU/OS,
compiler versions, revision/dirty state, source/binary hashes and raw samples,
and alternates engine/work/baseline ordering. One checked warm-up pair is
excluded. Each observation is a fresh process, including bootstrap/source loading
for the interpreter. Paired zero-run subtraction is approximate; raw totals and
medians remain available in `build/deltablue-bench/run-*/results.json`.
Run on an otherwise idle host. These are Harding-port timings, not Octane scores;
planner ownership, cleanup and numeric checks are included.

Initial local release observations (Intel Core Ultra 7 165U, Linux x86-64,
Nim 2.2.12, GCC 13.3.0, five measured pairs of ten standard repetitions):

| Memory manager / engine | Median total, 10 runs | Median zero-run baseline | Median paired net per run |
|---|---:|---:|---:|
| ARC interpreter | 4,671.774 ms | 113.214 ms | 456.363 ms |
| ARC Granite | 1,059.811 ms | 1.181 ms | 105.861 ms |
| ORC interpreter | 4,659.485 ms | 121.903 ms | 452.426 ms |
| ORC Granite | 1,131.366 ms | 1.443 ms | 112.975 ms |

Artifacts: `run-c4iq3cxn` (ARC), `run-rp0yesjd` (ORC), parent revision `ddf75df`.
Reports include the then-uncommitted benchmark source hashes and dirty state.
Native ten-run totals ranged from ~1,041 to ~1,264 ms (ARC) and ~1,081 to
~1,446 ms (ORC); interpreter totals ranged from ~4,291 to ~5,127 ms (ARC) and
~4,382 to ~5,314 ms (ORC). These are noisy initial local baselines, not a reliable
ranking of memory managers. The paired net median need not equal the difference
of separate total and baseline medians.
