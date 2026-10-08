# Granite completeness work

Work branch: `granite-completeness`.

## Validation

Build the interpreter with `nimble harding` and the compiler with:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py
```

The focused parity runner checks both engines against explicit expected output.
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

Twelve execution-parity cases pass, including escaped closure environments,
inherited method ownership,
class-side `super` in blocks, multi-level constructor inheritance, dynamic
accessors, selective read/write accessors, and overridden accessor methods. The VM now uses
class-side lookup and preserves class-side activation context for `super` sends.
The class-model unit suite also passes.

Compiled environments are managed heap references owned by their BlockNode.
Returned closures with string captures pass under ARC and ORC. Mutable captures
still use copied values with writeback; shared cells and sibling/nested binding
semantics remain unfinished. Recursive/escaped returns also remain follow-up work.

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
5. Resumable exceptions, processes, and library compilation. Determine which
   semantics require continuations or state-machine lowering before claiming
   parity with the stackless VM.
6. Optimization after semantic coverage: direct calls, specialization, unboxing,
   and dispatch caching.

The compiled runtime currently follows one superclass chain. Class-side support
does not imply multiple-inheritance parity, class-slot support, or general
reflection parity. Mixed-mode behavior also needs separate execution coverage.
