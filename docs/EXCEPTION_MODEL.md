# Harding exception model decision

## Status

Accepted language direction for the `granite-completeness` work. This document
specifies the target contract, not a claim that either engine fully implements
it. Interpreter and Granite must implement the same observable behavior.

The goal is conventional error handling and native integration without arbitrary
signal-point continuation restoration. Lexical block non-local returns remain
part of Harding. Resumable notifications are a narrower synchronous protocol.

## Errors

`Exception` is non-resumable by default. `Error` and its subclasses represent
failures that abandon the computation at the signal point.

For `[body] on: Error do: [:ex | handler]`:

1. Select the innermost matching active handler, including subclass matches.
2. Abandon the failing computation up to that protected-block boundary, running
   intervening cleanup before executing the handler.
3. Invoke the handler with the exception. Its ordinary result becomes the result
   of `on:do:`. `ex return: value` explicitly supplies that result.
4. `ex pass` delegates to the next matching outer handler; it does not resume
   the abandoned computation.
5. `ex retry` starts a fresh invocation of the protected block. Cleanup for the
   failed attempt must already have completed.

`resume` and `resume:` are invalid for errors and other non-notification
exceptions. They must report a normal Harding error, not silently continue or
restore the signal point. The executing handler is excluded from handling errors
raised by its own handler body; enclosing handlers remain eligible.

An unhandled error invokes the default-action/debugger policy and ends the
computation unsuccessfully. A returning default action must not silently resume
a failed computation. CLI execution returns a nonzero status.

## Notifications

`Notification` and its subclasses are synchronous signals, not unwinding errors.
Matching handlers are called while the signaling computation remains active.
The handler's ordinary result is the result of `signal`. Notification `resume:`
supplies that result explicitly; `resume` supplies nil. These operations do not
restore saved stacks or continuations. They only complete notification handling.

`pass` delegates to an outer matching handler while the computation remains
active. An unhandled notification invokes its default action; if that action
returns normally, signaling returns nil. A handler failure propagates as an
ordinary error. Notification `retry` and `return:` are not supported: they must
report a normal Harding error rather than initiate a second control protocol.

Dynamic handler lookup still applies. A currently executing handler is excluded
from handling signals raised by its own body, avoiding accidental self-recursion.

## Cleanup and non-local returns

`[body] ensure: [cleanup]` runs cleanup exactly once when the protected invocation
finishes, whether it finishes normally, fails, or leaves via a lexical block `^`.
Nested cleanup runs innermost first. On normal completion, `ensure:` answers the
body's result, not the cleanup result. Cleanup's ordinary result is ignored.

A successfully handled notification does not leave the protected invocation and
must not trigger cleanup early. A cleanup error or cleanup non-local return
supersedes the pending result/error/return; remaining outer cleanup still runs.

Block `^` targets the particular invocation of the lexically enclosing method.
Intervening handlers must not mistake this internal transfer for an application
exception. A completed home cannot receive a return; attempting it signals a
non-resumable Harding error. Retained closure bindings remain usable for ordinary
block evaluation after the creating invocation completes.

## Implementation constraints

- Keep the interpreter stackless: explicit work frames and unwind state implement
  the contract, rather than native try/finally around VM primitives.
- Granite can use Nim exceptions and try/finally for native error unwinding and
  cleanup. Internal return transfers must remain distinguishable from errors.
- Notifications use synchronous dispatch without general continuation capture.
- Preserve useful signal-site diagnostics without making live, resumable
  activation stacks part of the error contract.
- Do not unwind Harding/Nim exceptions or block return transfers across a C ABI
  boundary. Adapters catch and translate them into the foreign API's supported
  error mechanism. Callback lifetime and resource ownership remain explicit.
- Green processes and mixed mode must follow the same language contract; native
  compilation performance does not justify different interpreter semantics.

## Migration and validation

A non-local return targets the particular invocation of the lexically enclosing
method that created the block. Once that invocation has finished, the block can
still be evaluated and its captured variables remain usable, but there is no
invocation to return from, so `^` signals `BlockCannotReturn`, an `Error`
subclass. Both engines agree, so this is ordinary parity. Internal return
transfers while the home invocation is still active remain invisible to
application handlers.

`ensure:` now runs cleanup exactly once on normal completion, on errors and on
lexical non-local returns, innermost first. Cleanups execute as work frames on
the normal stackless path, and a scope is marked running before its cleanup body
starts so a cleanup that signals cannot run twice. The protecting handler is
marked consumed only after its cleanups, so a cleanup failure is still caught by
that handler while a failure in the handler body is not. Both engines pass the
cleanup tests; the native side runs cleanup through the compiled runtime's
`ensure:` handling. VM unwind continuations now run one cleanup at a time while
its home remains active, allowing cleanup errors/returns to replace the pending
transfer without losing outer cleanups. Retry attempts and uncaught exits have
executed coverage; process boundaries and legacy re-entrant paths remain open.

The first migration slice makes VM errors abandon protected work before handler
execution and reject error resumption. Native compiled error handlers cover
basic signaling, handler results, return:, pass, retry, handler failures and
resumption rejection.

The notification slice makes handlers supply the signal's value without unwinding
the signaling computation, allows `pass` to delegate outward, and rejects
`retry`/`return:` with a normal `Error`. The interpreter's 23 exception tests and
the compiled `notification_dispatch`/`notification_failure` parity cases pass.

Two gaps remain open and are tracked in PLAN.md. Carrying a `resume:` value back
to the signal point works through the `evalStatements`/doit path but not when the
signal runs inside a script block or compiled code, where it yields nil. Native
`pass` across nested handlers also returns nil instead of the outer handler's
result. Neither gap is asserted as parity, and the interpreter still retains
signal-point state for notifications pending a single shared mechanism.
Granite's custom exception subclasses, native arithmetic-error translation,
default-action/diagnostic parity, and mixed-mode coverage remain incomplete.
These are migration items, not exceptions to the target contract.

Replace tests/examples that resume errors with conventional fallback handling or
Notification signaling, according to their intent. Keep explicit negative tests
for error resumption. Replace escaped block `^` used as an ordinary block result
with a final expression. Do not silently reinterpret `resume:` on an Error as
notification signaling.

Required executed parity coverage:

- Handler matching, normal handler results, return:, pass, retry and unhandled
  errors, including failures raised by handler bodies.
- Rejection of error resume/resume: and notification retry/return:.
- Notification results, resume/resume:, pass, default action and handler failures;
  verify code after signaling runs and cleanup has not run prematurely.
- Cleanup order and exactly-once behavior on normal completion, error propagation,
  recursive block returns, retry attempts and errors/returns from cleanup.
- Inactive-home errors, application handlers not intercepting internal returns,
  and ordinary escaped closure evaluation.
- Foreign callbacks, process boundaries and mixed-mode transfers as those
  integration paths are implemented.

See `../PLAN.md` for implementation tracking. This decision replaces the earlier
plan to preserve arbitrary resumable exceptions through compiler continuation
lowering. The reference manual's current-behavior discussion remains labeled
until the migration is implemented and validated.
