# Granite completeness work

Work branch: `granite-completeness`.

## Validation

Build the interpreter with `nimble harding` and the compiler with:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py
```

The focused parity runner checks both engines against explicit expected output.
Both engines signal `BlockCannotReturn` for a return to a finished home, so
`inactive_return_target` is ordinary parity. Optional case names select focused
runs, e.g. `python3 scripts/test_granite_parity.py recursive_return_target`.
Each invocation uses a separate directory under `build/parity/`. Build logs and
engine output are retained. Execution defaults to a 30-second limit; compilation
defaults to 120 seconds. A timeout, failed build, failed engine, or incorrect
output fails the runner. Missing binaries fail rather than skip tests.

The older `tests/test_compiler_block_parity.nim` suite is not a comprehensive
compiled parity suite: most of its cases evaluate only the interpreter. During
initial assessment it stalled in `nested blocks with control flow`, after the
executed compiled case passed. Diagnose that separately; do not describe the
whole suite as passing until it completes.

## Current coverage and remaining gaps

Fifty-three parity cases cover the current milestones, including four unhandled-error checks and the
inactive-return case, which is now ordinary parity. Coverage includes class-side and inherited
method dispatch, factories and constructors, accessor permissions/overrides,
shared and escaped closures, forward temporaries, range captures, and lexical
shadowing in methods, blocks, inline conditionals, repetition, collections, and
while loops. Compiler tests
and the previously validated class-model suite also pass.

Compiled environments are managed heap references owned by their BlockNode.
Environments retain shared MutableCell references; reads and assignments target
cell values rather than copying bindings and writing them back. Sibling captures
and escaped counters pass under ARC and ORC. Capture-name analysis is limited to
each body but remains name-based rather than binding-identity-based. Collection
and while-loop scope regressions pass. While conditions evaluate all setup
statements in their lexical scope; select predicates preserve preceding side
effects. Method/block temporaries are declared
at scope entry; inline collection loops allocate parameter bindings on each
iteration. Specialized if/while blocks lowered inline no longer register closure
environments or force cells for otherwise uncaptured locals. Nested escaping
closures and non-local-return branches remain registered; generated-code tests
cover both paths. Compiled blocks retain a unique home-invocation return target;
recursive callbacks and nested-loop returns pass. Targets become inactive on exit,
and a later return signals `BlockCannotReturn`, which both engines raise as an
`Error` subclass. The recursive callback regression also passes under ORC. The
accepted [exception model](EXCEPTION_MODEL.md) removes arbitrary error resumption;
inactive-home returns, conventional errors and `ensure:` cleanup are integrated
across both engines, and synchronous notifications do not require signal-point
restoration.

The first error-model slice abandons VM protected work before handler execution
and excludes executing handlers from catching their own failures. Both engines
reject resumption entirely (no resume/resume:/return:), and native built-in Error/Exception signaling
supports handler results, pass and retry. Core exception, signal-point,
compiler and website-example suites pass.

Handlers supply values by returning them, and Harding has no resumption:
`resume`, `resume:`, `return:` and `isResumable` were removed, so those selectors
are unknown. This dropped the last construct that required saved state. Both
engines pass `notification_dispatch`, `notification_lifetime`,
`notification_default` and `notification_failure`. Expanded cases cover handler
results, immediate completion, repeated signals, nested pass to `Exception`,
handler failures and no premature protected-body cleanup. VM handlers run above
active signaling work, without saved work/eval snapshots; native resume
restoration is gone. Handler-local cleanup on `pass`, custom default-action
overrides, process yields and mixed mode still need coverage. Custom error subclasses, instance construction, arithmetic-error
translation, and general native defaultAction/diagnostic parity remain incomplete.

`ensure:` runs cleanup exactly once on normal completion, errors and lexical
non-local returns, nested innermost-first, in both engines. Cleanup failures are
caught by the handler protecting the scope. Retry attempts, cleanup replacing
pending errors/returns, nested cleanup failures, and cleanup on uncaught exit have
executed parity coverage. VM unwind continuations keep the cleanup's home active
and retain outer cleanup registrations until each is exited. The exception/cleanup suite also passes under ARC and ORC. Process boundaries
and legacy re-entrant native invocation paths remain unverified.

Compiled methods use shared global bindings; `global_scope` covers reads and
writes from methods and nested blocks. Receiver capture for slot accesses has
executed parity coverage. Capture traversal now includes specialized control-flow
and named-access nodes; write-only enclosing temporaries retain shared cells.

Verified eight-queens search (92 solutions) and object-based Towers of Hanoi
(8191 legal moves) now have parity coverage and ARC/ORC native execution evidence.
Instance wrappers strongly retain native storage through `compiledOwner` before
storing its raw pointer, avoiding premature collection without permanently rooting
every allocation. General cyclic-object lifetime coverage remains outstanding.
See [GRANITE_BENCHMARKS.md](GRANITE_BENCHMARKS.md) for measured object-workload
baselines; no Cog comparison has been measured for these workloads.

Generated accessor messages use ordinary compiled method registration, preserving
user overrides and inherited lookup. Generated setters return the receiver.
Direct named access (`::`) remains distinct from accessor message dispatch.
Compiler registration tests check that private and disallowed accessor directions
are not emitted. Generic instance/class/super lookup failures now signal catchable
MessageNotUnderstood rather than nil. VM DNU executes on the normal work queue,
preserving handler results; custom inherited instance/class DNU recovery and cleanup
before handled/uncaught errors have executed coverage. Wrong-type primitive fallback
and mixed-mode dispatch remain distinct gaps. Compiled methods now answer self
on fallthrough, with explicit ^ supplying values and blocks keeping last-expression
results; implicit_method_returns covers empty methods, literals, assignments,
handled errors and cleanup. Interpreter implicit class-side receiver chaining
still has a representation gap, separately recorded in PLAN.md.
Focused MNU tests, interpreter core, and exception/runtime suites pass (the latter
also under ORC). The full named-access suite timed out after its first inherited
layout test while entering JSON serialization coverage; only its four MNU tests
were independently re-run to completion. No full-repository suite success is
claimed.

## Legacy logging salvage

Application Log messages and FileStream print:/println: aliases are available in
both engines. Application logging respects host handlers and filters, keeps all
levels in release builds, and treats fatal as a log level rather than process
termination. Debug/release/ORC logging tests and an executed alias/output case
cover this slice. Printable Transcript routing is unchanged. See
[LEGACY_GRANITE_AUDIT.md](LEGACY_GRANITE_AUDIT.md) for preserved original code,
deferred collection/reflection ports, and retained historical stashes.

## Numeric specialization (first slice)

Pure compiled scripts may use native integer/float storage for directly initialized
lowercase locals whose assignments retain one kind and whose reads follow definite
initialization. Same-kind addition, subtraction, multiplication and comparisons
emit native expressions. General sends still receive boxed NodeValue arguments.
Captured bindings, lexical shadowing, real closures, type-changing assignments,
globals and mixed mode retain the dynamic representation. Method parameters, slots,
loop-local declarations, numeric promotions and division/modulo are not unboxed by
this slice. Sieve still counts 669, including under ORC; its inner divisor remains
boxed. This is not evidence of broad arithmetic-error or full compiler parity.

## Guarded allocation (first direct-call slice)

Statically named pure compiled class receivers use a native allocator directly
when a versioned guard proves that no own/inherited class-side `new` exists and
the registered allocator is unchanged. Class-method, allocator and superclass
registration invalidate the guard. Overrides, mixed mode, aliases and locally
shadowed names retain dynamic sends. Constructor/super parity cases and runtime
invalidation tests cover the fallback. General method devirtualization is not
implemented by this slice; compiled registration remains single-threaded.

## Monomorphic send caches (first slice)

Pure generic compiled send sites have thread-local positive caches for registered
instance methods, guarded by receiver class, selector and registration version.
Changing receiver class replaces the entry; nil results are valid hits. Method,
class-method, allocator and superclass registration invalidate cached targets.
Builtin fallback, exception protocols, class-side sends and mixed mode remain on
generic dispatch. Runtime replacement/hierarchy tests and alternating-class
execution parity cover these paths. Registry mutation is single-threaded; direct
writes to exported method tables bypass invalidation and are outside this contract.
Polymorphic caches and compact class/selector identities remain follow-ups.

## Implementation order

1. Bounded, isolated execution parity and output-directory-independent imports.
2. Class-side method extraction and registration; class receivers, inherited
   lookup, overridden `new`, factories, and class-side `super`.
3. Shared mutable closure cells and activation-specific non-local returns,
   including recursion and escaped-block lifetime checks.
4. Object-model parity: multiple inheritance, dynamic sends, missing-message
   errors, and reflection.
5. Conventional errors, synchronous notifications, guaranteed cleanup, processes,
   and library compilation. No arbitrary error resumption is required. Processes
   may still require continuations or state-machine lowering.
6. Optimization after semantic coverage: direct calls, specialization, unboxing,
   and dispatch caching.

The compiled runtime currently follows one superclass chain. Class-side support
does not imply multiple-inheritance parity, class-slot support, or general
reflection parity. Mixed-mode behavior also needs separate execution coverage.
