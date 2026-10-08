# Granite completeness work

Work branch: `granite-completeness`.

## Validation

Build the interpreter with `nimble harding` and the compiler with:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py
```

The focused parity runner checks both engines against explicit expected output.
The `class_super` case is explicitly labeled as a compiled-only semantic check
because the VM currently searches the wrong method side for `super`.
Each invocation uses a separate directory under `build/parity/`. Build logs and
engine output are retained. Execution defaults to a 30-second limit; compilation
defaults to 120 seconds. A timeout, failed build, failed engine, or incorrect
output fails the runner. Missing binaries fail rather than skip tests.

The older `tests/test_compiler_block_parity.nim` suite is not a comprehensive
compiled parity suite: most of its cases evaluate only the interpreter. During
initial assessment it stalled in `nested blocks with control flow`, after the
executed compiled case passed. Diagnose that separately; do not describe the
whole suite as passing until it completes.

## Measured interpreter discrepancies

Two focused cases need separate interpreter regression fixes:

- When `Base` defines both instance-side and class-side `answer`, a class-side
  `super answer` in a subclass invokes the instance-side method in the VM.
  Without an instance-side `answer`, that send fails even when a class-side
  implementation exists.
- `Product class>>new [ ^ super new initialize ]` fails in the VM with
  `Method 'new' not found in super class Object`.

Do not adopt these outputs as intended compiler semantics. The focused passing
cases separate same-selector side isolation from class-side `super` until the VM
is corrected. Keep recursive/escaped returns and mutable captures as follow-up
work rather than inferring correctness from the basic block cases.

Another compiled-runtime gap remains: dynamically dispatched generated slot
accessor messages are not registered as ordinary compiled methods. Factories
are covered using explicit instance methods; accessor visibility and registration
need their own regression coverage before changing dispatch.

## Implementation order

1. Bounded, isolated execution parity and output-directory-independent imports.
2. Class-side method extraction and registration; class receivers, inherited
   lookup, overridden `new`, factories, and class-side `super`.
3. Shared mutable closure cells and activation-specific non-local returns,
   including recursion and escaped-block lifetime checks.
4. Object-model parity: multiple inheritance, dynamic sends, missing-message
   errors, and reflection.
5. Resumable exceptions, processes, and library compilation. Determine which
   semantics require continuations or state-machine lowering before claiming
   parity with the stackless VM.
6. Optimization after semantic coverage: direct calls, specialization, unboxing,
   and dispatch caching.

The compiled runtime currently follows one superclass chain. Class-side support
does not imply multiple-inheritance parity, class-slot support, or general
reflection parity. Mixed-mode behavior also needs separate execution coverage.
