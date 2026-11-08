# A native numeric kernel generated from Harding

Source: [`examples/compilation/native_sum_squares.hrd`](../examples/compilation/native_sum_squares.hrd).

```harding
SumSquares := Object derive: #().
SumSquares class>>sumTo: limit [
  | index total |
  index := 1.
  total := 0.
  [index <= limit] whileTrue: [
    total := total + (index * index).
    index := index + 1
  ].
  ^total
].
(SumSquares sumTo: 10000) println.
```

Compile and inspect:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
./granite compile examples/compilation/native_sum_squares.hrd \
  --home:. --dir:build/native-squares -o:program
nim c -d:release --out:build/native-squares/program build/native-squares/program.nim
./build/native-squares/program
```

Both interpreter and compiled program print `333383335000`.

The generated native kernel, verbatim (not a separate implementation):

```nim
proc integerClassCall_Class_53756D53717561726573_hardingUser73756D546F3A_native*(hardingNativeArg_limit: int): int =
  var limit = hardingNativeArg_limit
  var total: int
  var index: int
  index = 1
  total = 0
  while (index <= limit):
    total = (total + (index * index))
    index = (index + 1)
  return total
```

The long name preserves Harding selector/class identity. The body is ordinary
Nim: primitive arguments, primitive result, local variables and a native loop.
No boxed `NodeValue`, dispatch, reference counting or closures occur in that
kernel. It uses the existing class-side Integer-region planner; no macro or
hand-written Harding method replacement is required.

The complete generated module is **not** fully unboxed: it includes library
registration, startup, a dynamic method body and a guarded call boundary. If
the class/method registration no longer matches, the call uses ordinary dispatch.
Printing also remains a Harding operation. This is an example of a contiguous
native region, not a claim that all Harding programs already compile this way.

## Isolated timing

The exact generated kernel was extracted to `build/native-squares/kernel.nim`
and compared to an idiomatic hand-written Nim sum-of-squares loop. Both were
compiled with `nim c -d:release`, received `2,000,000` at runtime and returned
`2666668666667000000`. CPU-pinned alternating runs (15 retained trials, one
warmup) measured medians **2.994 ms generated**, **2.997 ms reference**.
Process startup is included; the result establishes comparable performance for
this isolated kernel, not a whole-program speedup or a portable guarantee.
Artifacts: `build/demo_native_timing.py` and
`build/native-squares/kernel-comparison.json`.

## Extending this to object benchmarks

Numeric parameter variants now offer a bridge: a checked public entry calls a
body with native `int` parameters; other argument kinds retain the dynamic body.
Queens' `r`/`c` can become native, but `current row` still returns a boxed getter
result. Receiver-type propagation and typed getter results must connect those
regions before the hot loop can resemble this kernel.

Nim generics can express reusable typed bodies and typed macros can transform
resolved Nim syntax. Neither supplies Harding receiver evidence, dispatch-version
validity or mutation semantics automatically. Those remain Granite's job.
Object variants remain appropriate for genuinely mixed values; replacing a
proven `int` with another tagged representation would move away from this goal.
