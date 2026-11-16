# Collection value views: how a copy on every send made `size` O(n)

## Symptom

The AWFY Havlak port took **181.6 s** natively against CPython's 3.1 s on the
same workload (`main(1, 50, 10, 10, 5)`). Another benchmark set (Richards,
DeltaBlue, Queens) showed nothing of the kind, so the cost was not general
dispatch overhead.

## What the profile said, and what it did not

`gprof` on the compiled Havlak binary:

| % | function | calls |
|---|---|---|
| 43.1 | `eqdup` (a `seq` deep copy) | 309,093 |
| 21.4 | `eqdestroy` | 10,938,871 |
| 20.7 | `setLen` (the copy's allocation) | 346,172 |
| 1.0 | `HavlakBits class>>xor:with:` | 52,250 |

The last row matters: the port's portable XOR is a divide-in-a-loop, and it was
the obvious suspect for a slow hash table. **It was 1% of the time.** Guessing
would have produced a wrong fix; the profile ruled it out.

The call graph attributed 272,013 of the `eqdup` calls to `sendMessage` itself,
which pointed at the runtime rather than the benchmark.

## Root cause

The compiled runtime handled a message to an instance-backed collection with an
explicit `case selector` chain, then a fallback:

```nim
# Read-only operations use an ephemeral value view, never a mutable owner.
let view = if storage.kind == ikArray:
             NodeValue(kind: vkArray, arrayVal: storage.elements)
           else:
             NodeValue(kind: vkTable, tableVal: storage.entries)
let answer = sendMessage(runtime, view, selector, args)
```

`NodeValue`'s `vkArray` variant **owns** a `seq[NodeValue]`, so that conversion
deep-copied the entire element sequence. Every selector not in the explicit chain
therefore cost O(n) — including `size`, which is the most-called operation in a
loop like `[ ... v size ... ]`.

Measured directly, 20,000 `size` sends:

| elements | time |
|---|---|
| 10 | 0.00 s |
| 100 | 0.02 s |
| 1000 | 0.14 s |
| 4000 | 0.49 s |

Linear in the length of a constant-time query.

## Finding which selectors paid it

Rather than guess again, a compile-time probe (`-d:traceView`) counted fallback
reaches by selector. On a *small* Havlak graph it reported a single entry:

```
VIEW 380442 size
```

Every other collection selector was already handled in the explicit chain. The
fix therefore needed to be narrow.

## The fix

Answer the O(1) shape queries from the instance storage before the fallback:

```nim
of "size":     # ikArray -> elements.len, else entries.len
of "isEmpty", "notEmpty", "first", "last":
```

After the fix the probe reports **no** fallback reaches for Havlak at all, and the
scaling test above is flat at every length (0.00 s for 10 through 4000 elements).

## Result

Havlak `main(1,50,10,10,5)`, identical verified answer
(`Havlak loops=1605 nodes=5213`) both sides:

| | before | after |
|---|---|---|
| Havlak | 181.6 s | 48.4 s |

Paired measurement against the pre-fix commit (`a1a89f4`), retained binaries,
`taskset -c 2`, 12 alternating trials, all answers checked before timing:

| workload | before ms/pass | after ms/pass | ratio |
|---|---|---|---|
| Richards | 19.828 | 19.838 | 1.00 |
| DeltaBlue | 36.985 | 29.903 | **1.24** |
| Queens | 25.636 | 25.821 | 0.99 |

DeltaBlue gains because it walks constraint graphs held in Arrays and asks for
`size` inside those loops. Richards and Queens are unaffected, as expected: their
hot paths index known-length arrays rather than querying them. Queens first
measured 0.958 at 12 trials and 0.993 at 24 trials, so that reading was noise, not
a regression; the 24-trial figure is the one reported.

The full parity suite still passes (105/105), along with the compiler/runtime
gates under ARC and ORC (99 and 44 checks, both memory managers).

## Why not remove the view entirely

The remaining fallback also serves genuinely materializing selectors and the
`Set`-as-table path, where a copy is either required or harmless. The instance
storage is mutable state shared with the interpreter, so replacing the owning
`NodeValue` with a non-owning reference is a representation change, not a local
edit; it needs its own slice, ARC/ORC validation and alias-semantics tests. The
narrow fix removes the measured cost without that risk.

Arm semantics are reference-based and were already correct: `b := a` followed by
`b at: 1 put: 9` is visible through `a`, in the interpreter and natively.

## Regression coverage

`tests/test_collection_view.py`:

- **Correctness**: `size`, `isEmpty`, `notEmpty`, `first`, `last` on instance
  Arrays and Tables, including empty collections and after mutation, must match
  the interpreter exactly (both are executed).
- **Cost**: 20,000 `size` sends at 10 vs 4000 elements must not grow. A copying
  implementation fails this by two orders of magnitude.
- **Negative control**: `includes:` for an absent element must *increase* with
  length. Without this, the cost assertion could pass on a measurement that
  cannot detect linear work at all.

## Method notes

`perf` is unavailable here (`perf_event_paranoid = 4`) and was not lowered.
Instrumented `gprof` builds are used to locate cost and are never reported as
timings; every figure above is from a plain `-d:release` binary.
