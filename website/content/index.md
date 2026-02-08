---
title: Harding Smalltalk
tagline: Smalltalk Semantics, Nim Performance
---

## Hero Section

**Title:** Harding Smalltalk
**Subtitle:** Smalltalk semantics, modern tooling.
**Description:** A modern Smalltalk dialect aiming at native compilation. File-based, git-friendly, and designed for modern tooling.

**CTA Primary:** Get Started
**CTA Secondary:** See Examples

### Hero Code Example

```harding
# Define a Point class with x and y slots
Point := Object derive: #(x y)

# Add method using selector:put:
Point selector: #moveBy:and: put: [:dx :dy |
    x := x + dx
    y := y + dy
]

# Simpler way to add method using >> syntactic sugar
Point>>x: val [
    x := val
]

# Add several methods at once using a special mechanism
# to bind a block to a specific self - the Point class.
Point extend: [
    self>>y: val [ y := val ]
    self>>y [ ^y ]
    self>>x [ ^x ]
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
Compiles through Nim to C to machine code **(future)**. No VM, no bytecode, fast native binaries.

### File-Based
No image files. Source lives in .hrd files you can version control, diff, and edit with any editor.

### Multiple Inheritance
Experimental support for multiple inheritance with conflict detection.

### Green Threads
Cooperative multitasking with first-class Process objects. Built-in scheduler with round-robin execution.

### Nim Interop
Call Nim code directly. Access the entire Nim ecosystem: libraries, packages, and system APIs.

## Get Started

[Install Harding](/docs) and try the REPL, or explore the [full feature list](/features).
