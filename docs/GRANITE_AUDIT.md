# Granite exception and return migration audit

This is partial migration evidence, not a full compiler or application-suite
completion claim. The accepted contract is [EXCEPTION_MODEL.md](EXCEPTION_MODEL.md).

## Handler cleanup

`notification_pass_cleanup` executes nested handler-local cleanup before outer
notification dispatch, repeats the signal, and checks that a cleanup failure
replaces delegation. The signaling body's scopes remain active.
`handler_transfer_cleanup` executes error pass across handler/intervening scopes,
handler-local cleanup before retry, and cleanup failure replacing error pass.
The VM previously truncated these scopes without executing their cleanup,
leaving stale registrations that could affect later transfers. Transfers now
continue through ordinary work frames, one cleanup at a time.

Focused parity: ten cases passed; the subsequent full focused runner passed all
59 cases. Interpreter exception/cleanup tests pass under ARC and ORC. Sources: `scripts/test_granite_parity.py` and
`tests/test_exception_handling.nim`. Logs: `build/handler_cleanup_*`.

Custom exception subclasses/default actions, native arithmetic-error translation,
foreign ABI boundaries, process yields and mixed mode remain separate gaps.

## Deferred returns

An AST scan of `.hrd` files under examples, benchmark, lib, external, website and
docs parsed 136 files and found two non-local returns inside known deferred
callback registrations. Both were in `lib/gui/bona/Browser.hrd`:

- `showNewLibraryDialog`: empty-name validation inside `clicked:`.
- `showAddMixinDialog:`: missing-selection validation inside `clicked:`.

Those callbacks run after the creating method has finished, so ^ attempts to
return to an inactive home. They now branch around the success action instead.
`tests/test_browser_callbacks.nim` loads the actual Browser source and uses
headless widgets to store callbacks. It invokes invalid and valid branches after
dialog creation. Both ARC and ORC pass; running the same test against the old
Browser source exits with `BlockCannotReturn` on the empty-name callback.

The scan is heuristic: it recognizes named callback registration selectors, not
arbitrary dynamic registration, aliasing or escape analysis. Embedded Markdown
examples are not parsed by it. There are no installed external `.hrd` sources in
this checkout, so no external-library completeness claim is possible.

Five files failed parsing and were not audited through their AST:

- `examples/harding-echo/src/harding_echo/lib/echo/Echo.hrd`: declarative primitive
  argument names do not match the method parameters.
- `benchmark/loop_10000.hrd` and `benchmark/permute.hrd`: top-level temporary bars.
- `benchmark/arith_simple.hrd`: expected closing parenthesis.
- `docs/research/proposal-examples/Person_new.hrd`: historical proposal syntax.

The scanner and logs are retained in `build/audit_returns.nim`,
`build/audit_returns_fixed.log`; they are audit artifacts, not a language checker.

## Executed source checks

Bounded interpreter/build/native runs have matching successful output for:

- `examples/blocks.hrd`, `fibonacci.hrd`, `methods.hrd`, `harding_main.hrd`.
- `benchmark/sieve.hrd`, `queens.hrd`, `towers.hrd`.

`benchmark/storage.hrd` now builds and runs natively after built-in collection
construction and table literals were implemented, so it is no longer an audit
exception. Matching empty output for benchmarks is only a smoke check; the
focused queens and towers parity cases additionally assert 92 solutions and 8191
legal moves. Logs and exit statuses: `build/return-audit-execution/results.json`.

The bounded closure and compiler-block suites complete, including the previously
stalled nested-control-flow case. Signal-point diagnostics tests pass with three
explicitly skipped checks (full activation access, outer handler context, debugger
process suspension). Most old block-suite cases are interpreter-only, not native
parity. Logs: `build/audit_{closures,blocks,signal}_run.log`.
