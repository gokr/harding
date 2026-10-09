# Granite completeness plan

Work in branch `granite-completeness`. Prioritize semantic correctness over
optimization. Each coherent change needs executed regression coverage, a
changelog entry, and build/test validation. Update this checklist as work lands.

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

## 3. Correct non-local returns

- [ ] Replace method IDs with unique activation targets.
- [ ] Test recursion, callbacks, nested loops and escaped-block returns.
- [ ] Detect returns to inactive home activations.
- [ ] Ensure cleanup executes while unwinding.

## 4. Complete object-model dispatch

- [ ] Multiple inheritance and qualified `super`.
- [ ] Dynamic sends and reflection.
- [ ] Proper missing-message errors instead of silent nil.

## 5. Exceptions, processes and libraries

- [ ] Verify resumable exceptions using executed tests.
- [ ] Decide continuation/state-machine lowering for semantics that native
      stack execution cannot preserve.
- [ ] Compile library-heavy applications without interpreter fallback.
- [ ] Cover mixed-mode execution separately from pure compilation.

## 6. Optimize after semantic coverage

- [ ] Direct calls and specialization.
- [ ] Unboxing.
- [ ] Dispatch caching.

## Validation entry points

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
nim c -r tests/test_class_model.nim
python3 scripts/test_granite_parity.py
```

Use additional focused suites for changed behavior. Full suite completion is
required before claiming full compiler parity; known hangs must not be hidden.
