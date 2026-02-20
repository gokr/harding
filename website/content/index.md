---
title: Harding Smalltalk
tagline: Smalltalk feeling, modern tooling
---

## Hero Section

**Title:** Harding Smalltalk
**Subtitle:** Smalltalk feeling, modern tooling.
**Description:** A modern Smalltalk dialect aiming at native compilation. File-based, git-friendly, and designed for modern tooling.

**CTA Primary:** Get Started
**CTA Secondary:** See Examples

### Hero Code Example

```harding
# Define a Point class with x and y slots
# auto generate setter and getter methods
Point := Object deriveWithAccessors: #(x y)

# Add a method to the class using selector:put:
# and a block representing the code
Point selector: #moveBy:and: put: [:dx :dy |
    x := x + dx
    y := y + dy
]

# Simpler way to add a method using >> syntactic sugar
Point>>+ aPoint [
    x := x + aPoint x
    y := y + aPoint y
]

# Create and use a Point, cascades work fine
p := Point new
p x: 100; y: 200
p moveBy: 5 and: 10
```

## Features

### Smalltalk Heritage
Everything you love about Smalltalk - message passing, blocks, live programming - preserved and modernized.

### Native Performance
Two execution models: a stackless VM written in Nim and the Granite compiler for native binaries via Nim → C.

### File-Based
No image files. Source lives in `.hrd` files you can version control, diff, and edit with any editor.

### Multiple Inheritance
Experimental support for multiple inheritance with conflict detection.

### Green Threads
Cooperative multitasking with first-class Process objects. Built-in scheduler with round-robin execution.

### Smalltalk-Style Exceptions
Resumable exception handling with `on:do:`, `signal`, `resume`, `retry`, and `pass`. Full signal point preservation.

### Native Compilation
Granite compiler produces standalone native binaries. No runtime dependencies, true native performance.

### Nim Interop
Call Nim code directly with good primitive bridging support. Access the entire Nim ecosystem: libraries, packages, and system APIs.

## Get Started

[Install Harding](/docs) and try the REPL, or explore the [full feature list](/features).
