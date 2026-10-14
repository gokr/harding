# Executable example coverage

## Scope

`examples/manifest.json` covers all 39 `.hrd` sources under `examples/` and
`benchmark/`, with two additional nonempty-argument template cases (41 cases).
Examples are grouped into language, compiler, stdlib, concurrency, web,
integrations and templates. Algorithm/performance workloads remain in benchmark/.
The runner fails if a source is added without a manifest case or a manifest path
no longer exists. It does not treat Markdown snippets or historical proposals as
standalone programs.

Each ungated case must parse, execute successfully in the interpreter, match its
checked-in stdout/stderr, build natively, execute successfully, and match the same
output. Engine runs and builds are bounded; a timed-out compiler's subprocess
group is killed. Compiler diagnostics are separate from program output. Matching
failures do not pass, and stdout is not filtered to hide differences.

Run after building both engines:

```sh
nimble testExamples
nimble testExamplesStrict
```

The normal task checks stage/message-specific known failures without calling them
passes. Strict mode fails on every known gap. Unexpected success also fails until
the manifest is updated, preventing obsolete exclusions. A failing interpreter or
changed golden output is never waived by a known native failure. The runner has
unit tests for these distinctions and timeout handling.

## Executed baseline

`nimble testExamples` completed with **25 exact parity passes**, **7 known
compiler-failure cases**, and **9 syntax-only dependency/host gates**. All 32
ungated cases execute successfully in the interpreter and match their stdout and
stderr snapshots. Logs: `build/example-audit/run-si7j28rm/results.json`.
Runner unit tests (11 checks), Echo host tests/demo, interpreter-template host
tests, and both engine builds pass. A strict-mode run of the valid top-level-bars
example returns nonzero as required; known compiler gaps are not successes.

## Current gaps

- `benchmark/loop_10000.hrd`: valid script temporary bars; Granite's unwrapped
  top-level parser rejects them. Keep the valid example to exercise the gap.
- `examples/concurrency/process_demo.hrd`: interpreter finishes with counter 20;
  native `Processor fork:` is not implemented.
- `examples/stdlib/logging.hrd`: native default logging threshold emits more
  levels than the interpreter. Output comparison exposes the discrepancy.
- Both templates in `examples/templates/`, with and without arguments:
  native `System arguments` is not implemented (four cases).

Nine sources are syntax-only gates: six web applications/servers, BitBarrel, and
the two host-loaded Echo library sources. They require a build variant, host,
external service or controlled persistent storage. A syntax gate is not native
execution evidence. Echo's separate Nim host tests execute its actual embedded
sources and registered primitives; both ordinary and prefixed echo/count/reset
are tested. The interpreter app template's host tests exercise nonempty arguments.

## Source repairs

- Arithmetic benchmark uses `&` concatenation and checks its Float result against
  `100.0`, with a required success marker. Mixed Integer/Float equality is a
  separate recorded engine discrepancy, not an intended example result.
- Permutation benchmark uses comma-separated slot names, zero-based Array
  indices, one initialization, and asserts/prints the expected 8660 states.
- Collections demonstrate first-element index 0. Closure and Boolean examples
  use accurate output labels (`&` concatenates; it is not Boolean conjunction).
- Echo uses valid declarative primitive arguments; its bootstrap checks for the
  actual class rather than `isEmpty` after adding metadata. Nim host tests use
  current value kinds and fail safely on an evaluation error.
- The interpreter template uses `withIndexDo:` and accepts the argument supplied
  to its `ifNotNil:` block. Its test embeds the actual source so it can run from
  the repository root.
- README commands, CLI usage and documentation references use the new paths.

## Limits

Matching example output is useful regression evidence, not proof of arbitrary
Harding support. Empty-output workloads remain smoke checks; permutation, queens,
sieve and towers have count outputs. Table iteration currently produces stable
output in this toolchain; snapshots intentionally expose ordering changes rather
than normalizing them away. Scheduler trace changes may require a reviewed
snapshot update even when the final counter remains correct.

Historical `docs/research/proposal-examples/Person_new.hrd` remains a proposal,
not current valid source. Website/Markdown snippets require extraction into
executable fixtures; the current `test_website_examples.nim` suite executes
interpreter snippets only. GUI/service-host smoke tests and Granite process/FFI
coverage remain open. No claim of compiling all Harding applications is made.
