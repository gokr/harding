---
title: Harding Smalltalk
tagline: Smalltalk feeling, modern tooling
---

## Hero Section

**Title:** Harding Smalltalk
**Subtitle:** Smalltalk feeling, modern tooling.
**Description:** A modern Smalltalk dialect with a stackless VM, native compilation through Granite, reactive server-rendered web support, and file-based source that works well with git.

**CTA Primary:** Get Started
**CTA Secondary:** See Features

### Hero Code Example

```harding
Point := Object derivePublic: #(x, y)

Point>>moveBy: dx and: dy [
    x := x + dx.
    y := y + dy
]

Point>>printString [
    ^ "Point(" & x asString & ", " & y asString & ")"
]

p := Point new.
p::x := 100.
p::y := 200.
p moveBy: 5 and: 10.
p printString println
```

## Features

### Smalltalk Semantics
Message sends, blocks, non-local returns, resumable exceptions, and live-editable class definitions remain central to the language.

### Two Execution Paths
Use the interpreter for interactive development and Granite for standalone native binaries.

### File-Based And Git-Friendly
Harding code lives in `.hrd` files. No image is required for normal development workflows.

### Reactive Server Rendering
Build web apps with the Html DSL, HTMX fragment updates, and `RenderCache` invalidation driven by tracked state.

### Improved Ergonomics
Use dynamic literals such as `#(1, 2, 3)` and `#{"name" -> user name}`, `json{...}` support, `&` concatenation, direct member access with `::`, and optional `.` at line ends.

### External Libraries And Packages
Install Harding libraries with `harding lib`, and use a package system that can bundle native Nim code and Harding code together in one versioned unit.

### Web Server Built In
Harding can be built with integrated MummyX, a fast scalable native multithreaded HTTP server written in Nim.

### GTK4 Integration
Harding includes GTK4 bindings so you can write native GTK applications directly in Harding.

### IDE Tooling
Bona builds on the GTK integration and provides a Launcher, Workspace, Transcript, Browser, Inspector work, and an Application Builder workflow. VSCode support includes syntax highlighting, LSP, and DAP.

## What You Can Build

- command-line tools with `System`, `File`, and `FileStream`
- native binaries with Granite
- JSON APIs with `json{...}` and object serialization
- reactive HTMX web apps with MummyX
- installable packages that bundle Harding code and native Nim code together

## Get Started

[Install Harding](/docs) and try the REPL, explore the [full feature list](/features), or jump into the current docs for web, JSON, and packages.
