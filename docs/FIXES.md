# Fixes: confirmed defects and cheap Smalltalk alignment

Companion document: [`HARDING_VS_SMALLTALK80.md`](HARDING_VS_SMALLTALK80.md)
describes the comparison this list came out of.

## How this list is organized

- **Defects (D\*)** — behaviour that is wrong on its own terms: it contradicts
  another selector, another engine, or the manual. These should be fixed
  regardless of Smalltalk.
- **Alignment (A\*)** — small additions or renames that bring Harding closer to
  Smalltalk-80 *without* giving up an existing Harding decision. Each is
  independent and reviewable on its own.
- **Deferred (X\*)** — deliberately not now, with the reason recorded so the
  decision is not re-litigated.

Guiding constraints applied throughout:

- Source stays canonical; the interpreter stays the reference semantics and
  Granite must match it.
- `lib/` stays the source of truth: new protocol goes in `.hrd`, and a Nim
  primitive is added only when the operation cannot be expressed in Harding.
- No metaclass tower, no class variables, no pool dictionaries, no resumable
  exceptions, no image. Nothing below proposes any of those.
- 0-based indexing stays. `Conflicts` are resolved in favour of existing
  Harding decisions, not classic Smalltalk.
- Naming: Harding says **methods**, named by Symbols. New protocol uses the
  existing vocabulary rather than reintroducing "selector" as a concept.

Every defect below has a regression test in
`tests/test_smalltalk_alignment.nim` unless it is marked
**(no test yet)** with the reason.

## D1 — `&` is answered ahead of dispatch, so it cannot be overridden

**Evidence.** `K>>& other [ ^ 11 ]` then `K new & 1`:

| engine | result |
|---|---|
| interpreter | `<instance of K>1` |
| Granite | `11` |

The interpreter answers `&` from a quick-primitive case
(`src/harding/interpreter/vm.nim`, the `of "&":` block near the boolean
fast paths) *before* method lookup. `True>>&`, `False>>&` and `String>>&` in
`lib/core/` are therefore unreachable in the interpreter, while Granite honours
them. `1 & 2` answers the String `"12"`, `(true & false)` answers `"truefalse"`,
and `#(1,2,3) & #(4)` answers `"#(1 2 3)#(4)"`.

**Why it matters.** The two engines disagree, and a documented method cannot be
overridden — which breaks the "library is the source of truth" rule for one of
the most used binary selectors in the tree (`&` appears in ~40 `.hrd` files).

**Fix.** Delete the `of "&":` quick primitive and let `String>>&` plus
`Object>>asString`-based concatenation do the work through ordinary dispatch.
If a fast path is needed for the common `vkString & vkString` case, it belongs
*behind* a dispatch check of the same shape `resolvesToObjectDefinition`
already provides for `class`/`isNil`/`==`/`size`, so `String>>&` wins and any
override wins too. Same treatment for the parallel `&` branches in
`src/harding/codegen/expression.nim` (`genHostedBuiltin(..., "nt_comma", ...)`)
and `src/harding/runtime/runtime.nim`: `nt_comma` already dispatches to `&` for
`vkInstance`/`vkClass` receivers, so those paths need the same
"only when not overridden" guard rather than an unconditional string conversion.

## D2 — the shipped `Comparable` mixin is broken twice

**Evidence.** `Comparable.hrd` as committed:

```harding
Comparable>>compareTo: anObject [
  ^ self identityHash - anObject identityHash
]
```

1. `identityHash` does not exist anywhere in the tree, so every method that
   routes through `compareTo:` fails:

   ```
   "b" >= "a"      -> Error: Message not understood: identityHash
   "a" <= "b"      -> Error: Message not understood: identityHash
   "a" max: "b"    -> Error: Message not understood: >
   ```

   Note `"b" > "a"` fails differently (`Message not understood: >`) because of
   defect 2 below, while `"a" < "b"` works, since `String>>primitiveLessThan:`
   is defined directly.

2. The `>` definition lost its selector: the file contains

   ```harding
   Comparable>> anObject [
     ^ (self compareTo: anObject) > 0
   ]
   ```

   which installs a **unary** method named `anObject` and leaves `>` undefined.
   `(Comparable definedMethods) printString` →
   `#(#clampTo:max: #>= #<= #max: #anObject #< #between:and: #compareTo: #min:)`.
   `"b" respondsTo: #anObject` → `true`, `"b" respondsTo: #>` → `false`.

**Why it matters.** `String` and `Number` both adopt `Comparable` in
`lib/core/Bootstrap.hrd`, so half of the ordering protocol on the two most used
classes is a trap, and a bogus `anObject` method is exposed on every number and
string.

**Fix.** Restore the selector (`Comparable>> other [`) and give `compareTo:` a
real default that does not depend on an absent method. Two acceptable shapes:

- `Comparable>>compareTo: anObject [ ^ (self = anObject) ifTrue: [ 0 ] ifFalse: [ (self < anObject) ifTrue: [ -1 ] ifFalse: [ 1 ] ] ]`
  with `<` remaining the primitive each adopter supplies; or
- drop the default entirely and let `Comparable` require adopters to implement
  `compareTo:`, signalling `Error` when they have not.

The first keeps `String`/`Number` working with no further change; the second is
more honest but needs `Number>>compareTo:` added. Either way, add
`identityHash` separately (A1) — but do not let `compareTo:` depend on it.

## D3 — class-side reflection answers from the instance side

**Evidence.** With `K := Object derive: #(v)`, `K>>im [ ^ 1 ]`,
`K class>>cm [ ^ 2 ]`:

| expression | result | expected |
|---|---|---|
| `(K definedMethods) printString` | `#(#im)` | `#(#im)` ✔ |
| `(K class definedMethods) printString` | `#(#im)` | `#()` or `#(#cm)` |
| `(K class methods) size` | `88` (instance table, includes `im`) | class-side table |
| `(K methods) size` | `88` | instance table ✔ |
| `(K class respondsTo: #cm)` | `true` | ✔ |

`primitiveMethodsImpl`/`primitiveDefinedMethodsImpl`
(`src/harding/interpreter/vm.nim`) always read `self.class.methods`, which for a
class receiver is the *class object's* instance side. There is no expression
that answers "the class-side methods this class defines"; `allClassMethods`
answers the inherited set, which is not the same question.

**Fix.** Keep one name per table and make the receiver decide which table is
meant, consistent with how `respondsTo:` already behaves:

- `Object class>>methods` / `definedMethods` on a class receiver answer the
  class-side tables; `allClassMethods` stays the inherited superset.
- `Object>>methods` / `definedMethods` on an instance answer the instance-side
  tables (current behaviour).

That is a host-side change in the two primitives plus `.hrd` doc comments. It
keeps the existing vocabulary and adds no new selector.

## D4 — `Interval>>asArray` is off by one, and the engines disagree

**Evidence.**

```harding
(1 to: 3) asArray printString
```

| engine | result |
|---|---|
| interpreter | `#(nil 1 2)` |
| Granite | `#(nil 1 2 3)` |

`Interval>>asArray` (`lib/standard/Interval.hrd`) allocates
`Array new: self size` and then writes through `withIndexDo:`, whose indices are
1-based by its own comment, so slot 0 is never written. Everything shifts by one
and the last element falls off, or — in the compiled runtime — the write at
index `size` silently appends, which is why the two engines differ.

`(9 to: 1 by: -2) asArray` → `#(nil 9 7 5 3)` in the interpreter.

**Fix.** Rewrite `Interval>>asArray` without the index round trip:

```harding
Interval>>asArray [
    | result |
    result := Array new.
    self do: [:each | result add: each ]
    ^ result
]
```

Also fix `Interval>>withIndexDo:` to be 0-based like `Array>>withIndexDo:`
(`lib/core/Array.hrd`), and document the convention once. `withIndexDo:` is
only used by `asArray` and one Bona pane, so the change is contained.

## D5 — out-of-range `at:put:` is silently ignored

**Evidence.**

| expression | interpreter | Granite |
|---|---|---|
| `a := Array new: 3. a at: 9 put: 9. a printString` | `#(nil nil nil)` (write dropped) | raises `SubscriptOutOfBounds` |
| `a := Array new: 3. a at: 3 put: 9` | accepted, dropped | appends, `#(nil nil nil 9)` |
| `a := Array new: 3. a at: 9` | raises `SubscriptOutOfBounds` | raises |

So the read signals, the write silently does nothing, and the two engines
disagree about the boundary case. A dropped write is the worst outcome: the code
appears to work and the value is missing later.

**Fix.** Make `at:put:` signal `SubscriptOutOfBounds` for any index outside
`0 ..< size`, matching `at:`, in the interpreter primitive, in
`nt_at_kput_k` (`src/harding/runtime/compiled_support.nim`) and in the runtime's
`of "at:put:"` branches. Array growth stays the job of `add:`, which is
explicit. This removes the silent-drop and the engine divergence at once.

## D6 — operator symbol literals: truncated, or read as comments

**Evidence.** Two rules interact. The lexer's `#` branch
(`src/harding/parser/lexer.nim`) treats `#` followed by any of
`= - * / . | & @ !` as a **line comment** (that is how the `#====` separators
work), and `parseSymbol` accepts only an identifier, a `#"..."` string, or
exactly **one** non-alphanumeric character. Measured:

| literal | result |
|---|---|
| `#<`, `#>`, `#+`, `#%`, `#~` | correct |
| `#<=` | parse error (`#<` then `=` dangling) |
| `#>=`, `#~=`, `#<<`, `#>>` | parse error |
| `#=`, `#-`, `#*`, `#/`, `#&`, `#\|`, `#@` | parse error — lexed as a comment, so the line has no expression |
| `#//` | parse error (comment) |
| `#"<="`, `#"=="`, `#"-"` | correct ✔ (string-symbol escape hatch) |

**Why it matters.** `perform: #<` works but `perform: #<=` cannot be written;
reflection over comparison methods is impossible without the escape hatch. The
comment collision is the worse half: `#-` silently swallows the rest of the
line, so a table literal or array containing it loses everything after it
instead of reporting a bad symbol.

**Fix.** Two changes in the lexer, in this order:

1. `parseSymbol` keeps consuming an operator run: after the first character,
   take further characters from `~ < > = | & + - * / \ @ %` and stop at
   punctuation the grammar needs (`.`, `)`, `,`, `;`, `[`, `]`, `{`, `}`,
   whitespace, `:`). `#<=` then lexes as one symbol.
2. Only treat `#` as a comment when the run is **two or more** comment
   characters and is not a valid operator, or simply require the comment forms
   actually used in the tree (`#=`, `#!`, and `#` followed by whitespace).
   Keeping `#====` working while making `#-` a symbol needs the operator set to
   win: `-` alone is a valid operator, `--`/`==` runs are not, so length decides.

Either way, keep the `#"..."` form working as the general escape hatch and
add the `#<=`-style literals to `QUICKREF.md` once they exist.

Note `(#(a, b) at: 0) class` answers `nil` in the interpreter but `Symbol` in
Granite — that is D7, not a lexer problem.

## D7 — a Symbol value has no class in the interpreter

**Evidence.**

| expression | interpreter | Granite |
|---|---|---|
| `#foo class` | `nil` | `<class Symbol>` |
| `(#foo class) name` | `Message not understood: name` | `Symbol` |
| `#foo className` | `""` | n/a |
| `#foo isKindOf: Symbol` | `true` | `true` |

`classOfValue` (`src/harding/core/types.nim`) returns `nil` for `vkSymbol`;
Granite's compiled path wraps symbols in a Symbol instance. `respondsTo:`,
`printString`, `asString`, `size` and `=` all work on symbols, so dispatch is
fine — only the class answer is missing.

**Fix.** Return the `Symbol` class from `classOfValue` for `vkSymbol`, as it
already does for the other primitive kinds. One line plus the ordering
constraint that `Symbol` must exist when the function can be called.

## D8 — `Interval` defines three methods twice

**Evidence.** `lib/standard/Interval.hrd` contains two definitions each of
`anySatisfy:`, `allSatisfy:` and `sum` (lines ~157–200). The later definition
wins; the first is dead text that reads as if it were the implementation.

**Fix.** Delete the duplicates. Purely a `.hrd` cleanup, no behaviour change
(worth a test only in the sense that the file should stay deduplicated).

## D9 — the `Printable` mixin depends on three absent methods

**Evidence.** `Printable.hrd` uses `identityHash`, `"" writeStream`, `stream
contents`, `stream show:` and `Transcript show:`. None of `writeStream`,
`show:` or `identityHash` exists in core, so adopting the mixin:

```harding
K := Object derive: #(). K addSuperclass: Printable.
K new printString      # -> <K>
```

falls through to `Object>>printString` — the mixin's `printString` is present
(`K new respondsTo: #printOn:` → `true`) but cannot complete, and `print`/
`printCr` need `Transcript`, which is a Bona class.

**Fix.** Depends on A3 (`printOn:`) and A4 (a sink). Recommended shape: define
`Printable>>printOn: aStream` against whatever sink Harding settles on, and
implement `printString` as `^ self printOn: String new`-style only if the sink
is a String-like receiver; otherwise keep `printString` in `Object` and let
`Printable` supply only `printOn:`. Until then, either fix it or remove
`Printable` from the image so a shipped mixin does not advertise working
protocol it cannot deliver.

## D10 — dead code calls a method that does not exist

**Evidence.** `lib/gui/bona/Browser.hrd` `deleteClass:` does
`result := [ classObj become: Object ] on: Exception do: [...]`, but `become:`
is not implemented. The handler therefore always runs and the class is never
deleted; the `startsWith: "ERROR:"` string sniffing afterwards is the
prefix-classification pattern `AGENTS.md` says not to use.

**Fix.** Either implement class removal properly (a host primitive that removes
the class from its superclasses' `subclasses`, drops the global binding and
invalidates caches) and call it directly, or make `deleteClass:` refuse with a
clear `Error` until that exists. Do not leave a call that always fails inside a
handler.

## D11 — `indexOf:` answers different miss values per class

**Evidence.**

| expression | result |
|---|---|
| `#(10, 20) indexOf: 99` | `nil` |
| `"abc" indexOf: "z"` | `-1` |
| `(Bag new) indexOf: 9` | `nil` |
| `(SortedCollection new) indexOf: 9` | `nil` |

`NotFound.hrd` documents the convention as "search-style lookups keep answering
nil"; `String>>indexOf:` violates it. `-1` is also unsafe with 0-based indices:
`#(10, 20) at: (x indexOf: 99)` silently reads element 0 if a caller forgets the
check, whereas `nil` raises.

**Fix.** Make `String>>indexOf:` answer `nil` on a miss, matching every other
collection and the documented convention. Check the `.hrd` call sites
(`lib/gui/bona/Catalog.hrd` compares it to `">>"`; that usage keeps working since
it tests equality, not presence).

## D12 — Granite does not give class values the class protocol

**Evidence.** On this tree (uncommitted Granite work present):

```harding
x := 1 class.
x printString          # interpreter: <class Integer>   granite: Message not understood
x isKindOf: Object     # interpreter: true              granite: Message not understood
x name                 # both: Integer
```

**Fix.** Compile the class-value protocol through the same path instance sends
use, or route class receivers to the interpreted `Class`/`Object` definitions.
This is a Granite coverage gap rather than a language decision; it needs a
parity case in `scripts/test_granite_parity.py` so the next stdlib-compilation
slice cannot silently drop it again.

## D13 — a `super` send to a missing method kills the script

**Evidence.** A `super` send whose selector the parent does not implement raises
a Nim `ValueError` from the evaluator instead of signalling a Harding error:

```harding
P := Object derive: #().
C := P derive: #().
C>>m [ ^ super nope ].
[ C new m ] on: Error do: [:e | "caught" ]      # script dies
```

The run prints `Script error: Error: Method 'nope' not found in super class P`
and exits; the `on: Error do:` handler never runs. The same statement without a
handler behaves identically, so the difference is only visible when a caller
tries to recover. `src/harding/interpreter/vm.nim` raises
`newException(ValueError, ...)` for both the missing-parent and the
missing-method cases of the `nkSuperSend` branch.

This is the same class of bug as the old dispatch failures: an ordinary
programming error in user code becomes an unrecoverable process exit, which
contradicts "a handler supplies the value". Note that a plain
`Message not understood` *is* catchable, so the inconsistency is visible to any
user who tries.

**Fix.** Signal `MessageNotUnderstood` (or a `NotFound`-derived error, matching
whatever `doesNotUnderstand:` uses for ordinary sends) through the ordinary
signal machinery instead of raising a Nim exception, keeping the parent class
name and the selector in the message text. Add a Granite parity case so the two
engines keep agreeing.

## Regression coverage

`tests/test_smalltalk_alignment.nim` pins every item above and the guards
around them, and is part of `nimble testCore`. It contains three kinds of test:

- **defect tests (D\*)** — assert the intended behaviour and call `skip()` while
the defect is open, so the suite reports them as `SKIPPED` with the contract
already written down. Fixing the defect makes them pass with no edit to the test.
- **guard tests** — must stay green; they cover behaviour that is correct today
and easy to regress, including the three things that were mis-reported during
this review (`super` in class methods, mixin adoption, `Set>>clone`).
- **D8's source scan** — reads the `.hrd` files listed in `stdlibSourceFiles`
and reports any selector defined twice in one file. It currently reports the
three `Interval.hrd` duplicates and nothing else, which is a useful positive
control that the scan is precise rather than noisy.

## A1 — `hash` and `identityHash`

Agreed. Needed by `Comparable` (D2) and by any user-defined key type.

- `Object>>identityHash` — the address-derived integer the VM already has
  (`primitiveIdentity:` exists, so the value is available).
- `Object>>hash` — defaults to `identityHash`; value classes override:
  `String`/`Symbol` by content, `Integer`/`Float` by value (with
  `1 hash = 1.0 hash` to keep `=`/`hash` consistent for the numeric case),
  `Array`/`Table`/`Set`/`Bag` structurally.
- `Set` and `Table` should then use `hash`/`=` rather than identity where they
  currently do, so a user class with a value `hash` works as a key.

Keep it two selectors. Smalltalk's `hash`/`hashMappedBy:` additions are not
needed.

## A2 — the copy protocol

Agreed. `clone` stays as the primitive-ish shallow copy; add the standard
vocabulary on top of it in `lib/core/Object.hrd`:

```harding
Object>>copy [ ^ self clone ]                 # shallow, `postCopy` hook
Object>>shallowCopy [ ^ self copy ]
Object>>deepCopy [ ^ <structural copy> ]
Object>>postCopy [ ^ self ]                   # overridden by subclasses
```

`deepCopy` needs one host helper for the recursive walk over slots, `Array`
elements and `Table` entries; everything else is `.hrd`. `Set`/`Bag`/`Table` in
`lib/core/` already inherit `clone`; verify each answers the right species
after a copy (a test belongs with them, in `test_stdlib_collections.nim`).

## A3 — `printOn:` / `displayOn:` / `storeOn:`

Agreed, with a caveat: this needs a sink, so it interacts with A4 and X1.

- `Object>>printOn: aSink [ aSink write: self printString ]` — `write:` already
  exists on `FileStream`, so `System stdout` works today.
- `Object>>displayOn: aSink [ aSink write: self displayString ]`.
- `storeOn:`/`storeString` can wait for the sink decision; a readable literal
  form is useful but premature while literal rendering is being settled (F6).

Once `printOn:` exists, `Object>>printString` should be expressed in terms of it
only if `String` can be a sink (see X1). Otherwise keep `printString` as the
primitive-backed default and treat `printOn:` as the user extension point, which
is enough to unblock D9.

## A4 — naming: methods, not selectors

Agreed: keep **methods**. The public surface is already consistent
(`methods`, `definedMethods`, `allInstanceMethods`, `allClassMethods`,
`removeMethod:`, `conflictSelectors`), and a method is named by a Symbol, which
is what `perform:` accepts. No `Method` or `Selector` object type should be
introduced.

The remaining inconsistency is only internal: `selector` survives as a field
name on `Activation` and in the installation primitives `selector:put:` /
`classSelector:put:`. Those are the low-level paths the parser emits for `>>`,
so renaming them is churn with no user-visible benefit. Leave the fields; make
sure the `MANUAL.md` reflection section talks about methods throughout, and take
`methods`, `definedMethods` and `allClassMethods` as the vocabulary when adding
A1–A3.

## A5 — `,` in rendered literals

Observed inconsistency, all in rendered output rather than in source syntax:

| rendered | form | re-readable |
|---|---|---|
| `#(1 2)` (Array) | space separated | no — the parser requires `#(1, 2)` |
| `#{"a" -> 1, "b" -> 2}` (Table) | comma separated | yes |
| `#(#a #b)` (Array of Symbols) | space separated | no |
| `#("a" . "b")` from `formatTable`'s sibling path in `core/types.nim` | period separated | no |

Since `,` *is* the literal separator in Harding source, `printString`/`toString`
should emit it: `#(1, 2)`, `#(#a, #b)`, `#{"a" -> 1, "b" -> 2}`. Two
implementations must change together — `Array>>printString` in
`lib/core/Array.hrd` and `formatSeq`/`formatTable` in
`src/harding/core/types.nim` (used by `toString`) — plus the Granite runtime's
equivalent, and the `#(nil 1 2)`-shaped expectations in
`tests/test_lexical_scope.nim` (6 assertions) and `tests/test_compiler_basic.nim`
(slot-list strings) will need updating. Keep `#(` and `#{` as the markers and
keep the space after `,`, so output is stable and greppable.

Note this makes `printString` output parseable again, which is the point: it is
a precondition for a later `storeString`.

## C1 — `Iterable` should be the real collection protocol

`Array`, `Table` and `Set` adopt it; `Bag`, `SortedCollection` and `Interval`
each reimplement 9–13 of its methods. Adopting it was verified to work for all
three on a live image (`Bag addSuperclass: Iterable` etc.): the inherited
`collect:`, `select:`, `includesAll:`, `isEmpty` answer correctly and each
class's own definitions still win. So this is a deletion exercise, not a
redesign:

1. Adopt `Iterable` in `Bag`, `SortedCollection` and `Interval` from
   `Bootstrap.hrd`, next to the three that are already there.
2. Delete from those files only the methods whose `Iterable` version is
   identical, keeping any that legitimately differ (`Bag>>detect:ifNone:` and
   `SortedCollection>>copyEmpty` do differ and stay).
3. Delete the duplicates in `Interval.hrd` (D8).
4. Check `Bag>>species`/`copyEmpty` — `Iterable>>collect:` relies on
   `self species new`, and `Bag` already answers `Bag`, so this should work; a
   test per class belongs in `test_stdlib_collections.nim`.

`String` should adopt it too, which needs only `do:` and `species` (probed: with
those two added, `collect:`, `select:`, `inject:into:`, `detect:` and
`occurrencesOf:` all work and existing `=`/`printString`/`size` are unchanged).
`includes:` must stay string-specific (substring test), so define it on `String`
before adopting `Iterable`.

## C2 — `String` collection protocol without an abstract `Collection`

Agreed: polymorphism does not require inheriting from `Collection`. `String`
gets `do:`, `species` (`^ Array`), `first`, `last`, `asArray`, `reverse` and the
`Iterable` adoption; `at:` already answers a one-character String, which stays
(see X2). No `SequenceableCollection` is introduced.

## C3 — a `stringContents`-style result factory instead of streams

Deferred with X1, but flagged here because `Iterable>>collect:` on `String`
needs `species new` to produce something with `add:` — `Array` is the right
species for now, and that is what the probe used.

## X1 — streams

Deferred by decision. The classic `ReadStream`/`WriteStream`/`PositionableStream`
hierarchy is not wanted; the likely shape is a small sink/source protocol
(`write:`/`readAll`) that `FileStream` already approximates, plus a String sink
for building text. Until that is decided, A3 is limited to `printOn:` against
`FileStream`-like sinks, and `Printable` cannot be made whole (D9).

## X2 — `Character`

Deferred. `"abc" at: 1` answers a one-character String, which is coherent with
"strings are sequences of strings" and keeps the literal syntax free of `$`.
Revisit only if `String` iteration needs to distinguish a character from a
one-character string for some protocol; no current code does.

## X3 — the numeric tower

Deferred. `Fraction` would change the meaning of `/` and of `1/2` across the
tree and in Granite's numeric specialisation, so it is a language decision, not
a fix. The cheap part that can be done independently: add `asInteger` on Float
and `asFloat` on Integer (pure conversions, no semantic change), and decide
separately whether `/` should answer an Integer when it divides exactly.

## X4 — hexadecimal and radix literals

Deferred, but note the documentation is currently wrong (`AGENTS.md` advertises
`0xFF`, nothing else does, and the lexer does not accept it). Either add hex
literals to `parseNumber` or drop the claim from `AGENTS.md`; do not leave the
docs asserting a syntax that parses as `0` followed by a selector.

## Suggested order

1. D2, D4, D6, D7, D8, D11, D13 — small, local, no design decisions. D13 is the
   most user-visible of these: it turns a typo into a dead process.
2. D1, D5 — behaviour changes; do them together because both are "engine
   agreement" fixes, and both need parity cases.
3. D3, D10, D12 and the `AGENTS.md`/`MANUAL.md` corrections (X4).
4. A1, then A2 — `hash` first, because `Comparable` and `Set` both want it.
5. A4, A5 — vocabulary and rendering, before adding `storeString`.
6. C1, C2 — the `Iterable` cleanup, which shrinks `lib/` rather than growing it.
7. A3 and D9 once the sink question (X1) is settled.
