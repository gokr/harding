# Granite completeness plan

Work in branch `granite-completeness`. Prioritize semantic correctness over
optimization. Each coherent change needs executed regression coverage, a
changelog entry, reference-manual review, and build/test validation. Update this
checklist as work lands. Compiler fixes must conform to documented Harding
semantics; any intended language change must be explicit and documented.

## Baseline

- [x] Bounded execution-parity runner with isolated workspace build artifacts.
- [x] Nested output-directory imports.
- [x] Extract the fixed generated preamble into `runtime/compiled_support.nim`:
      primitive/operator helpers, managed blocks, return transfers and native base
      storage are shared imports, not emitted per program. Codegen and ARC/ORC
      support tests cover the boundary; generated hello shrinks 679 → 51 lines.
- [x] Class-side method extraction, registration, receivers, aliases and factories.
- [x] Class-side `super` lookup in the interpreter.
- [x] Seven executed parity cases and class-model unit tests passing.
- [x] Recheck the older block-parity suite's nested-control-flow hang. The current
      bounded run completes, including whileTrue/repetition/nested control flow;
      most cases remain interpreter-only rather than native execution coverage.
- [ ] Expand parity coverage continually; do not equate interpreter-only tests
      with compiled execution coverage.

## Example-driven completion priority

- [x] Organize examples into language, compiler, stdlib, concurrency, web,
      integrations and templates; retain algorithm workloads in benchmark/.
- [x] Inventory every current `.hrd` example/benchmark in examples/manifest.json.
      Bounded runner requires successful execution, exact stdout snapshots and
      interpreter/native parity; known compiler gaps are stage/message-checked,
      never counted as passes. New/unlisted files fail inventory validation.
- [x] Repair stale concat syntax, permutation syntax/indices and count assertion,
      Echo primitive/bootstrap registration, and template argument iteration and
      callback arity. Host package/template tests exercise nonempty argument paths.
- [x] Top-level temporary bars: CLI/file-codegen/compiler-primitive entry points
      preserve script temporaries, nil initialization and shared closure bindings;
      `Harding main:` retains its temporaries too. `loop_10000.hrd` now passes.
- [x] Default logging filter and streams: lazy sinks use Harding's configured
      threshold; interpreter CLI and native default logging both write stderr.
      Exact stdout/stderr example parity no longer waives logging.
- [x] Native `System arguments`: canonical class/aliases return process arguments
      without the executable name. Empty strings, spaces, Unicode and option-like
      values have exact example coverage. `Array>>withIndexDo:` passes element
      and zero-based index, answers the receiver, and supports compiled callbacks.
- [x] Calculator numeric-string conversion: shared whole-string Integer/Float
      parsing answers nil on failure; `asNumber` tries Integer then Float. VM
      instance/value primitive paths and native sends share it; asFloat is
      registered. Native nil callbacks pass receiver to the selected one-argument
      branch and preserve returns/errors/cleanup. Integer/float calculator inputs
      and unknown-operation fallback have exact example snapshots.
- [ ] Eliminate remaining manifest compiler gap: native processes.
- [x] Numeric equality is strict by decision, not by accident. Harding has no
      numeric tower (that keeps it Nim-compilation friendly), so Integer and Float
      are distinct classes and `=` answers false across them; `~=` therefore
      answers true. Ordering comparisons (`<`, `<=`, `>`, `>=`) do compare mixed
      Integer/Float operands as Float. This is implemented identically in both
      engines: the compiled runtime previously had no builtin `=` for nil,
      cross-kind or non-scalar pairs and no `<>` at all, so `100.0 = 100`,
      `nil = nil`, `"ab" = 100`, `x = x` on user instances and every `<>` signalled
      MessageNotUnderstood natively. Coverage: `numeric_equality` parity (21
      cases) plus interpreter tests. Nothing depends on the old behaviour; the
      arithmetic example checks a Float result against a Float.
- [ ] Collection value equality/size reflection in compiled code stays separate:
      `#(1,2) = #(1,2)` and `(a isKindOf: Array)` answer in the VM but signal
      natively. Not numeric equality; tracked with collection semantics.
- [ ] Add bounded service/GUI-host smoke tests for the syntax-gated examples.
- [x] Extract all six Harding fences from website docs/index Markdown into the
      manifest runner: four stdout-checked interpreter/native cases, two syntax-only
      host/context gates. No copied snippet source; unlisted/malformed fences fail.
      Remove obsolete resumable-error headings from source website pages.
- [x] Extract the 24 features-page fences too: nine runnable exact-output cases,
      fifteen syntax-only host/context gates. Repair missing demo setup, array
      grouping, and escaping without replacing correct dynamic JSON with static
      text; unsafe case ids and duplicate extraction keys fail validation.
- [ ] Extend extraction to other Markdown snippets with explicit contexts;
      generated website/dist is not a second authoritative source.
- [x] Native Json buildDynamic:/stringify: support scalars and collections,
      nested values and escaping with interpreter formatting. Both engines write
      nil as JSON null; native per-write cycle state is local and recoverable.
- [x] Native Json parse: creates nested scalar/collection values, returns nil on
      invalid input, supports aliased receivers and registered overrides, and
      round-trips through stringify:. Exact-output json_parse example and ARC/ORC
      runtime tests cover numeric kinds, Unicode/escapes, empty containers and null.
- [x] `perform:` conveys a real send in both engines. It previously ran as a
      native method that re-implemented dispatch, so it could not reach class-side
      methods, builtins, allocators or `doesNotUnderstand:`, and every miss
      answered nil. The VM now rewrites the send frame into the conveyed selector
      (only when the receiver's ordinary dispatch resolves `perform:` to
      Object's own definition, so overrides keep normal dispatch) and the native
      runtime conveys before the class-side/builtin tables. A missing selector now
      signals catchable `MessageNotUnderstood` in both engines, which keeps a miss
      distinguishable from a method that returns nil. Coverage:
      `dynamic_send_targets` parity plus six interpreter tests.
- [ ] `perform:` with a non-symbol/non-string selector (for example
      `obj perform: 42`) still answers nil in both engines rather than signalling;
      decide whether that should become an argument error. This is the remaining
      silent nil on the dynamic-send path.
- [ ] Native ordinary-object JSON serialization (slots, representation hooks,
      class JSON specs and plan caching) remains unsupported and raises explicitly.
- [x] Native builtin helpers defer to object/class dispatch, including dynamic
      receivers and nil-valued overrides, instead of shadowing accessors named
      last/size/abs/etc. Primitive collection/numeric fast paths remain intact.

## 1. Finish class-side and accessor semantics

- [x] Preserve defining-class ownership for inherited methods and `super`.
- [x] Test class-side `super` in nested blocks.
- [x] Test multi-level constructor inheritance.
- [x] Register dynamically dispatched generated accessors as compiled methods,
      respecting read/write permissions and user-defined overrides.

## 2. Correct closure semantics

- [x] Share mutable capture cells instead of copying independent values.
- [x] Capture write-only script locals and nested block declarations; focused
      cleanup/setter/shadowing parity and compiler tests pass under ARC/ORC.
- [x] Native collection reference-storage slice: mutation aliasing, shallow clones,
      identity equality, builtin reflection and Array/Table/Set query callbacks.
- [ ] Complete derived-collection, bulk/removal, override and mutation-during-loop
      coverage; Smalltalk-80 gaps are inventoried in COLLECTION_PROTOCOL_AUDIT.md.
- [x] Native ordinary-object JSON serialization with slots, hooks and class specs.
- [ ] Cache native JSON plans with explicit hierarchy/config invalidation after
      measuring the per-write plan construction path.
- [x] Test sibling and nested blocks observing the same bindings.
- [x] Declare method/block temporaries before closure creation; cover captures
      preceding first assignment.
- [x] Allocate per-iteration parameter bindings in inline `do:`/`collect:`/`select:`;
      executed coverage for escaped closures from `collect:`.
- [x] Limit capture-cell name analysis to each method/block/main body.
- [x] Cover locals shadowing slots and parameters shadowing outer bindings.
- [x] Bind range-loop parameters per iteration in ascending/descending loops.
- [x] Cover declared-local shadowing in inline conditionals/repetition blocks;
      exclude block temporaries from inherited VM captures.
- [x] Cover inline `do:`/`collect:`/`select:` and both while selectors with
      lexical scopes, condition setup, side effects, and escaped loop captures.
- [ ] Replace name-based analysis with precise lexical binding identities if
      additional shadowing cases require it (current tested scopes pass).
- [x] Keep escaped block environments alive safely under ARC/ORC (managed
      environments owned by BlockNode; returned string-capture regression tested).

## Reference manual maintenance (before the next implementation milestone)

- [x] Update `docs/MANUAL.md` for verified accessor behavior (including setter
      return values), lexical shadowing, shared captures, escaped closures, and
      lexical `super` lookup.
- [x] Review `docs/QUICKREF.md` for corresponding corrections.
- [x] Distinguish intended language semantics from Granite's tested support and
      remaining limitations; link to `docs/GRANITE_STATUS.md`.
- [x] Link semantic examples to executable regression cases and add missing
      tests where manual examples expose gaps.
- [ ] Review the manual and quick reference with every coherent semantic change;
      update them in the same commit when clarification is needed.

## Nim toolchain alignment

- [x] Pin `harding.nimble` to Nim 2.2.12 and align contributor/build instructions.
- [x] Validate interpreter, Granite, generated programs, and focused tests under
      installed Nim 2.2.12. Nimble selects its installed 2.2.12 compiler; direct
      builds and Granite child builds use PATH's 2.2.12. All 23 parity cases,
      compiler tests, and class-model tests pass.

## Accepted exception-model change (next implementation priority)

Target contract: `docs/EXCEPTION_MODEL.md`. Both engines must agree; do not retain
arbitrary error resumption solely in the interpreter.

- [x] Record non-resumable errors, synchronous notifications, guaranteed cleanup,
      lexical block returns, and foreign-boundary constraints as the target model.
- [x] Inventory core exception/signal-point/website tests, stdlib protocols and
      signal diagnostics. Error-resuming arithmetic/website examples now use
      handler fallback values; Notification tests remain for the next slice.
- [ ] Complete migration audit of debugger hooks, external libraries and website
      content; preserve diagnostic expectations without live error continuations.
- [x] Make VM errors abandon protected work before handler execution; executing
      handlers are excluded from catching their own failures. Native basic error
      signaling, handler results, return:, pass, and retry have parity coverage.
- [x] Reject resume/resume: on handled errors in both engines; rejection can be
      caught by an outer handler. Cover missing-handler actions and arbitrary
      exception subclass/native arithmetic paths in later slices.
- [x] Complete compiled exception hierarchy/instance protocol and custom
      subclasses. User exception classes inherit the built-in slots, `signal:`
      runs the class's compiled constructor/`initialize`, and user methods
      override the built-in protocol while signal/pass/retry keep it. Coverage:
      `custom_exception_hierarchy` parity plus runtime/compiler tests.
- [x] Native arithmetic-error translation: zero divisors signal
      `DivisionByZero` in compiled `//`/`%`/`\\`/`/` fast paths instead of
      raising an uncatchable Nim defect. The interpreter also signals for `/`
      zero-divisor forms that previously answered nil. Coverage:
      `arithmetic_zero_divisor`.
- [x] Custom defaultAction/exit parity: compiled uncaught errors run
      `defaultAction` (including user overrides), report the uncaught header and
      message, and exit nonzero. Coverage: `unhandled_custom_default_action`.
- [ ] Diagnostic/stack-trace parity and mixed mode.
- [x] Notification handler results are the signal's value; signals do not unwind
      the signaling computation; `pass` reaches outer handlers; `retry`/`return:`
      are rejected with a normal Error. Interpreter: 23 exception tests pass;
      native: `notification_dispatch`/`notification_failure` parity cases pass.
- [x] Unify notification handler results across doits, script blocks, and compiled
      execution. Native nested pass reaches outer handlers, including `Exception`;
      repeated signals re-arm installed handlers and running handlers are excluded
      from handling their own nested signals.
- [x] Remove exception resumption from the language: `resume`, `resume:`,
      `return:` and `isResumable` are gone, as is the native resume transfer. A
      handler answers by returning a value, which needs no saved state. This was
      the last construct requiring continuations, so errors can later lower to
      return values and nothing on the hot path needs unwinding machinery.
- [x] Remove saved work/eval snapshots and native ResumeException restoration.
      VM notification handlers run above the still-active signaling work queue;
      completion checkpoints only delimit the synchronous handler invocation.
- [x] Cover early resume/pass, repeated signals, nested notifications, no premature
      protected-body cleanup, handler errors, and built-in unhandled default action.
- [x] Cover notification-handler ensure scopes during `pass`: cleanup precedes
      outer dispatch without exiting signaling scopes; repeated signals and
      cleanup failures replacing delegation pass in both engines. Error pass
      also cleans intervening scopes and retry cleans handler-local scopes.
      Coverage: `notification_pass_cleanup`, `handler_transfer_cleanup`.
- [ ] Cover arbitrary user defaultAction overrides, process yields and mixed mode.
- [x] Exactly-once `ensure:` cleanup on normal exits, errors, and lexical
      non-local returns, including nested (innermost-first) cleanup and cleanup
      failures. Cleanups are scheduled as work frames so they run on the normal
      stackless path; a scope is marked running before its cleanup body so a
      cleanup that signals cannot run twice, and the handler is marked consumed
      only after its cleanups so such a failure is still caught by it.
      Interpreter: 6 cleanup tests pass; native: `ensure_cleanup` parity passes.
- [x] Cover cleanup on retry attempts, replacement of pending errors/returns by
      cleanup returns, nested cleanup failures, and cleanup before uncaught exit.
      VM unwind continuations run one cleanup at a time with its home still live;
      no synchronous block evaluation is used on these unwind paths.
- [ ] Cleanup across process boundaries and legacy re-entrant native invocation
      paths still needs coverage.
- [x] Fix compiled method access to **Harding globals**. Top-level uppercase names
      are module-level shared bindings (`getGlobal`/`setGlobal`); previously a
      method assigning one invented a shadow local, and blocks captured a fresh
      cell initialised to a symbol. Coverage: `global_scope` parity.
- [x] Fix **receiver capture for blocks inside methods**. A block naming an
      instance slot compiles to `getSlotValue(self, ...)`, but `self` was dropped
      from captures, so such a block failed to compile (`undeclared identifier:
      'self'`) when passed to another method. Now the block captures `self` when
      it names a slot, and enclosing method parameters/temporaries shadow
      same-named slots. Coverage: `block_slot_capture` parity plus unit tests.
      This also corrected a unit test that asserted the earlier, wrong behaviour.
- [x] Integrate inactive-home returns into non-resumable Harding errors; keep
      internal non-local-return transfers invisible to application handlers.
- [x] Remove obsolete signal-point snapshot restoration and native resume control
      machinery; retain signal-site diagnostic metadata. Debugger/external audits
      remain separate coverage items.
- [x] Dispatch failures are catchable by `on:do:` again. `MessageNotUnderstood`
      derived from `Exception`, so `on: Error` did not catch a failed send even
      though main's commit message and CHANGELOG said it did; it now derives from
      `Error`. A signal raised from `doesNotUnderstand:` also unwound the shared
      activation stack under a nested evaluation, crashing with "index out of
      bounds, the container is empty" on `[1 foo]`; `wfPopActivation` now reports
      completion when its activation is already gone, and every eval-stack
      restore is clamped to the live length.
- [x] Missing immediate sends preserve handler results: the VM now schedules
      doesNotUnderstand: as an ordinary send rather than synchronous executeMethod.
      Instance/class lookup exhaustion signals MessageNotUnderstood; native generic,
      class and super lookup misses raise the same catchable Error subclass. Custom
      inherited DNU may recover, including nil results; cleanup precedes handlers
      and uncaught exit. Executed parity covers these paths.
- [x] Correct compiled implicit method returns: methods answer self without ^,
      including literals, empty bodies, assignments, handled errors and cleanup.
      Explicit ^ supplies a value; blocks keep last-expression results. Removed
      the duplicate method-statement emitter and use ordinary genStatement.
      Executed parity: implicit_method_returns.
- [x] Preserve interpreter class-side receiver representation on implicit return.
      Activation self initialization and method fallthrough share receiverValue;
      a class-side receiver remains vkClass rather than an instance wrapper.
      class_return_representation covers inherited/chained sends, explicit self,
      empty methods, escaped self blocks, handled errors and cleanup.
- [ ] Add executed interpreter/Granite parity tests for the contract's validation
      matrix, including invalid operations and unhandled-error exit status.
- [ ] Update manual, quick reference, stdlib comments and stale research notes to
      describe implemented semantics; avoid claiming the migration is done early.

## 3. Correct non-local returns

- [x] Replace compiled method IDs with unique activation targets captured by
      block environments; deactivate targets when their invocation exits.
- [x] Test recursive callbacks and nested-loop returns; explicitly test compiled
      rejection of escaped-block returns rather than claiming VM parity.
- [x] Detect inactive compiled home targets with native BlockCannotReturnError.
- [x] Correct VM inactive-home returns: a return whose home invocation has
      finished now signals `BlockCannotReturn` instead of silently acting as a
      local block result. Both engines raise the same catchable Error subclass,
      and `inactive_return_target` is now real parity rather than a compiled-only
      check. Legacy tests that used escaped `^` as an ordinary block result were
      migrated to final expressions, and one test that never invoked its block
      was corrected.
- [x] Audit deferred GUI callback returns: two Browser dialog callbacks used ^
      after their creating method finished. Validation now branches without a
      non-local return. Headless callbacks test empty/valid inputs under ARC/ORC.
- [ ] Complete escaped-^ migration audit: 136 .hrd files parse in the current
      checkout, five fail parsing and installed external .hrd sources are absent.
      Seven selected examples/benchmarks have execution parity; storage fails
      natively on unsupported Array new:. Markdown/dynamic callback registration
      and foreign/process paths remain unverified. See docs/GRANITE_AUDIT.md.
- [x] Ensure cleanup executes while unwinding in tested native and VM paths;
      process and legacy re-entrant paths remain follow-up coverage.

## 4. Complete object-model dispatch

- [x] Lowercase top-level variables are consistent: file scripts, the REPL and
      `harding -e` all run top-level code as the `#doIt` method on
      `UndefinedObject`, so `x := 1` and `| x |` are locals and only uppercase
      names are globals. Earlier `-e` used a no-activation path and rejected
      lowercase assignments.
- [x] Encode generated binding/slot identifiers for Nim keywords and backend-owned
      names. Definitions, reads, assignments, method/block parameters, capture env
      fields, numeric expressions and slot accessors share identifier mangling;
      original selector and slot strings are unchanged. reserved_identifiers
      executes keyword/helper-named locals, captured bindings, slots and blocks.
- [x] Encode ordinary spelling identity: only all-lowercase alphanumeric names
      are emitted verbatim, so `fooBar`/`foo_bar`/`slotValue` no longer fold onto
      their lowercase forms under Nim's style-insensitive comparison. `mangleSlot`
      keeps punctuation and case instead of stripping them. Coverage:
      `case_sensitive_bindings` parity and fold-distinctness unit tests.
- [x] Class and module names no longer collapse case and punctuation.
      `mangleClass` and `mangleModuleName` hex-encode so distinct spellings
      (`FooBar`/`Foobar`, `MyClass`/`My_Class`, hyphenated filenames) never share
      one Nim identifier; string tables keep original class spellings. Coverage:
      `class_name_spelling` plus unit tests.
- [x] Native table literals and built-in collection construction: `Table`/
      `Array`/`Set`/`String` literals and `new`/`new:`/`new:withAll:` work in
      compiled code, and `benchmark/storage.hrd` runs natively. Coverage:
      `native_collections`. Remaining collection protocols and reflection are
      separate items.
- [x] Multi-value engine discrepancy: the interpreter now prints booleans as
      `true`/`false` like compiled code and `True>>printString`, instead of
      `<instance of True>`. Coverage: `boolean_display`.
- [x] Multiple inheritance: compiled dispatch registers every parent in
      declaration order and walks the parent graph depth-first with a cycle guard;
      `addSuperclass:` works at runtime. Coverage: `multiple_inheritance`.
- [x] Qualified `super`: instance/class-side and inherited methods and their
      blocks select a direct parent of the declaring class, retaining the receiver
      and arguments. Native runtime rejects unrelated classes and indirect
      ancestors as qualifiers, matching VM validation. Coverage:
      `qualified_super`, `invalid_qualified_super`, `indirect_qualified_super`.
      Invalid qualifiers remain evaluation errors rather than catchable Harding
      signals; engine diagnostic formatting differs.
- [x] Object identity sends: native `==`/`~=` operator helpers, generic and cached
      sends share VM-compatible identity comparisons for objects/classes/blocks
      and immediate values. Wrappers sharing retained native storage have one
      identity; `=` still dispatches value equality. Coverage: `object_identity`
      plus ARC/ORC runtime/support tests. Collection identity/layout and dynamic
      `perform:` override semantics remain separate coverage items.
- [x] Dynamic sends: `perform:`/`with:`/`with:with:` and `respondsTo:` work in
      compiled code for instances and classes. Coverage: `dynamic_send`. Full
      reflection parity is a separate item.
- [x] User-class reflection: compiled instances expose `class`, `className`,
      `superclassNames`; class receivers expose `class`, `name`, `className`,
      `superclassNames`. `isKindOf:` visits every parent, including transitive
      secondary parents, in both engines and requires a class argument. Coverage:
      `class_reflection`, runtime tests, interpreter dynamic-feature tests.
      Immediate/built-in reflection, class-side `isKindOf:` and method-list
      reflection remain open. Canonical `Root`/`Object`/`Mixin` class values
      support base-class ancestry targets without accepting symbol/string aliases;
      other built-in class identities and allocators remain separate work.
- [x] Reflection fast-path overrides: the VM's class-side `name` and instance
      `class` fast paths answered directly and bypassed user methods, while
      compiled dispatch honored them (`Override class>>name [^ "custom"]`). Both
      fast paths now answer only when the receiver's ordinary dispatch resolves
      the selector to Object's own definition, sharing one helper with the
      `perform:` guard, so an override keeps ordinary dispatch. Coverage:
      `class_reflection` parity plus interpreter tests, including a
      no-override case proving the fast paths still answer.
- [x] Generic missing-message errors instead of silent nil, including compiled
      instance/class/super lookup and custom DNU. Wrong-type primitive fallback,
      reflection and mixed-mode ambiguity remain separate coverage items.
- [x] Reconcile nil-predicate overrides: the interpreter's isNil/notNil fast
      path now falls through to ordinary dispatch when the receiver's class
      overrides the predicate, so both engines honor `notNil [ ^ false ]`.
      Coverage: `nil_override`.

## 5. Exceptions, processes and libraries

- [ ] Verify conventional errors, synchronous notifications, and cleanup using
      executed tests (see accepted exception-model change above).
- [ ] Evaluate continuation/state-machine lowering only where processes require
      it; arbitrary error resumption is no longer a language requirement.
- [ ] Lower errors to **scope-based unwinding** rather than a return-code at every
      call site. The VM already does this: `primitiveSignalImpl` computes
      `unwindDepth` from the dynamic handler stack (`-1` when no handler is
      installed) and `scheduleUnwindCleanup` walks registrations down to the
      matching handler. Generated code should follow the same policy — a handler
      installs a region/depth, an error skips directly to it, and only then is a
      transfer value used. Treating every call as potentially failing would
      double code size and cost for no benefit given one transfer kind.
- [ ] Introduce a **dynamic-result (erased) type** for sends whose result type is
      unknown (`perform:`, polymorphic receivers, library boundaries). Granite's
      inferred `varTypes` currently has no "unknown type" representation, which is
      why inference-backed specialization and boxing removal are not yet
      expressible. This is a prerequisite for unboxing, not a preliminary to it.
- [ ] Decide the inheritance model. Single inheritance permits inline-cache and
      layout optimizations that multiple inheritance mostly prevents; multiple
      inheritance (Harding's mixed-in-parents feature and Bona's Browser) keeps
      dispatch fully dynamic. Cranelift-class JITs, for example, are explicitly
      single-inheritance-only for this reason. Our now-removed resumption
      (`resume:`) was the one construct that would have needed continuation
      support; with it gone, no error-handling construct requires continuations.
      Background on continuation mechanisms: Nimony's `.passive` procs (CPS) risk
      introducing colored functions and suspendability obligations through
      `ensure:`, so adopting that model for processes is a deliberate trade, not a
      free win. `scripts/probe_nimony.py` runs isolated `.passive`/defer/closure
      probes against a locally unpacked toolchain and records compatibility; it
      does not replace the pinned Nim toolchain and downloads nothing.
- [ ] Catch/translate error and return transfers at C ABI boundaries; validate
      foreign callback lifetime and resource ownership.
- [ ] Compile library-heavy applications without interpreter fallback.
- [ ] Complete mixed-mode execution coverage separately from pure compilation.
      Value/shim/slot/block/super host slices work in executed tests; arbitrary
      control transfers and automatic mixed startup remain incomplete. See section 6.

## 6. Frozen stdlib and the engine boundary

Status: **partial implementation, not complete mixed-mode compilation.**
Instance/class shims, live method guards, value/slot/block/super host dispatch,
explicit embedded hosts, checked frozen source composition and limited native
sealing have executed regressions. Remaining language/protocol choices and
control-transfer defects are listed below. The historical baseline records the
original measurements, not the current implementation.

### Two deliverable modes

1. **Full compilation.** Everything is compiled; no runtime code changes are
   permitted. Frozen classes may be sealed outright.
2. **Partial compilation.** Frozen classes compile natively; unfrozen code keeps
   running in the embedded interpreter, and user code can create classes at
   runtime. This is the intended shape for a compiled Bona: tools and stdlib
   compiled, user Workspace code interpreted, Smalltalk-style live definition
   preserved. Image persistence is still out of scope.

### What "frozen" means

"Frozen" is a **compile-time artifact**, not a new core concept. A `.hrd` file
declares it with a header comment annotation (`# @frozen`); the annotation is the
declaration of intent, and a checked manifest is the enforcement.

Frozen classes come in three tiers:

| Tier | Mechanism | Intended use |
|---|---|---|
| Generic | `.hrd` source compiled to Nim codegen | Default; broadest stdlib coverage |
| Counterpart | Hand-written Nim implementation of the same semantics | Collections, Integer, String — where representation control pays |
| Sealed | No runtime redefinition permitted | Full-compilation deliverables |

Counterpart classes accept two sources of truth. That is already true of the
existing `nt_*` helpers, but it must be made *checkable*: a frozen class whose
counterpart has no executed conformance case against the interpreter path fails
the build. Reuse the `examples/manifest.json` discipline (unlisted/stale entries
fail) and the existing parity runner.

Freezing is meaningful only as a **dependency closure**, not per file. Freezing
`SortedCollection` alone gains little because it calls Array, Iterable and
closures over `sortBlock`; a set of classes must be frozen together.

### Historical baseline: crossing did not exist

Measured in `granite-completeness` at commit `5be9168`:

- `--mixed` compiles calls to `sendMessageHybrid` (`codegen/expression.nim:734`).
  That function (`runtime/runtime.nim:1863`) **rebuilds source text** from
  `receiver.toString()` and `evalStatements`. Object identity, captured state and
  block closures do not survive the crossing.
- Nim-proxy receivers are explicitly unsupported there: it prints a warning and
  returns `nil`.
- `registerCompiledMethod` writes only `compiledMethodProcs` and never
  `Class.methods`; the interpreter contains **zero** references to
  `compiledMethodProcs`. Interpreted code therefore cannot reach any compiled
  method at all. *(Fixed by step 1: generated modules now emit per-method shims
  bound onto the interpreter's method table.)*
- No mixed-mode regression tests exist. The flag is unexercised.

For a compiled Bona the missing direction is **interpreted → compiled**: a
Workspace Do It sending `SortedCollection new add: 3` must reach a compiled class.
Compiled → interpreted fallback is the second half.

### Why the dangerous direction is cheap

`lookupMethod` (`interpreter/vm.nim:881`) returns a `MethodResult` carrying a
`BlockNode`, not a callable — which looks like a blocker. But the VM already
invokes `nativeImpl` procs off `BlockNode`s (`vm.nim:1067-1081`, `8011-8105`;
`hasInterpreterParam` distinguishes the two arities). Each registered compiled
method therefore gets a shim `BlockNode` whose `nativeImpl` adapts the call:

```nim
proc adapter(interp: var Interpreter, self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledMethodProcs[key](self, args)
```

The interpreter then dispatches into compiled code through machinery it already
has — no new dispatch mechanism, no marshalling, and the receiver stays a real
`Instance`, so identity and captured state survive. `NodeValue` and `Instance`
are shared types (`core/types.nim`), and the compiled runtime already imports
them, so no source-text serialization is needed. Shared types alone do not
establish compatible native slot layouts, class identity, block calling conventions
or stackless control transfers; those remain separate boundary requirements.

### Redefinition policy (agreed)

When runtime code redefines a frozen class or method:

1. **Hard error** — simplest; the posture for full-compilation deliverables.
2. **Shadow** — user definition wins for new sends while compiled call sites keep
   the baked-in body. Fast but yields two behaviours for one class and must not
   be the default.
3. **Deoptimize and fall back** — frozen call sites carry a guard; a change
   invalidates it and dispatch falls back to the interpreter. **Agreed default
   for partial compilation**, because silent divergence is the worst outcome.

The existing `compiledClassDispatchVersion` (`runtime/runtime.nim:158`) already
implements this invalidation pattern for guarded allocation and per-site caches
(`runtime.nim:1821`), so (3) reuses established machinery rather than new design.

### Staging

Effort is relative to this codebase, not a schedule commitment.

1. **[x] Shim dispatch.** Interpreted code reaches compiled method bodies.
   Generated modules emit distinct instance and class-side shim procs with class/selector
   baked in, plus `bindCompiledMethodsTo(interp)`; `bindCompiledMethodShim` binds
   it onto the interpreter's own method table as the native implementation, so
   ordinary VM dispatch reaches compiled code. Receiver identity and arguments
   survive; an existing hand-written native implementation keeps precedence.
   Coverage: `tests/test_engine_boundary.nim` (ARC and ORC), generated-shim
   codegen assertions and `tests/test_engine_boundary_generated.py` (run via
   Python unittest discovery after building Granite; ARC/ORC generated host).
   Generated shims initialize the native runtime before invoking compiled bodies;
   integration tests exercise inherited factories with `self new`.
   Note: a single generic adapter that reads its own selector from the running
   activation does **not** work — during native dispatch
   `currentActivation.currentMethod` is the enclosing `doIt`, not the method being
   invoked. Per-method shims keep the identity static.
2. **Guard and deoptimize (method-send slices implemented).** Explicitly bound
   classes retain their host interpreter and original instance/class shim identities.
   Generic and cached native sends check live method resolution before using a
   compiled target; replacements and runtime subclass overrides dispatch via a
   literal-valued VM message, without source reconstruction or nil-as-miss.
   Hosts release registrations with `unbindCompiledMethodsFrom` before disposal.
   Detach restores original interpreted/native-dispatch metadata only for shim
   pointers still owned by that registration, preserving runtime replacements and
   allowing rebind. Instance/class detach and recovery are tested under ARC/ORC.
   Coverage: warm-cache replacement, subclass nil overrides and unchanged inherited
   shims in `test_engine_boundary`. The guard currently resolves live methods on
   every bound send rather than relying on interpreter mutations updating the
   compiled version counter. Class-side method replacement now uses the same
   live-resolution guard with separately tracked class-side shims. Layout replacement,
   exception/return translation, scheduler suspension and
   full-deliverable sealing remain follow-up work; this is not complete deoptimization.
3. **Value-based host sends implemented; full mixed mode still open.**
   `sendMessageInterpreted` builds a literal-valued VM message and uses the
   non-fatal callback boundary. `sendMessageHybrid` selects the engine by receiver
   ownership before execution: interpreted objects/classes reach live VM methods
   and bound shims; native-layout proxies, compiled blocks and native collection
   owners stay native. Nil is a successful result; a missing send or failure
   inside a compiled body is never retried in the interpreter. Tests cover object
   and block identity, captured state, nested round trips, missing messages and
   host recovery. Unbound native-layout proxies reject interpreted slot access.
   Slot access is now layout-dispatched (`getSlotValue`/`setSlotValue`), so compiled
   methods read and write interpreter-owned instances, runtime subclasses and native
   instances through each receiver's own layout instead of casting to a generated
   Nim type; `::` keeps its permission checks instead of lowering to `at:`.
   Compiled closures now carry an explicit `compiledInvoker` callback, separate
   from the native-method ABI. VM block application, direct invocation and native
   primitive helpers use it without copying captured cells into VM activations.
   The native runtime shares the same arity-checked dispatcher (0–3 arguments).
   Generated ARC/ORC coverage includes captured updates, collection callbacks,
   conditional/loop callbacks, nil and recovery after a wrong-arity send.
   Compiled-created native objects are now adopted automatically on first
   interpreted use when live slot names/order match exactly and accessors are
   registered, which removes the remaining mirroring step for normal crossing.
   Hosts can still call `bindNativeInstanceTo(interp, value)` eagerly for retained
   native object wrappers; mismatched layouts are refused in both paths. Binding validates exact live slot names/order, snapshots native
   accessors and adopts live class identity without a mirrored VM slot array.
   Interpreted ASTs, named/reflected slot access, escaped closures, JSON and shallow
   clones use the bridge; clones have independent ordinary VM slot storage.
   A changed live layout is rejected rather than migrated. Bound native receivers
   participate in live method guards, including warmed-cache replacement fallback.
   Hosts release retained host registrations with `unbindCompiledMethodsFrom`.
   Generated statically named `ClassName new` sends in bound method bodies now
   resolve the target class in the receiver's host and use ordinary VM `new`,
   returning interpreter-owned objects. Escaped/nested method closures retain the
   receiver for the same routing. Pure native/top-level code keeps native allocation;
   no ambient interpreter or source replay is introduced. Live `new` overrides,
   including nil, are respected without native retry.
   Uppercase global reads in bound methods/escaped closures now use isolated VM
   lookup (including imported libraries), retaining lexical local/slot precedence.
   Reads stay live after alias rebinding; nil/missing values do not fall back to
   native globals. Ordinary class sends, including local aliases and class-valued
   parameters, use the receiver's host even when the target class has no shims.
   Pure native reads keep their existing fallback.
   Uppercase global writes in bound methods/escaped closures assign through a fresh
   host VM block activation, so imported-library bindings, protected names and
   class renaming follow the interpreter's own `setVariable` path. Existing,
   newly created and imported variables work, including `nil` values; pure native
   writes keep `setGlobal`. Compiled blocks whose last statement is an assignment
   now answer the assigned value like the interpreter, evaluating the RHS once.
   Specialized builtin sends are now hosted as well: in bound methods, `size`,
   `last`, `keys`, `at:`, `at:put:`, arithmetic/comparison operators, `abs`,
   `even`, `odd`, `negated`, `asString` and `&` first offer interpreter-owned
   receivers to the calling method's host, falling back to the native helper.
   Runtime-defined overrides and VM collection species therefore apply, while
   primitive and native-collection receivers keep the fast helpers and pure
   compiled code retains native dispatch. Helper operands are stored once in
   left-to-right order before engine selection; fallback never repeats expressions.
   Native collection ownership is checked by class identity, unbound proxies stay
   native, and `==`/`~=` preserve native identity handling rather than entering the
   VM. Static allocation now resolves its class through the same isolated VM lookup
   as global reads, including imported-library precedence. Bound super sends now
   locate the lexical class in the live receiver hierarchy and use a non-fatal VM
   super entry with saved/restored host context. Direct/qualified parent lookup,
   class identity, escaped closures, native slot bridges and replacements have
   ARC/ORC regression coverage. This does not translate error/return transfers.
   Remaining: complete global/class resolution,
   layout migration, success-branch cross-engine transfers, yielding and automatic
   mixed startup. Checked modules have an explicit embedded host factory (step 5),
   while the legacy `--mixed` source-replay bootstrap remains outside that path. Class-side native shims now use
   the VM's NodeValue-native ABI, preserving actual/inherited class receiver identity.
   This does not yet establish a compiled Bona or arbitrary `--mixed` support.
4. **Frozen collections (Bag and Array slices done).** SortedCollection and Bag
   use the same interpreter/native protocols with executed conformance cases
   (`stdlib_sorted_collection`, `stdlib_bag`). User decision: Array doubles as
   OrderedCollection, so no separate OrderedCollection class is added. Bag lives
   in `lib/core/Bag.hrd` and compiles generically: duplicates count, `remove:`
   drops one occurrence, queries keep Bag species and `removeAll` clears in place.
   Bag declares its protocol explicitly rather than inheriting the Iterable mixin,
   because native class creation does not model mixins.
   The actual SortedCollection source now compiles generically with executed
   `stdlib_sorted_collection` conformance (insertion/duplicates, callbacks, queries,
   copies, indexed removal, comparator construction and conversions). Native
   `basicNew` allocates without initialize. Statement-level `add:` no longer
   rewrites the receiver binding with the added item; shared storage needs no
   writeback. User-approved Array `removeAll` clears in place and answers self
   in both engines. Native Array `sorted`/`sorted:` return independent shallow
   arrays using the interpreter's insertion-sort policy. SortedCollection clear,
   resort and comparator replacement now have exact-output conformance coverage.
5. **Generic freezing (experimental checked slice implemented).**
   `config/granite-frozen.json` inventories the annotated SortedCollection source
   and declared native-counterpart closure. `freeze-check` rejects missing/stale
   sources, annotations, entries, cases and undeclared uppercase references in
   generic ASTs. `scripts/check_frozen.py` executes every named parity case and
   writes a receipt bound to manifest, engines, runner, Nim runtime sources and
   all embedded `lib/**/*.hrd` bootstrap sources;
   failure removes old receipts. `--freeze-manifest` plus `--freeze-receipt`
   composes generic definitions with application ASTs (including script temporaries
   and `Harding compile:/main:` scopes) without executing application source twice.
   `nimble testFrozen` exercises this path. The receipt is local build evidence,
   not a signature or security gate. SHA-1 is a drift checksum, not authentication.
   `--seal-frozen` additionally seals the named native registries after startup
   registration. Instance/class method, allocator, slot-layout/accessor and parent
   registration APIs reject subsequent writes before cache/version changes; normal
   initialization finishes before sealing. Default partial compilation is unchanged.
   A sealed application AST preflight rejects direct frozen class reassignment,
   instance/class method definitions/removals and parent mutation, including nested
   compile/closure/cascade forms, before executing reflection definitions. Lexical
   parameter/temporary shadows and ordinary sends remain permitted. This remains
   syntactic/native-registry enforcement: aliases, dynamic perform/evaluate,
   VM mutation and direct Nim field/table writes are not proven safe, so it is not
   the complete full-deliverable contract.
   Not complete: dependency analysis is syntactic, counterpart dependencies are
   declared, dynamic selectors/evaluation are not proven closed, conformance covers
   listed protocols rather than every method, and full-deliverable enforcement,
   whole-stdlib compilation and automatic mixed bootstrap remain open. Checked
   modules expose `newFrozenHost()` for explicit embedding: it creates a scheduler
   host, loads embedded stdlib sources once, and binds generated method shims;
   application statements and the application source file are not replayed.
   `packageOnlyLoads` prevents bootstrap/Harding/Library loads from reading disk
   and propagates through isolated evaluation and forks. The current factory uses
   the standard core bootstrap; custom bootstrap and external-library packaging
   are not established. This embeds source for VM bootstrap, not whole-stdlib
   native compilation. `--mixed` with a freeze manifest still fails explicitly.

### Open discussion gates and completion evidence

The original steps 1–4 target the compiled-Bona scenario, but the current tested
host slices do not establish that complete deliverable. Do not check all stages
complete from the focused host or freeze-task results.

- Collection decisions agreed and implemented: Bag exists in both engines from
  one generic source, and Array remains the ordered collection instead of a new
  OrderedCollection class. Array `removeAll` clears in place and answers self.
  Array-literal parsing still treats a bare uppercase identifier as a symbol, so
  tests parenthesise such elements; that is existing dialect behaviour.
- Fixed interpreter defect: redefining a derived class into an existing global
  kept the creation placeholder name (`Object+Derived`), and binding an existing
  class to a new global (`Alias := Bag`) renamed the original class. Binding
  names now apply only while a class still carries a placeholder name, in both
  assignment paths.
- Engine transfer translation implemented (user-approved).`CompiledHardingError`
  and compiled non-local returns raised inside an interpreted call are now caught
  at the VM's native/compiled-block invocation sites: pending interpreted
  `ensure:` scopes run first, then an error is signalled into the interpreter so
  ordinary `on:do:` handling applies, and a return token stops VM unwinding and is
  re-raised to its compiled home. Error identifiers become Harding exception
  class names (unknown names fall back to a VM diagnostic). Uncaught compiled
  errors keep their previous diagnostic and do not terminate a host. Return
  targets are not compared across engines: `BlockCannotReturn` still applies only
  within an engine. Regression coverage:
  `test_engine_boundary` (ARC/ORC) for handler, cleanup and uncaught paths.
- Evidence: full native parity sweep covers all 98 cases; the latest run passed
  97 in-suite and the remaining `benchmark_queens` case passed in an isolated
  rerun (it timed out at 30s in the interpreter while a build saturated the host,
  not a semantic mismatch). An earlier sweep passed 98/98 in one run. Interpreter
  regressions pass: 388 tests across exception handling, interpreter core,
  closures, load/eval, scheduler, precedence, primitives, dynamic features,
  literals, slots, extend, cascade, floats, nil conditionals, tagged values,
  library namespace, signal points, source editing and stdlib collections. Freeze task executes the declared
  parity cases, manifest/host unit tests under ARC/ORC and the Python gate/build
  tests including generated ARC/ORC hosts. These tests do not prove dynamic
  dependency closure, every counterpart method, full sealing, native process
  suspension, complete C ABI lifetime coverage or compiled Bona acceptance.

The original plan aimed to reach this scenario **without** requiring generic
whole-stdlib compilation.
Step 5 is the real project and carries the schedule risk; it is not a prerequisite
for the target user experience. Keep sealing posture (step 2) orthogonal to freeze
annotation (step 5): "can the two engines talk" and "may this class change" are
separate axes and should not be entangled.

Not covered here: debugging across the boundary, GC/ownership interaction between
engines, process/green-thread state, and library-external classes.

## Legacy work salvage

See [LEGACY_GRANITE_AUDIT.md](docs/LEGACY_GRANITE_AUDIT.md) for original commit
IDs, saved evidence, and deferred choices. Log and stream aliases are salvaged;
old resumption lowering and unguarded self/slot optimizations are not restored.
Collection/reflection implementations remain design material for section 4.
Printable output routing and the three historical stashes are retained for
separate review, not silently applied or dropped.

## 7. Optimize after semantic coverage

Near-term order: measured numeric-local unboxing, collection semantics, then
native processes. Numeric optimization may proceed independently. Before
choosing a native-process lowering, extend the isolated Nimony passive-proc probe
to nested calls, captured state, cleanup, errors, lexical non-local returns and
foreign callbacks; passing a suspend/resume smoke test alone is not sufficient.
Nimony is an evaluation target, not a replacement for the pinned Nim toolchain.

Measured baseline and methodology: [GRANITE_BENCHMARKS.md](GRANITE_BENCHMARKS.md).
On the trial-division benchmark Granite native is ~89x faster than the release
interpreter but ~40x slower than C and ~25x slower than Nim, consistent with
tagged values and dynamic dispatch. Use that benchmark to evaluate the items
below rather than relying on impressions.

- [ ] Direct calls and specialization.
- [ ] Unboxing.
- [ ] Dispatch caching.
- [x] Add checked object/allocation benchmarks: full eight-queens backtracking
      (92 solutions) and linked-object Towers of Hanoi (8191 legal moves).
      `scripts/bench_objects.py` compares release interpreter, Granite and native
      Nim with per-trial output checks, timeouts and startup subtraction.
- [x] Fix correctness defects exposed by those workloads: native instance wrappers
      retain their storage, nil predicates work without bypassing user overrides,
      capture traversal handles specialized control flow/named access, and writes
      to enclosing method temporaries share bindings.
- [ ] Measure Cog on the same queens/towers algorithms before estimating a
      cross-workload performance gap. Sieve numbers alone do not predict it.
- [x] A, first slice: specialized if/while blocks lowered inline no longer enter
      closure registration or capture-cell analysis. Ordinary method parameters
      and temporaries used only there stay stack values; nested escaping closures
      and branches with non-local returns retain their environments. Generated-code
      tests assert no MutableCell/home target for a plain accumulator loop.
- [ ] Complete capture precision with lexical binding identities, including
      declarations inside nested scopes; the current analysis remains name-based.
- [x] B, first slice: script-local integer/float bindings initialized directly with
      numeric literals specialize only when every assignment retains its kind and
      every read follows definite initialization. Same-kind +, -, *, comparisons
      emit native operations; ordinary message arguments/results remain NodeValue.
      Captures, shadowing, real closures, globals, mixed mode and type changes fall
      back to dynamic. Division/modulo are deliberately unchanged.
- [x] B, method-local slice: explicitly declared method temporaries initialized
      directly to numeric literals use native storage only when every read follows
      initialization and every assignment retains one kind. Slot/argument names
      are excluded before dependency analysis. Captures, shadowing, real closures,
      type changes and division fall back to dynamic. Parameters/slots remain boxed.
- [ ] Extend B to loop-local declarations/parameters and interprocedural types,
      with sound joins and arithmetic-error/overflow tests. No parameter or slot
      unboxing is claimed by the method-local slice.
- [x] C, first slice: statically named class allocation uses a guarded native
      allocator when no inherited/own class-side new method exists. Allocator,
      class-method and superclass registrations invalidate the cached guard;
      fallback retains ordinary dispatch. Mixed mode and locally shadowed class
      receivers do not use this fast path.
- [ ] Extend C to method targets with exact receiver proofs or guarded dispatch;
      preserve overrides, declaring-class super and return/cleanup semantics.
- [x] D, first slice: pure generic send sites own thread-local positive
      monomorphic caches for registered instance methods. Receiver class, selector
      and registration version guard each hit. Method, class-method, allocator and
      superclass registration invalidate targets; nil is a valid cached result.
      Builtins, exception protocols, class-side sends and mixed mode retain the
      generic runtime path. Runtime invalidation tests and alternating receiver
      parity cover this slice.
- [ ] Extend D with polymorphic sites and compact class/selector identities after
      measurements. Concurrent mutation/direct writes to exported runtime tables
      are not covered by this registration-based invalidation contract.

## Validation entry points

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
nim c -r tests/test_class_model.nim
python3 scripts/test_granite_parity.py
```

Use additional focused suites for changed behavior. Full suite completion is
required before claiming full compiler parity; known hangs must not be hidden.
