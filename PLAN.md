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

## 1. Finish class-side and accessor semantics

- [x] Preserve defining-class ownership for inherited methods and `super`.
- [x] Test class-side `super` in nested blocks.
- [x] Test multi-level constructor inheritance.
- [x] Register dynamically dispatched generated accessors as compiled methods,
      respecting read/write permissions and user-defined overrides.

## 2. Correct closure semantics

- [x] Share mutable capture cells instead of copying independent values.
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
- [ ] Reflection fast-path overrides: VM class-side `name` bypasses user methods,
      while compiled lookup honors them (`Override class>>name [^ "custom"]`).
      Instance `class` overrides also need reconciliation with VM's fast path.
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
- [ ] Cover mixed-mode execution separately from pure compilation.

## Legacy work salvage

See [LEGACY_GRANITE_AUDIT.md](docs/LEGACY_GRANITE_AUDIT.md) for original commit
IDs, saved evidence, and deferred choices. Log and stream aliases are salvaged;
old resumption lowering and unguarded self/slot optimizations are not restored.
Collection/reflection implementations remain design material for section 4.
Printable output routing and the three historical stashes are retained for
separate review, not silently applied or dropped.

## 6. Optimize after semantic coverage

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
- [ ] Extend B to lexical method/loop bindings and interprocedural types, with
      sound joins and arithmetic-error/overflow tests. No method parameter or slot
      unboxing is claimed by the first slice.
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
