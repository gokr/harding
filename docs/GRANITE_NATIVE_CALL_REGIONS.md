# Native Integer call regions (prototype)

The compiler plans pure expression methods with explicit returns, Integer
parameters, literals and `+`, `-`, `*`. It builds plans in dependency order so a
method can call a previously planned method through lexical `self`, keeping both
parameters and returns as Nim `int` across that call. No benchmark names or
selectors are special-cased. Methods with fallthrough, mutation, slots, callbacks,
recursion, division or real closures are not planned yet.

For example:

```smalltalk
Calc>>outer: n [ ^(self inner: n) * 3 ].
Calc>>inner: n [ ^n + 1 ].
```

produces the equivalent of:

```nim
proc inner_native(n: int): int = n + 1
proc outer_native(n: int): int = inner_native(n) * 3
```

There is no `NodeValue`, argument sequence or dynamic send *inside* this region.
A boxed adapter at its external boundary checks all input tags, exact receiver
class identity and the current registered procedure for every transitive method
dependency before entering it. Bound interpreters disable the native path. All
operands arrive evaluated before guards run, so argument-side method replacement
cannot select a stale body. Class/subclass mismatch, Float arguments, changed
methods and nil-returning replacements retain ordinary dispatch.

Selectors must be unique within the module for this first routing implementation.
This is a conservative candidate filter, not a claim that the world is closed.
No source declaration or training profile is needed for these pure regions.
Observed slot contracts can support later extensions, but this prototype does not
yet propagate slot values or loops into regions.

## Validation so far

- `tests/test_native_call_regions.py`: generated native chain, warmed calls,
  Float fallback, transitive method replacement, replacement during a once-only
  operand callback, subclass override, top-level replacement and nil results;
  executed under ARC and ORC.
- Compiler basic: 99 checks under ARC and ORC.
- Generated host fixture: the `answer` class-side test fails under both this
  prototype and the retained pre-prototype compiler; recorded in
  `build/native-region-host.log` and `build/native-region-baseline-host.log`.
  It remains an unresolved baseline failure, not a passing gate.
- Final broader parity sweep: **105 passed, 0 failed**
  (`build/native-region-parity-final.log`, `build/parity/run-ac6a2xkx`). The first
  sweep caught an over-broad forward declaration for an uncompiled Array method;
  declarations now cover only emitted region candidates. The failing
  SortedCollection case passes after the fix.
- The focused fixture also binds an interpreter, replaces the transitive callee
  there, detaches, and checks native dispatch resumes. It verifies callbacks,
  recursion, division and implicit-return bodies are not planned.

An exploratory three-call arithmetic microbenchmark produced a promising result,
but overlapped validation/build work and has large absolute-time drift. It is not
accepted performance evidence. No Richards, DeltaBlue or Queens improvement is
claimed. The next step is a quiet paired run, followed by extension to native
locals and structured control flow after the boundary contract is validated.
