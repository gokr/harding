# Absence and nil: findings and decisions

## Status and decision

**Investigated, decided: no dramatic change for now.** `nil` stays nameable in
Harding. This note records what was examined, what was measured, why the
"remove nameable nil" idea was rejected, and which concrete defects were found
that are worth fixing regardless.

Date of investigation: `main` at `5ff020b`. Counts come from the audit described
in *Exhaustive audit of current nil usage*; the script is
`build/lang/nil_audit.py` and its output `build/lang/nil_audit.json`.

### Decision

1. **Keep `nil` nameable.** No grammar restriction.
2. **Make `isNil` a primitive.** It is too fundamental to be a method whose body
   names `nil`, and a primitive lets the compiler reason about it.
3. **Make access-style lookups signal instead of returning nil.** Verified today:
   `(Array at: 99)` → nil, `(Table at: "missing")` → nil, `(Library at: #nope)` →
   nil — none raise. Proposal: `Array at:` out of bounds raises
   `SubscriptOutOfBounds`; `Table`/`Library` `at:` on a missing key raises a new
   `NotFound` (`Error` subclass), with `at:ifAbsent:` and friends for cases where
   absence is expected.

   **Absence in *search*-style lookups keeps answering nil** — `indexOf:`,
   `detect:`, `findFirst:`, `findLast:`, `Bag indexOf:`, `Table detect:`. There
   absence is a normal answer, not a caller error, and every one of them already
   has or should have an `ifNone:` sibling.

   Safety evidence for the switch: **zero** call sites in `lib/` rely on
   `(x at: k) isNil`. The remaining plain `at:` uses are array indexing with
   loop-proven indices or table reads of keys the producing API guarantees
   (`evaluation at: "value"` from the `Object evaluate:` contract, `classInfo at:
   "source"` from source indexing). Those would begin raising if the guarantee is
   ever broken — which is the desired outcome, since a missing key in a structured
   result is a bug rather than a value.
4. **Keep both nil representations, scoped per engine**, with `isNilValue()` as the
   sole predicate. Implemented — see *Representation* below.
5. **Fix `Root`** so `Root derive:` works. **Done** — see *Fixed: Root derive:*
6. **Close the absent-protocol gaps** rather than removing nil: `at:ifAbsent:`,
   `detect:ifNone:` exist already and should be preferred in new code.
7. **Make integer overflow catchable** as `Overflow` under a new `ArithmeticError`,
   mirroring Nim's `ArithmeticDefect`. **Done** — see below.

### Why "remove nameable nil" was rejected

The idea was to forbid `nil` as a literal (`x := nil`, `^ nil`, `foo: nil`) while
keeping it as an internal slot state checkable only via `isNil`. It does not work,
because banning the *literal* does not remove the *value*. A slot still holds nil,
and nil flows out through every read path without the word `nil` ever appearing:

```harding
h := H new.                # H derivePublic: #(v); v never assigned
tmp := h::v.               # -> nil
(K new take: (h::v))       # -> nil, passed as an argument
H>>get [ ^ v ]             # -> nil, returned
(h v)                      # -> nil, via the generated getter
```

All four were verified. So the restriction would cost a large migration — 194 of
275 nil occurrences would need touching — while leaving the leak that motivated it
intact. The mechanism was cosmetic.

A coherent version is possible, but it is a *typed-slot* proposal with a grammar
restriction as a side effect, not the reverse:

- **A. Protocols only** (chosen): no grammar change; close absent-protocol gaps and
  make access lookups signal. Cheap, honest, no cliff.
- **B. Typed optionality**: a slot is `ref T` (guaranteed populated) or an explicit
  `Maybe[T]` with total deconstruction. Delivers real guarantees, but adds wrapper
  ceremony on exactly the hot paths that matter.
- **C. Unrepresentable nil**: `ref T` slots can never hold nil, so unassigned slots
  must not exist. Coherent, but it is option B's type work in disguise.

One detail worth keeping from the analysis: `ref T` being *nil-capable* is what
keeps the hole open. Either a ref may be nil — then reads leak it — or it may not,
and you need B or C. `ref T` cannot simultaneously mean "cheap nil" and "nil is
rare".

An earlier note in this repository reached the same conclusion
(`GRANITE_SLOT_TYPE_INFERENCE.md`): *do not attempt to eliminate nil; it buys no
performance over a typed ref, and a global Null Object convention converts loud
failures into silent ones.* The investigation here independently reproduced that,
and the slot-read demonstration above explains why.

## The original goal

The investigation asked whether nil could be reduced. The two intended effects
were:

1. **Developers stay away from using nil as a valid value.**
2. **The nil surface area shrinks**, so both humans and the compiler can reach
   better conclusions about where a nil-valued reference can appear.

The second is the interesting one. Nil is not the worst dynamic-language bug — a
wrongly-typed object is equally bad and completely unprovable in a dynamic
language. But nil is the **one wrong value a compiler can see coming**: it is the
only value guaranteed not to understand the selector you are about to send. That
is the entire case for tightening it.

## The rejected option: unnameable nil literal

As explored (and rejected, see above):

In source code:

- `nil` is no longer a literal. `x := nil`, `^ nil`, `= nil`, `== nil` and
  `nil send` are all rejected.
- `isNil` becomes a **primitive** (a compiler-known predicate), not a method
  whose body mentions `nil`.
- Nil remains a runtime state, produced only by the four legitimate sources
  listed under *Legitimate internal nil* and consumed only by absent-protocols.

Rationale for the primitive: `Object>>isNil` is currently
`^ self = nil` (`lib/core/Object.hrd:302`). If nil is unnameable that body is
illegal, so `isNil` must move below the language. This is a win rather than a
concession — a primitive predicate is total, cannot be shadowed unexpectedly, and
gives the compiler something to reason about, which a normal send never would.

`=` (equality) and `==` (identity) both stay. They are needed so that `isNil`
is definable over *something*, and identity comparison is load-bearing for
collections and `compiledIdentityEqual`.

## Legitimate internal nil

Four sources, in order of how hard they are to avoid.

### 1. Uninitialized slots

`Slot := Object derive: #(v)` leaves `v` nil. Verified: `C new` then
`items isNil`, `name isNil`, `count isNil` all answer `true`.

This is the case that must survive. With object slots as `ref T`, nil is the
zero pointer: no `Option`, no tag, no branch, **zero cost**. It is also statically
known — the compiler knows a slot has not been assigned, which is precisely the
conclusion effect (2) is after.

Note what removing `:= nil` achieves here: uninitialized becomes the *only* way
to get a nil-valued slot, so "is this slot nil?" stops being a question about
program flow and becomes a question about declaration plus definite assignment.

### 2. Discarded statement-position results

`ifTrue:` in statement position, `do:`, `whileTrue:`, `timesRepeat:` all answer
nil today. Verified: `a := false ifTrue: [1]` → nil, `[false] whileTrue: [1]` →
nil, `#() do: [...]` → nil, while `select:` and `timesRepeat:` answer their
receiver or a collection.

Volume in `lib/` alone, split by position:

| Form | Statement position | Value/return position |
|---|---:|---:|
| `ifTrue:` | 201 | 101 |
| `whileTrue:` | 50 | 1 |
| `do:` | 188 | 32 |

These **must keep working with no syntax change**. They can, because the value is
discarded before any send reaches it, so no nameable nil is required — the nil is
created and dropped inside one statement. This is the cheapest case to preserve
and the one where a naive "no nil anywhere" rule would break the most code.

### 3. Absent results consumed by absent-protocols

`at: k ifAbsent:`, `detect: ... ifNone:`, `ifNil:`, `ifNotNil:`, `removeKey:ifAbsent:`.
The nil is produced and consumed inside a single expression, so nothing escapes.

The stdlib is further along here than a previous revision of
`GRANITE_SLOT_TYPE_INFERENCE.md` claimed (that note counted these as zero; the
count was wrong, now corrected in place):

| Form | Lines in `lib/` |
|---|---:|
| `at:...ifAbsent:` | 99 |
| `detect:...ifNone:` | 8 |
| `ifNil:` | 4 |
| `ifNotNil:` | 3 |
| plain `at:` | 422 |
| plain `detect:` | 14 |

`Iterable>>detect: block ifNone:` already exists (`lib/core/Iterable.hrd:53`).

### 4. Array holes

`Array new: 3` yields `#(nil nil nil)` (verified). Either:
- require a filler (`Array new: 3 withAll:` already exists), or
- keep holes internal-only and require absent-protocol access.

**Open question** — not yet decided.

## The `at:` readability question

Answer: **no, `at:` does not have to become `at:ifAbsent:`.** The distinction that
makes this work is between *collections whose miss is an error* and *collections
whose miss is a normal outcome*.

Measured, and this is the key finding: **`Array at:` out of bounds returns nil, it
does not raise.** `primitiveArrayAtValueImpl` returns `nilValue()` for a bad index
(`src/harding/interpreter/vm.nim:3323`), and `SubscriptOutOfBounds` is declared but
never signalled for arrays. So today both Array and Table silently answer nil on
a miss.

The only `at:` sites that genuinely return nil are **Table and Library lookups** —
about 148 `at:` lines in `lib/`, of which the overwhelming majority (102) are
array indexing with a proven in-bounds index (`self at: index` inside a `do:`,
`self at: 0`, `self at: i` in a loop). Array indexing is not a nil-return surface
once bounds are checked.

So the proposal is:

| Receiver | Miss behaviour | Source form |
|---|---|---|
| Array | **raise** `SubscriptOutOfBounds` | `at:` stays plain, unchanged |
| Table | nil (internal) | `at:` in value position requires `at:ifAbsent:`; `at:` alone is **statement/discard-only** |
| Library | nil (internal) | same as Table |

That keeps the 102 array sites and all 51 `whileTrue:` sites unchanged, and only
touches genuine hash-lookup misses — which is where an explicit absent-branch is
worth reading anyway.

If `Table at:` must stay usable in value position without a fallback, the
alternative is a `Result`/`Maybe` return, which is strictly more verbose than
`at:ifAbsent:` and buys nothing here. Recommendation: don't.

## The `::` question

`::` is currently the **largest silent-nil hole in the language**, and it is worse
than `at:`:

```
t := #{"k" -> 1}.
t::zzz            -> nil      (no error)
t::zzz isNil      -> true
h := H new.                   # H derivePublic: #(v)
h::v              -> nil      (uninitialized slot)
```

Neither case raises. So `::` cannot be left as-is under this proposal, and it
cannot simply be banned either, since it exists for O(1) access.

Options, in order of preference:

1. **`::` becomes strict for tables.** A missing key raises (a
   `SubscriptOutOfBounds`-style error or a dedicated one). Reads of *uninitialized
   slots* still answer internal nil, but that nil can only be consumed by
   `isNil`/`ifNil:` — so `h::v println` fails at the send, not at the lookup.
   This preserves the performance purpose and removes the silent-absent read.
2. **`::` requires a declared witness** (`::` on a table only where the key is
   known present), which needs flow analysis the language does not have.
3. **Restrict `::` to slots only**, and route table access through
   `at:`/`at:ifAbsent:`.

Recommendation: (1). It is the smallest change that removes the hole and it keeps
the documented reason `::` exists.

## Semantics to decide

### `isNil` as a primitive over a closed predicate

Current nil protocol, verified: nil answers `isNil`, `notNil`, `class`,
`printString`, `asString`, `yourself`, `==`, `=`, `~=`, `ifNil:`, `ifNotNil:`,
`isKindOf:`; `respondsTo: #foo` answers **false**; everything else raises
`MessageNotUnderstood`.

That set is the whitelist the proposal must make explicit in one place, with a
boot-time assertion that nothing else answers on nil. Today it is implicit and
scattered across `vm.nim:7947`, `runtime.nim:1639` and
`UndefinedObject>>printString`.

### Representation: keep both, enforce the predicate (implemented)

Earlier drafts proposed unifying on a single representation. Measurement showed
that is the wrong framing: the split is an **engine boundary**, not an accident.

| Path | Raw `NodeValue(kind: vkNil)` sites |
|---|---:|
| Compiled/Granite (`runtime.nim` 48, `codegen/expression.nim` 13, `compiled_support.nim` 11, `codegen/module.nim` 6) | 78 |
| Interpreter (`vm.nim` 2, `objects.nim`, `compiler_primitives.nim`, `activation_pool.nim`) | 6 |
| Shared (`types.nim`, `log_support.nim`) | 2 |

Compiled code speaks `vkNil`; the interpreter speaks `nilInstance` after
bootstrap. `nilValue()` already prefers the instance form and falls back to
`vkNil` only during early bootstrap.

**Decision: keep both, scope them per engine, and make `isNilValue()` the only
legal predicate.**

- `vkNil` is the right form for compiled code: a zero-cost immediate, which is
  also what future `ref T` representation will reflect.
- `nilInstance` is the right form for the interpreter: `nil` is a real
  `UndefinedObject` there, so `class`, `respondsTo:` and `printString` work by
  dispatch rather than special-casing.
- Unifying either way is worse. On `vkNil`, every semantic nil operation becomes a
  dispatcher special case. On `nilInstance`, compiled code pays for absence on
  every nil check.

The hazard was never the two forms — it was 86 raw sites bypassing the predicate,
which is what caused a measurement to report zero nil writes.

### Implemented cleanup

Done as part of this investigation:

1. **Semantic nil checks now use `isNilValue()`** — `lookupVariableWithStatus`
   (table property, slot), `applyContractZeros`, and the two REPL result printers
   (`repl/harding.nim`, `repl/doit.nim`)
2. **Interpreter-side constructions now return the canonical nil** —
   `graniteCompileImpl` and `writeHardingLog` returned raw `vkNil` to the
   interpreter; both now return `nilValue()`
3. **Guard: only 3 raw `vkNil` comparisons remain**, all of them deliberate and
   now commented as such:
   - `performWithImpl` (`vm.nim`) — "an argument was supplied", because a supplied
     argument may legitimately be nil. Changing it would silently drop real nil
     arguments.
   - `wfReturnValue` (`vm.nim`) — `frame.returnValue` uses `vkNil` as the "no
     explicit return value" placeholder, which must be distinguishable from a nil
     value.
   - `isNilValue` (`types.nim`) — the predicate itself.

   Two candidate sites were **left raw on purpose** after inspection:
   `activation_pool.returnValue` and the `nkReturn` placeholder frames, both of
   which use `vkNil` as a sentinel that is semantically distinct from nil.

Regenerate the list with:

```bash
grep -rn "== vkNil\|!= vkNil" src/harding/ --include=*.nim
```

Expect exactly the three sites above. A fourth means a new bypass was introduced.

### Definite assignment for temporaries

Orthogonal to nil, cheap, and already half-built: `analyzeNumericBindings`
(`src/harding/codegen/module.nim`) rejects reads before definite initialisation
for numeric locals. Extending it to all temporaries catches real bugs and lets a
native local be a plain Nim `var` with no nil sentinel.

Recommendation: implement as a **warning** first. It is a source-compatibility
break, and the violation count across `lib/`, external libraries, Bona and
`examples/` is unknown.

## Exhaustive audit of current nil usage

Counts from a positional scan of every `.hrd` file under `lib/`, `examples/`,
`external/`, `benchmark/` and `tests/` (script: `build/lang/nil_audit.py`,
output `build/lang/nil_audit.json`). Classification is syntactic: each `nil`
occurrence is assigned to the position it occupies.

**275 occurrences across 48 files.**

| Position | Occurrences | Files | Legit under the proposal? |
|---|---:|---:|---|
| Keyword argument (`foo: nil`) | 95 | 9 | **No** — must be transformed |
| `^ nil` (return) | 77 | 31 | **No** — caller-side protocol |
| Slot assignment (`slot := nil`) | 57 | 13 | **Yes** — the one allowed form |
| Local assignment (`tmp := nil`) | 24 | 9 | **No** — locals cannot be re-nilled |
| Block result (`[ nil ]`) | 25 | 6 | **No** — but usually becomes `ifNil:` |
| Table/declaration value (`-> nil`) | 0 | 0 | n/a (no such form exists) |
| Comparison (`= nil`) | 1 | 1 | Replaced by `isNil` |
| Other | 5 | 4 | case by case |

By area:

| Area | kwarg | return | slot-assign | local-assign | block | compare |
|---|---:|---:|---:|---:|---:|---:|
| `lib/` | 88 | 42 | 51 | 10 | 24 | 1 |
| `examples/` | 7 | 22 | 0 | 0 | 0 | 0 |
| `external/` | 2 | 11 | 0 | 1 | 0 | 0 |
| `benchmark/` | 12 | 2 | 6 | 13 | 0 | 0 |
| `tests/` | 6 | 0 | 0 | 0 | 0 | 0 |

The headline is that **the allowed form (slot assignment) is only 21% of usage.**
The dominant pattern is *nil as an argument value* (95), and second is
*absent return* (77).

### The optional-parameter pattern, and how it transforms

This is the pattern the proposer identified: multi-parameter methods called with
`nil` for arguments the invocation does not need, with the callee checking which
were supplied. It is real and concentrated, and the canonical example is worth
reading in full because it is the hardest case in the codebase.

`lib/gui/bona/Browser.hrd:727`:

```harding
Browser>>rewriteManagedClassFileWithClassDefinition: classDefText
        overridingSelector: overrideSelector
        methodText: overrideMethodText
        removeSelector: removeSelector [
    | editOwner selector replacement deleting response |
    editOwner := self currentMethodOwnerClass.
    editOwner isNil ifTrue: [ editOwner := self currentClass ].
    deleting := removeSelector notNil.
    selector := deleting ifTrue: [ removeSelector ] ifFalse: [ overrideSelector ].
    replacement := overrideMethodText.
    selector isNil ifTrue: [
        selector := "<classDefinition>".
        editOwner := self currentClass.
        replacement := classDefText
    ].
    ...
```

Four parameters, of which **exactly one is meaningfully supplied per call**:

| Call site | Supplies |
|---|---|
| `overridingSelector: selectorLine methodText: methodText removeSelector: nil` | 2 of 4 |
| `overridingSelector: nil methodText: nil removeSelector: self currentMethod` | 1 of 4 |
| `overridingSelector: nil methodText: nil removeSelector: nil` | 1 of 4 |

So the method is really **three mutually exclusive operations** sharing a body:
rewrite a class definition, override a method, or delete a method. The `nil`s are
the encoding of a sum type.

Transformation options, best first:

1. **Split into three selectors** — the honest fix:

   ```harding
   rewriteManagedClassFileWithClassDefinition: classDefText
   rewriteManagedMethod: methodText selector: aSelector
   removeManagedMethod: aSelector
   ```
   Each has no optional parameters, no nil guards, and the private uniform worker
   takes concrete values. Cost: 3 call sites change; the body is already
   branch-shaped so splitting is mechanical.

2. **Explicit sentinel values per position** — if a single selector must remain:

   ```harding
   overridingSelector: #none methodText: #none removeSelector: #none
   ```
   Works, but replaces one unnameable absence with a nameable one, which is
   strictly weaker than the proposal's goal.

3. **Table of options** — `rewriteManagedClassFile: def options: #{#override -> sel, #method -> text}`.
   Flexible, but moves checking to runtime key lookups and loses the arity check.

**Recommendation: option 1.** The optional-argument pattern is almost always a
sum type in disguise, and splitting is both nil-free and more readable. This is
the single largest transformation in the codebase (95 occurrences) and nearly all
of it should collapse into selector splits or default-providing wrappers.

### The short-form delegation family (the classic Smalltalk idiom)

The other half of the optional-argument story, and the one with the cleanest fix.
A full-arity method is wrapped by shorter selectors that forward `nil` for the
arguments the caller does not care about:

```harding
Terminal class>>open                    [ ^self openFor: nil in: System cwd command: nil ]
Terminal class>>openFor: anOwner        [ ^self openFor: anOwner in: System cwd command: nil ]
Terminal class>>openIn: aPath           [ ^self openFor: nil in: aPath command: nil ]
Terminal class>>openCommand: aCmd       [ ^self openFor: nil in: System cwd command: aCmd ]
Terminal class>>openCommand: aCmd in: p [ ^self openFor: nil in: aPath command: aCmd ]
```

Five short forms feeding one 3-parameter method. **15 such delegations exist in
`lib/`**, concentrated in the Bona window classes (`Terminal` 12 nils, `Workspace`,
`Browser`, `Transcript`, `Inspector`, `RenderCache`).

Crucially, in the `Terminal` case the receiving slots treat `nil` correctly
already: `launchCommand` is only ever tested with
`(launchCommand notNil and: [ launchCommand isEmpty not ])`, and `nil` there means
"none given". So this is **not** a semantic problem — it is a naming problem.

**The clean fix is default arguments.** Harding has no default-argument support
today (verified: no `default` handling in the parser, no mention in the manual),
and this pattern is exactly the feature it is emulating. One declaration:

```harding
Terminal class>>openFor: anOwner in: aPath command: launchCommand
    [ ... ] with: { anOwner -> nil, aPath -> System cwd, launchCommand -> nil }
```

or the shorter conventional form, would replace all five delegations with zero
`nil` at the call sites. This is strictly better than selector splitting here,
because unlike the `Browser` case the arguments are genuinely independent options
rather than mutually-exclusive operations — a sum type would be wrong.

**Recommendation:** for the *independent-options* shape, add default arguments
(or an explicit `?`-style optional marker) rather than deleting the short forms.
For the *mutually-exclusive-operations* shape (`Browser>>rewrite...`), split the
selector. The distinguishing test is whether the nil-checks are independent
(`notNil and:`) or form a dispatch chain (`ifTrue: [...] ifFalse: [...]` around
which parameter was supplied).

This raises a design question the proposal must answer: **is `nil` in a default
argument declaration nameable?** If defaults may be `nil`, then `nil` is nameable
in declarations even though not in expressions. If they may not, defaults need
another absence marker, and the `Terminal` case becomes awkward. My recommendation
is to allow `nil` in *declarations only* — it is not a runtime value there, it is
a statement about the parameter's optionality, which is exactly the well-defined
nil case the proposal is trying to concentrate.

### What Spry tried

Spry (the proposer's own language, sprylang.se) experimented with a `?` sigil for
exactly this optionality question. Worth revisiting: a marker on the *parameter*
(`command?: nil`) makes optionality a property of the declaration, readable at
both the definition and the call site, and it avoids the "which nil meant what"
problem entirely. It also composes with the sum-type distinction above: `?` for
independent options, selector splitting for exclusive operations.

### Second-largest: absent returns (77 occurrences)

`^ nil` means "no result". The transformations, in order of preference:

1. **Caller uses an absent-protocol** where one exists — `at:ifAbsent:`,
   `detect: ... ifNone:`, `removeKey:ifAbsent:`.
2. **Add the missing `ifNone:` sibling** for library methods that return nil on
   absence (14 `detect:` lines vs 8 `detect:...ifNone:` lines today).
3. **Split the query into a predicate plus a total accessor**:
   `includesKey:` + `at:`, rather than one nil-returning `at:`.
4. **Raise** where absence is a programming error rather than a normal outcome —
   which is what the proposal already wants for Array bounds and Table `::`.

Note `lib/core/Object.hrd:278,284` return nil from `sender` when there is no
activation. That is a genuinely-absent *optional*, and should become an
absent-protocol (`sender ifNil:`) rather than a named nil — a good example of the
small number of places where the answer is "wrap it", not "remove it".

### Third: local assignment (24 occurrences, concentrated in `benchmark/`)

13 of the 24 are in benchmark workload code (`richards.hrd`,
`richards_checks.hrd`). These are linked-structure and "not yet computed"
locals. Under the proposal a local cannot be re-nilled, so these need either:

- a sentinel/optional value type for the temp, or
- restructuring so the local is initialized on every path (which the definite
  assignment rule would then enforce).

This is the smallest group but the least mechanical, because it is the one place
where the proposal removes a capability rather than reshaping a protocol.

### Fourth: block results already inside absent-protocols (25 occurrences)

`entries at: fullKey ifAbsent: [ nil ]` is the dominant shape. Under the proposal
this stays **legal as written** — the nil is produced and consumed within one
expression, never named. But it is redundant: `at: fullKey` already yields absent,
so `ifAbsent: [ nil ]` can be dropped and the result handled by the surrounding
`isNil`/`ifNil:`. Mechanically removable, zero semantic change.

One exception: `RenderCache` uses `ifAbsent: [ nil ]` as a *store* result, which
needs the `isNil` check to remain. That is fine — it is a legitimate internal nil.

### Fifth: the vestigial-parameter discovery

`Html class>>appendFragment: to: with: context` (`lib/web/Html.hrd:649`) is called
five times, always with `with: nil`, and **the `context` parameter is never
read** — the body only passes it to its own recursive call. It is dead weight.

This is worth calling out because it is a category the audit otherwise misses:
some `nil` arguments exist because a parameter was added and later abandoned. The
fix is deletion, not transformation. A `nil` that is never inspected is evidence
the parameter should not exist.

### What the audit implies for sequencing

The proposal as written would require touching **194 of 275 occurrences** (all but
the 57 slot assignments, 24 block results, and some misc). That is a large, mostly
mechanical migration, and it argues for a specific order:

1. Fix `Root` so ProtoObject works (prerequisite for sentinels and for a clean
   `undefinedObjectClass` reparenting).
2. Land the absent-protocol and `ifAbsent:`/`ifNone:` gaps, and make Array bounds
   raise — this converts absent returns without any grammar change.
3. Split optional-argument methods (the 95 kwarg occurrences).
4. Only then introduce the grammar restriction, with a lint pass that lists
   remaining violations per file.

Doing the grammar first would produce a codebase that does not load, which is why
steps 2 and 3 must precede it.

## Migration cost

| Today | Replacement | Cost |
|---|---|---|
| `x := nil` (clear a reference) | concern-specific protocol (`detach:`, `unlink:`, `release`) or null object | **Highest.** 62 `:= nil` lines in 16 `lib/` files |
| `^ nil` (absent result) | caller-side absent-protocol | 46 `^ nil` lines across 22 `lib/` files |
| `t at: k` in value position | `at:ifAbsent:` | Bounded to Table/Library misses |
| `t::k` missing key | raises (option 1 above) | Mechanical |
| `x == nil` / `x = nil` | `isNil` | **Trivial**: exactly one genuine `= nil` in `lib/` (`Object>>isNil`, `lib/core/Object.hrd:302`); all 62 other matches are `:= nil` |
| statement-position `ifTrue:`/`whileTrue:`/`do:` | **no change** | zero |
| Array indexing | **no change** (raises on miss instead of nil) | zero |

The `:= nil` case is the only one that demands design work rather than
mechanical rewriting, and it is concentrated: mostly initializers and
re-entrancy clears in GUI code (`BrowserPane` has six in one initializer and two
on selection change) plus benchmark linked structures (`Packet#link`,
`TaskControlBlock#queue`, `Tower#heldDisk`).

Those two populations are different:

- **GUI clears** are "detach" operations wearing nil as a costume. Real protocols
  make the code say what it means; the work is bounded and mechanical.
- **Linked-structure sentinels** are genuinely-absent links. Null objects here
  would convert loud failures into silent ones: a sentinel `Packet` answers
  messages, so it propagates through traversal and yields a wrong answer instead
  of raising. These slots should keep internal nil — with `ref T` it is free, and
  `isNil` on the link is the correct idiom.

## What this does not fix

Removing nameable nil does not remove the general problem. These still fail late
and silently with a non-nil wrong value:

- a method that accidentally returns `self`;
- a wrong-typed object (`Socket` where `File` was expected);
- a method that falls off the end without returning;
- value-position `ifTrue:` with no `ifFalse:`.

Nil is the *loudest and most predictable* member of that family, which is why it
is worth tightening first. The general fix is typed slots as `ref T` and,
eventually, typed parameters. This proposal is a targeted reduction, not the
whole answer — and it is a prerequisite for the typed-slot work, because it
shrinks what that work has to reason about.

## Fixed: Root derive:

`Root derive: #()` exhausted memory. Root is deliberately the zero-protocol root
("Root has zero methods - used as base for DNU wrappers/proxies",
`initRootClass`), and it therefore inherited **no class-side methods** — the core
class protocol (`derive:`, `new`, `derivePublic:`) is registered on Object's class
side, not Root's.

Dispatch then fell through to the class-receiver fallback that tries the
*instance* side of `Class`/`Object` for selectors missing from a class object's own
table. That fallback calls the method as `proc(self: Instance, args)`, but
`classDeriveImpl` is `proc(self: Class, args)`. The receiver is an `Instance`
wrapper whose `nimValue` is `cast[pointer](cls)`, so the pointer is reinterpreted
as a `Class` — `nimValue` is read as `classMethods`, a `Table` — and the resulting
memory walk runs until the process dies.

Fix: after registering Object's class-side methods, Root inherits them
(`initCoreClasses` in `src/harding/interpreter/objects.nim`, immediately after
`registerPrimitivesOnObjectClass`). Root keeps its zero *instance* protocol, which
is the property that matters for DNU wrappers, while gaining the class-side
protocol needed to be a usable base.

Verified: `Root derive: #()` and `Root derivePublic: #(v)` work, a Root subclass
answers `Root`/`Object` protocol as expected, and `Root foo` still raises
`MessageNotUnderstood` loudly. This unblocks the ProtoObject and sentinel-class
directions noted below.

The underlying unsoundness is **not** fixed: the class-receiver fallback still
casts an `Instance` receiver to a `Class` parameter for any selector that a class
object lacks. Root was the one class that could reach it. Making that fallback
type-correct (or refusing it) is worth a separate look.

## Fixed: the two access-lookup defects

`Array at:` and `Table at:` now signal instead of answering nil, and a new
`lib/core/NotFound.hrd` (`Error` subclass) covers keyed misses. Search-style
lookups are unchanged: `indexOf:`, `detect:`, `findFirst:`, `findLast:` and
`detect:ifNone:` still answer nil, because absence there is a normal result.

Implemented alongside it, because the signalling was not catchable as intended:

**`DivisionByZero` and `SubscriptOutOfBounds` derived from `Exception`, not
`Error.`** Verified before the fix: `[ 1 // 0 ] on: Error do: [...]` did **not**
catch a division by zero, while `on: Exception` and `on: DivisionByZero` did. Both
are now `Error` subclasses, matching `MessageNotUnderstood`, `LoadError` and
`UnhandledError`. The hierarchy is now uniform:

```
Exception := Object derive: #(message, stackTrace, signaler)
├── Error
│   ├── UnhandledError, LoadError, NotFound, SubscriptOutOfBounds,
│   ├── DivisionByZero, MessageNotUnderstood, BlockCannotReturn
└── Notification
```

This matters more than it looks: `X := Error` is the natural way to catch
failures, and it silently missed two of the most common runtime errors.

One caller relied on nil from `at:`: `Browser>>addMixin:` looked up a mixin with
`Harding at:` and tested the result. It now uses `Harding at: aMixinName ifAbsent:
[ nil ]`. Note `Library at:` is a separate primitive and still answers nil on a
miss — unchanged here, and the remaining inconsistency if `at:` strictness is
wanted everywhere.

### Verification and a false alarm

All focused suites pass (interpreter core 57, exception handling 46, stdlib basics
42, stdlib collections 31, primitives 15, class model 23, slots 19, dynamic
features 37, load/eval 11, nil conditionals 7) and Granite parity is **105/105**.

The first parity run reported `benchmark_queens: timeout after 30s`. This was not
a regression: `nimble harding` builds a **debug** binary and the harness runs it,
while queens takes ~26s in debug even at the pre-change commit. In release the
same case takes ~1.5s before and after the change (1.545s vs 1.577s). The parity
harness is borderline on that case in debug and would be more robust run against a
release binary.

## Fixed: catchable arithmetic overflow and an ArithmeticError root

Integer overflow signalled nothing catchable. `9223372036854775807 + 1` surfaced as
`Error: VM error: over- or underflow` — a VM error string with no exception class,
so `on: Error do:` could not intercept it and the process died.

Added:

- `ArithmeticError := Error derive` (`lib/core/ArithmeticError.hrd`), mirroring
  Nim's `ArithmeticDefect`.
- `Overflow := ArithmeticError derive` (`lib/core/Overflow.hrd`).
- `DivisionByZero` reparented onto `ArithmeticError`, so one selector catches any
  arithmetic failure.

Interpreter: `handleContinuation` now converts Nim's `OverflowDefect` to the
Harding `Overflow` signal, alongside the existing `DivByZeroDefect` conversion.

Compiled path: three gaps had to be closed, and each was found only by testing the
compiled output rather than the interpreter.

1. `nt_plus`/`nt_minus`/`nt_star` performed raw integer arithmetic, so an overflow
   escaped as an unhandled Nim `OverflowDefect` and aborted the binary. They now
   use bounds-checked helpers that signal `Overflow`. The multiplication check must
   precede the multiply, since an overflowing product would raise inside the check
   itself.
2. `ensureCompiledExceptionHierarchy` and `compiledExceptionClassValue` registered
   `Overflow` against **both** `Error` and `ArithmeticError`. Since
   `matchesCompiledError` walks the primary-parent chain only,
   `on: ArithmeticError` was bypassed. Registration now gives arithmetic classes a
   single parent.
3. Codegen resolved only a hardcoded list of exception names
   (`Exception, Error, Notification, DivisionByZero, MessageNotUnderstood,
   SubscriptOutOfBounds`) to class values; everything else fell through to a
   **symbol**, which `matchesCompiledError` rejects. The list is now
   `ctx.exceptionClassNames`, seeded with the builtin names and extended with every
   class in the parse tree that descends from `Exception`, so a new exception class
   works without editing codegen.

Verified at all three handler levels (`Overflow`, `ArithmeticError`, `Error`) in
both engines, with byte-identical output between interpreter and compiled binary
for the same script, and normal arithmetic unchanged.

**Method note worth keeping:** the compiled-path defects were invisible to the
interpreter and to unit tests. Each was found only by compiling a real script and
running the binary. A unit-test-only check would have declared this fixed.

## Naming decision: NotFound rather than KeyError

`NotFound` was chosen over Nim/Python's `KeyError` because it reads better in
Harding source and covers Library and binding lookups as well as Table keys, where
"key error" would be narrower than the condition. Structure is what aligns with
Nim (an `Error` subclass for access-style misses); the spelling stays Harding's.

## Still-open questions

These are independent of the nil decision and remain worth answering:

1. **Table `at:` in value position**: with `at:` signalling on a missing key,
   every value-position `Table at:` needs either a proven key or
   `at:ifAbsent:`. Decide whether that is the intent or whether `Table at:` keeps
   answering nil while only `::` becomes strict.
2. **Definite assignment for temporaries**: warning-only, or a hard error in a
   strictness mode? `analyzeNumericBindings` already rejects reads before definite
   initialisation for numeric locals, so the analysis exists.
3. **Default arguments**: add them? They would replace the 15 short-form
   delegations measured in `lib/` (see the `Terminal` ladder), and are a better fit
   than selector splitting where the options are genuinely independent.
4. **`?`-style optional parameter marker** (the Spry experiment): adopt, or rely on
   default arguments?
5. **`Root`/ProtoObject**: `Root derive:` exhausts memory. `Root` needs the
   class-side `derive:`/`new` protocol. Should it also be renamed `ProtoObject` to
   match modern Smalltalk?
6. **Sentinel classes as an opt-in idiom**: a `Sentinel`/`NoPacket` class works as
   an absent value (verified: identity comparison works, domain sends raise
   loudly). Worth documenting as an alternative to nil in untyped code? Note the
   hazard: `Symbol := String derive` means a `#nopacket` sentinel answers the whole
   String protocol (`#nopacket size` → `8`), so symbol sentinels are unsafe.
7. **Two representations of nil** (`vkNil` and `nilInstance`): unify? The split
   already caused a measurement to silently report zero nil writes.
8. **Arity debris**: `Workspace>>openWindowFor:id:` is called with an explicit
   `id: 1` while the parameter is unused, and
   `Html class>>appendFragment:to:with:` takes a `context` parameter that is never
   read. Unrelated to nil, but found by the same audit.

## Suggested order of work

Only the decision items, ordered by value per unit of risk. None of this is a
language change.

1. **Fix `Root`** so `Root derive:` works instead of exhausting memory. Prerequisite
   for ProtoObject and for sentinel classes.
2. **Add `NotFound`** (an `Error` subclass) and make `Table`/`Library` `at:` signal
   it on a missing key; make `Array at:` signal `SubscriptOutOfBounds` out of
   bounds. Verified safe: **zero** call sites in `lib/` rely on `(x at: k) isNil`.
3. **Make `isNil` a primitive** over a declared, single selector whitelist for nil,
   with a boot-time assertion that nothing else answers on nil.
4. **Unify nil's two internal representations** on `vkNil`, with `UndefinedObject`
   resolved virtually.
5. **Close protocol gaps**: audit remaining `^ nil` "not found" returns in the
   library; prefer `at:ifAbsent:` / `detect:ifNone:`; consider dropping
   `ifAbsent: [ nil ]` where it is redundant.
6. **Definite assignment** for temporaries as a warning.
7. **Typed slots (`ref T`)** and default arguments, as separate work.

Items 1–3 are small and each removes a real defect. Items 4–7 are larger and can
be deferred without blocking anything.

## Revisit checklist

Before trusting this note:

- `git log --oneline -1` — the review reflects `5ff020b`.
- Re-run the audit: `python3 build/lang/nil_audit.py`.
- Confirm the decision items are still open or done:
  `grep -n '^Root derive\|NotFound' docs/REMOVING_NAMEABLE_NIL.md` and check
  `lib/core/` for a `NotFound.hrd`.
- Re-verify that access lookups still answer nil rather than signalling
  (`Array at:` out of bounds, `Table at:` on a missing key) before relying on the
  defect list.
