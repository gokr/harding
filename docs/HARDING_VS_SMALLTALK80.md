# Harding compared to classic Smalltalk-80

Companion document: [`FIXES.md`](FIXES.md) records the defects found here with
concrete, Harding-consistent fixes. This document is the comparison summary;
that one is the work list.

## Implementation follow-up

The D1–D13 defects and parenthesized cascades have implementation updates; see
[FIXES.md](FIXES.md#current-implementation-status) for the current status, safe
Browser-deletion refusal, and validation scope. The observations below preserve
the original review baseline, not a claim that every defect remains present.

## Scope and status

A review of Harding "the language" plus the current standard library against the
classic Smalltalk-80 language and image as described in the blue book. The
baseline is broad rather than version-pinned.

Every behavioural claim below was executed against this tree (`b41eb7b` plus
uncommitted Granite work) with a locally built `./harding`; engine claims were
checked against `./granite`. Probes were one-off scripts, not a test suite.
The defects that were confirmed are now covered by
`tests/test_smalltalk_alignment.nim`, so this document can be re-checked by
running that file instead of re-probing by hand.

[`LANGUAGE_COMPARISON.md`](LANGUAGE_COMPARISON.md) covers Python, Ruby and Go;
this document only covers Smalltalk-80.

## What is already faithful

Verified by execution, in both engines unless noted:

- message sends in unary, binary and keyword form, plus `;` cascades including
  mixed keyword segments;
- blocks with lexical scope and block temporaries (`[:x | | y | y := x + 1. y]`);
- `^` as a non-local return from a block inside a method, and `self` captured by
  blocks;
- `on:do:` supplying a handler *result*, `ensure:` running exactly once;
- `nil` as a real object answering `ifNil:`/`ifNotNil:`;
- primitives declared in `.hrd` with the implementation in Nim;
- runtime class redefinition, runtime method addition and removal;
- `doesNotUnderstand:` as a recovery hook; `perform:` for zero to three
  arguments;
- mixins through `Mixin derive` plus `addSuperclass:`, with conflict detection;
- `Interval`, `SortedCollection`, `Bag`, `Table`, `Set`, `Array`;
- green processes (`Processor fork:`/`yield`/`current`), `Semaphore`, `Lock`,
  `Monitor`, `SharedQueue`;
- `Library load:` for namespaced bindings;
- **the message precedence table**: unary, then binary (strictly left-to-right,
  no arithmetic precedence), then keyword, then cascade. This is Smalltalk-80's
  table, so `2 * 3 max: 4` answers `6` (parsed `(2 * 3) max: 4`) and
  `2 + 3 * 4` answers `20` in both languages. Documented under "Grammar
  Reference" in `MANUAL.md`.

## Deliberately different: `super<P>`

Multiple inheritance makes a bare `super` ambiguous, so Harding adds a qualifier
that Smalltalk-80 cannot need:

```harding
P1 := Object derive: #().
P1>>who [ ^ "p1" ].
P2 := Object derive: #().
P2>>who [ ^ "p2" ].
C := P1 derive: #().
C addSuperclass: P2.
C>>who [ ^ super who & "/" & super<P2> who ]      # "p1/p2"
```

Semantics:

- plain `super` searches from the first direct parent of the method's declaring
  class, matching Smalltalk's single-inheritance meaning;
- `super<Parent>` names one **direct** parent; a non-parent, an indirect
  ancestor, or an unknown name is an error rather than a silent fallback;
- both are lexical: the search starts at the declaring class's parent, not the
  runtime receiver's, so a method inherited by a descendant still sees the same
  parent;
- both work on the class side (`C class>>tag [ ^ super<P2> tag ]`) and inside
  blocks (`[super<P2> tag] value`).

This has no Smalltalk-80 counterpart, so code using it does not port. Bare
`super` does.

**Existing coverage** (verified, no new work needed):

| Layer | Location |
|---|---|
| interpreter, unqualified `super` and multi-level chaining | `tests/test_interpreter_core.nim` (`super calls parent method`, `super chains through multiple levels`) |
| interpreter, parser shape of both forms | `tests/test_interpreter_core.nim` (`unqualified super looks up in first parent`, `qualified super looks up in specific parent`) |
| native runtime, qualifier selection, receiver/argument, inherited qualifier, rejection of non-parents | `tests/test_compiled_runtime.nim`, suite `Compiled qualified super sends` |
| Granite end-to-end, both engines: instance and class side, through blocks, receiver identity, descendants | `scripts/test_granite_parity.py`, case `qualified_super` |
| bound-super lexical parents and error recovery | `tests/test_engine_boundary.nim` |
| class-side `super` for ordinary dispatch | `scripts/test_granite_parity.py`, cases `class_super`, `inherited_super`, `block_super`, `super_new` |
| regression guard in this review | `tests/test_smalltalk_alignment.nim`, `guard: super works in class methods`, `guard: qualified super selects a named parent` |

The one gap is behavioral: a `super` send to a selector the parent does not
implement raises a Nim `ValueError` that `on:do:` cannot catch. That is D13 in
`FIXES.md`, not a coverage gap in the qualifier itself.

## Where the class model differs

Classes are objects, but there is no metaclass tower. The practical loss is
narrower than it first appears, because class-side methods *do* inherit:

```harding
B class>>greet [ ^ "B" ]
D := B derive: #()
(D greet)                       # -> B
```

What is genuinely absent:

| Smalltalk-80 | Harding | Evidence |
|---|---|---|
| every class is an instance of a metaclass | classes are values; `(Object class) class` is `<instance of Object>` | probed |
| `Class` is a member of the hierarchy | `Object new isKindOf: Class` → `false`; `K class isKindOf: Class` → `false` | probed |
| `subclass:`, `subclasses`, `superclass`, `inheritsFrom:`, `allSuperclasses` | only `superclassNames` (direct parents), plus `derive:`/`addSuperclass:` for building | `Object subclasses` → Message not understood |
| class variables, class instance variables, pool dictionaries | absent by design; class-side state lives in globals, `Library` bindings, or a class-side holder object | `MANUAL.md` "Missing Features" |
| method categories, class comments, change sets | absent; source is canonical and lives in git | `Object class comment` → Message not understood |

## Where the kernel and reflection protocol differs

Verified missing (each answered `Message not understood`):

| Smalltalk-80 | Harding equivalent |
|---|---|
| `copy`, `shallowCopy`, `deepCopy`, `postCopy` | only `clone` (shallow, instance-backed) |
| `hash`, `identityHash` | none |
| `printOn:`, `displayOn:`, `storeOn:`, `storeString` | `printString`, `displayString` only |
| `isMemberOf:` | `isKindOf:` only |
| `allInstances` | none |
| `become:` | none |
| `subclassResponsibility`, `shouldNotImplement`, `halt`, `assert:` | none |
| `dependsOn:`, `changed:`, `update:` (model–view) | none |
| `Block>>numArgs`, `ifCurtailed:` | `parameterCount` only; no `ifCurtailed:` |
| `ExceptionSet`, `on:do:on:do:` | single-handler `on:do:` |
| `thisContext` giving a reified frame | `thisContext` answers an `Activation` with `receiver`, `sender`, `selector`, `line`, `column`, `isClassMethod`, `cacheKey` — debug metadata; no `method`, `tempAt:`, `pc`, `resume`, `return:` |

### Naming: methods, not selectors

Harding says **methods**. The public protocol is `methods`, `definedMethods`,
`allInstanceMethods`, `allClassMethods`, `removeMethod:`, `removeClassMethod:`,
`conflictSelectors`. A method is *named* by a Symbol: `(Object methods at: 0)`
answers `#ifNotNil:`, and `perform:` accepts a Symbol or a String. There is no
"selector" object type distinct from Symbol; the word survives only inside
`conflictSelectors`, `selector` on `Activation`, and `selector:put:`, which are
the low-level installation/debugging paths.

## Collections

The hierarchy is flat: no `Collection`, `SequenceableCollection`, `Magnitude`,
`Association`, `Dictionary`, `OrderedCollection`, `LinkedList`,
`IdentityDictionary`, `Character`, and no streams. Present: `Object`, `Iterable`
(mixin), `Array`, `Table`, `Set`, `Bag`, `SortedCollection`, `Interval`,
`String`, `Symbol`.

- `Array` is both the fixed-size vector and the growable ordered collection
  (`add:`, `remove:`), standing in for `OrderedCollection`; indexing is 0-based.
- `Table` is the dictionary. It compares by value; `Set`, `Bag` and `Interval`
  do too, while `Array` does not (`#(1,2) = #(1,2)` → `false`), because
  `Object>>=` is identity and `Array` does not override it.
- `,` is reserved for literal separators, so concatenation is `&` — and `&` is
  string concatenation for *every* receiver: `#(1,2,3) & #(4)` answers the
  String `"#(1 2 3)#(4)"`, `(true & false)` answers `"truefalse"`, `1 & 2`
  answers `"12"`. See `FIXES.md` F2.
- There is no `Array with:` or `Set with:`; `Array new: n` and `Array new` both
  work, `String new: n` does not.
- `Iterable` is adopted by `Array`, `Table` and `Set` only. `Bag`,
  `SortedCollection` and `Interval` each re-implement 9–13 of its methods
  instead of adopting it, and `Interval.hrd` defines `anySatisfy:`,
  `allSatisfy:` and `sum` twice in the same file.

## Strings and characters

- No `Character` class; `$a` is a parse error; `"abc" at: 1` answers the
  one-character String `"b"`, which is `isKindOf: String` and not `= 98`.
- Strings are not collections: `do:`, `collect:`, `select:`, `reverse`,
  `asArray`, `first`, `last`, `includes:` are all absent. Adding `do:` and
  `species` plus adopting `Iterable` is enough to supply the rest and was
  verified to work; see `FIXES.md` C5.
- `String withCapacity: n` gives a mutable sink that `<<` appends to and that
  prints as its contents; a literal string ignores `<<` and answers a new
  string (`b := "abc". b << "def". b printString` → `"abc"`). The manual states
  the mutating behaviour unconditionally; see `FIXES.md` F8.
- Single quotes are reserved and produce a parse error.

## Numbers

- No `Fraction`, no exact rationals: `1/2` answers `0.5` (Float), so
  `(1/3) * 3` answers `1.0` and `1/2 + 1/2` answers `0.75`.
- `/` always answers Float (`4/2` → `2.0`); `//` is Nim `div` (`-7 // 2` →
  `-3`, `7 // -2` → `-3`); `\\` is Nim `mod` (`-7 \\ 2` → `-1`). There is no
  `rem:`/`quo:` pair.
- Integers are 64-bit; a literal outside that range is a parse error. Habitual
  overflow signals a catchable `Overflow` (subclass of `ArithmeticError`) in
  both engines; a bare top-level overflow still ends the run after the uncaught
  banner.
- `1 = 1.0` is `false` by design, while `1 + 1.0` is `2.0`.
- Missing scalar protocol: `bitAnd:`, `bitOr:`, `bitShift:`, `raisedTo:`, `**`
  (parse error), `floor`, `ceiling`, `rounded`, `truncated`, `fractionPart`,
  `asInteger` on Float, `asFloat` on Integer, `isInteger`, `printStringRadix:`,
  `Float pi`, `Float infinity`, `atRandom`. Present: `abs`, `negated`, `sqrt`,
  `even`, `odd`, `factorial`, `gcd:`, `lcm:`, `max:`, `min:`, `between:and:`,
  `isZero`, `isPositive`, `isNegative`, `sign`, `squared`, `to:do:`,
  `to:by:do:`, `timesRepeat:`.
- No hexadecimal or radix literals: `0xFF` lexes as `0` followed by the binary
  selector `xFF`, and `16rFF` as `16` followed by `rFF`.

## Exceptions and processes

- No resumption: `resume`, `resume:`, `return:`, `isResumable` do not exist.
  This is a documented contract decision (`EXCEPTION_MODEL.md`).
- Handlers supply values through their ordinary result; `pass` and `retry`
  exist; notifications call handlers synchronously above the live computation.
- Processes are cooperative and externally pumped: `Processor fork:` alone
  produces no output until something drives the scheduler
  (`Scheduler runToCompletion:`), and `Processor yield` at top level is not
  enough. No `Delay`, no priority accessor, no `activeProcess`, no channels.
  `Semaphore`, `Lock`, `Monitor`, `SharedQueue` are the offered primitives.

## Image and environment

No image, no snapshot/resume, no change sets, no source-code reflection from the
language (`selectors`, `sourceCodeAt:`, `methodSourceFor:` are absent; Bona uses
host-side source indexing). The global dictionary is `Harding` (99 entries), not
`Smalltalk`. Namespacing is `Library load:`; there is no module system in the
Python/Go sense. `Transcript` and `Inspector` are Bona classes, not core ones.

## Syntax and semantics that differ

- Array literals require commas: `#(1, 2, 3)`; `#(1 2 3)` is a parse error. A
  bare identifier inside such a literal is a Symbol (`#(a, b)` → `#(#a #b)`).
- Statement separation by newline or period; `| x |` temporaries are legal in
  method bodies and in script files, but not in `-e` one-liners.
- A cascade needs a preceding statement to attach to and cannot appear inside
  parentheses: `(Array new: 2; at: 0 put: 1)` is a parse error, while
  `a := Array new: 2. a at: 0 put: 1.` is fine.
- `json{...}` builds a JSON *string*; `#{...}` builds a Table; `array{...}` and
  `table{...}` are the evaluated forms.
- Rendered literals are not re-readable: `#(1, 2)` prints as `#(1 2)` while
  `#{"a" -> 1, "b" -> 2}` prints with commas; see `FIXES.md` F6.

## Summary: the gaps that matter most

1. No `hash`/`identityHash`, which makes the shipped `Comparable` mixin unusable
   and leaves no hashing protocol (`Comparable` also lost its `>` selector).
2. No copy protocol (`copy`/`shallowCopy`/`deepCopy`/`postCopy`).
3. No `printOn:`/`storeOn:`, so there is no user-defined printing.
4. `&` is answered by a quick primitive ahead of dispatch, so it cannot be
   overridden and silently stringifies collections and booleans.
5. Class-side reflection answers the instance side: on a class receiver,
   `methods`, `definedMethods` and `allInstanceMethods` all return the
   instance-side tables.
6. `Iterable` is under-adopted: three core collections re-implement it, and
   `String` is not iterable at all.
7. No `Character`, no streams, no `Fraction`.

`FIXES.md` classes each of these as either a defect to fix now, a cheap
alignment fix, or a deliberate deferral.
