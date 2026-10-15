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
compiled parity suite: most of its cases evaluate only the interpreter. The
current bounded run completes, including the nested-control-flow case that
stalled in the initial assessment. This establishes suite completion, not broad
native execution coverage.

## Shared generated support

Generated programs import `runtime/compiled_support.nim` for primitive/operator
helpers, closure creation, non-local-return targets and native base storage.
Class/method/block bodies and registrations remain generated. Compiled globals
are shared through this module; loop conversion keeps its former permissive
behavior as `compiledLoopInt`, distinct from the runtime's strict `toInt`.
Manual/quick-reference semantics are unchanged by this extraction.

A hello program shrinks from 679 to 51 generated lines. Three isolated-cache
Nim 2.2.12 debug build trials measured median cold builds of ~5.56 s before and
~5.22 s after, and warm builds of ~3.01 s before and ~2.83 s after. These trials
ran alongside validation and are noisy, not a speedup guarantee. Importing a
module still requires Nim to analyze the runtime; the earlier estimate of
sub-second builds was not established. No binary-size/startup improvement is
claimed. Logs and samples: `build/preamble-measurement/results.json`.

## Current coverage and remaining gaps

Eighty-one parity cases cover the current milestones, including five unhandled-error
checks, two invalid-super-qualifier checks, and the inactive-return case, which is
now ordinary parity. Coverage includes class-side and inherited
method dispatch, factories and constructors, accessor permissions/overrides,
shared and escaped closures, forward temporaries, range captures, and lexical
shadowing in methods, blocks, inline conditionals, repetition, collections, and
while loops. Compiler tests
and the previously validated class-model suite also pass.

File-level temporary bars and `Harding main:` temporaries are retained by native
codegen, initialized to nil before closure creation (`script_temporaries`,
`main_temporaries`). CLI, file-codegen and compiler-primitive entry points use the
script parser without shifting source token lines. The example suite now has
51 exact parity passes, 1 known compiler-failure case and 26 syntax-only gates
(including 17 website host/context fragments).
Native `System arguments` returns user argument strings (including empty,
spaced, option-like and Unicode values) without the executable name; aliases
and registered class-side overrides work. `withIndexDo:` passes element and
zero-based index and answers the Array, with callback cleanup/return parity.
All template argument cases now pass, including integer/float calculator inputs
and unknown-operation fallback. Shared whole-string conversion returns nil on
failure; `asNumber` prefers Integer then Float, and VM `asFloat` is registered.
Native `ifNil:`/`ifNotNil:` and combined nil callbacks select the proper branch,
pass the receiver to the non-nil callback, and preserve cleanup/non-local returns.
Native `json{...}` literals build JSON strings without an interpreter: literal-level
entries use `", "`/`": "` with compact nested values, matching the interpreter, and
arrays, scalars, escaping and cycle detection are covered. `Json stringify:`
supports scalars and collections. Native `Json parse:` creates nested scalar,
Array and Table values; invalid input and JSON null answer nil. Direct/aliased
receivers and registered overrides are covered, with exact-output parsing and
round-trip evidence from `examples/stdlib/json_parse.hrd`. Dynamic
`Json perform: #parse: with: "42"` returns nil in the VM and signals MNU natively;
primitive class-side dynamic dispatch remains a separate gap, not intended
parse behavior.
Collection identity, mutation aliasing and reflection remain separate work.
Ordinary object JSON serialization (including
slot layouts, representation hooks and class JSON specs) remains unimplemented
natively and raises explicitly instead of silently writing an empty object.
Per-write cycle state is local; failed writes do not poison later writes. Both
engines serialize nil as JSON null, including wrapped UndefinedObject values.
Shared native helpers dispatch object/class receivers before builtin fallback,
so dynamically typed receivers and generated accessors named `last`, `size` or
`abs` are not shadowed (`accessor_selector_shadowing`). Nil-valued overrides and
method replacement are covered under ARC/ORC; primitive fast paths are retained.
Declared numeric method temporaries with proven one-kind initialization unbox to
native storage (`numeric_method_locals`); measured gains and limits are in
[GRANITE_BENCHMARKS.md](GRANITE_BENCHMARKS.md). Mixed mode stays boxed.
Collection mutation and numeric value-equality coverage remain separate gaps.
Logging stream/filter parity is covered too: lazy native sinks use Harding's
threshold, CLI logging uses stderr,
and existing host handlers/global filters are preserved. The logging manifest
failure marker has been removed.
The full 81-case semantic suite passes with a 60-second execution bound
(`run-toovwg8r`). An earlier concurrent 30-second run timed out
only on interpreted queens, which passed in isolation.

Compiled programs construct built-in collections: `Array`/`Table`/`Set`/`String`
`new`/`new:`/`new:withAll:`, table literals, and array/table `add:`/`includes:`
run natively (`native_collections`), so `benchmark/storage.hrd` executes natively.
The interpreter prints booleans as `true`/`false`, matching compiled output and
`True>>printString` (`boolean_display`).

`mangleClass`/`mangleModuleName` hex-encode class and module names, so spellings
that differ only by case, underscores or punctuation generate distinct Nim
identifiers instead of conflicting under Nim's style-insensitive comparison
(`class_name_spelling`). String registries keep original class spellings.
Earlier `mangleIdentifier`/`mangleSlot` still cover ordinary bindings and slots.
The interpreter's `isNil`/`notNil` fast path honors class overrides like compiled
dispatch (`nil_override`). Compiled `perform:`/`with:`/`with:with:` and
`respondsTo:` support dynamic sends (`dynamic_send`). Native `==`/`~=` compare
instance/class/block identity with the VM's immediate-value rules
(`object_identity`), independently of value equality (`=`). Operator helpers,
generic sends and cached sends share the comparison; wrappers retaining the same
native owner compare as one object. Collection representation/identity and
`perform:` override semantics are not covered by this slice.

User-defined compiled instances expose their registered `class`, `className`,
and direct `superclassNames` in declaration order; class receivers expose
`class`, `name`, `className`, and `superclassNames`. `isKindOf:` now searches all
parent branches in both engines, including transitive secondary parents, and
requires a class argument (`class_reflection`). Canonical `Root`/`Object`/`Mixin`
class values support base ancestry targets; symbols/strings are not class aliases.
Other built-in/immediate reflection,
class-side ancestry tests and method-list reflection remain incomplete. VM's
class-side `name` and instance-side `class` fast-path override discrepancies are
tracked in PLAN.md; this coverage does not assert override parity for them.

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
restoration is gone. `notification_pass_cleanup` covers handler-local cleanup
before outer dispatch, repeated signals and cleanup failure replacing delegation.
`handler_transfer_cleanup` covers error pass through intervening cleanup scopes
and handler-local cleanup before retry. The VM continues these transfers through
work frames. Custom default-action overrides, process yields and mixed mode
still need coverage. Custom error subclasses, instance construction and
inherited exception slots are implemented; zero divisors signal catchable
`DivisionByZero` in compiled `//`, `%`, `\` and `/` fast paths
(`arithmetic_zero_divisor`). An uncaught compiled error runs `defaultAction`
(user overrides included), reports the uncaught header and message, and exits
nonzero (`unhandled_custom_default_action`); the entry point propagates the
status. Diagnostic/stack-trace parity and mixed mode remain incomplete. A
user-defined
`message`/`describe` overrides the built-in protocol, while `signal`, `pass` and
`retry` keep it. `custom_exception_hierarchy` executes both engines.

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
handled errors and cleanup. Interpreter implicit class-side returns now preserve
the actual class receiver; class_return_representation covers same-named instance
and class selectors, inheritance, empty bodies, explicit self, escaped self blocks,
handled errors and cleanup.
Focused MNU tests, interpreter core, and exception/runtime suites pass (the latter
also under ORC). The full named-access suite timed out after its first inherited
layout test while entering JSON serialization coverage; only its four MNU tests
were independently re-run to completion. No full-repository suite success is
claimed.

## Example regression suite

Current source examples are grouped by purpose and inventoried in
`examples/manifest.json`; `nimble testExamples` checks successful execution and
exact reviewed stdout/stderr in both engines. Known compiler failures are explicit
and are not successes; strict mode rejects them too. Service/host-gated inputs are
syntax-only. See [GRANITE_EXAMPLE_AUDIT.md](GRANITE_EXAMPLE_AUDIT.md) for scope,
source repairs, native gaps and website/Markdown follow-up work. All 30 Harding
fences on website docs/index/features pages are extracted directly from Markdown:
13 runnable exact-output cases and 17 syntax-only host/context gates. Other
Markdown contexts remain follow-ups, not implicit successes. Source
website pages no longer describe errors as resumable; generated HTML is not
regenerated by the regression runner.

## Migration audit

The deferred-return audit found and fixed two Browser dialog callbacks that
attempted ^ after their home method finished. Headless tests invoke the actual
callbacks after dialog creation, checking invalid and valid inputs under ARC/ORC.
The original audit ran seven selected examples/benchmarks and recorded a native
Array-allocation failure in storage plus five parse failures. Current example
coverage supersedes those source failures: storage executes, stale sources were
repaired, script temporary bars parse in context, and the historical Person_new
proposal remains excluded. This checkout has no installed external .hrd sources.
The audit is partial; see [GRANITE_AUDIT.md](GRANITE_AUDIT.md) and the executable
example report for evidence and limits.

## Main synchronization

Merged main's scheduler continuation and class-registration lifetime fixes,
followed by bf112b0's pending-operand/Daisy/Badminton updates. Exception resume
restoration was deliberately excluded under the accepted contract; its tests use
ordinary handler results instead. on:do:/retry remove native placeholder results
before checkpoints. Native signal sends discard placeholders only when scheduled
error/handler work supplies a result; unhandled notifications retain their actual
nil return. `handler_pending_operands` covers normal completion, handled errors,
notifications, missing messages and retry inside larger expressions. Synchronization,
web rendering, compiler, core and logging suites have focused validation; this is
not a full-repository test claim.

## Legacy logging salvage

Application Log messages and FileStream print:/println: aliases are available in
both engines. Application logging respects host handlers and filters, keeps all
levels in release builds, and treats fatal as a log level rather than process
termination. Debug/release/ORC logging tests and an executed alias/output case
cover this slice. Printable Transcript routing is unchanged. See
[LEGACY_GRANITE_AUDIT.md](LEGACY_GRANITE_AUDIT.md) for preserved original code,
deferred collection/reflection ports, and retained historical stashes.

## Generated identifier hygiene

Nim keywords and backend-owned local/field names are encoded consistently in
binding declarations, references, assignments, method/block parameters, captures,
numeric expressions and slot accessors. Original Harding selector and slot strings
remain unchanged. Name spelling is part of identity: only all-lowercase alphanumeric
spellings are emitted verbatim, so `fooBar`, `foo_bar` and `slotValue` no longer
collapse onto their lowercase forms under Nim's style-insensitive comparison, and
`mangleSlot` keeps punctuation rather than replacing it. reserved_identifiers covers
keyword/helper-named variables, closures, slot messages and direct access, and
case_sensitive_bindings covers case/underscore-distinct bindings, slots and block
parameters. The encoded namespace is itself reserved to prevent user spellings
colliding with an encoding. `mangleClass` and `mangleModuleName` still strip case and
punctuation, and generated proc names embed raw `{cls.name}` interleaved with such
identifiers, so class/module spelling collisions remain separate follow-up work;
this slice does not establish general name-identity parity.

## Numeric specialization

Pure compiled scripts and explicitly declared method temporaries may use native
integer/float storage for directly initialized lowercase locals whose assignments
retain one kind and whose reads follow definite initialization. Method candidates
are restricted to declared temporaries before dependency analysis, so slots and
parameters cannot be mistaken for native lexical variables. Native temporary
storage initializes to zero only when no read can observe that pre-assignment
state; otherwise the temporary stays a nil-initialized NodeValue. Same-kind
addition, subtraction, multiplication and comparisons
emit native expressions. General sends still receive boxed NodeValue arguments.
Captured bindings, lexical shadowing, real closures, type-changing assignments,
globals and mixed mode retain the dynamic representation. Method parameters, slots,
loop-local declarations, numeric promotions and division/modulo are not unboxed by
this slice. Sieve still counts 669, including under ORC; its inner divisor remains
boxed. `numeric_method_locals` checks integer/float methods, class-side locals,
early nil reads, type changes, captured cells, shadowing, slot dependencies and
zero-divisor fallback. Paired release benchmarks measured ~5.16x/~5.28x for
Integer/Float method loops and ~2.23x with a dynamic bound parameter; see
[GRANITE_BENCHMARKS.md](GRANITE_BENCHMARKS.md) for scope and raw evidence.
This is not evidence of broad arithmetic-error or full compiler parity.

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

The compiled runtime registers every superclass in declaration order and walks
the parent graph depth-first with a cycle guard, so multiple inheritance follows
the interpreter's lookup order (`multiple_inheritance`); `addSuperclass:` works at
runtime. Qualified `super<Parent>` selects a direct parent of the declaring
class for instance/class-side and inherited methods, including lexical blocks
(`qualified_super`). Unrelated and indirect-ancestor qualifiers fail in both
engines (`invalid_qualified_super`, `indirect_qualified_super`), but remain
evaluation errors with different diagnostic formatting. Class-slot support,
collection identity/layout, general reflection parity, and mixed-mode execution
coverage remain open.
