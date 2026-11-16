# Harding compared to Smalltalk-80, Python, Ruby and Go

This document answers one question: *how does Harding differ from languages a
reader is likely to arrive from, and which differences are decisions rather than
defects?*

It replaces three earlier documents, which are preserved with their original
measurements in `research/language/`:

- `LANGUAGE_COMPARISON.md` — the four-language review;
- `HARDING_VS_SMALLTALK80.md` — the Smalltalk-80 comparison;
- `COLLECTION_PROTOCOL_AUDIT.md` — the selector-level collection inventory.

Defects found while writing those reviews are tracked as work items in
[plans/FIXES.md](plans/FIXES.md), not here. This document records the
*comparison*; that one records the *work*.

## Scope and how to re-verify

Baselines are broad rather than version-pinned: "Smalltalk-80" means the classic
language and image as described in the blue book; Python, Ruby and Go are
referenced by general behaviour, not by a specific release.

Behavioural claims were executed against a locally built `./harding` and
`./granite` at revisions `5ff020b` and `b41eb7b`. They are not a suite.
The confirmed Smalltalk-facing defects are pinned as named cases in
`tests/test_smalltalk_alignment.nim`, so re-checking this document means running:

```sh
nim c -r tests/test_smalltalk_alignment.nim
```

Anything that document marks as an open contract reports `SKIPPED` rather than
`FAILED` while the behaviour is still wrong, so a green run is not by itself
proof that the comparison below has changed. Re-probe any row you intend to
rely on.

## What Harding is

A class-based Smalltalk dialect running on a Nim-implemented **stackless VM**:
work-queue driven, not native-call-stack driven. Two execution paths must agree.

| Path | Command | Role |
|---|---|---|
| Interpreter | `./harding` | reference semantics |
| Granite | `./granite` | compiles the same AST to Nim, then a native binary |

This shared-AST, dual-engine design is the main structural difference from every
language in this document, and it is what makes parity tests meaningful
(`scripts/test_granite_parity.py`, `examples/manifest.json`).

The library is layered into `lib/{core,standard,syntax,gui,web,granite,mummyx,reactive,process,mysql}`.
`lib/core/` holds the class kernel that both engines share.

Scripts are compiled as `#doIt` on `UndefinedObject`, matching the Smalltalk
workspace convention: `self` is `nil`, lowercase top-level assignments are locals
of the do-it, `| x |` temporaries are legal, and `^` returns from it. Only
uppercase names are globals (`MANUAL.md`, "Script Files").

## Feature comparison

Legend for the Harding column: **yes** = works in both engines; **partly** = see
the named section; **no** = absent by design or unimplemented, per the section
named.

| Feature | Smalltalk-80 | Python | Ruby | Go | Harding |
|---|---|---|---|---|---|
| Message sends, blocks, cascades | yes | n/a | yes (blocks) | closures | yes |
| Non-local return from a block | yes | no | yes (block-local only) | no | yes |
| Runtime class redefinition | yes | yes | yes | no | yes |
| Optional per-slot type contracts | no | no | no | no (static) | yes, enforced |
| Metaclass tower | yes | n/a | yes | no | partly — no tower, class-side methods inherit |
| Resumable exceptions | yes | no | no | no | no, deliberate |
| Images / snapshots | yes | no | no | no | no |
| Native binary without a runtime image | no | no | no | yes | yes (Granite) |
| Arbitrary-precision integers | yes | yes | yes | no (64-bit) | no (64-bit, trapping) |
| Dedicated character type | yes | no (one-character `str`) | no (String) | rune | no |
| Operator precedence | Smalltalk table | Python table | Ruby table | Go table | Smalltalk table — no arithmetic precedence |
| Namespaces / modules | image-wide | modules | modules | packages | `Library load:` binding capture |
| Goroutine-like concurrency | no | no | threads | yes (preemptive) | cooperative green processes |
| Channels | no | no | no | yes | no (`Semaphore`, `Lock`, `Monitor`, `SharedQueue`) |
| Reflection over method *source* | yes | yes | yes | via build | no |

## Faithful to classic Smalltalk

Verified by execution in both engines unless noted:

- message sends in unary, binary and keyword form, plus `;` cascades including
  mixed keyword segments;
- blocks with lexical scope and block temporaries (`[:x | | y | y := x + 1. y]`);
- `^` as a non-local return from a block inside a method, and `self` captured by
  blocks;
- `on:do:` supplying a handler *result*, and `ensure:` running exactly once on
  error, nested innermost-first;
- `nil` as a real object answering `ifNil:`/`ifNotNil:`;
- primitives declared in `.hrd` with the implementation in Nim;
- runtime class redefinition, method addition and removal;
- `doesNotUnderstand:` as a recovery hook; `perform:` for zero to three
  arguments;
- mixins through `Mixin derive` plus `addSuperclass:`, with conflict detection;
- `Interval`, `SortedCollection`, `Bag`, `Table`, `Set`, `Array`;
- green processes (`Processor fork:`/`yield`/`current`), `Semaphore`, `Lock`,
  `Monitor`, `SharedQueue`;
- `Library load:` for namespaced bindings.

### Precedence: the same table as Smalltalk

Unary binds tighter than binary, binary binds tighter than keyword, and binary is
strictly left-to-right with no arithmetic precedence:

```
2 + 3 * 4           -> 20      # left-to-right, no arithmetic precedence
10 - 2 - 3          -> 5
5 - 2 negated       -> 7       # unary binds tighter than binary
2 * 3 negated       -> -6
#(10,20,30,40,50) at: 1 + 2 -> 40
2 * 3 max: 4        -> 6       # parses as (2 * 3) max: 4
2 * (3 max: 4)      -> 8
```

This matches Smalltalk-80 exactly. The trap for readers arriving from Python,
Ruby or Go is the *absence* of arithmetic precedence, not a difference from
Smalltalk.

## Deliberately different

Each row is a decision, with the consequence stated.

| Topic | Smalltalk-80 | Harding | Consequence |
|---|---|---|---|
| Slot visibility | all instance variables private; accessors are methods | `derivePublic:`, plus `read:`/`write:` lists | `::` direct access **bypasses** accessor overrides |
| Where code lives | incremental compiler inside the image | source is canonical; target is Nim | no change sets; git is the history |
| Integer range | exact integers and `Fraction` | 64-bit | habitual overflow signals `Overflow`; unguarded, it ends the run |
| Exceptions | resumable (`resume`) | resumption removed | handlers supply values, they are not resumption points |
| Numeric equality | `1 = 1.0` is true | `1 = 1.0` is **false** | `==`/`~=` are identity only, so `1 == 1.0` is also false |
| String concatenation | `,` | `&` | `,` is reserved for literal separators; `"a" , "b"` is a parse error |
| Characters | `$a` is a Character | no Character class | `$a` is a parse error |
| Collection indexing | 1-based | **0-based** | porting a Smalltalk loop needs care |
| Module system | image-wide namespace | `Library load:` captures bindings | `Harding load:` loads globally |
| `nil` | `nil` | `nil`, nameable | see `research/language/NIL_AND_ABSENCE.md` for why removal was rejected |

### `super` with multiple inheritance

Multiple inheritance makes a bare `super` ambiguous, so Harding adds a qualifier
Smalltalk-80 cannot need:

```harding
P1 := Object derive: #().
P1>>who [ ^ "p1" ].
P2 := Object derive: #().
P2>>who [ ^ "p2" ].
C := Object derive: #().
C addSuperclass: P1.
C addSuperclass: P2.
C>>who [ ^ super who & "/" & super<P2> who ]      # "p1/p2"
```

- plain `super` searches from the first direct parent of the method's declaring
  class, matching Smalltalk's single-inheritance meaning;
- `super<Parent>` names one **direct** parent; a non-parent, an indirect
  ancestor, or an unknown name is an error rather than a silent fallback;
- both are lexical: the search starts at the declaring class's parent, not the
  runtime receiver's;
- both work on the class side (`C class>>tag [ ^ super<P2> tag ]`) and inside
  blocks (`[super<P2> tag] value`).

Code using the qualifier does not port to Smalltalk. Bare `super` does. Coverage
is in `test_interpreter_core.nim`, `test_compiled_runtime.nim`,
`test_engine_boundary.nim` and `test_granite_parity.py` (cases
`qualified_super`, `class_super`, `inherited_super`, `block_super`,
`super_new`).

### `::` direct named access

One syntax reaches three namespaces:

```harding
person::name        # slot
table::key          # table entry
MyLib::Class        # library binding
```

There is no Smalltalk equivalent. It deliberately does **not** invoke accessor
overrides, so it is a performance escape hatch with its own semantics — not a
short spelling of a message send.

### Optional slot type contracts

Slot types are optional and declared in the language, then enforced at
allocation, `::` writes, generated setters and reflective `at:put:` in *both*
engines:

```harding
Record := Object derivePublic: #{#count -> Integer, #ratio -> Float, #ok -> Boolean}.
```

verified: defaults `0`, `0.0`, `false` at allocation; `r count: "text"` raises a
catchable `Error` and preserves the old value. On top of that, *advisory*
inference (`src/harding/compiler/slot_inference.nim`) informs native unboxing
without changing semantics. See `DECLARED_SLOTS.md` and
[compiler/GRANITE.md](compiler/GRANITE.md).

Smalltalk has no types, Go has no optionality, and Python and Ruby have neither
enforced nor advisory slot types.

## Where the class model differs

Classes are objects, but there is no metaclass tower. The practical loss is
narrower than it first appears, because class-side methods *do* inherit:

```harding
B class>>greet [ ^ "B" ]
D := B derive: #()
(D greet)                       # -> B
```

Genuinely absent:

| Smalltalk-80 | Harding | Evidence |
|---|---|---|
| every class is an instance of a metaclass | classes are values; `(Object class) class` is `<instance of Object>` | probed |
| `Class` is a member of the hierarchy | `K class isKindOf: Class` → `false` | probed |
| `subclass:`, `subclasses`, `superclass`, `inheritsFrom:`, `allSuperclasses` | only `superclassNames` (direct parents), plus `derive:`/`addSuperclass:` | `Object subclasses` → Message not understood |
| class variables, class instance variables, pool dictionaries | absent by design; class-side state lives in globals, `Library` bindings, or a holder object | `MANUAL.md` "Missing Features" |
| method categories, class comments, change sets | absent; source is canonical and lives in git | `Object class comment` → Message not understood |

## Kernel and reflection protocol

Verified missing (each answered `Message not understood`):

| Smalltalk-80 | Harding equivalent |
|---|---|
| `copy`, `shallowCopy`, `deepCopy`, `postCopy` | only `clone` (shallow, instance-backed) |
| `hash`, `identityHash` | none — see the `Comparable` defect below |
| `printOn:`, `displayOn:`, `storeOn:`, `storeString` | `printString`, `displayString` only |
| `isMemberOf:` | `isKindOf:` only |
| `allInstances` | none |
| `become:` | none |
| `subclassResponsibility`, `shouldNotImplement`, `halt`, `assert:` | none |
| `dependsOn:`, `changed:`, `update:` | none |
| `Block>>numArgs`, `ifCurtailed:` | `parameterCount` only |
| `ExceptionSet`, `on:do:on:do:` | single-handler `on:do:` |
| `thisContext` as a reified frame | `thisContext` answers an `Activation` with `receiver`, `sender`, `selector`, `line`, `column`, `isClassMethod`, `cacheKey` — debug metadata, no `method`, `tempAt:`, `pc` |

### Naming: methods, not selectors

Harding says **methods**. The public protocol is `methods`, `definedMethods`,
`allInstanceMethods`, `allClassMethods`, `removeMethod:`, `removeClassMethod:`,
`conflictSelectors`. A method is *named* by a Symbol: `(Object methods at: 0)`
answers `#ifNotNil:`, and `perform:` accepts a Symbol or a String. There is no
selector object distinct from Symbol; the word survives only in
`conflictSelectors`, `selector` on `Activation`, and `selector:put:`.

## Collections

The hierarchy is flat: no `Collection`, `SequenceableCollection`, `Magnitude`,
`Association`, `Dictionary`, `OrderedCollection`, `LinkedList`,
`IdentityDictionary`, `Character`, and no streams.

Present: `Object`, `Iterable` (mixin), `Array`, `Table`, `Set`, `Bag`,
`SortedCollection`, `Interval`, `String`, `Symbol`.

- `Array` is both the fixed-size vector and the growable ordered collection
  (`add:`, `remove:`), standing in for `OrderedCollection`; indexing is 0-based.
- `Table` is the dictionary. It compares by value, as do `Set`, `Bag` and
  `Interval`; `Array` does not (`#(1,2) = #(1,2)` → `false`), because
  `Object>>=` is identity and `Array` does not override it.
- `,` is reserved, so concatenation is `&` — and `&` is string concatenation for
  *every* receiver: `#(1,2,3) & #(4)` answers `"#(1 2 3)#(4)"`, `(true & false)`
  answers `"truefalse"`.
- There is no `Array with:` or `Set with:`; `Array new: n` and `Array new` both
  work, `String new: n` does not.
- `Iterable` is adopted by `Array`, `Table` and `Set` only. `Bag`,
  `SortedCollection` and `Interval` each re-implement 9–13 of its methods
  instead of adopting it.
- `SortedCollection` and `Bag` compile from stdlib source. Any audit describing
  `SortedCollection` as interpreter-only predates source-backed stdlib
  compilation; see [compiler/GRANITE.md](compiler/GRANITE.md).

### Selector-level inventory

Covered on `Iterable`/`Array`: `do:`, `collect:`, `select:`, `reject:`,
`detect:`, `detect:ifNone:`, `inject:into:`, `anySatisfy:`, `allSatisfy:`,
`noneSatisfy:`, `sum`, `count:`, `includes:`, `includesAll:`, `size`, `isEmpty`,
`occurrencesOf:`, `addAll:`, `first`, `last`, `indexOf:`, `copyFrom:to:`,
`findFirst:`, `findLast:`, `reverseDo:`, `removeAt:`, `removeFirst`,
`removeLast`. On `Table`: keyed access, `values`, `associations`,
`keysAndValuesDo:`, `removeKey:`. On `Set`: membership, `remove:`, `union:`,
`intersection:`, `difference:`, `asArray`. On `Bag`: multiplicity via
`occurrencesOf:`, `remove:` dropping one occurrence, species-preserving queries.
On `Interval`: bounds, step, traversal, reversed, queries.

Absent or different, by family:

| Family | Gap |
|---|---|
| Membership | `Array` has removal by value, `remove:ifAbsent:` and `removeAllSuchThat:`; equivalent coverage on the other collections is not established |
| Conversion | `asBag`, `asOrderedCollection`, general `asSet` |
| Sequence | `replaceFrom:to:with:startingAt:` |
| Ordered mutation | `addFirst:`, `add:before:`, `add:after:`; no `OrderedCollection` |
| Sets | `IdentitySet` |
| Dictionaries | `Association` objects, `IdentityDictionary`; `Table` callbacks pass key *and* value, where Smalltalk enums pass values |
| Search failure | `detect:` answers `nil` where Smalltalk signals without `ifNone:`; `indexOf:` answers `nil` where Smalltalk answers `0` |
| Strings/streams | `String` is not a collection; no `Character`, no `Stream` hierarchy |

Closing these requires agreed contracts for hierarchy, equality/hash, indexing
and failure, then selector-by-selector runtime and Granite regressions. Adding
methods without those contracts would give superficial rather than behavioural
coverage. The proposed work items are in [plans/FIXES.md](plans/FIXES.md).

## Strings and characters

- No `Character` class; `$a` is a parse error; `"abc" at: 1` answers the
  one-character String `"b"`, which `isKindOf: String` and is not `= 98`.
- Strings are not collections: `do:`, `collect:`, `select:`, `reverse`,
  `asArray`, `first`, `last`, `includes:` are absent.
- `String withCapacity: n` gives a mutable sink that `<<` appends to and that
  prints as its contents; a literal string ignores `<<` and answers a new
  string. The documented contract says `<<` mutates unconditionally, which is
  wrong for literals — an open defect (F8 in `plans/FIXES.md`).
- Single quotes are reserved and produce a parse error.

## Numbers

- No `Fraction`, no exact rationals: `1/2` answers `0.5`, so `(1/3) * 3` answers
  `1.0`.
- `/` always answers Float (`4/2` → `2.0`); `//` is Nim `div` (`-7 // 2` →
  `-3`); `\\` is Nim `mod` (`-7 \\ 2` → `-1`). There is no `rem:`/`quo:` pair.
- Integers are 64-bit; a literal outside that range is a parse error.
- `1 = 1.0` is `false` by design, while `1 + 1.0` is `2.0`.
- Present: `abs`, `negated`, `sqrt`, `even`, `odd`, `factorial`, `gcd:`,
  `lcm:`, `max:`, `min:`, `between:and:`, `isZero`, `isPositive`, `isNegative`,
  `sign`, `squared`, `to:do:`, `to:by:do:`, `timesRepeat:`.
- Missing scalar protocol: `bitAnd:`, `bitOr:`, `bitShift:`, `raisedTo:`, `**`,
  `floor`, `ceiling`, `rounded`, `truncated`, `fractionPart`, `asInteger` on
  Float, `asFloat` on Integer, `isInteger`, `printStringRadix:`, `Float pi`,
  `Float infinity`, `atRandom`.
- No hexadecimal or radix literals: `0xFF` lexes as `0` followed by the binary
  selector `xFF`. `MANUAL.md`'s literal section documents the working syntax;
  treat this limitation as current.

## Exceptions and processes

- No resumption: `resume`, `resume:`, `return:`, `isResumable` do not exist
  (`EXCEPTION_MODEL.md`). Handlers supply values through their ordinary result;
  `pass` and `retry` exist; notifications call handlers synchronously above the
  live computation.
- An uncaught signal at the top level runs the exception's `defaultAction` and
  exits with the `=== Uncaught Exception ===` banner, except
  `MessageNotUnderstood`, which is reported as an error so tooling keeps
  running. Inside an embedded host, anything reached through a host callback uses
  `evalCallbackNonFatal`.
- Processes are cooperative and externally pumped: `Processor fork:` alone
  produces no output until something drives the scheduler
  (`Scheduler runToCompletion:`), and `Processor yield` at top level is not
  enough. Verified: two forks interleaved correctly only under
  `Scheduler runToCompletion:`. The shipped example drives the scheduler
  explicitly (`examples/concurrency/process_demo.hrd`).
- No `Delay`, no priority accessor, no `activeProcess`, no channels.
  `Semaphore`, `Lock`, `Monitor`, `SharedQueue` are the offered primitives.

## Image and environment

No image, no snapshot/resume, no change sets, no source-code reflection from the
language (`selectors`, `sourceCodeAt:`, `methodSourceFor:` are absent; Bona uses
host-side source indexing). The global dictionary is `Harding`, not `Smalltalk`.
`Transcript` and `Inspector` are Bona classes, not core ones.

## Python and Ruby

Nothing here is Pythonic or Rubyish, deliberately:

- no statement-level `if`/`while`/`def`, no operator precedence table, no `for`,
  no comprehensions, no default or keyword parameters;
- construction is `new`, not a constructor call;
- newlines act as statement separators, so periods are optional outside cascades.

Ruby is the nearer relative: blocks read like `do |x|`, and
`doesNotUnderstand:` occupies the `method_missing` niche, but the mapping is
loose. **The DNU argument is the selector symbol, not a message object**: it
answers `printString` (yielding `#bogus:with:`) but not `class`, `name`,
`arguments` or `selector`, so a handler cannot reach the actual arguments.
`Library load:` resembles a namespaced `require` but captures *bindings*, not a
module.

Where Python and Ruby are friendlier:

- **Integers trap.** `9223372036854775807 + 1` signals a catchable `Overflow`
  (subclass of `ArithmeticError`), but an unguarded one ends the run. Python
  promotes to a bignum; Ruby also uses arbitrary-precision integers.
- String-to-number conversion is nil-answering rather than exception-raising:
  `"42" asInteger` → `42`, `"bad" asNumber` → `nil`. That is more disciplined
  than Ruby's `to_i` → `0`.

## Go

Harding's green processes are the closest analogue to goroutines, and the
difference is sharp: they are **cooperative and externally pumped**, not
multiplexed by a runtime. There is no channel type.

What Go shares with Granite, and Smalltalk-80 does not, is a **native binary
with no runtime image**. Neither Go nor Harding offers an image snapshot.

## What is distinctive

The distinctiveness is compositional, not per-feature:

1. **Smalltalk semantics with two engines over one AST.** Source is canonical,
   the interpreter is the reference, and Granite must match it. That is enforced
   by the differential parity runner (`scripts/test_granite_parity.py`) plus the
   example audit (`examples/manifest.json`, see
   [compiler/GRANITE.md](compiler/GRANITE.md)). Neither Smalltalk-80 nor Go nor
   Python needed cross-engine parity, having one implementation each.
2. **`::` direct named access** unifying slots, table keys and library bindings
   under one syntax, deliberately bypassing accessor overrides.
3. **Optional slot type contracts** enforced in both engines, with advisory
   inference on top.
4. **A stackless VM that still compiles to native code.** Because frames live on
   a heap work queue, deep recursion is bounded by VM limits rather than the
   native stack. The same definition is also Granite's input.

## Open defects found by these comparisons

These are behaviour that contradicts the promise, reproduced, and listed with
fixes in [plans/FIXES.md](plans/FIXES.md):

1. **Shipped mixins call a method that does not exist.** `Comparable>>compareTo:`
   is `^ self identityHash - anObject identityHash`, and `Printable>>printOn:`
   calls `self identityHash printString`; there is no `identityHash` anywhere in
   `lib/`. `Comparable` was unusable in every probe; `Printable` degraded to
   printing `<K>`. `Equatable` works.
2. **`<<` mutates conditionally** while being documented as always mutating.
3. **Arithmetic overflow ends an unguarded run**, though it is catchable.
4. **Unknown identifiers silently answer `nil` inside methods** (`K>>oops [
   ^ counterr ]` → `nil`). At script level this is the documented lowercase-local
   rule; inside a method a typo becomes a silent nil.
5. **`doesNotUnderstand:` cannot see its arguments.**
6. **`&` answers by primitive ahead of dispatch**, so it cannot be overridden and
   silently stringifies collections and booleans.
7. **Class-side reflection answers the instance side**: on a class receiver,
   `methods`, `definedMethods` and `allInstanceMethods` return the instance-side
   tables.

## Performance positioning

Harding's compiler exists to make Harding fast; the honest summary is "much
faster than its own interpreter, much slower than a mature VM". Current numbers,
method and reproduction commands are in
[performance/BENCHMARKS.md](performance/BENCHMARKS.md). For orientation:

- Granite is roughly two orders of magnitude faster than the release interpreter
  on arithmetic-heavy workloads.
- Cog (Squeak 6.0, Spur/Cog), GNU Smalltalk and native Nim are all materially
  faster on the recorded workloads.

Those are workload-specific ratios, not a language ranking. Historical
measurements and the OpenSmalltalk Oil verification record are in
`research/benchmarks/`.
