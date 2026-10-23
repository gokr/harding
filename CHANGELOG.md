# Changelog

All notable changes to Harding are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added
- Generated class-side engine shims use the VM's NodeValue-native ABI, preserving actual and inherited class receiver identity without fabricated instance wrappers. Class-side bindings are tracked separately from instance bindings; live class-method replacements and subclass overrides fall back through VM lookup. A repeatable generated-module integration test executes both binding sides under ARC and ORC.
- Mixed dispatch uses receiver ownership and literal-valued VM messages rather than rebuilding source, treating nil as a miss, or retrying failures inside native methods. Interpreter-owned object/class sends preserve identity, arguments and captured blocks; native-layout fallback remains explicitly unsupported. Boundary tests cover nested interpreted/native calls and non-fatal host recovery.
- Bound compiled instance sends check live interpreter method resolution before generic dispatch or cache hits. Runtime replacements and subclass overrides fall back through literal-valued VM messages, preserving nil results. Hosts can release boundary registrations with `unbindCompiledMethodsFrom`; class-side/layout changes and cross-engine control transfers remain outside this slice.
- Interpreted-to-compiled dispatch (engine boundary, PLAN.md section 6 step 1): generated modules emit a per-method shim and a `bindCompiledMethodsTo(interp)` entry point, and `bindCompiledMethodShim` binds it onto the interpreter's own method table as the native implementation. Interpreted code -- a Workspace Do It or a subclass created at runtime -- can now reach compiled method bodies with receiver identity and arguments intact, instead of the previous `toString()` round-trip. An existing hand-written or interpreter-registered native implementation keeps precedence, and binding unknown classes/selectors or rebinding is a no-op. Coverage: `tests/test_engine_boundary.nim` (6 cases, ARC and ORC) plus a generated-module end-to-end check.
- Deterministic portfolio stress showcase combining native object dispatch, JSON, escaped closures and exception cleanup, with exact-output manifest coverage and a checked release interpreter/native benchmark (`scripts/bench_portfolio.py`). Measurements and a remaining cleanup-local capture discrepancy are documented in `docs/GRANITE_PORTFOLIO_EXAMPLE.md`.
- Conservative native storage for numeric method temporaries: definitely initialized, same-kind Integer/Float locals unbox; reads before initialization, captures, lexical shadowing, slot/parameter dependencies, type changes and division remain dynamic. Paired numeric-method benchmarks check identical output before reporting timings.
- Native `Json parse:` builds nested scalar, Array and Table values; invalid input and JSON null answer nil. Aliased receivers and registered overrides work. Exact-output parsing/round-trip examples and ARC/ORC runtime tests cover Unicode, escapes, numeric kinds and empty containers. Collection identity/mutation aliasing/reflection remain separate compatibility work.
- Native `json{...}` literal construction: compiled programs no longer fail with `Message not understood: buildDynamic:`. Literal-level entries keep the interpreter's `", "`/`": "` spacing with compact nested values; arrays, scalars, escaping and cycle detection are covered, and `Json stringify:` supports compiled scalars/collections. Ordinary object JSON serialization, representation hooks and class JSON specs remain unsupported natively and raise explicitly. Per-write cycle state is local and recoverable. Dynamic JSON in the website syntax example now passes instead of carrying a known failure.
- Website features-page Harding fences are extracted directly into the manifest runner (runnable examples with exact stdout plus explicit host/context gates); unsafe manifest ids are rejected and duplicate fence headings are disambiguated rather than silently dropped.
- Website docs/index Harding fences are extracted directly into the example manifest runner: hello, Counter, handled error and Point compare exact interpreter/native stdout; server/Html fragments remain explicit syntax-only gates. Missing/duplicate/unclosed fences fail validation, avoiding drift onto copied test source.
- Native `System arguments` returns a fresh Array of user argument strings (without the executable name), through a canonical class receiver or alias. Native `withIndexDo:` passes element and zero-based index to compiled callbacks and answers the Array. Template and argument examples cover empty lists, empty strings, spaces, Unicode and option-like strings; the calculator's remaining numeric-conversion gap is tracked separately.
- Manifest-driven example regression suite (`nimble testExamples`, `testExamplesStrict`): every current example/benchmark source is inventoried; successful interpreter/native execution must match reviewed stdout/stderr. Explicit compiler gaps and dependency gates are reported separately, never as passes. Logs and isolated binaries stay under build/.
- Compiled code supports dynamic sends: `perform:`, `perform:with:`, `perform:with:with:` (selector as symbol or string) and `respondsTo:` on instances and classes. Coverage: `dynamic_send` parity.
- Compiled dispatch follows multiple inheritance. `registerSuperclass` records every parent in declaration order instead of replacing the first, dispatch and method-existence walks are depth-first over the parent graph with a cycle guard, and `addSuperclass:` works at runtime for class receivers. Coverage: `multiple_inheritance` parity (parent-order lookup, methods from each parent, local override).

### Added
- Collection bulk/sequence protocol: Iterable addAll:/includesAll:/occurrencesOf:/isEmpty/notEmpty with Array addAll: answering its argument; Array findFirst:/findLast:/reverseDo:; native Array removeAt:/removeFirst/removeLast, Table values/associations/at:/removeKey: and Set remove:/union:/intersection:/difference:/asArray. Native inline do:/collect:/select: lowering is now restricted to literal Array receivers so Table/Set species and callback arity keep ordinary dispatch.

### Fixed
- Native runtime reference storage is zero-initialized before managed-reference assignment and releases its reference before freeing the pointer slot, avoiding an ORC crash in first-time runtime initialization.
- Granite mutable collections retain shared Array/Table instances across constructors, literals, JSON parsing and helper results. Aliases observe mutation; clones have independent shallow storage. Table queries retain key/value callback arity and species, Set queries retain element callbacks, builtin collection reflection works, and Array `do:`/`at:put:` preserve their documented results.
- Native object JSON serialization supports inherited slots, representation hooks and class JSON configuration (exclusion, selection, rename, omission, formats, field order and reset), with per-write cycle detection. Effective native field plans are rebuilt per write; caching remains an optimization follow-up.
- Granite capture analysis recognizes script-local bindings introduced by direct assignment and nested block parameters/temporaries when a closure only writes them. Cleanup blocks share the enclosing cell instead of creating a separate local; executed parity covers error cleanup, nested write-only setters and explicit shadowing.
- Native Array query sends support reject:, detect:, detect:ifNone:, anySatisfy:, allSatisfy: and noneSatisfy:, including short-circuit and empty-input behavior, plus dynamic collect:/select: callbacks and collection emptiness checks.
- README installation instructions use Debian/Ubuntu package names, distinguish Bona's build and runtime dependencies, document the missing GTK4 VTE runtime error, and include VTE in the macOS prerequisites.
- Compiled comparison operators match the interpreter, and numeric equality is settled as a documented decision rather than an accident: Harding has no numeric tower, so Integer and Float are distinct classes and `=` answers false across them. The compiled runtime had no builtin `=` for nil, cross-kind or non-scalar pairs, no `<>` at all, and no mixed-kind ordering, so `100.0 = 100`, `nil = nil`, `"ab" = 100`, `x = x` on user instances, `100 < 100.0` and every `<>` signalled `MessageNotUnderstood` in compiled code while the VM answered. `=` now compares same-kind scalars by value, answers false across kinds and for nil-versus-non-nil, defers to a user-defined `=` on compiled classes, and otherwise compares by identity as `Object>>=` does. `<>` is added to the operator map and answers for the scalar and String pairs the core library defines, keeping ordinary dispatch elsewhere. Ordering comparisons compare mixed Integer/Float operands as Float. Coverage: `numeric_equality` parity (21 cases, including overrides and the `<>` signal cases) plus interpreter tests.
- The interpreter's class-side `name` and instance `class` fast paths answered directly and bypassed user-defined methods, so `Override class>>name [ ^ "custom" ]` was ignored in the VM while compiled dispatch honored it. Both fast paths now answer only when the receiver's ordinary dispatch resolves the selector to Object's own definition, so an override keeps ordinary dispatch. That check is shared with the `perform:` guard. Coverage: extended `class_reflection` parity plus interpreter tests, including a no-override case proving plain classes still answer their real name and class.
- `perform:` conveys an ordinary send in both engines. It was implemented as a native method that re-implemented dispatch, so it reached neither class-side methods, builtin class-side methods, allocators nor `doesNotUnderstand:`, and every miss silently answered nil; dynamic sends in `Html`, `Router` and `Builder` code could therefore never reach their targets. The interpreter rewrites the send frame into the conveyed selector and the compiled runtime conveys before its class-side and builtin tables, in both cases only when the receiver's own dispatch resolves `perform:` to Object's definition so overrides keep normal dispatch. A selector with no matching method now signals catchable `MessageNotUnderstood` rather than answering nil, so a miss is distinguishable from a method that legitimately returns nil. Coverage: `dynamic_send_targets` parity plus interpreter tests.
- Native collection/numeric/string helpers respect object/class method dispatch, including dynamic receivers and nil-valued overrides, instead of shadowing accessors such as `last`, `size` and `abs`. Primitive fast paths are retained.
- JSON serialization emits `null` for nil (including the VM's UndefinedObject singleton), not `{}`.
- Website source pages describe unwinding errors and synchronous notifications rather than obsolete resumable errors. Handler explanations use comments, not string expressions; generated website HTML remains separate from this source audit.
- Numeric string conversion is shared between interpreter primitive paths and native sends. `asInteger` answers nil for invalid/out-of-range input instead of zero; registered `asFloat` enables `asNumber`'s Integer-then-Float fallback. Conversion consumes the whole string. Native nil-condition sends select the proper callback/arity and preserve cleanup/non-local returns. The calculator example now works for Integer/Float input and unknown-operation fallback; its known-failure marker is removed.
- Lazy application logging uses Harding's configured threshold (ERROR by default) in compiled programs, preserving existing host handlers and filters. Interpreter CLI logging now writes to stderr as documented, rather than contaminating stdout. The logging example compares stdout and stderr separately and no longer carries a known-failure marker; ARC/ORC/release logging tests cover default and host-controlled thresholds.
- Granite accepts valid file-level temporary declarations (`| counter |`) across CLI, file-codegen and compiler-primitive entry points. Script and `Harding main:` temporaries are nil-initialized before closure creation; parsing preserves original source lines. The unchanged `benchmark/loop_10000.hrd` now passes native example parity.
- Repair stale example concatenation and primitive syntax, zero-based indices and permutation count checking, Echo package bootstrap/native host tests, and application-template indexed iteration/callback arity. Correct misleading closure/Boolean output labels.
- `isKindOf:` searches all superclass branches in the interpreter and compiled runtime, including transitive secondary parents, rather than only the primary chain. Native user-class reflection supports `class`, `className`, and ordered `superclassNames`; class receivers also expose `name`. Class arguments are required for `isKindOf:`, including canonical native `Root`/`Object`/`Mixin` class values. Coverage: `class_reflection` parity plus runtime/interpreter tests; built-in/immediate reflection and reflection override discrepancies remain tracked separately.
- Compiled `==`/`~=` sends compare object, class and block identity instead of failing with `MessageNotUnderstood`. Operator helpers, generic sends and cached sends share the same comparison; retained native storage gives multiple wrappers one identity. User-defined value equality (`=`) remains separate, and identity sends bypass overrides as in the interpreter. Coverage: `object_identity` parity and ARC/ORC runtime/support tests.
- Compiled qualified `super<Parent>` rejects unrelated classes and indirect ancestors as qualifiers, matching the interpreter's direct-parent rule. Regression coverage exercises instance/class-side sends, inherited methods, lexical blocks, arguments and receiver preservation; invalid qualifiers remain evaluation errors.
- The interpreter's `isNil`/`notNil` fast path now falls through to ordinary dispatch when the receiver's class overrides either predicate, matching compiled behavior and `Object>>isNil`/`notNil`. An object whose class defines `notNil [ ^ false ]` answers false in both engines instead of the interpreter forcing true. Coverage: `nil_override` parity.
- `harding -e` and REPL do-its now compile their source as the `#doIt` method on `UndefinedObject`, matching file scripts. A lowercase top-level assignment (`x := 1`) and `| x |` temporaries behave the same in a script, the REPL, and `-e`; previously `-e` reused the no-activation expression path and rejected them as "Global variables must start with uppercase letter".
- Class and module names are now encoded injectively. `mangleClass` hex-encodes every byte instead of transliterating, so `FooBar`/`Foobar` and `MyClass`/`My_Class` no longer collapse onto one Nim type under Nim's style-insensitive comparison; a module name that is not a valid identifier (for example a hyphenated filename) is encoded rather than rejected by the Nim compiler. String tables keep the original spellings. Coverage: `class_name_spelling` parity plus fold-distinctness unit tests.
- Compiled table literals and empty tables use a runtime helper instead of Nim's `{}` syntax, which inferred the wrong key type and failed to build. Native `Array new`/`new:`/`new:withAll:`, `Table new`, `Set new`, `String new`/`new:` and table/array `add:`/`includes:` now work in compiled programs, so `benchmark/storage.hrd` builds and runs natively. Coverage: `native_collections` parity.
- The interpreter printed booleans as `<instance of True>`/`<instance of False>` while compiled programs printed `true`/`false`, contrary to `True>>printString`/`False>>printString`. Both engines now print `true`/`false`; coverage: `boolean_display` parity.

### Changed
- Group examples under language/, compiler/, stdlib/, concurrency/, web/, integrations/ and templates/; update documentation/CLI paths. Algorithm workloads remain under benchmark/. The old example shell runner delegates to the manifest runner instead of comparing matching failures or using a shared /tmp directory.
- Compiled programs run `defaultAction` for an uncaught error and exit with a nonzero status, reporting `=== Uncaught Exception ===` and `<Class>: <message>` on stderr, instead of letting a Nim exception escape `main`. A user-defined `defaultAction` runs. The generated entry point now propagates `main`'s status via `quit`. Coverage: `unhandled_custom_default_action` plus the existing uncaught-error cases.
- Zero divisors now signal catchable Harding `DivisionByZero` in compiled code for `//`, `%`, `\` and `/` (all operand combinations), instead of raising an uncatchable Nim `DivByZeroDefect`. The interpreter's `/` fast path also signals for these forms, which previously answered nil. Messages match between engines; coverage: `arithmetic_zero_divisor` parity.
- Native exception handling supports user-defined exception classes: subclasses of `Error`/`Notification` inherit the built-in `message`/`stackTrace`/`signaler` slots, `Class signal:` allocates through the class's own constructor (running a compiled `initialize`), and user methods (`describe`, overridden `message`) take precedence over the built-in protocol while `signal`/`pass`/`retry` keep it. The built-in `Exception`/`Error`/`Notification` chain is registered eagerly so a compiled subclass matches `on: Exception`. Coverage: `custom_exception_hierarchy` parity plus runtime/compiler tests.
- Handler-local `ensure:` scopes now clean up before VM notification/error `pass` and error `retry`; error pass also cleans intervening protected scopes. Pending transfers continue through stackless frames, and cleanup failures replace delegation. Executed parity and ARC/ORC exception regressions cover the paths.
- Granite-generated modules import shared primitive/operator, block-return, closure and base-object support instead of re-emitting the fixed preamble. Generated loop conversion retains its permissive behavior separately from runtime's strict `toInt`; compiled globals now share the imported support module.
- Pure compiled generic sends use positive per-site monomorphic instance-method caches. Hits guard receiver class, selector and registration version; method/superclass/allocator registration invalidates targets. Nil results remain successful sends, while builtin, exception, class-side and mixed-mode paths retain generic dispatch. Concurrent registry mutation is not supported by this slice.
- Statically named compiled class allocation uses a guarded native allocator. Inherited or own class-side new overrides fall back to ordinary dispatch, and allocator/class-method/superclass registrations invalidate the guard. Mixed-mode and locally shadowed class receivers stay dynamic.
- Granite specializes proven, directly initialized script-local integer/float bindings and same-kind addition, subtraction, multiplication and comparisons. Values are boxed at ordinary message boundaries. Type changes, captured/shadowed names, real closures, potentially uninitialized reads and mixed-mode scripts remain dynamic; division and modulo keep their existing runtime paths. Method parameter/slot unboxing is not included.
- Granite excludes literal specialized if/while blocks from closure registration when they are lowered inline. Ordinary parameters and locals used only by these blocks stay stack values rather than MutableCell allocations; nested escaping closures and non-local-return environments remain registered.
- **Removed exception resumption from the language.** `resume`, `resume:`, `return:` and `isResumable` no longer exist in the interpreter or Granite: a handler's ordinary result is the value (of `on:do:` for errors, of the `signal` expression for notifications), `pass` delegates outward, and `retry` re-executes. The native resume transfer and all internal resumption state were deleted. The primary reason is semantic: these actions are rarely used and obscure which computation continues, while a handler's ordinary result already expresses the same value-passing. Removing them also drops the last construct whose lowering needs continuation capture, which simplifies the native path; that is a simplification taken rather than a hard requirement. Docs state this explicitly as unsupported.
- A non-local return whose home invocation has already finished now signals `BlockCannotReturn`, an `Error` subclass, instead of silently behaving as a local block result. The interpreter and Granite agree, so `inactive_return_target` is ordinary parity; a finished home still allows ordinary closure evaluation. Legacy tests using escaped `^` as a block result were migrated to final expressions.
- `ensure:` now runs cleanup exactly once on normal completion, errors and lexical non-local returns, including nested innermost-first ordering; the body's result is preserved and a cleanup failure is caught by the handler protecting that scope. Cleanups are scheduled as work frames so they stay on the stackless path. Interpreter cleanup tests and a native `ensure_cleanup` parity case cover this.
- Notification slice of the exception-model migration: notification handlers supply the signal's value without unwinding the signaling computation, `pass` delegates to outer handlers, and `retry`/`return:` on a notification signal a normal `Error`. Interpreter exception tests (23) and native `notification_dispatch`/`notification_failure` parity cases pass. Known gaps are recorded in PLAN.md: carrying a `resume:` value through script/compiled contexts, and native nested-handler `pass`.
- First exception-model migration slice: non-notification VM errors abandon protected work before handler execution; handled error resume/resume: signals Error, and executing handlers do not catch their own failures. Granite supports native built-in error signaling, handler results, return:, pass and retry. Core/website fallback tests replace error resumption with handler results. Notification and cleanup migration remain pending.
- Accepted exception-model direction recorded in `docs/EXCEPTION_MODEL.md`: non-resumable errors, synchronous resumable notifications, guaranteed cleanup, and lexical block returns, with identical interpreter/Granite semantics. Migration is pending; arbitrary signal-point restoration is no longer a compiler requirement.
- Reference manual and quick reference clarify verified accessor returns/overrides, lexical shadowing, shared/escaped closure bindings, and declaring-class `super` lookup; link semantic examples to regression cases and distinguish Granite limitations. Counter and non-local-return examples were executed in both engines.
- Build toolchain requirement updated to Nim 2.2.12; interpreter, Granite, generated programs, and tests use the same installed compiler version.

### Added
- Salvaged application Log debug:/info:/warn:/error:/fatal: and FileStream print:/println: aliases from the legacy Granite branch. Both engines share host logging handlers and filters; application debug/warn remain available in release builds, fatal logs without exiting, and no automatic Bona Transcript sink is claimed. Legacy audit and deferred salvage decisions are recorded in docs/LEGACY_GRANITE_AUDIT.md.
- Checked eight-queens search (92 solutions) and linked-object Towers of Hanoi (8191 legal moves), plus `scripts/bench_objects.py` comparing release interpreter, Granite and native Nim with per-trial correctness checks and bounded execution. Baselines are recorded in `docs/GRANITE_BENCHMARKS.md`.
- Cross-language benchmark harness (`scripts/bench_sieve_languages.py`) and baseline (`docs/GRANITE_BENCHMARKS.md`) comparing the `benchmark/sieve.hrd` workload across C, Nim, Go, Node.js, Squeak Cog, Ruby, Python, Granite native and the Harding interpreter.
- Focused Granite execution-parity runner (`python3 scripts/test_granite_parity.py`) with build/execution time limits, isolated workspace build directories, retained logs, and explicit expected output checks.

### Fixed
- Browser's new-library and add-mixin button callbacks no longer use non-local returns after the dialog-creation method exits. Validation uses branches, retaining the dialog on invalid input. Headless deferred-callback regressions pass under ARC and ORC.
- Granite encodes Nim keyword and backend-owned binding/slot identifiers consistently across method/block parameters, temporaries, assignments, capture environments, numeric expressions and slot accessors. Names such as object, type, result, args and env no longer produce invalid Nim or capture helper storage; runtime selector/slot spellings remain unchanged. General case/style-insensitive collision analysis remains separate.
- Granite preserves identifier spelling beyond keyword encoding: only all-lowercase alphanumeric names are emitted verbatim, and `mangleSlot` keeps punctuation and case. Bindings, slots and block parameters that differ only by case or underscores (`fooBar`/`foobar`, `foo_bar`/`foobar`, `slotValue`/`slotvalue`) now generate distinct Nim identifiers instead of conflicting under Nim's style-insensitive comparison. Coverage: `case_sensitive_bindings` parity plus fold-distinctness unit tests. Class and module names, and raw `{cls.name}` uses in generated proc names, are not yet covered.
- Interpreter class-side method fallthrough returns the actual class receiver rather than a class-wrapper instance. Chained sends retain class-side lookup, including inherited methods; activation self initialization and implicit returns share the receiver conversion. Executed parity covers empty bodies, same-named instance/class selectors, explicit self, escaped self blocks, handled errors and cleanup.
- Compiled methods answer their receiver on fallthrough, including empty bodies, literals, assignments, handled errors and cleanup. Only explicit ^ supplies a different method result; blocks retain last-expression results. Removed the duplicate method-statement codegen path. Instance-method return parity is covered; interpreter implicit class-side receiver chaining remains a separately documented representation gap.
- Missing sends now preserve handler results through ordinary stackless DNU dispatch. Native generic instance/class/super lookup exhaustion signals catchable MessageNotUnderstood instead of returning nil; inherited custom DNU may recover, including nil results. Regression cases cover missing immediate sends, class recovery, outer handlers, and cleanup before caught/uncaught failures.
- Generated native instance wrappers strongly retain their native storage instead of leaving only an ARC-invisible raw pointer. Object chains now remain valid without permanently rooting every allocation; queens and towers also execute correctly under ORC.
- Capture analysis traverses specialized if/while and named-access nodes, and write-only enclosing method temporaries share their binding. Compiled nil predicates preserve ordinary method overrides.
- Compiled methods now read and write Harding globals. Top-level uppercase names are shared module-level bindings instead of per-method shadow locals, so a method assigning one is seen by later top-level code and by other methods; blocks no longer capture a placeholder symbol. Covered by a `global_scope` parity case.
- Blocks inside compiled methods that read or write an instance slot now capture the receiver. Such a block previously failed to compile because `self` was dropped from its captures; enclosing method parameters and temporaries correctly shadow same-named slots. Covered by a `block_slot_capture` parity case and unit tests.
- Notification resume values and nested pass now agree across doits, scripts, and native programs. Installed handlers re-arm for repeated signals; running handlers are excluded from nested lookup. Removed VM signal-point snapshots and native resume restoration. Expanded parity tests cover handler results, early resume/pass, nested signals, handler failures, built-in default actions, and protected-body cleanup timing.
- VM cleanup unwinding uses explicit work-queue continuations instead of synchronous block evaluation. Cleanup runs before uncaught exit, and cleanup errors/returns replace pending transfers while outer cleanups still run. Five new execution-parity cases cover retry counts, transfer replacement, nested cleanup failures, and uncaught cleanup ordering.
- Granite non-local returns target a unique home invocation retained by block environments, rather than a static method id. Recursive callbacks and nested-loop returns preserve the correct target; targets deactivate on exit and inactive returns raise native BlockCannotReturnError. The runner passes 25 parity cases plus an explicitly labeled compiled-error case; VM inactive-home behavior and resumable exception integration remain open.
- Granite collection and while blocks preserve lexical locals. While conditions execute their full setup before testing the final value; `select:` executes statements preceding its predicate. Twenty-three execution-parity cases cover these scopes.
- Inline conditional/repetition blocks use separate lexical scopes in Granite; parsed conditional expressions produce branch values. The VM excludes declared block temporaries from inherited captures, preventing shadowed locals from mutating outer bindings. Twenty-one execution-parity cases pass.
- Granite local bindings take precedence over slot assignments. Capture-cell analysis is limited to each lexical body, and range-loop block parameters are bound per iteration in ascending/descending loops. Twenty execution-parity cases cover shadowing and escaped range captures.
- Granite declares method and block temporaries at scope entry so closures created before the first assignment retain the correct binding. Inline collection loops allocate per-iteration parameter cells; execution parity covers escaped closures returned by `collect:`.
- Granite captured bindings use shared MutableCell references rather than copied values and writeback. Execution parity covers sibling/nested captures, enclosing-scope mutation, independently escaped counters, and captured block parameters; sibling and escaped-counter cases also pass under ORC.
- Granite closure environments are managed heap objects owned by their BlockNode, replacing stack-local pointers and raw copied allocations. Assignment and expression block creation share the same path; returned string-capturing blocks retain their environments under ARC and ORC.
- Granite registers generated accessor messages for ordinary dynamic dispatch, respecting selective read/write generation and explicit overrides. Removed slot-message inlining that bypassed overrides and visibility; direct `::` access remains separate. Generated setters return the receiver. Eleven execution-parity cases and compiler registration tests cover these paths.
- Inherited VM methods retain their declaring class for `super` lookup; block activations preserve lexical class-side context, and Granite captures `self` and defining-class context for block `super` sends. Nine execution-parity cases cover inherited instance/class methods and multi-level constructors.
- Interpreter class-side `super` sends look up class methods and preserve class-side activation context, including `super new initialize`; execution parity covers these paths.
- Granite extracts and registers class-side methods separately from instance methods; compiled class receivers support inherited lookup, aliases, overridden `new`, factories, and class-side `super` dispatch.
- Pure compiled method bodies use the compiled runtime for generic sends rather than implicitly entering mixed-mode dispatch.
- Granite generated imports resolve relative to the selected output directory, including nested build directories.
- `MessageNotUnderstood` now derives from `Error` (it derived from `Exception`), so `on: Error do:` catches a failed send. The previous change to signal `MessageNotUnderstood` instead of the generic `Error` had made dispatch failures escape an ordinary error handler. A signal raised from `doesNotUnderstand:` also unwound the shared activation stack beneath a nested evaluation and crashed with "index out of bounds"; `wfPopActivation` now reports completion when its activation is already gone, and eval-stack restores are clamped to the live length.
- `on:do:` discards its native placeholder result before installing handler and block checkpoints. Native signal sends also discard their placeholder before scheduled cleanup/handler work, keeping it out of pending binary operands. Normal completion, errors, notifications, missing messages and retry inside larger expressions have executed parity coverage; exception resumption remains unsupported.
- Daisy retains instance-side `shellClass` and `themeAttribute` for applications using configured Daisy instances, alongside the class-side styling helpers.
- Badminton integration tests use the current repository/page API, in-memory SQLite, and an owned HTTP child on an ephemeral port. They no longer require an external server, kill arbitrary port owners, or touch the application's database. SQLite and MummyX cases explicitly skip when their build features are absent.
- Redefining a class no longer leaks the previous one. `Class` values are process-global, so re-running a `.hrd` class definition created a new class and left the old one in its parent's `subclasses` list. Every `loadStdlib` added ~14 orphan classes to `Object` and made `loadStdlib` quadratic (1.6s on the first interpreter, 8.2s by the sixth). Subclass registration is now centralised in `registerSubclass`, which dedupes by name, and `renameClass` re-registers a derived class once its `.hrd` binding gives it its real name (previously it was renamed after registration, so the placeholder entry stayed behind). `Object.subclasses` is now stable at 27 with no duplicate names across repeated interpreters.
- `initGlobals` no longer creates a second `Number`, `Integer`, `Float`, `String`, `Boolean`, `True`, `False`, `Block`, `Random`, `Json`, `UndefinedObject` or `Class` when called again; it reuses the existing class. This was contrary to the contract documented at the top of the proc. `initCoreClasses` no longer creates `Integer`, `Float` or `String` either, which also restores `Integer`/`Float` deriving from `Number` (they had been attached to `Object` as a duplicate class, so `Number` methods such as `max:`, `min:` and `isZero` were not reachable through `Integer`).
- Fixed the bounded `SharedQueue` livelock: blocked processes retain their VM continuations and evaluated send operands, so loops and nested methods resume at the blocked message rather than restarting the statement. The scheduler advances only the outer fork activation and terminates only after its final statement drains all pending work. This also removes PC rewinding that could produce negative statement indices or prematurely terminate a nested block. Added bounded regressions for empty reads, full writes, single argument evaluation, and repeated waits in a final loop statement.
- An uncaught signal inside a host callback no longer terminates the process. `invokeGtkCallbackBlock` (and every widget signal path through it) now evaluates with `evalCallbackNonFatal`, so a mistake in a button/row/selection handler is reported and the IDE keeps running instead of quitting. A CLI script keeps the existing top-level behaviour (uncaught signal exits with the stack-trace banner).
- `evalWithVM` restores the saved work queue and eval stack in a `finally` block. It is a re-entrant entry point, so an error raised out of a nested evaluation previously left that evaluation's frames on the shared stacks, corrupting the caller, which then failed with an unrelated `index out of bounds` error. This affected nested `eval`/callback failure paths generally, not only GTK.
- `Object>>doesNotUnderstand:` now signals `MessageNotUnderstood` (a specific `Error` subclass) instead of the generic `Error`, and `Object>>error:` signals a catchable Harding `Error` rather than raising a Nim exception. Previously `error:` unwound past the Harding handler stack, so `Message not understood` could not be caught with `on:do:` at all.
- Unhandled dispatch failures are reported as an error instead of terminating the process, while an uncaught user exception still runs `defaultAction` and exits with the stack-trace banner. `evalStatements`/`doit` now handle `EvalError` before its `ValueError` supertype, which had been swallowing VM error reporting.
- Inherited slots keep a parent-first layout when `allSlotNames` is rebuilt. It was previously rebuilt own-first, so slot lookup past the first inheritance level addressed the wrong slot; JSON serialization of an object with inherited slots emitted swapped values.
- Exception unwinding no longer indexes the work queue past its end when a signal originates below the depth recorded at handler installation (for example a signal raised from `doesNotUnderstand:`); handler installation now clamps to the live queue and eval-stack depth.
- `::` falls back to the documented string key for tables and library bindings, so `table::name` and `myLib::Binding` resolve instead of returning nil. Slot reads and writes through `::` are unchanged.
- An external library bootstrap that signals an exception no longer terminates the host process; a failed bootstrap is reported and the remaining libraries still install.
- Failed `Harding load:` and `Library load:` operations now signal a catchable `LoadError` (new `lib/core/LoadError.hrd`) instead of printing to stderr and returning nil, so a bootstrap can no longer treat a failed load as success. Globals and library bindings are left unchanged when a load fails.
- Added `Object evaluate:`, returning a structured `{ok, value, error}` result; `Object eval:` keeps its existing plain-value/error-string behavior. Isolated evaluation now shares source indexing and scheduler ownership with the calling interpreter, and drives Bona's Workspace, Inspector, Browser, Builder, Transcript, and BonaMCP instead of error-message prefix matching.
- Workspace Do It reports its result to the Transcript again, matching the documented behavior.
- Browser refresh defers while the editor contains unsaved changes; Transcript retains bounded output independently of its window and reuses an already-open viewer.
- Browser source saves and deletions now replace only the selected parser-delimited definition, preserving unrelated classes, statements, comments, and file permissions; invalid or ambiguous edits are rejected before atomic replacement.
- Granite library bootstrap now initializes despite source-directory metadata and preserves class identity on reload; its dependency-list setup uses an explicit runtime Array instead of an invalid literal.
- GTK4 alert dialogs pass messages as literal text, use the correct button/completion ABI, free completion errors and dialog references, and treat cancellation as declining confirmation.
- **Non-local return (`^`) from blocks invoked through `do:`/`whileTrue:` no longer crashes the VM** with "Work queue underflow". `invokeBlock` now stops when its own activation receives a return (it can be the lexical home of an inner block), and the VM run loop treats a drained work queue as completion instead of popping from an empty queue.
- **`derivePublic:` / `derive:read:write:` generate accessor methods again** (`obj slot`, `obj slot: value`), restoring the documented behavior alongside `::` direct access (regression introduced by the v0.8.0 class-model refactor).
- Compiler: `parseTypeList` handles all derive slot list forms (`#(x y)`, `#(x, y)`, `#(x: Int)`, `#(x:, Int)`); analyzer tests updated and passing.
- Removed stale committed binaries `src/harding/interpreter/evaluator` and `src/harding/interpreter/vm`.
- `examples/language/blocks.hrd` now demonstrates non-local return from a method (Smalltalk `^` returns from the enclosing method/doIt, so the return target must be a method).

### Changed
- `tests/test_precedence.nim` and `tests/test_sync_primitives.nim` build one image apiece instead of one per test. Each test used to call `newInterpreter` + `loadStdlib`, and every image registers fresh core classes as subclasses of the shared global `objectClass` without detaching the old ones, so `objectClass.subclasses` grew by ~22 per image and `loadStdlib` became quadratic (1.7s, then 12.8s by the sixth image). `test_precedence` went from an apparent hang to 12.7s.
- `Object>>doesNotUnderstand:` signals `MessageNotUnderstood`; code that caught dispatch failures with `on: Error` still works because it is an `Error` subclass.
- `Workspace` gained `filePath:` / `filePath` accessors so callers that must not write into the working directory (tests, embedded use) can redirect the workspace file. GUI automation tests now write workspace files into a disposable temp directory instead of the repository root.
- Builder now loads an application's real `main:` source into its editor, tracks unsaved edits, and persists the edited body back to the owning `.hrd` file through the validated atomic writer; other definitions in that file are preserved. Builder templates use documented double-quoted strings.
- `tests/test_badminton_buddy.nim` no longer deletes the tracked `badminton-buddy/badminton.db` during setup/teardown.
- `tests/test_stdlib_io_and_packages.nim` used `&` as boolean conjunction; it now uses `and:`, matching current syntax. `test_load_and_eval` joined the core test group and `test_named_access_and_slots` joined the stdlib group.
- **Granite: single method-body codegen path.** Removed the dead `genMethodBodyFromAST`/`genMethodBody`/`genMethod`/`genMethodSignature`/`genMethodHeader`/`genSlotFastAccess` pipeline (~200 lines); compiled methods are generated by `genCompiledMethods` + `genMethodBodyStatement` only.
- **Granite: non-local return targeting.** Compiled methods get stable ids; blocks raise `NonLocalReturnException(value, targetId)` aimed at the lexically enclosing compiled method, and method boundaries only consume matching ids, re-raising others (matches VM home-activation semantics more closely).
- **Granite: shared block registry for method bodies.** Method-body blocks are registered into the module block registry before codegen, so every registered block gets exactly one procedure with a forward declaration; blocks containing `^` are no longer skipped by `collectBlocks` (they cannot be inlined) and inline `if` in block context dispatches through the runtime instead of mis-inlining return-bearing branches.
- **Granite: execution parity test suite.** `tests/test_compiler_block_parity.nim` now compiles a real case file through `genModule`, builds it with `granite build`, runs both engines, and asserts identical stdout (previously a placeholder that never executed generated code).
- `nimble test`-style core suites re-verified after VM fixes (interpreter, exceptions, closures, scheduler, compiler tests all green).

### Added
- Bona assessment documenting reproduced source-save data loss, bootstrap and MCP startup failures, GTK dialog binding issues, Builder workflow gaps, and AT-SPI/MCP automation options (`docs/BONA_ASSESSMENT.md`).
- External Harding library management (`library` command) for installing and managing third-party Harding packages.
- External BitBarrel library published as `bitbarrel` with registry support and package installation flow.
- External NimCP library packaging for installable MCP server support, including a Harding `NimCPServer` wrapper aimed at Bona-hosted MCP workflows.
- Corral database design documents covering the library vision (`CORRAL.md`) and a first technical RFC for SQL templates, table gateways, mapping, and schema support.
- Initial Corral external library package with registry entry, table/connection wrappers, parameterized `query:with:` and `execute:with:` support on SQLite and MySQL connections, first-pass row mapping and table CRUD helpers, and `sql{...}` template support with `$value` / `$(expression)` interpolation.
- Optional MummyX HTTP server integration documentation, including build tasks for both `harding` and `bona`.
- A Harding htmx-style web component layer, DaisyUI-backed Todo app example, and Bona workflow notes for live-editable MummyX web experiments.
- Block-aware cached Html templates and buffer-backed component rendering for reusable static markup with dynamic slots.
- Granite compiler Phases 0-7: exception handling codegen, remaining node types, and direct slot access compilation.
- VM optimization for declarative primitives eliminating dispatch overhead.
- **Prefix literal syntax** with `json{...}` for creating JSON strings directly. Pluggable design allows any class to implement `parseLiteral:` for custom `{...}` syntax. Case-insensitive prefix normalization (json, Json, JSON all work). Includes `Json parse:` and `Json stringify:` for bidirectional conversion.
- **`String class>>withCapacity:`** - Create pre-allocated mutable strings for efficient building.
- **`String>><<`** operator - In-place string appending that returns self for chaining. Uses Nim's efficient `add()` with automatic capacity doubling.
- **Constant literal optimization** - Array and Table literals with only constant elements (literals, no variables or message sends) are evaluated at parse time and cached. Interpreter uses pre-computed values, Granite generates compile-time Nim constants. Nested collections not yet optimized.
- Triple-quoted multiline string literals (`"""..."""`) for raw multi-line text with embedded `"` characters.
- Process and activation introspection APIs including `Process current`, `Scheduler current`, `Object>>activation`, and `Object>>thisContext`.
- Reactive state primitives in `lib/reactive/` (`TrackedValue`, `TrackedTable`, `TrackedList`) plus web render caching via `RenderCache`/`RenderEntry`.
- Simplified the Todo web example to a single tracked-state cached rendering path and removed the older parallel Todo rendering variants.
- Compiled JSON object serialization with class-side configuration (`jsonExclude:`, `jsonOnly:`, `jsonRename:`, `jsonOmitNil:`, `jsonOmitEmpty:`, `jsonFormat:`, `jsonFieldOrder:`, `jsonReset`) and `Object>>toJson`.
- JSON serialization benchmarks for nested Table/Array payloads and ordinary Harding object graphs.
- JSON API server tutorial with complete example application demonstrating REST patterns.
- MCP (Model Context Protocol) integration documentation for AI-assisted development workflows.
- Thin HTMX response helpers on `HttpRequest` for main fragments plus out-of-band fragments (`respondFragment:`, `oob:`, `oobs:`).
- `&` is now available as generic concatenation, and `#(...)` now accepts comma-separated elements as part of the syntax migration.

### Changed
- Bona workspace artifacts are no longer tracked in git (added to .gitignore).
- Class definitions in core libraries now include class-specific comments.
- BitBarrel support now ships as an external library instead of built-in Harding source and build flags.
- The Todo web example now renders through component-level `RenderCache` plus tracked-state invalidation, updates counters with HTMX out-of-band swaps, and drops the old template/benchmark routes.
- Html rendering now uses direct `Html render:` / `Html canvas:` entry points for the active web path, and the old auto-keyed Html cache helpers have been removed.
- MummyX request handling now runs through scheduler-backed green worker processes instead of executing on the socket thread.
- Granite block/codegen parity now covers captured block expressions, top-level block returns, 0-based collection access, and more runtime selector coverage.
- MummyX routes can now be cleared and rebuilt, and URL-encoded form data is exposed on `HttpRequest`.
- Bona now pumps scheduler work from the GTK main loop, refreshes open Browsers after successful Workspace evaluations, and documents the web stack through `Web` and `WebTodo` library bootstraps.
- **Removed Buffer class** - String now has `withCapacity:` and `<<` operator, making Buffer redundant. Use `(String withCapacity: 100) << "text"` instead of `Buffer withCapacity: 100` + `<<` + `contents`.
- `Json stringify:` now serializes ordinary Harding objects through compiled slot plans, supports primitive-only formatters (`#string`, `#rawJson`, `#symbolName`, `#className`), and falls back to `jsonRepresentation` when a class needs custom structure.
- Parser now supports binary expressions directly in table literal values with loosened precedence rules.
- Removed native collection block iteration paths in favor of interpreted implementations for consistency.
- `nimble test` now discovers and runs external library tests automatically.
- MummyX now includes request logging for debugging HTTP handlers.
- `lib/web/Html.hrd` now renders directly for the active todo path instead of routing through the older template-cache segment layer.
- Web-related bootstraps now use explicit initialization guards instead of `isEmpty`, so setting `__sourceDir` no longer prevents library contents from loading.
- The todo app now builds HTMX panel responses through `HttpRequest` fragment helpers instead of manually stitching response bodies.
- The active website content was refreshed to reflect current syntax, web/runtime capabilities, package workflows, and the newer tooling story.

### Fixed
- Hardened browser dialogs and class reflection in Bona IDE.
- Fixed source tracking temp file cleanup in tests.
- External library builds now resolve transitive Nimble dependency paths needed by installed packages.
- MummyX request handlers now resume correctly after blocking native receives in the stackless VM.
- Interpreter native-value dispatch now marks interpreter-aware wrappers correctly, fixing crashes in collection iteration and block benchmark examples.
- Interpreter `print` and `println` now render arrays and tables using their actual Harding string forms.
- **Fixed VM eval stack underflow** with nested HtmlTemplates using dynamic content blocks (`textWith:`, `attrWith:`, `fragmentWith:`). Root cause was BlockNode AST mutation during non-local returns corrupting the target activation. Fixed by copying block nodes before mutation.
- JSON table-key serialization now rejects unsupported key types explicitly and detects cycles in slot-based and `jsonRepresentation`-based object serialization.
- Fixed inherited slot access in both interpreter and Granite compiler.
- Restored external library runtime compatibility for proper loading.
- Collection species handling and non-local block return edge cases.

## [0.8.0] - 2026-03-09

### Added
- MummyX HTTP server support for building web applications and REST APIs.
- Application Builder tool for visual Granite compiler workflow.
- Canonical class derivation APIs: `derivePublic:`, `derive:read:write:`, and `derive:read:write:superclasses:`.
- `::` named access syntax for direct readable/writable slot access plus `Table`/`Library` binding access.
- Multiple-inheritance conflict reflection via `conflictSelectors` and `classConflictSelectors`.
- Source indexing for Browser method and class-definition lookups, including `<classDefinition>` pseudo-entries.
- `startsWith:` and `endsWith:` methods for `String`.

### Changed
- Multiple inheritance now uses first-parent-wins lookup order instead of failing on direct-parent selector conflicts.
- System Browser shows class definitions when selecting a class and refreshes source locations before save/delete.
- Browser-generated class definitions now use canonical `derive: ... read: ... write: ... superclasses: ...` form.
- Library restructure: reorganized into layered directories (core, stdlib, etc).
- Improved GTK callback stability and closure capture handling.

### Fixed
- Source location tracking now reparses files after edits so method offsets follow line-count changes.
- GUI/browser editing paths no longer depend solely on stale cached line ranges.
- Closure capture in IfNode/WhileNode control flow blocks.
- Array sorting and collection method improvements.
- Exception handling and block unwind cleanup fixes.
- Builder heightRequest and compilation fixes.

## [0.7.1] - 2026-03-02

### Added
- IDE Inspector rewritten with tree view and embedded workspace support.
- System Browser context menus with method deletion capability.
- GTK widget support: `GtkListBox`, `GtkPaned`, and separator support in `ContextMenu`.
- `startsWith:` and `endsWith:` methods for `String` (implemented as Nim primitives).
- Alert dialog integration and GTK automation hooks for IDE.
- Comprehensive compiler block parity test suite.

### Changed
- Replaced button-based BrowserPane with `GtkListBox` for improved UX.
- Browser save/reload workflow improvements with keyboard shortcuts.
- `printIt` now inserts at cursor position and selects inserted text.
- Improved debug/warn templates and removed unused logging imports.

### Fixed
- Compiler nested block compilation with proper registry sharing and forward declarations.
- Block compilation with captures and environment structs.
- Recursive non-local return detection in blocks.
- Preserved captured variable writes in indexed assignment fast path.

### Performance
- VM optimizations: indexed locals, frame pooling, and logging improvements.

## [0.7.0] - 2026-02-27

### Added
- Mixed-mode compilation fallback to interpreter runtime (`--mixed`) and supporting runtime integration.
- Native Nim class generation support in the compiler, plus Harding-side `compile:` / `main:` workflow improvements.
- Exception signal-point capture and restoration (`ExceptionContext`, `resume`, `resume:`), including `Notification` resumable behavior.
- Slot reflection and improved native type conversion pathways (`toValue`, `classRef` support).

### Changed
- Merged major development lines from `compiler-next` and `fix-exceptions` into `main`.
- Strengthened stackless VM control flow around returns, activation cleanup, and work-queue handling.
- Tightened boolean semantics for conditional evaluation to align with Smalltalk-style true/false logic.
- Updated standard library behavior for arrays, intervals, sorted collections, symbols, and strings to match current runtime semantics.

### Fixed
- Exception control-flow correctness for handler actions (`pass`, `return:`, uncaught default action, resume continuation behavior).
- Closure isolation and receiver/home-activation edge cases in block evaluation.
- Release-build safety issue in `println` (memory safety fix).
- Parser/operator consistency issues and several method dispatch/lookup edge cases.
- Multiple stdlib and website example regressions uncovered during merge stabilization.

### Performance
- Method-table lazy rebuild optimization (significant speedup in lookup-heavy paths).
- Activation/frame pooling and follow-up VM optimization phases.
- Compiler-side optimization passes and block/codegen improvements.

### Tests
- Expanded and stabilized tests for exceptions, stdlib, parser precedence, dynamic dispatch, and website examples.
- Split large stdlib coverage into focused suites for faster diagnostics.

[Unreleased]: https://github.com/gokr/harding/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/gokr/harding/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/gokr/harding/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/gokr/harding/compare/v0.6.0...v0.7.0
