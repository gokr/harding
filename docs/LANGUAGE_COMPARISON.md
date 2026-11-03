# Harding compared to Smalltalk-80, Python, Ruby and Go

## Scope and status

This is a **language-design review**, not a specification and not a conformance
claim. It records what Harding looks like next to four reference languages, what
is distinctive about it, and where its design promises and its implementation
disagree.

Every behavioural claim below was executed against `main` at `5ff020b` with a
locally built `./harding`, not inferred from documentation. Where a claim rests
on a documented measurement (benchmarks) or on source reading (mixins), the
source is named. Probes were one-off scripts; they are **not** a test suite, and
several of the surprising results below are candidates for regression tests
rather than established contracts.

Baselines are broad rather than version-pinned: "Smalltalk-80" means the
classic language and image as described in the blue book; Python, Ruby and Go are
referenced by general behaviour, not by a specific release. This document should
be re-read against a current tree rather than trusted as current state.

## What Harding is

A class-based Smalltalk dialect running on a Nim-implemented **stackless VM**
(work-queue driven, not native call stack). Two execution paths must agree:

- the **interpreter** (`./harding`), the reference semantics;
- **Granite** (`./granite`), which compiles the same AST to Nim and then to a
  native binary.

`lib/core/` holds 32 classes; the library is layered into 11 directories
(`core`, `standard`, `syntax`, `gui`, `web`, `granite`, `mummyx`, `reactive`,
`process`, `mysql`, `corral`). Binaries require Nim 2.2.12 as the toolchain.

Scripts are compiled as `#doIt` on `UndefinedObject`, matching the Smalltalk
workspace convention: `self` is `nil`, lowercase top-level assignments are locals
of the do-it, `| x |` temporaries are legal, and `^` returns from it. Only
uppercase names are globals (`docs/MANUAL.md`, "Script Files").

## Smalltalk-80: same bones, deliberately different limbs

### Faithful to classic Smalltalk

Verified by execution:

- message sends, `[...]` blocks, and `^` as a **non-local return** from a block
  inside a method (`[ ^ "early" ] value` returned `early`, skipping the rest);
- `self` is captured by blocks (`[ ^ self v ] value` answered `5`);
- cascades, including mixed keyword segments;
- `on:do:` supplying a handler *result*, and `ensure:` running exactly once on
  error (`cleanup` printed before the uncaught banner);
- `nil` as a real object answering `ifNil:`;
- primitive declaration in `.hrd` with the implementation in Nim;
- **runtime class redefinition**: redefining a live class kept existing
  instances on the old slot layout and gave new instances the new one;
- the metaclass tower: `K class class = K` answered `true`, and `K class
  respondsTo: #new` answered `true`;
- `doesNotUnderstand:` as a recovery hook (see the caveat under shortcomings).

### Deliberately different

| Topic | Smalltalk-80 | Harding |
|---|---|---|
| Slot visibility | all instance variables private; accessors are methods | `derivePublic:`, and `read:`/`write:` lists; `::` direct access **bypasses** accessor overrides |
| Where code lives | incremental compiler inside the image | source is canonical; target is Nim |
| Integer range | exact integers and `Fraction` | 64-bit only; overflow is a **fatal, uncatchable** VM error |
| Exceptions | resumable (`resume`) | resumption removed; `e resume` answers *Message not understood* |
| Numeric equality | `1 = 1.0` is true | `(1 = 1.0)` is **false**; `==`/`~=` are identity only, so `1 == 1.0` is also false |
| String concatenation | `,` on strings and collections | `,` is **reserved for literal separators**; `"a" , "b"` is a parse error, `&` concatenates |
| Characters | `$a` is a Character literal | **no Character class**; `$a` is a parse error |
| Array printing | `(1 2 3)` | `#(1 2 3)` -- unchanged literal syntax in `printString` |
| `<<` append | mutates the receiver | mutates **only** instance-backed strings; a value string answers a new string |
| Module system | image-wide namespace | `Library load:` captures bindings into a named library; `Harding load:` loads globally |

### Precedence: mostly Smalltalk, with one divergence

Smalltalk's rule is unary > binary > keyword, with binary strictly
left-to-right and no arithmetic precedence. Harding matches the first two:

```
2 + 3 * 4        -> 20      # left-to-right, no arithmetic precedence
10 - 2 - 3       -> 5
3 + 4 printString -> 4      # unary binds tighter than binary
```

It does **not** match the third. Binary operators bind tighter than keyword
message arguments:

```
2 * 3 max: 4     -> 6       # parses as (2 * 3) max: 4
2 * (3 max: 4)   -> 8
```

In Smalltalk-80 the unparenthesised form parses as `2 * (3 max: 4)` and answers
`8`. This is the kind of difference that silently changes arithmetic in
otherwise portable code, and it is currently undocumented.

## Python and Ruby: dynamic, but not a scripting-language syntax

Nothing here is Pythonic or Rubyish, deliberately:

- no statement-level `if`/`while`/`def`, no operator precedence table, no `for`,
  no comprehensions, no default or keyword parameters;
- construction is `new`, not a constructor call;
- newlines act as statement separators, so periods are optional outside cascades
  (`x := 1` then `y := 2` on successive lines needs no `.`).

Ruby is the nearer relative: blocks read like `do |x|`, and
`doesNotUnderstand:` occupies the `method_missing` niche. The mapping is loose:

- **the DNU argument is the selector symbol, not a message object.** It supports
  `printString` (yielding `#bogus:with:`) but not `class`, `name`, `arguments`
  or `selector`. There is no way to reach the actual arguments from a handler.
- `Library load:` resembles a namespaced `require`, but it captures *bindings*
  into a library object, not a module.

Where Python and Ruby are friendlier, and Harding is not:

- **Integers trap.** `9223372036854775807 + 1` raises `Error: VM error: over- or
  underflow`, and it is **not catchable**: wrapping it in `on: Error do:` still
  aborts the script. Python promotes to a bignum, Ruby to a Float.
- String-to-number conversion is nil-answering rather than exception-raising:
  `"42" asInteger` -> `42`, `"bad" asNumber` -> `nil` (documented in
  `docs/QUICKREF.md`). That is more disciplined than Ruby's `to_i` -> `0`.

## Go: the interesting pair

Harding's green processes are the closest analogue to goroutines, and the
difference is sharp.

```
Processor fork: [ ... Processor yield ... ]   # cooperative
Scheduler runToCompletion: 1000               # something must pump the queue
```

Verified: `Processor fork: [ "hello" println ]` alone printed **nothing**, and
repeated `Processor yield` in the top-level process did not drain the queue.
Only `Scheduler runToCompletion:` produced output -- after which two forks did
interleave correctly (`A1 A2 A3 B1 B2 B3`). The shipped example drives the
scheduler explicitly (`examples/concurrency/process_demo.hrd`).

So: processes are **cooperative and externally pumped**, not multiplexed by a
runtime. There is also **no channel type**; the offered concurrency primitives
are `Semaphore`, `Lock`, `Monitor` and `SharedQueue`.

What Go shares with Granite, and Smalltalk-80 does not, is a **native binary
with no runtime image**. Neither Go nor Harding offers an image snapshot: there
is no "save the running world and resume it" as in Smalltalk-80.

## What is distinctive

The distinctiveness is **compositional**, not per-feature. None of these is
unique in isolation; the combination is.

1. **Smalltalk semantics with two engines over one AST.** Source is canonical,
   the interpreter is the reference, and Granite must match it. That is enforced
   by **105 differential parity cases** (`scripts/test_granite_parity.py`) plus an
   **81-case example audit** (`examples/manifest.json`). Neither Smalltalk-80 nor
   Go nor Python needed cross-engine parity, having one implementation each.

2. **`::` direct named access** unifying three namespaces under one syntax:
   `person::name` (slot), `table::key`, `MyLib::Class` (library binding). There
   is no Smalltalk equivalent. It deliberately **does not** invoke accessor
   overrides, so it is a performance escape hatch with its own semantics.

3. **Optional slot type contracts declared in the language**, enforced at
   allocation, `::` writes, generated setters and reflective `at:put:` in *both*
   engines. Verified: `#{#count -> Integer, #ratio -> Float, #ok -> Boolean}`
   yielded defaults `0`, `0.0`, `false` at allocation, and `r count: "text"`
   raised a catchable `Error` while preserving the old value. On top of that,
   **advisory** inference (`src/harding/compiler/slot_inference.nim`) informs
   native unboxing without changing semantics. Smalltalk has no types; Go has no
   optionality; Python and Ruby have neither enforced nor advisory slot types.

4. **A stackless VM that still compiles to native code.** Because frames live on
   a heap work queue, deep recursion is bounded by VM limits rather than the
   native stack: `deep: 20000` completed and returned `20000`. The same
   definition is also the input to Granite.

## Simplifications

Legitimate design wins:

- newlines as separators;
- one `nil` with `ifNil:`/`ifNotNil:` instead of null-checking;
- strict `=` versus `==`, so `1 = 1.0` does not quietly succeed;
- `--mixed` compilation to bridge to the interpreter;
- primitives declared in `.hrd` with the Nim half shipped as a package
  (`docs/NIM_PACKAGE_TUTORIAL.md`).

Aggressive simplifications worth flagging:

- **No resumption.** `resume`, `resume:`, `return:` and `isResumable` do not
  exist (`docs/EXCEPTION_MODEL.md`). Defensible as a contract, but it changes
  what exception handling is *for*: handlers become value suppliers rather than
  resumption points.
- **No `subclassResponsibility`** (answers *Message not understood*), no
  `allInstances`, and no method-list reflection -- `respondsTo:` works, `methods`
  does not. Class-side `removeMethod:` does work at runtime.
- **No `case`/`switch`** construct.
- **`json{...}` builds a JSON *string***, not a Table, so it is a different type
  from the visually similar `#{...}` table literal.
- **`Lib load:` and `Harding load:` are the only import mechanism**; there is no
  module system in the Python/Go sense.

## Shortcomings

These are places where behaviour contradicts the promise. Each was reproduced.

1. **Arithmetic overflow is fatal and uncatchable.**
   `9223372036854775807 + 1` aborts the process with `VM error: over- or
   underflow`; an `on: Error do:` wrapper does not intercept it. This is the
   sharpest edge in the language, because a numeric bug becomes a dead process
   with no in-language recovery.

2. **`<<` is documented as mutating but mutates conditionally.**

   ```
   b := "abc". b << "def". b println.              -> abc    (new value returned)
   b := String withCapacity: 16. b << "def". b println. -> abcdef (receiver mutated)
   ```

   `primitiveStringAppend:` returns a new `NodeValue` for `vkString` and mutates
   only for `vkInstance`-backed strings (`src/harding/interpreter/vm.nim`,
   `stringAppendMethod`). `docs/QUICKREF.md` and `docs/MANUAL.md` both state
   "mutates, returns self". Identical-looking code therefore behaves differently.

3. **The shipped mixins contain a call to a non-existent method.**
   `Comparable>>compareTo:` is `^ self identityHash - anObject identityHash`, and
   `Printable>>printOn:` calls `self identityHash printString`; **no
   `identityHash` exists** (`K new identityHash` -> *Message not understood*).
   `Comparable` was unusable in every probe (`Measured addSuperclass: Comparable`
   then `m compareTo: m` failed). Adopting `Printable` still printed `<K>`, so the
   practical damage is confined to `Comparable`, but the default is broken as
   written. `Equatable` works.

4. **Unknown identifiers silently answer `nil` inside methods.**
   `K>>oops [ ^ counterr ]` returns `nil` rather than signalling. At script level
   this is correct and documented (lowercase names are do-it locals), but inside
   a method a typo becomes a silent nil, which undercuts the missing-selector
   discipline the manual otherwise emphasises.

5. **`doesNotUnderstand:` cannot see its arguments**, as described above. Reaching
   them would require a message object rather than a symbol.

6. **Precedence divergence** between binary and keyword messages (see above) is
   undocumented and differs from Smalltalk-80.

7. **Documentation drift, both directions:**
   - string interpolation is listed in `src/harding/core/types.nim`'s literal
     section (`#` + `{`) but `"Hello, #{name}!"` prints literally; it is not in
     `docs/QUICKREF.md`. This looks like a Nim-ism that never fires.
   - `<<` mutation is overpromised (item 2).
   - `$a` characters and `,` concatenation are Smalltalk reflexes that parse as
     errors, which is fine but is not called out where a Smalltalk reader will
     look.

## Performance context

Granite exists to make Harding fast, and the honest summary is "much faster than
its own interpreter, much slower than a mature VM":

- Granite is **~89x faster** than the release interpreter on trial division
  (`docs/GRANITE_BENCHMARKS.md`), and ~23x/~13x on object workloads.
- Against Cog (Squeak 6.0, Spur/Cog), Cog is **~17x, ~112x and ~355x faster**
  on trial division, queens and towers respectively
  (`docs/BENCHMARK_COMPARISON_CURRENT.md`); Granite is ~325x/~195x slower than
  Cog on the object workloads recorded there.
- These are workload-specific ratios, not a language ranking, and the docs are
  careful to say so.

## If a later reader picks this up

Suggested order, smallest risk first:

1. **Make `Comparable` work** -- give it a real default (`compareTo:` cannot
   depend on an absent `identityHash`), or make `identityHash` exist. This is a
   broken shipped class.
2. **Fix the `<<` contract** -- either mutate consistently or stop documenting
   mutation. Either choice removes a silent divergence.
3. **Make overflow catchable**, or document the trap as intentional alongside the
   `asInteger`-answers-nil policy.
4. **Decide the keyword/binary precedence rule** and document it, whichever way
   it goes.
5. **Add regression tests** for the behaviours this review probed ad hoc:
   cascade-with-control-flow, `doesNotUnderstand:` arity, `<<` on literals,
   `Comparable` adoption, and script-level soft scoping. Several of these were
   bugs found by inspection and are currently unprotected.
6. **Consider `subclassResponsibility` and `identityHash`** -- both are cheap and
   both are expected by anyone arriving from Smalltalk.

## Revisit checklist

When re-reading this document, confirm the following before trusting it:

- `git log --oneline -1` -- the review reflects `5ff020b`; language behaviour has
  moved since then if the log shows newer commits touching `lib/core/`,
  `src/harding/interpreter/` or the parser.
- Re-run the probes: `./harding build <script>` for each claim.
- Re-check counts: `scripts/test_granite_parity.py` (105 cases at review time)
  and `examples/manifest.json` (81 cases).
