# Guarded direct slots and native slot arithmetic

Scope: a code-generation optimization on top of the declared-field representation
at `bd1a7a0`. No parser, interpreter typing, constructor or inheritance changes.

## Generated fast paths

Granite emits an inline read/write helper for each native slot. The helper
accesses the retained Nim owner's member directly, avoiding accessor-table hashing
and indirect calls after a successful guard. Method-local slot reads, assignment
expressions/statements, rewritten `SlotAccessNode`s and generated public accessors
use these helpers. Escaped blocks use the same guarded access helpers.

The guard checks:

- instance/object/native-proxy shape and a non-nil retained owner;
- the owner's actual Nim type (`of GeneratedClass`), not merely a class name;
- agreement between the raw storage pointer and that retained owner;
- the expected language class name;
- no interpreter-native-slot bridge attached;
- the registered getter and setter still match this generated layout.

Accessor identity checks are cached per thread and refreshed when
`registerSlotAccessor` increments `compiledSlotAccessorVersion`. Registering a
replacement invalidates a warmed fast path. Direct mutation of the exported
accessor tables bypassing registration is not a supported invalidation API.

A failed guard calls the existing `getSlotValue` / `setSlotValue`. In particular,
Nim types are still flat: inherited parent methods on a subclass cannot cast it
to the parent's layout. They fall back, as do plain VM instances and explicitly
bridged instances. Bridges retain live-layout validation and reject layout drift.
No owner or receiver is cached by the new helpers.

## Arithmetic

For method expressions made from declared Integer/Float slots, proven numeric
locals and literals, Granite emits native same-kind `+`, `-`, `*` and comparisons
using the existing numeric-expression rules. The layout/accessor guards for all
participating slots must succeed first. Otherwise the original dynamic expression
runs. Primitive values are boxed only at the expression boundary; assignments
still use the existing checked conversion at their storage boundary.

The pass recognizes both identifiers and the VM-reflected slot-read AST shape.
It does not assume parameter types, resolve arbitrary receiver getters, inline
ordinary methods or specialize mixed Integer/Float expressions. Operators with
side-effecting sends are not promoted. Unsupported expressions and callbacks
keep their existing generated paths. Block slot access is accelerated; numeric
specialization in separately emitted blocks is not promised by this slice.

Message lookup itself is unchanged: generated getter/setter bodies are faster,
but a user override still wins through ordinary dispatch. Named `::` access
retains its existing visibility-checked path.

## Measurements

Retained before binaries were built at runtime revision `bd1a7a0`, before edits.
After binaries use the same source snapshots. Both use Nim release ARC. Seven
measured alternating trials, one checked warm-up pair excluded. Every process
checks expected stdout, empty stderr and exit status. No gprof timings are used.

| Workload | Before total | After total | Time reduction |
|---|---:|---:|---:|
| Declared Integer counter, 500,000 increments | 110.249 ms | 38.240 ms | ~65% |
| Unannotated Richards, 20 complete runs | 1,097.202 ms | 879.364 ms | ~20% |

Evidence: `build/slot-direct/paired-results.json`, per-case source/generated Nim,
retained `before`/`after` binaries, build logs and per-observation output.
Drivers: `build/slot_direct_baseline.py`, `build/measure_direct_slots.py`.

The counter isolates a hot typed slot update; it is not a claim of a comparable
whole-application speedup. Richards measures direct access to dynamic fields, not
type inference. Host load was not isolated. No new Cog comparison was made.

A second experiment annotates five Richards slots (TCB identity/priority/state and
scheduler queueCount/holdCount, leaving other fields dynamic) in a disposable copy, without algorithm changes. The
interpreter and native version verify the reference counters. Its seven paired
samples are too noisy for a performance conclusion: unannotated process
per-run values span ~55–116 ms, annotated ~47–138 ms. Their medians (~78/~66 ms)
are not evidence of a reliable annotation-only improvement. Evidence:
`build/slot-direct/richards/annotated-results.json`; driver:
`build/measure_annotated_richards.py`. The baseline and after binary pair in the
first table remains the initial measured optimization evidence.

## Validation and limitations

`tests/test_direct_slots.py` compiles and executes an embedded host under ARC and
ORC. It checks native Integer/Float expressions, Boolean/String access, subclass
fallback with different physical layout, escaped block reads/writes, exactly-once
assignment effects, warmed accessor replacement/restoration, VM-owned fractional
values, interpreted method replacement, native adoption and layout-drift rejection.
Generated-source assertions also require the real field arithmetic and fallback.

Validation completed for this change set:

- Direct-slot executed host and generated-boundary tests under ARC/ORC.
- Runtime/boundary/reentrant-return/block-lifetime/support suites: respectively
  42/34/16/15/10 tests under both memory managers.
- Compiler basic/block suites: 84/29 tests.
- Richards and DeltaBlue conformance tasks, both engines under ARC/ORC.
- GTK application task: four tests including four real accessibility acceptances.
- Core group: 18 PASS results inspected, no failure markers (the task masks exits).
- Isolated-cache freeze conformance: 12 declared cases; frozen-build suite: seven
  tests. Logs: `build/direct-frozen-isolated.log`, `build/direct-frozen-build.log`.
- Broader parity: 102/102 cases pass in recorded batches, not one uninterrupted
  invocation (`build/direct-parity.log`). Declared-slot parity: seven cases.
  Slot-inference tests: 14; base-allocation tests: two under ARC and ORC.

These are the named validation gates, not a claim that every repository test ran.

This optimization does not complete declared-slot semantics: the interpreter
currently stores declared values dynamically and does not enforce all declared
kinds; native setters retain the conversions introduced earlier. Symbol fields,
object-class enforcement and typed-reference inheritance are not implemented by
this slice. These existing gaps must not be treated as proof of language-wide
typed-slot parity. Static/dynamic inference remains subsequent work.
