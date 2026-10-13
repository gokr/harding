# Bona assessment

This assessment combines source review, headless tests, and interaction with a live GTK4 Bona process through AT-SPI. It is not a complete UI acceptance test. The initial assessment preceded fixes; the progress section below records subsequent hardening work.

## Hardening progress

- `gnome-ui-mcp` 0.5.0 was installed in a local system-Python virtual environment and registered with the harness. App boundaries restrict interaction to Bona. Workspace interaction and Builder New have been exercised; text reading through this MCP needs an AT-SPI cross-check. Operational details are in `AGENTS.md`.
- Granite bootstrap initialization is repaired, including a previously hidden invalid runtime-expression array literal in `Granite.hrd`. Builder New now creates `MyApp` in a live MCP-driven trial.
- GTK4 dialog bindings and literal-message handling are corrected, including cancellation cleanup and declining a cancelled confirmation.
- Browser writes use parser-delimited targeted edits with validation and atomic replacement. Shared-file, class-side, extension-file, Unicode/CRLF, duplicate-definition, and invalid-edit preservation tests were added. Reflection/display and successful image reload still need further work; syntax validation is not a transactional runtime validation.
- Browser refresh defers while source is dirty. Transcript keeps bounded history while closed, restores it on reopen, and provides class-side `contents` for BonaMCP.
- The bounded-queue scheduler livelock is repaired: blocking retains the VM continuation and retries the blocked send, not the whole statement. Nested loop/method completion no longer terminates the outer fork prematurely. Tests cap scheduler slices and check both worker completion and queue contents.
- Focused validation: 12 source-editor tests, 10 Bona model tests, 22 GUI automation tests, and the interpreter core suite pass under ARC. GTK callback/dialog tests also run under ORC. Full-suite and complete black-box tool acceptance remain outstanding.
- Interpreter contracts for load failure, structured evaluation outcomes, and eval scheduler ownership are flagged for discussion rather than silently changed. Direct `::` access in tool test setup also needs a focused reproduction.

The numbered findings below describe the original baseline; use this progress section and `AGENTS.md` to distinguish repaired paths from outstanding work.

## Validation performed

- `nimble bona`: initially failed to link because `libvte-2.91-gtk4.so.0` was missing. GTK3 VTE does not satisfy this dependency. Downloading and extracting the Ubuntu GTK4 VTE runtime under `build/bona-assessment/deps`, then setting `LIBRARY_PATH` and `LD_LIBRARY_PATH`, allowed the normal build task to succeed without installing system packages.
- `nim c -r tests/test_bona_models.nim` (with output redirected under `build/`): four tests passed; two failed with `Message not understood: derive:` on `Application`.
- `nim c -r tests/test_gui_automation.nim` (with the local VTE library paths): all 18 tests passed on the available desktop session.
- Live AT-SPI interaction: discovered the Bona accessibility tree, activated Workspace, set the editor contents, and activated Do It. Evaluating `3 + 4` did not crash the application. No coordinate-based input or desktop-wide accessibility setting changes were needed; Bona was launched with `GTK_A11Y=atspi`.
- Live Builder interaction: activated Builder and New; read the output through AT-SPI. Output was `Creating new application...` followed by `Error: Created source but class not registered: MyApp`.
- Live MCP startup: entered `BonaMCP startOn: 18765.` in a Workspace and activated Do It. Repeated attempts crashed Bona with SIGSEGV before an MCP connection could be established. A GDB capture stopped in Pango/GTK layout; this does not establish the root cause of the crash.
- Headless disposable source-edit probe: saving a method in a two-class source file through Browser's rewrite helper removed the other class, a top-level assignment, and a file-level comment.

Scratch probes and runtime/GDB logs are under `build/bona-assessment/`. GUI and model test logs are `test_gui_automation_assessment.log` and `test_bona_models_assessment.log`.

## Findings, ordered by priority

### 1. Browser saving can remove unrelated source — confirmed

`Browser>>managedMethodInfosForCurrentClass` selects only source entries for the current class and current file. `rewriteManagedClassFileWithClassDefinition:overridingSelector:methodText:removeSelector:` then overwrites that entire file with the supplied class definition and those method entries.

A fixture containing `RewriteFoo`, `RewriteBar`, their methods, a comment, and `RewriteSentinel := 42` became just:

```harding
RewriteFoo := Object derive: #().
RewriteFoo>>answer [ ^ 3 ].
```

The same rewrite helper serves method saves, class-definition saves, and method deletion. It also writes before validating successful installation/reload. This should be addressed before using Browser to edit shared source files.

Recommended fix: preserve the original file and replace only the targeted source span; parse/validate the proposed source before an atomic write. Cover multi-class files, extension files, top-level statements, comments, invalid edits, and class-side methods.

Source: `lib/gui/bona/Browser.hrd`, especially `managedMethodInfosForCurrentClass`, the rewrite helper, `saveCurrentMethod`, and `deleteCurrentMethod`.

### 2. Application is skipped during bootstrap — confirmed

`lib/granite/Bootstrap.hrd` stores `__sourceDir` in `GraniteLib` and then checks `GraniteLib isEmpty` before loading `Application.hrd` and `Granite.hrd`. The metadata entry makes the library nonempty, so initialization is skipped.

This explains the two headless test failures and the live Builder New failure. Explicitly loading `lib/granite/Application.hrd` made `Application derive: #()` succeed in the disposable probe.

Recommended fix: use an explicit initialization guard, as the Process and Web bootstraps do, with a regression test asserting that the default bootstrap resolves Application to a class.

Sources: `lib/granite/Bootstrap.hrd`, `tests/test_bona_models.nim`, `Builder>>createNewApp`.

### 3. Existing Bona MCP is not usable in the tested startup path — confirmed

There is already an implementation: `lib/gui/bona/BonaMCP.hrd`, backed by the installed external `nimcp` package. It registers eight tools:

- `bona_ping`
- `bona_eval`
- `bona_transcript_tail`
- `bona_list_libraries`
- `bona_list_classes`
- `bona_list_methods`
- `bona_get_method_source`
- `bona_load_file`

It is loaded with the other IDE tools but is not started automatically or exposed by a launcher button.

Debug logging during Workspace startup reported:

```text
WARN Failed to initialize external worker bridge: Parse error at line 1, col 162: Unexpected token: ','
```

`ensureWorkerBridge` in `external/nimcp/src/nimcp/harding_integration.nim` embeds `"NimCP tool error: " , ex printString`; the language now uses `&` for concatenation. Listening continues even when worker installation fails, and the proxy reports itself as running without waiting for successful server startup.

Additional source-review concerns:

- `Object eval:` creates a separate interpreter sharing globals but does not propagate the main interpreter's scheduler context. Starting a main-thread service through Workspace evaluation therefore needs explicit ownership/dispatch handling, not just a syntax correction.
- Server state and worker/channel state are process-global.
- Tool handlers wait indefinitely on stack-owned response channels. Stop does not explicitly cancel pending requests or join retained server threads.
- Reply proxies accumulate in a keep-alive registry, with no visible retirement on reply.
- There are no dedicated end-to-end tests of BonaMCP tools, startup failure, shutdown, or restart. `tests/test_mcp_bridge.nim` exercises the separate built-in bridge, not this NimCP-backed path; its HTTP tests are placeholders.

Recommended fix order: correct worker syntax, fail startup when the bridge cannot install, bind dispatch to Bona's main interpreter/scheduler, investigate the reproduced crash, then add real initialize/list/call/stop/restart tests.

### 4. GTK alert dialog bindings do not match GTK's ABI — source-confirmed

Compared with the installed GTK header:

- `gtk_alert_dialog_new` is variadic and treats its first argument as a printf format. Passing arbitrary error text directly as the format is unsafe when it contains `%` conversions.
- `gtk_alert_dialog_choose_finish` requires a third `GError **` argument; the binding omits it.
- `gtk_alert_dialog_set_buttons` takes a null-terminated labels array, not an additional label count.

These are in `src/harding/gui/gtk/ffi.nim`, used by `alertdialog.nim`. The missing error argument can make cancellation/error completion unsafe. These defects were not proven to cause the MCP startup crash.

Recommended fix: correct the declarations and callers, use a fixed format or a message setter, and test alert/confirmation acceptance, cancellation, and messages containing `%`.

### 5. Builder editing/build workflow contains placeholders — source-confirmed

Even after fixing Application loading:

- `loadApp:` always displays `defaultMainSource`, not the selected application's actual `main:` source. Building then saves that placeholder back to the live class.
- The default template uses a single-quoted message instead of Harding's documented double-quoted strings.
- Library selection is disabled; `getSelectedLibraries` returns an empty array and `saveLibraries:for:` does nothing.
- Despite the file header promising `.hrd` autosaving, `saveCurrentApp` installs a method in the image but does not persist application source to a file.
- Compile failures do not stop the save/build flow reliably.
- Build creates an application with `new`, but does not configure its name to match the class. Run assumes `./build/<class-name>`; the primitive requires a string in the application name slot.
- The live-image build primitive's AST synthesis copies the `main:` body into top-level statements rather than reconstructing the application class and dependencies. This is not equivalent to the full Granite CLI path.
- Nim compilation runs synchronously on the GTK thread, blocking UI processing while the compiler runs.

Sources: `lib/gui/bona/Builder.hrd`, `lib/granite/Application.hrd`, `src/harding/interpreter/compiler_primitives.nim`.

### 6. Logging, refresh, and shutdown need safeguards — source-review findings

- Transcript discards output when its window is not open. `bona_transcript_tail` consequently cannot retrieve earlier diagnostics. A bounded model-side log should exist independently of the widget.
- Browser `refresh` resets selection and overwrites editor contents without checking unsaved changes. Successful Workspace evaluation calls the owner's `refreshBrowsers`, so unrelated evaluation can discard another window's edits.
- Launcher quit closes the launcher, whose destroy callback calls Nim `quit(0)` directly. This bypasses coordinated child-window saves and MCP shutdown. Workspace normally saves in its own destroy handler.
- Workspace, Browser, Inspector, and BonaMCP detect errors using string prefixes. A valid result such as `"Error: example"` is therefore misclassified. Evaluation should return explicit success/error data.
- Library rename is an explicit stub. Primitive-line methods cannot be saved or deleted from Browser.
- No integrated Bona debugger UI for stepping, suspended processes, or resumable exception interaction was found in the inspected tool files. Runtime introspection and the separate debugger/LSP infrastructure are not the same as that UI.

## Automation recommendation

Use two complementary layers rather than replacing the existing work.

### Semantic Bona MCP

Repair and extend BonaMCP for live-language operations. Add explicit APIs for:

- open tools and stable tool/window IDs;
- Browser selection, dirty state, source retrieval, and validated edits;
- Workspace text, selection, evaluation, and structured results;
- Inspector selection and expansion;
- retained diagnostics and process/activation snapshots.

Execute all Harding/GTK operations on the Bona main thread. Use bounded dispatch, explicit lifecycle ownership, request cancellation, and structured errors. Do not assume a transport timeout can preempt arbitrary VM code.

Keep the default listener on loopback. `bona_eval` and `bona_load_file` grant the client's full live-image/file authority, not a read-only interface; remote exposure requires authentication and an explicit trust decision.

### Accessibility automation MCP

Use AT-SPI for black-box UI verification: widget discovery, button activation, editable text, selection, dialog handling, and state assertions. This works on the tested Bona GTK4 surface, including under Wayland, without relying on global mouse coordinates. Input simulation and screenshots may still require compositor/portal permissions.

Existing projects whose current READMEs describe this functionality:

- [computer-use-linux](https://github.com/agent-sh/computer-use-linux): MCP/CLI with AT-SPI discovery/actions, application state, screenshots, and compositor-dependent input/window control.
- [gnome-ui-mcp](https://github.com/asattelmaier/gnome-ui-mcp): GNOME Wayland MCP with AT-SPI snapshots, element actions, and Mutter input support.
- [waydriver](https://github.com/BohdanTkachenko/waydriver): headless Wayland testing infrastructure with AT-SPI and capture support, worth evaluating for isolated CI runs.

These candidates were researched, not installed or acceptance-tested. Prefer app-scoped selectors and a dedicated session for destructive tests. Do not give a general desktop MCP unrestricted access to unrelated applications merely to test Bona.

## Suggested next change sets

1. Prevent source loss; fix Granite bootstrap; add focused regressions.
2. Correct dialog ABI; add cancellation and format-string tests.
3. Repair BonaMCP startup/ownership and add live protocol tests.
4. Replace Builder placeholders with source-backed editing and persistence.
5. Retain diagnostics, protect dirty editors, and coordinate shutdown.
6. Add app-scoped AT-SPI acceptance tests for these workflows, alongside the existing direct callback tests.
