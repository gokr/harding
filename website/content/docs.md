---
title: Documentation
---

## Getting Started

### Installation

```bash
git clone https://github.com/gokr/harding.git
cd harding

# Build the interpreter into the repo root
nimble harding

# Or install it to ~/.local/bin
nimble install_harding
```

Requirements:
- Nim 2.2.6 or later

### Quick Start

```bash
# Interactive REPL
harding

# Run a script
harding script.hrd

# Evaluate an expression
harding -e "3 + 4"

# Show AST and execute
harding --ast script.hrd

# Debug logging
harding --loglevel DEBUG script.hrd
```

### Granite Compiler

```bash
granite compile myprogram.hrd -o myprogram
granite build myprogram.hrd --release
granite run myprogram.hrd
```

## Where To Start

### Core Language

- [Language Manual](https://github.com/gokr/harding/blob/main/docs/MANUAL.md)
- [Quick Reference](https://github.com/gokr/harding/blob/main/docs/QUICKREF.md)
- [Implementation Notes](https://github.com/gokr/harding/blob/main/docs/IMPLEMENTATION.md)

### Web And APIs

- [MummyX Integration](https://github.com/gokr/harding/blob/main/docs/MUMMYX.md)
- [Reactive Web Rendering](https://github.com/gokr/harding/blob/main/docs/REACTIVE_WEB_RENDERING.md)
- [JSON API Server Tutorial](https://github.com/gokr/harding/blob/main/docs/API_SERVER_TUTORIAL.md)
- [Bona Todo Workflow](https://github.com/gokr/harding/blob/main/docs/BONA_WEB_TODO.md)

MummyX is Harding's current web server path: a fast scalable native multithreaded HTTP server with Harding handlers executed through the interpreter's green-process model.

### Packages And External Libraries

- [Nim Package Tutorial](https://github.com/gokr/harding/blob/main/docs/NIM_PACKAGE_TUTORIAL.md)
- [External Libraries](/libraries)

Harding packages can bundle native Nim code and Harding source together, so one installable package can expose both primitives and `.hrd` APIs.

### Tools And Development

- [Tools & Debugging](https://github.com/gokr/harding/blob/main/docs/TOOLS_AND_DEBUGGING.md)
- [VSCode Extension](https://github.com/gokr/harding/blob/main/docs/VSCODE.md)
- [GTK Integration](https://github.com/gokr/harding/blob/main/docs/GTK.md)

## Example Code

### Hello World

```harding
"Hello, World!" println
```

### Simple Class

```harding
| c |

Counter := Object derive: #(count)
Counter>>initialize [ count := 0 ]
Counter>>value [ ^ count ]
Counter>>increment [ ^ count := count + 1 ]

c := Counter new.
c initialize.
c increment.
c value println
```

### Resumable Exception

```harding
result := [
    10 // 0
] on: DivisionByZero do: [:ex |
    ex resume: 0
].

result println
```

### Web Route

```harding
Harding load: "lib/mummyx/Bootstrap.hrd".

Server := HttpServer new.
Router := Router new.

Router get: "/" do: [:req |
    req respondHtml: "<h1>Hello</h1>"
].

Server router: Router.
Server serveForever: 8080.
```

### Html + HTMX Fragment

```harding
Router get: "/" do: [:req |
    req respondHtml: (Html render: [:h |
        h div: [:panel |
            panel id: "todo-panel".
            panel button: [:button |
                button post: "/todos/1/toggle";
                    target: "#todo-panel";
                    swap: "outerHTML".
                button text: "Toggle"
            ]
        ]
    ])
].
```

## For Smalltalk Programmers

What feels familiar:

- unary, binary, and keyword messages
- cascades with `;`
- lexical blocks with non-local returns
- everything is an object
- collection protocols such as `do:`, `collect:`, `select:`, `inject:into:`

What is different:

- comments use `# ` instead of quoted comments
- strings use `"..."`
- periods are optional at line ends
- class creation uses `derive:` forms
- source is file-based and git-friendly
- no metaclasses in the Smalltalk-80 sense

## IDE Support

### VSCode

- syntax highlighting
- completions / hover / go-to-definition
- debugger integration

### Bona

```bash
nimble bona
./bona
```

Current emphasis:

- Launcher
- Workspace
- Transcript
- Browser / Inspector work
- Application Builder

## Project Docs

- [Future Plans](https://github.com/gokr/harding/blob/main/docs/FUTURE.md)
- [Contributing](https://github.com/gokr/harding/blob/main/CONTRIBUTING.md)

## Getting Help

- [GitHub Issues](https://github.com/gokr/harding/issues)
- [GitHub Discussions](https://github.com/gokr/harding/discussions)
