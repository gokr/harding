# Granite completeness plan

Work in branch `granite-completeness`. Prioritize semantic correctness over
optimization. Each coherent change needs executed regression coverage, a
changelog entry, reference-manual review, and build/test validation. Update this
checklist as work lands. Compiler fixes must conform to documented Harding
semantics; any intended language change must be explicit and documented.

## Baseline

- [x] Bounded execution-parity runner with isolated workspace build artifacts.
- [x] Nested output-directory imports.
- [x] Class-side method extraction, registration, receivers, aliases and factories.
- [x] Class-side `super` lookup in the interpreter.
- [x] Seven executed parity cases and class-model unit tests passing.
- [ ] Diagnose the older block-parity suite's nested-control-flow hang.
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
- [ ] Complete compiled exception hierarchy/instance protocol, custom subclasses,
      arithmetic-error translation, defaultAction and diagnostic parity.
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
- [ ] Cover ensure scopes entered inside notification handlers during `pass`,
      arbitrary user defaultAction overrides, process yields and mixed mode.
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
- [ ] Two dispatch-failure defects remain, both **interpreter and compiled**:
      (a) `[1 foo] on: Error do: [:ex | ...]` answers nil instead of the handler's
          result, while `[Object new bar]` answers correctly — the DNU fallback in
          `wfSendMessage` runs the handler via `executeMethod` and its result is
          not propagated through the normal return path;
      (b) when a signal is handled inside an `on:do:` act that is the **final
          expression of a compiled method**, the method yields the signal's class
          name (`"Error"`) instead of the handler's result; returning the value
          once (`^`) fixes it.
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
- [ ] Audit remaining uses of escaped `^` across examples, benchmarks, docs and
      external libraries; run those suites to confirm nothing still depends on
      the previous silent behaviour.
- [x] Ensure cleanup executes while unwinding in tested native and VM paths;
      process and legacy re-entrant paths remain follow-up coverage.

## 4. Complete object-model dispatch

- [ ] Lowercase top-level script variables are rejected in some contexts
      ("Global variables must start with uppercase letter: r"), while `x := 1` at
      top level works; determine the intended rule and whether the checker should
      apply to scripts at all.
- [ ] Multiple inheritance and qualified `super`.
- [ ] Dynamic sends and reflection.
- [ ] Proper missing-message errors instead of silent nil.
- [ ] Reconcile nil-predicate overrides: the interpreter's unconditional isNil/
      notNil fast paths bypass registered user methods, while compiled dispatch
      checks overrides before the fallback. Minimal reproduction: a class with
      `notNil [ ^ false ]` answers true in the interpreter, false natively.
      Changing interpreter semantics requires discussion; benchmark parity only
      asserts the ordinary nil predicates, not this discrepancy.

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
      free win.
- [ ] Catch/translate error and return transfers at C ABI boundaries; validate
      foreign callback lifetime and resource ownership.
- [ ] Compile library-heavy applications without interpreter fallback.
- [ ] Cover mixed-mode execution separately from pure compilation.

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
- [ ] A: distinguish genuine escaping captures from literal blocks lowered inline;
      allocate MutableCell only where shared closure storage is required.
- [ ] B: introduce conservative value-type joins and numeric representations with
      boxing at dynamic boundaries; preserve arithmetic/error semantics.
- [ ] C: emit direct calls only for proven dispatch targets (or guarded targets),
      preserving overrides, declaring-class super and return/cleanup semantics.
- [ ] D: cache dynamic send targets with a defined invalidation policy; retain the
      generic dispatch path and differential correctness tests.

## Validation entry points

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
nim c -r tests/test_class_model.nim
python3 scripts/test_granite_parity.py
```

Use additional focused suites for changed behavior. Full suite completion is
required before claiming full compiler parity; known hangs must not be hidden.
