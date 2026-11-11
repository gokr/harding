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
