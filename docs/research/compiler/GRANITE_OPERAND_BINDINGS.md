# Operand bindings and host checks on the send path

Two independent savings, found by reading the generated `canPlaceRow` in Queens
(~44 `NodeValue` copies per call) rather than by guessing.

## 1. Bind only operands that need it

`genHostedBuiltin` bound every operand of every builtin operation into a `let`,
because it must evaluate operands once, left to right, before selecting an engine.
That is required for an operand with effects — but a bare local, parameter or
literal is already re-readable, so the binding only costs a `NodeValue` copy.

Queens' diagonal test is a chain of comparisons on locals (`delta = 0`,
`delta = distance`, `delta = 0 - distance`), so nearly every operand was a bare
name that got copied for no reason. `isReusableOperand` now recognises plain
identifiers and numeric literals, and those are passed through directly. Anything
with effects — sends, slot reads, nested blocks — is still bound exactly once, so
operand order and single-evaluation are unchanged.

Effect on generated `canPlaceRow`: receiver bindings fall from 9 to 3, and the
remaining 3 are the genuinely effectful `guardedSend_…row(self, …)` reads.

## 2. Skip the host check when no host is bound

`sendMessageCached` called `boundInterpretedSend` unconditionally. That proc is
not inlined: it reads the receiver, walks `boundClassFor`, and returns a tuple.
For a standalone compiled program `boundCompiledClasses` is empty and all of it is
wasted. The length check now guards the call, and is re-tested per send so a
callback can still bind or detach an interpreter between sends.

## Measured effect

Same-core (CPU 2) paired trials, `build/granite-profiles/run-o1ainvzc` →
`run-2bmhoact`, 30 verified passes per process:

| Workload | Trial 1 | Trial 2 |
|---|---:|---:|
| Richards | 1.100x | 1.126x |
| DeltaBlue | 1.019x | 1.039x |
| Queens | 1.226x | 1.222x |

Counts per verified pass, before → after:

| Workload | `eqcopy` (NodeValue) | `boundInterpretedSend` |
|---|---:|---:|
| Richards | 362,790 → 328,876 | 121,952 → 36,808 |
| DeltaBlue | 340,927 → 325,689 | 187,244 → 116,300 |
| Queens | 747,200 → 316,922 | 132,970 → 15,720 |

`rawAlloc` is unchanged, which is the useful control: this removed copies, not
allocations. Queens gains most because its hot loop is builtin arithmetic and
comparison on locals — exactly the pattern both changes target. DeltaBlue gains
least; its hot path is slot reads and object dispatch, not builtin operands.

## Validation

ARC and ORC, zero failures: `test_compiler_basic` 99, `test_compiled_runtime` 43,
`test_engine_boundary` 36, `test_compiled_support` 11, `test_engine_reentrant_returns`
16, `test_engine_block_lifetime` 15. Queens still prints 92.

Two compiler tests asserted the old always-bind output; they now assert the new
contract — no binding for a bare local, and a binding still present for an operand
with effects.

## What this does not fix

`eqcopy` remains 316–329k per pass on all three workloads, plus the `eqdestroy`
counts that accompany them. Those are argument sequences (`@[...]`) and `NodeValue`
returns, not operand bindings, which is the next slice.
