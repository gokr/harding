# Benchmark coverage

The three classic workloads (richards, deltablue, queens) are graph and
arithmetic code from the 1990s benchmarks suite. They are useful, but they are not
representative of what Granite's specialization actually targets, and that caused a
repeated measurement problem in this worktree: four separate slices measured 0% on
those three while measuring 80%+ on their own shape, because the shapes did not
occur there at all.

Two benchmarks were added to close that gap. Both are ordinary Harding programs, not
code shaped to flatter the compiler, and both assert their own answer so a wrong
result cannot be timed.

## `benchmark/shapes.hrd` — polymorphic dispatch

A heterogeneous collection (`Circle`, `Rect`, `Square` (a `Rect` subclass),
`Triangle`, `Ellipse`) behind one `Shape` protocol, driven through a single send site
per message. Exercises: polymorphic dispatch on one site with 5-6 receiver classes,
superclass sharing, a subclass overriding its parent, and both Symbol and String
results from the same protocol.

Measured region repeats the whole protocol 200 times per pass, so dispatch dominates
setup rather than the reverse. Expected `178000` per pass.

## `benchmark/tree.hrd` — object graphs and boxed call boundaries

Builds a 2047-node binary tree, then walks it three ways: a sum that passes the node
as an argument and returns Integers, a depth recursion returning Integers, and a leaf
count. Exercises: object arguments crossing method boundaries, object returns,
recursive sends, and nil-terminated child slots.

Expected `10227` per pass.

## Why these two, and what they showed

They are the two structures the classic set lacks: many receiver classes at one send
site, and objects crossing call boundaries repeatedly.

First measurement, current worktree against `main` (`5d8f750`), pinned, alternating,
answers checked every run:

| Benchmark | main | current | Change | Pairs |
|---|---:|---:|---:|---:|
| shapes (200 dispatches/pass) | 7.16 ms | 5.25 ms | **28.38% faster** | 8/8 |
| tree (depth 11, 3 walks) | 14.88 ms | 6.85 ms | **49.86% faster** | 8/8 |

Both unanimous. The same tree of work measured as 0% or negative on
richards/deltablue/queens. That is the whole argument for adding them: the engine
work was real, and the old corpus could not see it.

Against CPython 3.12.3 on the same host, same pinned policy:

| Benchmark | Granite | CPython | Ratio |
|---|---:|---:|---:|
| shapes | 7.8 ms | 29.0 ms | **0.27x** (Granite ~3.7x faster) |
| tree | 72.4 ms | 25.8 ms | 2.81x (Granite slower) |

The split is informative rather than a scoreboard: Granite is much faster than
CPython where dispatch dominates and the work per send is small, and still slower
where each node visit allocates and the call boundary boxes. That is exactly the
remaining target listed as native parameters and returns.

## Native Nim references (the floor)

Each added benchmark has a hand-written Nim port in `benchmark/native/`, matching the
existing richards/deltablue convention: idiomatic Nim, `ref object` hierarchies,
`paramStr(1)` repetitions, the same asserted answer, and the same printed output.

These exist to give an aim and a floor: they are what the same protocol costs when
every call is a native method call on a native field. They are representation
references, not semantics oracles -- they are hand written, and their existence says
nothing about what the Harding source must compile to. Compare trends, not exact
multipliers.

Pinned, alternating, answers checked on every run, 20 passes:

| Benchmark | Granite | Native Nim | Granite/Native |
|---|---:|---:|---:|
| shapes | 0.989 ms | 0.071 ms | **13.90x** |
| tree | 4.424 ms | 0.092 ms | **48.01x** |

Through the routine harness at 50 passes (`scripts/bench_compare_native_nim.py`),
which subtracts startup differently and includes CPython:

| Benchmark | Granite | CPython | Native Nim | Granite/Native | CPython/Native |
|---|---:|---:|---:|---:|---:|
| shapes | 0.957 ms | 0.346 ms | 0.035 ms | 26.53x | 9.78x |
| tree | 4.347 ms | 1.591 ms | 0.036 ms | 118.36x | 44.33x |

Reading these honestly: on `shapes`, Granite is ~2.7x further from native than CPython
is (26.53 / 9.78). On `tree` it is ~2.7x further as well (118.36 / 44.33). That is a
more useful statement than either ratio alone, and it says the remaining gap is the
same order of magnitude on both new workloads rather than concentrated in dispatch.

The absolute floors also show the headroom plainly: native `tree` is ~0.04 ms/pass
while Granite is ~4.3 ms/pass. The traversal itself is trivial; what costs 100x is
representing and passing objects.

## Where they run

Both are now part of the routine tooling rather than ad-hoc scripts:

- `scripts/profile_granite.py` retains checked release binaries and pinned paired
  comparisons for all five cases. It also gained an optional case subset
  (`profile_granite.py shapes tree`), and refuses to compare a subset against a
  baseline run that does not contain those cases.
- `scripts/bench_compare_python_pinned.py` times them against CPython, using
  mechanical Python ports in `scripts/python_benchmark_source.py`.
- `scripts/bench_compare_native_nim.py` times them against the hand-written Nim
  ports, iterating whichever of its known cases the retained run contains.
- `tests/test_profile_granite.py` pins the expected answers and checks the snapshots
  are the checked sources with no synthesis; it also reads the expected value back
  from the interpreter instead of trusting the constant.
- `tests/test_python_pinned_runner.py` runs each Python port and the Harding source
  and requires both to print the same answer, so a drifting port cannot quietly
  make the comparison meaningless. It does the same for the native Nim ports, for
  zero, one and two passes, including a zero-pass run so the harness's startup
  subtraction is exercised.

## Adding a benchmark

1. Write the program in ordinary Harding. Assert the expected answer so the harness
   cannot time a wrong result.
2. Read the expected value from the interpreter, never by hand. Three hand-derived
   values in this file's own history were wrong; the interpreter was right.
3. Build both sides from the *same* source snapshot with the *same* flags.
   `scripts/profile_granite.py` synthesises its own Queens driver, and comparing a
   direct `granite build` of `benchmark/queens.hrd` against a profiler run compares
   one iteration with thirty.
4. Take pinned alternating pairs on an idle machine, and check the pair count as
   well as the percentage. A concurrent compile once produced a 3/31 result that
   read as a regression and became 5/31 noise when repeated quietly.
