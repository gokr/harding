---
title: Features
---

## Language Features

### Smalltalk Semantics

Harding preserves the essence of Smalltalk:

- **Everything is an object** - Numbers, strings, blocks, classes
- **Everything happens via message passing** - No function calls, only messages
- **Late binding** - Method lookup happens at message send time
- **Blocks with non-local returns** - True lexical closures with `^` return

```harding
# Message passing
3 + 4                    # binary message
obj size                 # unary message
dict at: key put: value  # keyword message

# Blocks with non-local return
findPositive := [:arr |
    arr do: [:n |
        (n > 0) ifTrue: [^ n]   # Returns from findPositive:
    ].
    ^ nil
]
```

### Modern Syntax

Optional periods, hash comments, double-quoted strings:

```harding
# This is a comment, as long as it has a space after hash
x := 1                  # No period needed at end of line
y := 2
z := x + y              # But periods work too if you prefer

"Double quotes for strings" # More standard for most languages
```

### Class-Based with Multiple Inheritance

Create classes dynamically with slots and methods:

```harding
# Declare a temporary variable to hold an instance
| p |

# Create a new class with two instance variables
Point := Object derive: #(x y)

# Add methods using >> syntax and direct slot access
Point >> x: val [ x := val ]
Point >> y: val [ y := val ]

# Add multiple methods at a time
Point extend: [
    self >> moveBy: dx and: dy [
        x := x + dx
        y := y + dy
    ]
    self >> distanceFromOrigin [
        ^ ((x * x) + (y * y)) sqrt
    ]
]

# Create and use a Point
p := Point new
p x: 100; y: 200
p distanceFromOrigin println   # 223.6068...
```

#### Multiple Inheritance

Harding supports multiple inheritance with conflict detection:

```harding
# Inherit from multiple parents
ColoredPoint := Point derive: #(color)
ColoredPoint addParent: Comparable
ColoredPoint addParent: Printable
```

**Full Constructor Syntax:**

```harding
# Create a class with multiple parents and methods in one call
MyClass := Object derive: #(slot1 slot2)
    parents: #(Parent1 Parent2)
    slots: #(extraSlot)
    methods: [
        self>>method1 [ ... ]
        self>>method2 [ ... ]
    ]
```

**Comprehensive Constructor:**

For complete control with selective getters and setters:

```harding
# derive:parents:slots:getters:setters:methods: - full control
MyClass := Object derive: #(slot1 slot2)
    parents: #(Parent1 Parent2)
    slots: #(extraSlot)
    getters: #(slot1 extraSlot)
    setters: #(slot2)
    methods: #{
        #method1 -> [:arg | ...],
        #method2 -> [:a :b | ... ]
    }
```

**Mixin Class:**

For slotless composition, use the `Mixin` class:

```harding
# Mixin is a slotless class for shared behavior
Comparable := Mixin derive: #()
Comparable >> < other [ <primitive: primitiveLessThan> ]
Comparable >> > other [ <primitive: primitiveGreaterThan> ]
```

**Conflict Detection:**

When multiple parents define the same method, Harding detects conflicts:

```harding
A := Object derive: #() methods: #{ #foo -> [ ^ 'A' ] }
B := Object derive: #() methods: #{ #foo -> [ ^ 'B' ] }
C := Object derive: #() parents: #(A B)  # Conflict detected on #foo
```

## Advanced Features

### Primitives

Primitives provide direct access to VM-level operations and Nim interop. They use a declarative syntax:

```harding
# Basic primitive syntax
Array>>at: index <primitive primitiveAt: index>

# Primitive with validation wrapper
Array>>at: index [
    (index < 1 or: [index > self size]) ifTrue: [
        self error: "Index out of bounds"
    ].
    ^ <primitive primitiveAt: index>
]
```

**Available Primitives:**

| Primitive | Description |
|-----------|-------------|
| `primitiveClone` | Create a shallow copy of an object |
| `primitiveAt:` | Access element at index (1-based) |
| `primitiveAt:put:` | Set element at index |
| `primitiveIdentity:` | Check object identity |
| `primitiveCCall:with:` | Call C library functions |

**Nim Integration via Primitives:**

Primitives enable calling Nim code directly from Harding:

```harding
# Call Nim primitive
String>>size <primitive primitiveStringSize>

# Wrapper with error handling
String>>at: index [
    (index < 1 or: [index > self size]) ifTrue: [
        self error: "Index out of bounds"
    ].
    ^ <primitive primitiveStringAt: index>
]
```

### Super Sends

Harding supports both unqualified and qualified super sends for method overriding.

**Unqualified Super:**

```harding
# Call parent implementation without specifying which parent
Rectangle>>area [
    ^ width * height
]

ColoredRectangle>>area [
    # Do colored rectangle specific work
    baseArea := super area.  # Calls Rectangle>>area
    ^ baseArea + colorAdjustment
]
```

**Qualified Super:**

When using multiple inheritance, specify which parent's method to call:

```harding
# Multiple inheritance scenario
A := Object derive: #() methods: #{ #foo -> [ ^ 'A' ] }
B := Object derive: #() methods: #{ #bar -> [ ^ 'B' ] }
C := Object derive: #() parents: #(A B)

# In C, call specific parent's implementation
C>>foo [
    # Explicitly call A's foo
    ^ super<A> foo, " from C"
]

C>>bar [
    # Explicitly call B's bar
    ^ super<B> bar, " from C"
]
```

### Class-Side Methods

Define methods on the class itself (analogous to static methods):

```harding
# Instance method
Person>>greet [ ^ "Hello, I am " + name ]

# Class-side method syntax using "class>>"
Person class>>newNamed: n aged: a [
    | p |
    p := self new.
    p name: n.
    p age: a.
    ^ p
]

# Usage
alice := Person newNamed: "Alice" aged: 30
```

**Alternative Pattern:**

Since classes are first-class objects, you can also define class methods by sending `selector:put:` to the class:

```harding
Person selector: #createDefault put: [
    ^ self new initialize
]
```

### Dynamic Dispatch

Send messages dynamically at runtime using `perform:` family of methods:

```harding
# Perform a selector with no arguments
obj perform: #description   # Same as: obj description

# Perform with one argument
obj perform: #at: with: 5    # Same as: obj at: 5

# Perform with two arguments
obj perform: #at:put: with: 5 with: 'value'  # Same as: obj at: 5 put: 'value'

# Dynamic method invocation
methodName := condition ifTrue: [#process] ifFalse: [#skip]
result := obj perform: methodName
```

**Use Cases:**

- Implementing proxy objects
- Message forwarding
- Building interpreters or DSLs
- Reflection-based tools

### Introspection

Inspect and query objects and classes at runtime:

**Superclass Hierarchy:**

```harding
# Get list of superclass names
Point superclassNames   # Returns array like #(Object)

# Check inheritance
obj isKindOf: Collection
obj respondsTo: #do:
```

**Root Class:**

Harding provides a `Root` class that serves as the proxy/DNU base:

```harding
# Root is the ultimate parent class
Object superclass   # nil

# Mixin is a slotless class for shared behavior
Comparable := Mixin derive: #()
```

**Object Inspection:**

```harding
obj class           # Get the class of an object
obj class name      # Get class name
obj slotNames       # Get list of instance variable names
```

## Runtime Features

### Green Threads (Processes)

Cooperative multitasking with first-class Process objects:

```harding
# Fork a new process
worker := Processor fork: [
    1 to: 10 do: [:i |
        i println
        Processor yield
    ]
]

# Process control
worker suspend
worker resume
worker terminate

# Check state
worker state    # ready, running, blocked, suspended, terminated
```

Each process has:
- Unique PID
- Name
- State tracking
- Independent execution

**Process States:**

| State | Description |
|-------|-------------|
| `ready` | Waiting for CPU time |
| `running` | Currently executing |
| `blocked` | Waiting for I/O or condition |
| `suspended` | Paused via `suspend` message |
| `terminated` | Finished execution |

**Scheduler Operations:**

```harding
# Yield CPU to another process
Processor yield

# List all processes
Scheduler listProcesses

# Get current process
Processor activeProcess

# Set process priority (higher = more CPU)
process priority: 5
```

### Stackless VM

Each Process runs in its own stackless VM, enabling:
- Lightweight processes
- Easy serialization
- Path to true parallelism

## Development Features

### REPL

Interactive development environment:

```bash
$ harding
Harding REPL (:help for commands, :quit to exit)
harding> 3 + 4
7

harding> "Hello, World!" println
Hello, World!

harding> numbers := #(1 2 3 4 5)
#(1 2 3 4 5)

harding> numbers collect: [:n | n * n]
#(1 4 9 16 25)
```

### File-Based Development

Source code lives in `.hrd` files:

```bash
# Run it
harding myprogram.hrd

# Git friendly
git add myprogram.hrd
git commit -m "Add feature"
```

### VSCode Extension

Syntax highlighting and basic IDE support:

- Syntax highlighting for `.hrd` files
- Comment toggling
- Bracket matching
- Code folding

## Standard Library

### Core Classes

**Object** - The root of all classes
- `clone`, `derive`, `class`, `isNil`
- `at:`, `at:put:`, `respondsTo:`
- `perform:`, `perform:with:`

**Block** - Closures
- `value`, `value:`, `value:value:`
- `whileTrue:`, `whileFalse:`

**Boolean** - true/false
- `ifTrue:`, `ifFalse:`, `ifTrue:ifFalse:`
- `and:`, `or:`, `not`

**Number** - Integers and floats
- Arithmetic: `+`, `-`, `*`, `/`, `//`, `\`
- Comparison: `<`, `>`, `<=`, `>=`, `=`, `==`
- `to:do:`, `to:by:do:`, `timesRepeat:`

**String** - Text
- `,` (concatenation)
- `size`, `at:`, `println`

**Collections**
- **Array** - Ordered collection `#(1 2 3)`
- **Table** - Dictionary `#{"key" -> "value"}`
- Methods: `do:`, `collect:`, `select:`, `detect:`, `inject:into:`

### Collection Examples

```harding
# Array literal
numbers := #(1 2 3 4 5)

# Table literal
scores := #{"Alice" -> 95, "Bob" -> 87}

# Iteration
numbers do: [:n | n println]

# Transformation
squares := numbers collect: [:n | n * n]

# Filter
evens := numbers select: [:n | (n % 2) = 0]

# Reduce
sum := numbers inject: 0 into: [:acc :n | acc + n]

# Find
ten := numbers detect: [:n | n = 10]  # nil if not found
```

## Compilation Pipeline

```
Harding source (.hrd)
       ↓
   Parser (AST)
       ↓
   Interpreter (now)
       ↓
   Nim source (.nim) (coming)
       ↓
   C source (.c)
       ↓
   Machine code
       ↓
   Native binary
```

## Interoperability

### Nim Integration

Call Nim code directly via primitives:

```harding
# Access Nim functions
Array>>at: index <primitive primitiveAt: index>

# With validation
Array>>at: index [
    (index < 1 or: [index > self size]) ifTrue: [
        self error: "Index out of bounds"
    ].
    ^ <primitive primitiveAt: index>
]
```

**Native FFI Fields:**

Objects can hold references to Nim values through special fields:

```harding
# Objects can have native Nim backing
obj isNimProxy     # true if object wraps a Nim value
obj hardingType    # Get the Harding type name
obj nimValue       # Access the underlying Nim value
```

These fields enable seamless integration with the Nim ecosystem, allowing Harding objects to wrap Nim structs, pointers, and other native types.

### C Library Access

Through Nim's FFI:

```harding
# Can wrap C libraries
<primitive primitiveCCall: function with: args>
```


## Debugging Tools

### Log Levels

Control verbosity of execution output:

```bash
# Debug level shows detailed execution flow
harding --loglevel DEBUG script.hrd

# Available levels: DEBUG, INFO, WARN, ERROR, FATAL
harding --loglevel INFO script.hrd
```

**DEBUG level shows:**
- Each AST node being evaluated
- Message sends with receiver and selector
- Method lookups and execution
- Variable assignments and lookups
- Activation stack push/pop operations

### AST Output

View the parsed Abstract Syntax Tree before execution:

```bash
# Show AST and then execute
harding --ast script.hrd

# Combine with debug logging for full visibility
harding --ast --loglevel DEBUG script.hrd
```

The AST output shows the hierarchical structure of parsed expressions, useful for understanding how code is interpreted.

### Process Inspection

Inspect running processes:

```harding
# List all processes
Scheduler listProcesses

# Check process properties
process state      # ready, running, blocked, suspended, terminated
process pid        # Unique process ID
process name       # Process name
process priority   # Scheduling priority
```

### REPL Debugging Commands

When in the REPL, use these commands:

```
harding> :help        # Show available commands
harding> :vars        # Show current variables
harding> :quit        # Exit REPL
```

## What's Next

See [Future Plans](/docs/FUTURE.md) for:
- Compiler to Nim
- Actor-based concurrency
- GTK GUI bindings
- AI integration hooks
