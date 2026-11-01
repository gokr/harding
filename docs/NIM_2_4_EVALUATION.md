# Nim 2.4.0 evaluation

## Current state

The project pins `requires "nim == 2.2.12"` in `harding.nimble`. Nim 2.4.0 is the
current stable channel and was installed alongside 2.2.12 with `choosenim 2.4.0`
(both toolchains remain available; `choosenim 2.2.12` switches back).

## Compatibility: clean

Both the interpreter and Granite compile on 2.4.0 with **zero errors** and no new
warnings. Executed suites at 2.4.0, ARC and ORC, all passing with no failures:

| Suite | ARC | ORC |
|---|---:|---:|
| `test_interpreter_core` | 57 | 57 |
| `test_exception_handling` | 46 | 46 |
| `test_compiler_basic` | 87 | — |
| `test_compiled_runtime` | 43 | 43 |
| `test_engine_boundary` | 35 | 35 |

The exception suite matters most because 2.4.0 changes bare `except:` to panic on
`Defect` instead of catching it. Harding's ~40 bare `except:` sites (in
`external/discovery.nim`, `external/libmanager.nim`, `core/scheduler.nim`,
`lsp/server.nim`, and others) still behave correctly in these suites. That is
evidence, not proof: a `Defect` raised on a path these suites do not execute would
now propagate. This should be reviewed site by site before adopting 2.4.0.

Float printing is unchanged. 2.4.0 makes Dragonbox round-trip formatting the
default, but Harding's `printString` output is byte-identical across 2.2.12 and
2.4.0 for a representative set (`0.1+0.2`, `1/3`, `1/7`, `sqrt 2`, a long decimal,
`1e-15`, pi). Interpreter and Granite output also agree.

## Performance: a regression for Granite output

Measured on the same generated `.nim` source, built by each compiler, release ARC
with `-O3` (identical C flags in both cache manifests), benchmark children pinned
to one performance core, alternating trials, verified output:

| Workload | Nim 2.2.12 | Nim 2.4.0 | Ratio |
|---|---:|---:|---:|
| Native Nim Richards (30 passes) | 0.273 ms/pass | 0.268 ms/pass | 1.02x |
| **Granite-generated Richards** | **32.10 ms/pass** | **39.90 ms/pass** | **0.80x** |

Reproduced in two independent runs (35.67 vs 45.11 ms/pass in the first). Native
Nim is unaffected; Granite output is ~24% slower. This is the decisive result:
2.4.0 is currently a performance regression for the workload Granite exists to
make fast.

### Cause

gprof on identical source, 30 verified passes:

| Symbol prefix | 2.2.12 | 2.4.0 | Change |
|---|---:|---:|---:|
| `eqdestroy` | 105,769,244 | 161,289,271 | +52% |
| `eqwasMoved` | 6,723,905 | 39,755,735 | +491% |
| `eqcopy` | 28,537,321 | 28,216,564 | unchanged |
| `rawAlloc` | 10,275,737 | 10,275,598 | unchanged |
| `newSeqPayload` | 4,152,676 | 4,152,676 | unchanged |

Allocation counts are identical, so this is not extra heap traffic. It is extra
destruction and move-reset work: ~1.85M additional `eqdestroy` and ~1.10M
additional `eqwasMoved` calls per pass, plus a new hot `len` helper that 2.2.12
inlined away. `eqwasMoved` zeroes a `(int, NodeValue)` tuple field by field through
a `case` on `ValueKind`; on a 32-byte variant that is far more work than a plain
reset, and it now runs on the hot sequence-assignment path.

The 2.4.0 C output for the core types module is also 31% larger (16,967 vs 12,923
lines) for the same Nim source, consistent with the extra move/destroy/bounds
helpers.

## Recommendation

**Do not move the pin to 2.4.0 yet.** Reasons:

1. It is ~24% slower on Granite-generated Richards, the workload that matters.
2. Nothing in 2.4.0's changelog addresses a problem Harding currently has. The
   relevant items are unattractive or inapplicable:
   - *Sum types* are a plausible future fit for the AST or `NodeValue`, but
     they change the shape of the core variant type and interact with the
     existing `case kind` dispatch, ARC/ORC ownership and `cast` usage.
   - *`owned refs`* would let callback fields stay out of the cycle collector,
     which is relevant to the existing cycle-avoidance work in the runtime.
   - *`--experimental:typeBoundOps`* would make `hash`/`==` resolution for
     nominal types more predictable, which touches how `NodeValue` keys behave.
   - *`readRawDataStable`* and *`setLenUninit` for strings* are small wins for
     buffer handling, not for the measured bottlenecks.
   - *Dragonbox float formatting*, *bare `except:` panics* and *`array` items
     yielding `lent T`* are compatibility risks rather than benefits.
3. The bottlenecks our profiles actually show are argument-sequence churn,
   dispatch resolution and managed-value copying. None is addressed by 2.4.0;
   the copying got worse.

Recommended sequence instead:

1. Keep 2.2.12 as the supported toolchain and record this evaluation.
2. Investigate the `eqwasMoved`/`eqdestroy` regression upstream with a minimal
   reproduction (a `seq` of a 32-byte variant object under ARC). If it is fixed
   in a later 2.4.x, re-run this comparison before changing the pin.
3. Enable `--experimental:ownedRefs` experiments on 2.2.12 first where they do not
   change value semantics, so the runtime cycle-collector surface shrinks without
   paying the codegen regression.
4. Revisit the version bump when either the regression is fixed or a 2.4.x
   feature becomes a prerequisite for work we are already doing.

## Reproduction

```sh
# Both toolchains installed side by side:
choosenim 2.4.0    # or 2.2.12
nim --version

# Compatibility
nim c -p:external -o:build/granite240 src/harding/compiler/granite.nim
nim c -p:external -o:build/harding240 src/harding/repl/harding.nim
nim c -r --mm:arc --out:build/n240_interpreter_core tests/test_interpreter_core.nim

# Performance: build one generated source with each compiler, then time
# the two binaries alternately on the same pinned core.
```

Evidence logs: `build/nim240-*.log`, `build/nimver/` (paired binaries,
`cmpprof/*/gprof.txt`, cache manifests), `build/nim-2.4-changelog.md`.
Host load was not isolated; the direction and rough magnitude reproduced across
runs, but the exact percentage is not portable.
