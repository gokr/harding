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

### Green Threads And Synchronization

Harding includes cooperative processes and synchronization primitives:

- `Process`
- `Processor`
- `Monitor`
- `Semaphore`
- `SharedQueue`

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

## Current Strengths

If you want Harding today, the strongest areas are:

- Smalltalk-style object/block semantics
- stackless VM + green threads
- Granite native compilation
- reactive server-rendered web apps
- JSON / API workflows
- external library packaging
