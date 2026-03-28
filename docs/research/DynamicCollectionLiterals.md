# Dynamic Collection Literals And `&` Concatenation

## Status

Proposal.

This note describes a language cleanup we want after the current web/runtime work:

- make `#(...)` an evaluated array literal
- reserve `,` for syntax separators inside collection literals
- move string/sequence concatenation from `,` to `&`
- keep bare parenthesized comma expressions out of the language for now

## Motivation

Today Harding uses `#(...)` for array literals, but the parser treats elements in a special restricted way and existing docs still reflect a more static-leaning model.

At the same time, `,` is used as string concatenation, which blocks it from becoming a clean collection separator syntax.

This creates tension in three places:

1. array/table/json literal syntax wants separators
2. concatenation wants an infix operator
3. parser rules become harder to reason about when `,` is both syntax and message send

Using `&` for concatenation and reserving `,` for literal syntax gives Harding a cleaner long-term surface.

## Proposed Syntax

### Concatenation

Replace concatenation with `&`:

```harding
"Hello " & name
"/todos/" & id printString & "/toggle"
```

This aligns well with Nim and frees `,` for syntax.

### Dynamic array literals

Make `#(...)` evaluate expressions at runtime:

```harding
#(3 + 4, #symbol, user name)
#(item id, item title, item completed)
```

The parser should treat `,` as the element separator inside the literal.

### Dynamic table literals

The same separator rule should apply naturally inside table-like syntaxes:

```harding
#{"name" -> user name, "age" -> user age}
json{"count": 3 + 4, "items": #(1, 2, 3)}
```

## What We Are Not Proposing

Do not make bare comma expressions create arrays globally.

These should remain invalid or keep their current meaning until explicitly designed:

```harding
3 + 4, 9, 4
(34, #symbol)
```

Reasons:

- too implicit
- harder precedence rules
- easier accidental arrays
- worse readability in a Smalltalk-like language

The recommendation is to keep array creation explicit through `#(...)`.

## Current Implementation Notes

Relevant places today:

- lexer tokenizes `,` as `tkComma` in `src/harding/parser/lexer.nim`
- parser handles `#(...)` in `src/harding/parser/parser.nim`
- parser currently reads array elements with restricted expression parsing in `parseArrayLiteral`
- string concatenation currently maps `,` in:
  - `src/harding/interpreter/objects.nim`
  - `src/harding/codegen/expression.nim`

There is also constant literal analysis for arrays/tables in:

- `src/harding/parser/constant_analysis.nim`

## Parser Plan

### Phase 1: introduce `&`

Add `&` as concatenation and migrate generated/runtime support.

Tasks:

1. add/confirm `&` binary selector support in parser precedence
2. route `&` to concatenation in interpreter/runtime
3. route `&` to concatenation in Granite/codegen
4. update docs/examples to prefer `&`

### Phase 2: change `#(...)` parsing

Update `parseArrayLiteral` so elements are separated by commas instead of whitespace-only sequencing.

Desired examples:

```harding
#(1, 2, 3)
#(3 + 4, foo bar, someTable at: #x)
```

Tasks:

1. require or strongly prefer `,` separators in `#(...)`
2. parse each element as a normal expression
3. keep closing `)` handling and newline skipping clean
4. update constant analysis so compile-time folding still works when all elements are constant

### Phase 3: align table/json literal separators

Use the same separator story consistently:

- array literal: commas between elements
- table literal: commas between entries
- json literal: commas between properties/items

## Runtime Plan

### Concatenation

Current concatenation implementation is centered on `,`.

We should:

1. move the runtime implementation to `&`
2. update codegen to emit the same concatenation helper for `&`
3. decide whether `,` remains temporarily as compatibility or is removed immediately

Recommended: keep `,` temporarily only if migration pain is high; otherwise remove it quickly.

### Constant literals

We should preserve constant folding when possible:

```harding
#(1, 2, 3)
#{"x" -> 1, "y" -> 2}
```

If every element/value is constant, keep the current optimization path.
If not, evaluate at runtime.

## Migration Plan

### Step 1: support both styles briefly

- add `&`
- keep `,` working for concatenation for one transition window
- update core docs and examples to use `&`

### Step 2: migrate library code

Update:

- `lib/`
- `tests/`
- docs/examples

especially web code where concatenation appears often in route/url building.

### Step 3: switch literal docs and examples

Document:

```harding
#(1, 2, 3)
#{"a" -> 1, "b" -> 2}
```

and stop promoting whitespace-only array elements.

### Step 4: remove `,` concatenation

After migration, `,` becomes syntax-only in collection contexts.

## Open Questions

1. Should `#(...)` require commas, or allow both commas and whitespace during a transition period?
2. Should `&` be string-only concatenation, or generic sequence/fragment concatenation like today?
3. Should `#{...}` and `json{...}` share exactly the same separator rules from day one?
4. Should we add warnings for `,` concatenation before removal?

## Recommendation

Recommended direction:

- use `&` for concatenation
- make `#(...)` dynamic
- use `,` as separator inside explicit collection syntaxes
- do not make bare `a, b, c` a general array constructor

This keeps Harding explicit, easier to parse, and more internally consistent.
