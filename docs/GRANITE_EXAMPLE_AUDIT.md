# Executable example coverage

## Scope

`examples/manifest.json` covers all 41 `.hrd` sources under `examples/` and
`benchmark/`, with nonempty-argument template and argument-preservation variants
(46 source cases). Six website fences from `website/content/docs.md` and
`website/content/index.md` are also inventoried (52 cases total). The Markdown
itself is extracted at run time, so tests cannot drift onto copied snippets.
Examples are grouped into language, compiler, stdlib, concurrency, web,
integrations and templates. Algorithm/performance workloads remain in benchmark/.
The runner fails if a source is added without a manifest case or a manifest path
no longer exists. It does not treat Markdown snippets or historical proposals as
standalone programs outside the selected Markdown pages.

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

`nimble testExamples` completed with **40 exact parity passes**, **1 known
compiler-failure case**, and **11 syntax-only dependency/host/context gates**. All 41
ungated cases execute successfully in the interpreter and match their stdout and
stderr snapshots. Logs: `build/example-audit/run-p2z_keb5/results.json`.
Runner unit tests (15 checks), Echo host tests/demo, interpreter-template host
tests, and both engine builds pass. The valid top-level-bars example now passes
unchanged rather than carrying a known-failure marker; known gaps are not successes.

## Current gaps

`benchmark/loop_10000.hrd` now passes unchanged: Granite parses script
scope and preserves top-level temporaries, nil initialization and closure capture.
Its obsolete manifest failure marker has been removed.

The logging example also passes unchanged: lazy native sinks use Harding's
configured threshold (ERROR by default), and interpreter CLI logging uses stderr
as documented. The snapshot separates `Hello World` on stdout from ERROR/FATAL
records on stderr; no stream-merging normalization is used.

Remaining native gaps:

- `examples/concurrency/process_demo.hrd`: interpreter finishes with counter 20;
  native `Processor fork:` is not implemented.

The calculator now passes with integer and float arguments and with an unknown
operation. Shared numeric conversion answers nil on whole-string parse failure,
registers `asFloat` in the VM, and enables Integer-then-Float `asNumber` fallback.
Native nil callbacks receive the proper arguments and preserve cleanup and
lexical non-local returns. `examples/stdlib/numeric_conversion.hrd` checks valid
conversions, invalid input, and nil fallback results.

`examples/stdlib/arguments.hrd` checks canonical/aliased System receivers, repeated
calls, indexed iteration, empty arguments, embedded spaces/quotes, option-like
strings and Unicode. Snapshots preserve stdout/stderr exactly. Native `withIndexDo:`
passes element and zero-based index and answers its receiver; semantic parity
also checks callback non-local returns, errors and cleanup.

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
not current valid source. All Harding fences on website docs/index pages are
extracted and classified: hello/counter/error/Point run in both engines, while
the server and Html/Router fragment are syntax-only host/context gates. Missing,
renamed, duplicated and unclosed fences fail validation. Features-page and other
Markdown extraction remains follow-up work; `test_website_examples.nim` separately
executes selected interpreter snippets only. Generated website/dist is not read
or regenerated by this audit. GUI/service-host smoke tests and Granite process/FFI
coverage remain open. No claim of compiling all Harding applications is made.
