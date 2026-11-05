---
name: coding-harding
cluster: coding
description: "Harding Smalltalk: literals, interpolation, :: access, cascades, both engines, Granite parity"
tags: ["harding","smalltalk","granite","gtk","coding"]
dependencies: []
composes: []
similar_to: ["coding-nim"]
called_by: []
authorization_required: false
scope: general
model_hint: claude-sonnet
embedding_hint: "harding smalltalk literals interpolation array table prefix literal cascade named access granite parity gtk"
---

# coding-harding

## Purpose

Use this skill when writing, reviewing, or migrating Harding source (`.hrd`), or
when reasoning about differences between Harding's interpreter and the Granite
compiler. It records the syntax decisions that are easy to get wrong — especially
when arriving from Smalltalk, where several constructs look familiar but behave
differently.

## The most important rule

**The interpreter and Granite must always agree.** Any difference in observable
behaviour is a bug in one of them, never something to work around in a demo.
When you find one, reduce it to a minimal `.hrd` file that runs in both engines,
then fix the engine — do not paper over it.

```bash
./harding script.hrd                                                # interpreter
./granite build script.hrd -d:build/x -o:build/x/s && ./build/x/s   # compiled
python3 scripts/test_granite_parity.py                              # both, compared
python3 scripts/test_granite_parity.py my_case                      # one case
```

## Literals

Two families, deliberately split:

| Form | Meaning | Static? |
|---|---|---|
| `#(1, #sym, "s")` | literal array; bare identifiers become **symbols** | yes, compile-time |
| `#{key -> value}` | literal table; keys and values must be literals | yes, compile-time |
| `array{x, 1 + 2}` | array of **evaluated expressions** | no |
| `table{"k" -> x}` | table of evaluated keys and values | no |
| `json{"k": x}` | JSON *string* built at runtime | no |
| `sql{...}` | parsed, but has no backing class — do not use | n/a |

- A bare identifier in `#(...)` is a symbol: `#(name, age)` is `#(#name #age)`.
  This is what makes `Object derive: #(name, age)` work. It is compile-time and
  identical in both engines.
- A bare identifier in `array{...}` is a **variable read**. Use `array{}` when
  you mean values, `#()` when you mean symbols.
- Keys in `#{...}` and `table{...}` are expressions; keys in `json{}` are names.
- Nested literals inside `#(...)` / `#{...}` need no `#`: `#((a, b), (c, d))`
  works, and `#(#(a, b))` stays valid.
- Every evaluation of a literal produces a **fresh** instance. Never assume
  Smalltalk's shared-literal identity, and never add such caching.
- Empty `#()`, `#{}`, `array{}` and `table{}` are all valid and all empty.

## String interpolation

Double-quoted strings interpolate at parse time; triple-quoted strings are raw.

```harding
name := "bob"
"Hi $name"              # Hi bob
"slot $point::x"        # named member, no braces needed
"sum ${1 + 2}"          # expression
"sum $(1 + 2)"          # same
"cost \$5"              # escaped dollar
"""raw $name"""         # stays literal
```

- The hole grammar is `$name`, `$name::slot`, `${expr}` or `$(expr)`. A `$` not
  followed by one of those is literal text.
- Interpolation uses `displayString`, so a string embeds **unquoted**.
- `String>>interpolate: aTable` interpolates a raw string later, against
  bindings; unknown names are left untouched. It takes an explicit table because
  a dynamically built string cannot see the caller's locals.

## printString vs displayString

Both exist in both engines, and the split is Smalltalk's:

- `printString` → the **literal** form: a string quotes itself (`"bob"`),
  collections quote their elements (`#("x" 1)`).
- `displayString` → the **human-facing** form: `Object` answers `printString`,
  `String` answers its characters (`bob`).
- `println`/`print` use `toString`, matching the interpreter's `Object>>println`.

## Named access, not accessors

`::` reads and writes members directly. Prefer it over hand-written getters and
setters, and drop trivial accessors rather than keeping both.

```harding
note::title                # read a slot
note::title := "new"       # write it
table::key                 # table entry
MyLib::ClassName           # library binding
```

- Requires the slot to be readable/writable: `derivePublic:` marks all slots so;
  `derive:` leaves them private and `::` correctly refuses from outside.
- Direct writes bypass overridden setters by design — use a setter when you need
  one to run.

## Style

- A newline separates statements; a trailing `.` is unnecessary. Keep `.` only
  when two statements share a line.
- `#` starts a comment. `"..."` is **always a string literal**, never a comment —
  a bare string statement is a silently discarded no-op.
- A method without `^` answers **self**, not its last statement. Factories and
  anything returning data must say `^value`; setters and mutators need nothing.
- Cascades are classic Smalltalk: every `;` message goes to the **same
  receiver**, the receiver is evaluated once, and the cascade answers the **last**
  message's result (`obj msg; yourself` is the idiom to answer `obj`). A cascade
  may follow `^`: `^self new label: t; connect: "clicked" do: b`.
- Because a newline separates statements, the receiver and its first message must
  start on the same line. `a one; two` and `a` followed by `  one: 1; two: 2`
  (receiver plus first message below) are fine; a bare receiver alone on a line
  is a complete statement and the `;` on the next line is a parse error.
- `::` needs a simple receiver: `note::title := x` works, `self current::title`
  and `nb last::title` do not. Bind a temp first (and declare temporaries at the
  top of the method, before any statement).
- Unary binds tighter than binary, binary tighter than keyword, so
  `self setHexpand: true` needs no parentheses.
- Prefer interpolation over `&` chains.

## Both engines in practice

- Class definitions are process-global; a redefinition replaces rather than
  duplicates.
- Uncaught signals at CLI top level run `defaultAction` and exit with the banner,
  except `MessageNotUnderstood`, which is reported. Host callbacks (GTK, MCP)
  must use the non-fatal path so an IDE never quits.
- Compile Granite with `nim c -p:external -o:granite src/harding/compiler/granite.nim`.
- `nimble` test tasks mask failures with `|| true`; run `nim c -r` directly and
  read the output.

## Validation before claiming success

```bash
python3 scripts/test_granite_parity.py <case>...   # both engines, exact output
./harding demos/notebook/notebook.hrd -- --self-test
./harding_gtk demos/notebook/notebook.hrd -- --self-test --gui-test --data build/x.json
python3 -m unittest tests.test_notebook_application
```

Report the exact command and its actual result. Never present a skipped or
unrun test as a pass, and check `git status` after sweeps that write files.
