# Portfolio stress showcase

`examples/compiler/portfolio_stress.hrd` constructs a portfolio from JSON, creates
polymorphic cash/equity/bond positions through an inherited class-side factory,
and prices deterministic integer-cent shock scenarios. It exercises inherited
slots, overridden methods and `super`, dynamic class receivers, `collect:`/`do:`,
`perform:`, ancestry checks, a non-local return from iteration, an escaped mutable
counter closure, handled errors with `ensure:`, and JSON report serialization.
It uses no interpreter fallback, network, clock or randomness.

## Build and run

From the repository root (Nim 2.2.12):

```sh
nimble harding_release
nim c -p:external -d:release -o:granite src/harding/compiler/granite.nim
mkdir -p build/portfolio-stress
./granite build examples/compiler/portfolio_stress.hrd --release \
  --dir:build/portfolio-stress -o:build/portfolio-stress/portfolio
./harding examples/compiler/portfolio_stress.hrd
./build/portfolio-stress/portfolio
python3 scripts/bench_portfolio.py --scenarios 20000 --trials 5
```

The compiler driver's optimization does not determine the generated program's
optimization: `granite build --release` is required for the native workload.
The interpreter must also be a release build for this comparison.

Default output:

```text
equity
true
demonstration rejection
true
[2,200,600000,119857500,575000]
```

The JSON array contains report number, scenario count, base value, accumulated
scenario value, and minimum scenario value. The counter's second call answers 2.
The error is caught and its cleanup marks the book before execution continues.
The final report uses explicit Array construction rather than bare identifiers
in literal arrays. The argument-count check uses `size = 0`; native Array
`isEmpty` was not supported by the tested compiler.

## Measured results

One local Linux run, release ARC builds, five trials, identical 20,000-scenario
workloads, alternating engine order:

| Engine | Median elapsed | Zero-scenario baseline | Approximate net workload |
|---|---:|---:|---:|
| Interpreter | 3713.875 ms | 438.030 ms | 3275.845 ms |
| Granite native | 99.824 ms | 2.887 ms | 96.937 ms |

Native elapsed time was **37.2× lower**; baseline-subtracted workload time was
approximately **33.8× lower**. Baselines include process startup, class setup,
JSON parsing and feature demonstrations, not only stdlib loading. Compilation
is excluded. These are workload-specific local measurements, not a general
compiler speedup claim. Every measured invocation requires the expected exit
status, empty stderr and independently calculated exact stdout. Raw samples:
`build/portfolio-stress/timings-phb6avxn/results.json`.

## Cleanup capture regression found during construction

Top-level captured assignment in an error cleanup does not propagate in Granite:

```smalltalk
cleaned := false.
[[Error signal: "x"] ensure: [cleaned := true]] on: Error do: [:error | nil].
cleaned println.
```

The original native build answered `false` instead of the interpreter's `true`.
Capture analysis now recognizes direct script assignments as enclosing bindings,
and `write_only_cleanup_capture` checks cleanup setters, nested block locals,
method locals and shadowing in both engines. The showcase retains its object-held
cleanup state. This fixes binding sharing without changing language semantics.
The original reproduction and build logs are under `build/portfolio-stress/`.
