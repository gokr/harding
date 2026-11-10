# Fixes: confirmed defects and cheap Smalltalk alignment

Companion document: [`HARDING_VS_SMALLTALK80.md`](HARDING_VS_SMALLTALK80.md)
describes the comparison this list came out of.

## Current implementation status

The D1–D13 findings below preserve the original reproductions and proposals.
The working implementation now has these outcomes:

| Item | Outcome |
|---|---|
| D1 | Ordinary `&` dispatch in the interpreter and compiled helper; overrides win. Boolean `&` reaches the shipped conjunction methods, not string conversion. |
| D2 | Restored `>`; `compareTo:` derives from the adopter's `<` and `=`. The mixin no longer defines `<` recursively. |
| D3 | Added `classMethods` and `definedClassMethods` in both engines. Existing instance-side queries remain unchanged: `K class == K`, so the proposed receiver-based distinction was impossible. |
| D4, D8 | Interval conversion appends all values; indexed enumeration starts at zero; duplicate definitions removed. |
| D5 | Out-of-range array writes signal `SubscriptOutOfBounds`, including writes at `size`; growth uses `add:`. |
| D6 | Whitespace/EOL starts an ordinary comment; `##` preserves documentation text in lexer tokens and is ignored during evaluation. Operator symbols consume the whole operator. Separators migrated. CLI shebangs remain valid despite script wrapping. Documentation attachment/hover generation remains future work. |
| D7 | Symbol values resolve to the shared Symbol class cache. |
| D9 | Printable uses `write:` sinks and plain string formatting; no `writeStream`, `identityHash`, `String cr` or core Transcript dependency. It does not introduce a String sink or Streams. |
| D10 | Browser deletion explicitly refuses without mutating bindings, selection or source. Real class deletion remains unimplemented; the unsafe partial removal primitive was discarded. |
| D11 | Shared String search primitive returns nil on a miss; Catalog checks nil before slicing. |
| D12 | Compiled class sends fall back to Class/Object instance protocol, without requiring Class to have a registered superclass edge. |
| D13 | Missing super methods signal catchable MessageNotUnderstood; instance- and class-side error parity is covered. |
| Cascades | Parenthesized expressions now use the same cascade continuation as statements. The receiver is evaluated once; the final message supplies the value (`yourself` returns the receiver). Intermediate cascade results are discarded, so a cascade used as an argument cannot leave extra operands on the VM stack. |

Fixed defects have unconditional assertions, not skip-on-failure tests.
Coverage is in `test_smalltalk_alignment`, `test_comment_syntax`, `test_cascade`,
`test_alignment_runtime`, `test_bona_models` and the `alignment_*` /
`parenthesized_cascade` differential cases in `scripts/test_granite_parity.py`.
Validation logs are under `build/fixes/`; only explicitly listed suites are
evidence of passing tests.

Known pre-existing failure, reproduced on a clean `HEAD` archive and therefore not
caused by this work: `tests/test_compiled_support.nim` fails its
`Boolean helpers` and `indexed iteration` tests because the *tests* call
`nt_not`/`withIndexDo:` on receivers whose methods are not registered in that
harness. Recorded here so a later reader neither attributes it to these fixes nor
assumes it is a runtime regression.

A1–A5/C1–C2 remain separate work. Streams are still deferred, so `Printable` takes
an injected `write:` sink rather than growing a String sink. Image-level class
deletion is likewise not silently added: Browser refusal is the implemented
behaviour, not a stub to be completed later without design.

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

See the coverage map above; the original evidence below is historical, not a
claim that the implementation still has each defect.

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

## D6 — the `#` comment rule collides with symbol literals

**Evidence.** The lexer's `#` branch (`src/harding/parser/lexer.nim`) treats `#`
followed by any of `= - * / . | & @ !` as a **line comment**, on top of `#`
followed by whitespace. Separately, `parseSymbol` accepts only an identifier, a
`#"..."` string, or exactly **one** non-alphanumeric character. Together:

| literal | result |
|---|---|
| `#<`, `#>`, `#+`, `#%`, `#~` | correct |
| `#<=`, `#>=`, `#~=`, `#<<`, `#>>` | parse error (`#<` then `=` dangling) |
| `#=`, `#-`, `#*`, `#/`, `#&`, `#\|`, `#@` | parse error — lexed as a comment, so the line has no expression |
| `#"<="`, `#"=="`, `#"-"` | correct (string-symbol escape hatch) |

**Why it matters.** `perform: #<` works but `perform: #<=` cannot be written, so
reflection over comparison methods needs the escape hatch. The comment collision
is the worse half: `#-` silently swallows the rest of the line, so an array or
table containing it loses everything after it instead of reporting a bad symbol.

**Fix: one rule instead of two.** `#` starts a comment **only when followed by
whitespace or another `#`**; in every other case it starts a symbol or a
literal. That is one condition, matching what `QUICKREF.md` already claims
("Hash `#` + whitespace = comment"). Concretely, in the lexer's `#` branch:

1. line 1 + `!` → shebang, unchanged;
2. `#(` / `#{` → array / table literal, unchanged;
3. `##` → documentation comment token (see below);
4. `#` followed by whitespace or end of line → line comment;
5. otherwise → `parseSymbol`, which also keeps consuming an operator run
   (`~ < > = | & + - * / \ @ %`) after the first character, so `#<=` lexes as
   one symbol.

The special-character list disappears, so `#====` is no longer a comment.

**Reserve `##` for documentation comments.** `##` is currently unclaimed: no
tracked `.hrd` uses it, and `##trailing doc` today lexes as `#`+symbol then a
stray identifier (*Message not understood: trailing*).

In Nim `##` is not a general comment, it is a **documentation comment**: a token
that belongs to the syntax tree, legal `only at certain places` and collected by
`nim doc`/`jsondoc`. Verified against the bundled manual
(`toolchains/nim-2.2.12/doc/manual.md`, "Comments"), and by experiment: a `##`
block **preceding** a declaration is collected, while `##` trailing a statement
is legal but **not** collected.

Adopting the same meaning gives each form one job:

```harding
## Half-open interval; `to:` is exclusive. Documented for the Browser and LSP.
Interval>>size [
  ^ stop - start
]

Seconds perDay [
  ^ 24 * 60 * 60   # ordinary comment, never collected
]
```

- `#` + whitespace — ordinary comment, prose, ignored by tooling.
- `##` — documentation for the following method (or class), the form a future
  Browser hover or LSP `hover` should surface.

Keeping the distinction means ordinary comments stay free-form and the
collectable form stays deliberate, exactly as in Nim. Whether trailing `##`
is *collected* should follow Nim too: no. It stays a legal comment, so a reader
is never punished for it, but documentation belongs above the definition.

**Migration is mechanical.** The only source form that breaks is the separator
line. `#====` becomes `# =====`, which already satisfies rule 4, so no special
case is needed anywhere.

Tracked occurrences needing the change: 112 lines across 15 files — 12 under
`lib/core` (96 × `#====….`, and the `#---` kind), 1 `lib/standard`, 1
`examples/integrations`, 1 `docs/research/proposal-examples`. The majority are
the 68-character `#====…====.` rule; some end in a period, so insert a space
rather than rewriting the line:

```bash
# git ls-files '*.hrd' | xargs sed -i -E 's/^#([=-])/# \1/'
```

That turns `#====.` into `# ====.`, marker intact. Shebang lines (`#!/`) are
unaffected, and so are the 80 tracked `.hrd` files that carry one.

If a `#!` shebang is ever wanted on a line other than line 1, rule 1 covers only
line 1, so `#!/x` later in a file would still parse as a symbol — that is
already true today and is not a regression.

Because `##`-before-a-definition is a new capability rather than a fix, it can
land as a separate commit: the comment-rule simplification above does not depend
on it, and the lexer only needs to recognise `##` as its own token when doc
collection exists.

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

`tests/test_smalltalk_alignment.nim` now fails on a regression rather than
turning it into SKIPPED. Parser/comment regressions live in
`tests/test_comment_syntax.nim`, parenthesized cascades in `test_cascade`, and
Browser deletion refusal in `test_bona_models`. The method-headline scan finds
no duplicate definitions in its listed standard-library files.

Interpreter/Granite parity cases cover class protocol, class-side reflection,
custom/Boolean `&`, String ordering/search, bounds errors, interval conversion,
Printable sinks, missing super methods, comments/symbols and nested cascades.

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
