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
- [ ] Implement synchronous Notification dispatch/results and outer-handler pass;
      reject notification retry/return: without capturing resumable continuations.
- [ ] Implement exactly-once `ensure:` cleanup on normal exits, errors, retries,
      and lexical non-local returns, including nested cleanup and cleanup failures.
- [ ] Integrate inactive-home returns into non-resumable Harding errors; keep
      internal non-local-return transfers invisible to application handlers.
- [ ] Remove obsolete signal-point restoration machinery after migration; retain
      diagnostic information needed by default actions and debugger hooks.
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
- [ ] Correct VM inactive-home returns (currently treated as local returns),
      update legacy tests using escaped `^` as ordinary block results, and
      integrate compiler errors with the accepted non-resumable error contract.
- [ ] Ensure cleanup executes while unwinding.

## 4. Complete object-model dispatch

- [ ] Multiple inheritance and qualified `super`.
- [ ] Dynamic sends and reflection.
- [ ] Proper missing-message errors instead of silent nil.

## 5. Exceptions, processes and libraries

- [ ] Verify conventional errors, synchronous notifications, and cleanup using
      executed tests (see accepted exception-model change above).
- [ ] Evaluate continuation/state-machine lowering only where processes require
      it; arbitrary error resumption is no longer a language requirement.
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
- [ ] Add an object/allocation-heavy benchmark (e.g. `benchmark/towers.hrd`) so
      optimization work is not guided by an arithmetic loop alone.

## Validation entry points

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
nim c -r tests/test_class_model.nim
python3 scripts/test_granite_parity.py
```

Use additional focused suites for changed behavior. Full suite completion is
required before claiming full compiler parity; known hangs must not be hidden.
