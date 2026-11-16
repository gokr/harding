# Send-cache lifetime in expression blocks

## Diagnosis

Warm `sendMessageCached` hits already bypass method resolution. Instrumenting
resolution and site misses by selector showed that Queens' sites never warmed:

| Selector | Resolutions before | After |
|---|---:|---:|
| `notNil` | 2,450,880 | 1 |
| `canPlaceRow:column:after:` | 471,600 | 1 |
| `searchRow:after:` | 61,681 | 2 |

Counts are for 30 passes. The remaining 61,681 `initialize` resolutions belong
to allocation, not these send sites. Probe timings were not used as scores.

The generated C resets the template-local `{.global, threadvar.}` cache at the
expression-block declaration, including inside loops. A minimal Nim 2.2.12
reproducer counts `1,1,1` for repeated template expansions at one site, rather
than `1,2,3`. Adding `noinit` does not fix it.

## Fix

Both `cachedSend` and `cachedSendBound` now define a tiny cache-address proc per
expansion, containing the thread-local global, and pass its dereferenced address
to the existing dispatcher. Proc-scope TLS persists across calls under ARC and
ORC. No shared cache, second selector-id space, new invalidation policy, or
language-specific specialization is needed. Cache ownership stays per-site,
per-thread; recursion still copies the selected target before invoking it.
Host routing, selector safety exclusions and registration-version checks remain
unchanged.

## Measurements

Retained before/after binaries: `build/cache-lifetime-ywz92v8a/`, baseline
`014131e` versus the lifetime fix. Nim 2.2.12, release ARC, CPU 2, 12 alternating
trials after warmup, 30 passes per process, all builds finished before timing.
Every execution checked exact stdout, zero status and empty stderr.

| Workload | Before ms/pass | After ms/pass | Speedup |
|---|---:|---:|---:|
| Richards | 19.470 | 17.898 | 1.088x |
| DeltaBlue | 34.757 | 33.843 | 1.027x |
| Queens | 32.566 | 27.648 | 1.178x |

Host load averages: 5.75/2.10/1.53 before, 2.98/2.67/1.85 after. Paired timings
are evidence for this run, not machine-independent scores; DeltaBlue's small
change should not be overinterpreted. These are default builds, with no training
profile or observed-type narrowing.

## Regression coverage

`tests/test_compiled_runtime.nim` exercises both templates inside a loop and
across repeated activations. It deliberately changes the public method table
without bumping the epoch, then evicts the shared resolution cache: only a
persistent site can retain the original target. Official registration must then
invalidate those same warmed sites. The test-only direct-table mutation is not a
supported production mutation API.

Negative control: the regression fails with the original runtime. With the fix,
the complete compiled-runtime script passes 44 checks under ARC and ORC.
Guarded-direct-send and native-region tests also pass. Full parity: **105 passed,
0 failed** (`build/cache-final-parity.log`, `build/parity/run-avr3o_9k`).
