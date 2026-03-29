---
title: Features
---

## Language Features

### Smalltalk Semantics

Harding keeps the core Smalltalk model:

- everything is an object
- message sends are unary, binary, or keyword
- blocks are lexical closures with non-local return support
- method lookup stays late-bound

```harding
3 + 4
dict at: key put: value

findPositive := [:arr |
    arr do: [:n |
        (n > 0) ifTrue: [ ^ n ]
    ].
    ^ nil
]
```

### Modernized Syntax

- `#` comments instead of quoted comments
- double-quoted strings
- periods optional at line ends
- `&` for concatenation
- comma-separated collection literals

```harding
# comment
greeting := "Hello, " & name
values := #(1, 2, 3)
payload := json{"ok": true, "count": values size}
```

### Dynamic Collection Literals

Array, Table, and JSON literals now fit better into normal expression flow.

```harding
skills := #(user primarySkill, user secondarySkill, "reserve")
profile := #{"name" -> user name, "active" -> true}
payload := json{"skills": skills, "count": skills size}
```

### Current Class Definition Style

Harding now has a clearer class-definition surface with direct slot access when needed.

```harding
Point := Object derivePublic: #(x, y)

Point>>moveBy: dx and: dy [
    x := x + dx.
    y := y + dy
]

Point>>distanceSquared [
    ^ (x * x) + (y * y)
]
```

### Multiple Inheritance And Mixins

Harding supports multiple inheritance plus mixin-style behavior sharing.

```harding
Comparable := Mixin derive.
Comparable>>between: min and: max [
    ^ (self >= min) and: [ self <= max ]
]

Point := Object derive: #(x, y).
Point addSuperclass: Comparable.
```

### Direct Slot / Binding Access

The `::` syntax gives explicit access to slots, table entries, and library bindings.

```harding
person::name := "Alice".
config::theme := "business".
WebTodo::TodoApp resetRepository
```

### Conflict Handling In Multiple Inheritance

Harding supports multiple inheritance with explicit conflict handling when parent classes overlap.

```harding
Parent1 := Object derive: #(a)
Parent1>>foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2>>foo [ ^ "foo2" ]

Child := Object derive: #(x)
Child>>foo [ ^ "child" ]
Child addSuperclass: Parent1.
Child addSuperclass: Parent2.
```

## Runtime Features

### Stackless VM

Harding runs on a stackless VM with an explicit work queue instead of relying on the native call stack.

This enables:

- green threads
- resumable exceptions
- explicit control-flow scheduling
- safer long-running evaluation paths

### Smalltalk-Style Resumable Exceptions

```harding
result := [
    10 // 0
] on: DivisionByZero do: [:ex |
    ex resume: 0
]
```

Handlers can `resume`, `resume:`, `retry`, `pass`, or `return:`.

```harding
result := [
    riskyOperation value
] on: Error do: [:ex |
    ex resume: 42
]
```

### Green Threads And Synchronization

Harding includes cooperative processes and synchronization primitives:

- `Process`
- `Processor`
- `Monitor`
- `Semaphore`
- `SharedQueue`

```harding
worker := Processor fork: [
    1 to: 10 do: [:i |
        i println.
        Processor yield
    ]
]

worker suspend.
worker resume.

monitor := Monitor new.
monitor critical: [ shared := shared + 1 ]

queue := SharedQueue new.
queue nextPut: "item".
item := queue next.

sem := Semaphore forMutualExclusion.
sem wait.
sem signal
```

Processes remain inspectable at runtime through the scheduler and process APIs.

### System And File I/O

Harding includes practical process and file helpers in the standard library.

```harding
content := File readAll: "README.md".
File write: content to: "README.copy.md".

System stdout writeline: ("args: " & (System arguments size) asString)
```

## Web And Reactive Rendering

### MummyX HTTP Support

Build Harding with MummyX, a fast scalable native multithreaded HTTP server, and define routes directly in Harding code.

```harding
Harding load: "lib/mummyx/Bootstrap.hrd".

Server := HttpServer new.
Router := Router new.
Router get: "/" do: [:req | req respondHtml: "<h1>Hello</h1>" ].
Server router: Router.
Server serveForever: 8080.
```

You can keep handlers small and HTML-first:

```harding
Router get: "/" do: [:req |
    req respondHtml: (Html render: [:h |
        h main: [:main |
            main h1: "Harding Todo".
            main p: "Reactive server rendering with HTMX"
        ]
    ])
].
```

And router actions can stay tiny while still feeling declarative:

```harding
Router post: "/todos/@id/toggle" do: [:req |
    repository toggle: (req pathParam: "id").
    req respondFragment: panel oob: page statsOobHtml
].
```

The Html side stays just as small:

```harding
Html render: [:h |
    h section: [:panel |
        panel id: "todo-panel".
        panel button: [:button |
            button class: "btn";
                post: "/todos/1/toggle";
                target: "#todo-panel";
                swap: "outerHTML".
            button text: "Mark done"
        ]
    ]
]
```

### Html DSL

Harding's Html DSL renders directly and stays intentionally simple.

```harding
Html render: [:h |
    h div: [:card |
        card class: "card".
        card h1: "Hello"
    ]
]
```

```harding
Html render: [:h |
    h section: [:panel |
        panel id: "todo-panel".
        panel button: [:button |
            button class: "btn";
                post: "/todos/1/toggle";
                target: "#todo-panel";
                swap: "outerHTML".
            button text: "Mark done"
        ]
    ]
]
```

### Reactive Server Rendering

The current web model is:

- `TrackedValue` / `TrackedList` in `lib/reactive/`
- `RenderCache` / `RenderEntry` in `lib/web/`
- invalidation driven by tracked reads and writes during component rendering

This supports fragment-level cache reuse without reviving the older Html template-hole design.

### HTMX-Friendly Responses

Harding now has thin response helpers for HTMX-style fragment workflows:

```harding
req respondFragment: panel oob: page statsOobHtml
```

That keeps the API close to HTMX concepts rather than inventing a separate framework layer.

And the HTML side stays close to HTMX too:

```harding
h button: [:button |
    button class: "btn";
        post: "/todos/1/toggle";
        target: "#todo-panel";
        swap: "outerHTML".
    button text: "Mark done"
]
```

## Reflection And Dynamic Dispatch

Harding supports dynamic messaging and runtime inspection when you need it.

```harding
obj perform: #description.
obj perform: #at: with: 5.
obj perform: #at:put: with: 5 with: "value".

Point superclassNames.
obj class.
obj slotNames.
obj respondsTo: #do:
```

## Super Sends And Class-Side Methods

Harding supports both class-side methods and qualified or unqualified super sends.

```harding
Person class>>newNamed: aName [
    | p |
    p := self new.
    p name: aName.
    ^ p
]

ColoredRectangle>>area [
    ^ super area + colorAdjustment
]
```

## Primitives And Nim Interop

Primitives provide the bridge between Harding code and native Nim-backed behavior.

```harding
Array>>at: index <primitive primitiveAt: index>

String>>& other <primitive primitiveConcat: other>
```

This is also the basis for the package model where native Nim code and Harding source ship together.

## JSON And API Workflows

### `json{...}` Literals

```harding
json{"status": "ok", "count": 42}
```

### Object Serialization

Harding supports object serialization through `Json stringify:` plus class-side configuration such as:

- `jsonExclude:`
- `jsonOnly:`
- `jsonFieldOrder:`
- `jsonOmitNil:`
- `jsonFormat:`

### API Server Patterns

The repo includes a JSON API tutorial and Todo API examples using MummyX and BitBarrel.

## Collections

Harding includes the classic Smalltalk collection style with arrays, tables, sets, intervals, and rich iteration protocols.

```harding
numbers := #(1, 2, 3, 4, 5).
scores := #{"Alice" -> 95, "Bob" -> 87}.

numbers do: [:n | n println].
squares := numbers collect: [:n | n * n].
evens := numbers select: [:n | (n % 2) = 0].
sum := numbers inject: 0 into: [:acc :n | acc + n]
```

## Live REPL

The interactive REPL is still a first-class part of the development workflow.

```text
$ harding
harding> 3 + 4
7

harding> numbers := #(1, 2, 3, 4, 5)
#(1, 2, 3, 4, 5)

harding> numbers collect: [:n | n * n]
#(1, 4, 9, 16, 25)
```

## External Libraries And Packages

### `harding lib`

Install external Harding libraries through the built-in library manager.

```bash
harding lib list
harding lib install bitbarrel
```

### Nim + Harding Package Model

Harding's package model can bundle native Nim implementations together with Harding source so both layers ship as one installable unit.

```text
package/
|- src/        # Nim primitives and support code
|- lib/        # Harding .hrd sources
`- .harding-lib.json
```

## Tooling

### Bona IDE

Current Bona workflows include:

- Launcher
- Workspace
- Transcript
- Browser / Inspector work
- Application Builder for Granite-oriented app creation

### VSCode

The VSCode extension provides:

- syntax highlighting
- language server support
- debugger integration

## Granite Compiler

Compile Harding code to native binaries through Granite.

```bash
granite compile myprogram.hrd -o myprogram
granite build myprogram.hrd --release
granite run myprogram.hrd
```

Compilation flow:

```text
Harding source -> AST -> Granite -> Nim -> C toolchain -> native binary
```

## Debugging Tools

Use log levels, AST output, and scheduler inspection to understand running programs.

```bash
harding --loglevel DEBUG script.hrd
harding --ast script.hrd
```

## Current Strengths

If you want Harding today, the strongest areas are:

- Smalltalk-style object/block semantics
- stackless VM + green threads
- Granite native compilation
- reactive server-rendered web apps
- JSON / API workflows
- external library packaging
