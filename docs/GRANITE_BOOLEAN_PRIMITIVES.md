# Eager Boolean primitives

## Change

Granite now emits primitive helpers for two eager Boolean sends in compiled code:

- `receiver | argument` → `nt_pipe(receiver, argument)`
- `receiver not` → `nt_not(receiver)`

Both answer directly when the receiver (and argument) are `Boolean`; otherwise
they fall through to ordinary `sendMessage`. That preserves user-defined `|` and
`not` methods, and keeps the historical generic answer for wrong primitive kinds.
Mixed-mode compilation keeps the previous path.

`and:`/`or:` are deliberately excluded. Their argument is a block, not an already
evaluated value, so a primitive cannot honour the existing lazy short-circuit
without inventing a differently-shaped helper. `|` is eager by definition: both
operands have already been evaluated left to right before the send, which the
existing `genHostedBuiltin` argument binding already guarantees exactly once. The
fixture asserts the right-hand effect still runs when the left side is `true`.

## Measured effect

Same-core (CPU 2) paired trials against retained baseline
`build/granite-profiles/run-zwwmft5i` (runtime `5bc5555`), 30 verified passes per
process, twelve measured alternating trials after one warm-up:

| Workload | Trial 1 | Trial 2 |
|---|---:|---:|
| Richards | 1.000x | 0.995x |
| DeltaBlue | 0.990x | 1.001x |
| Queens | **1.246x** | **1.228x** |

Richards and DeltaBlue are unchanged within noise. Queens improves ~23% because
its diagonal attack test is an eager chain of `|` comparisons. This is a
workload-specific win from removing generic dispatch and its argument sequence,
not a general send optimization. Evidence: `build/bool-helper-pinned.log`,
`build/bool-helper-pinned-repeat.log`.

Allocation counts are unchanged; what disappeared is the dispatch hop, not heap
traffic. Queens' `|` sends per pass are now primitive calls.

## Validation

- `nimble testBooleanHelpers`: builds Granite, then compares interpreter and
  compiled output against an explicit expected transcript under ARC and ORC —
  full truth tables, custom `|`/`not` overrides, nil answers, exactly-once
  right-hand effects, left-to-right operand order, and an exception raised in the
  right operand still reaching `on:do:`.
- Generated host fixture: primitive receivers use the helper, `SizedProbe`
  overrides still win, and a runtime redefinition to `^nil` is observed after
  binding an interpreter.
- Compiler test asserts operands bind before host routing and that mixed mode
  does not emit the helpers.
- ARC/ORC: `test_compiled_support` 11, `test_compiled_runtime` 43,
  `test_engine_boundary` 35, `test_compiler_basic` 88,
  `test_engine_reentrant_returns` 16, `test_engine_block_lifetime` 15 — 0 failures.
- Full parity sweep: **102 passed, 0 failed**
  (`build/parity/run-odu3a329`).

Logs use `build/bool-final-*`. This is named-gate validation, not a full-suite
claim.

## Rejected in the same session

A `compiledInstanceSelectors` negative gate in `sendMessage` — skipping hierarchy
resolution for selectors no compiled method implements — was measured and
dropped. Hierarchy resolutions fell (Queens 123k→42k per pass) but hash calls did
not, because the set membership is itself a hash probe: ~7% on Queens, nothing on
DeltaBlue. Not worth the added invariant that `compiledMethodProcs` stays
monotonic.

## Next candidates

Remaining hot costs are argument/copy machinery and generic block iteration, not
send resolution. Two directions, each to be measured separately:

1. Keep values native across a region (interprocedural typed parameters/returns),
   so unboxing is not undone at the next call.
2. Specialize idiomatic collection loops (`do:`, `collect:`, `select:`,
   `detect:`, `inject:into:`) when the receiver is a native Array/ByteArray and
   the block does not escape — noting that capturing an accumulator is fine, so
   "no captures" is the wrong test; "does not escape" is the right one.
