# Granite completeness work

Work branch: `granite-completeness`.

## Validation

Build the interpreter with `nimble harding` and the compiler with:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py
```

The focused parity runner checks both engines against explicit expected output.
`inactive_return_target` is labeled separately as a compiled-error check because
the VM currently permits returns to completed homes. Optional case names select
focused runs, e.g. `python3 scripts/test_granite_parity.py recursive_return_target`.
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

Twenty-seven successful-output parity cases, two unhandled-error parity checks,
and one explicit compiled-only inactive-return check pass. Coverage includes class-side and inherited
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
iteration. Compiled blocks retain a unique home-invocation return target;
recursive callbacks and nested-loop returns pass. Targets become inactive on exit,
and escaped non-local returns raise native BlockCannotReturnError. The recursive
callback regression also passes under ORC. The VM still treats completed-home
returns as local block returns. The accepted [exception model](EXCEPTION_MODEL.md)
removes arbitrary error resumption: integrate inactive-home errors with conventional
Harding errors and guarantee `ensure:` cleanup. Both engines must migrate together;
synchronous notifications do not require signal-point restoration.

The first error-model slice abandons VM protected work before handler execution
and excludes executing handlers from catching their own failures. Both engines
reject handled error resume/resume:, and native built-in Error/Exception signaling
supports handler results, return:, pass and retry. Core exception, signal-point,
compiler and website-example suites pass. Notification behavior remains legacy
in the VM and unsupported by this native error slice; synchronous migration is
next. Custom error subclasses, instance construction, arithmetic-error translation,
native defaultAction/diagnostics and mixed mode remain incomplete.

Generated accessor messages use ordinary compiled method registration, preserving
user overrides and inherited lookup. Generated setters return the receiver.
Direct named access (`::`) remains distinct from accessor message dispatch.
Compiler registration tests check that private and disallowed accessor directions
are not emitted. Missing-message error parity remains a later milestone.

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
