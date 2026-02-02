# Nemo Language Specification

Nemo is a class-based Smalltalk dialect that compiles to Nim code. This document specifies the complete language syntax, semantics, and behavior.

## Overview

Nemo combines Smalltalk's message-passing semantics with Nim's compilation and performance characteristics. Key features include:

- Class-based object system with single inheritance (multiple parents planned)
- Message-passing semantics (unary, binary, keyword)
- Block closures with lexical scoping
- Direct slot access for declared instance variables (O(1) access)
- Method definition syntax using `>>` operator
- `self` and `super` keywords for method dispatch
- Merged method tables for fast O(1) method lookup
- Symbol canonicalization for identity-based method lookup

## Lexical Structure

### Literals

```smalltalk
42              # Integer literal
3.14            # Float literal
"hello"         # String literal (double quotes)
"\n"            # Escape sequences (\n, \t, \r, \", \\)
```

### Symbols

```smalltalk
#symbol         # Symbol literal
#"with spaces"  # Symbol with spaces (double quotes)
```

### Comments

```smalltalk
# This is a comment
#==== Section header
#---------- Also works with dashes
```

**Note**: Hash `#` followed by whitespace or special characters marks a comment.

### Arrays and Tables

```smalltalk
#(1 2 3)                    # Array literal (ordered collection)
#{"key" -> "value"}         # Table literal (key-value pairs)
```

### Identifiers

```smalltalk
variable         # Lowercase for instances
VariableName     # Capitalized for classes (convention)
_at:put:_        # Keyword method selector with colons
```

## Operators

### Binary Operators

All binary operators are implemented as message sends:

```smalltalk
3 + 4            # Addition
5 - 3            # Subtraction
x * y            # Multiplication
a / b            # Division
x > y            # Greater than
x < y            # Less than
x = y            # Assignment or value comparison
x == y           # Equality comparison
x ~= y           # Inequality
a <= b           # Less than or equal
a >= b           # Greater than or equal
a // b           # Integer division
a \ b            # Modulo
a ~~ b           # Not identity
"a" , "b"        # String concatenation (comma operator)
a & b            # Logical AND
a | b            # Logical OR
```

### Cascade Operator

The `;` operator sends multiple messages to the same receiver:

```smalltalk
obj at: #x put: 0; at: #y put: 0; at: #z put: 0.
```

### Return Operator

The `^` operator returns a value from a block or method:

```smalltalk
[obj someMessage ^ result]
```

## Types

### Object

The root type that defines structure and behavior:

- `methods: Table[string, BlockNode]` - Methods defined directly on this object
- `allMethods: Table[string, BlockNode]` - All methods including inherited (for fast lookup)
- `slotNames: seq[string]` - Slot names defined on this object
- `allSlotNames: seq[string]` - All slots including inherited (instance layout)
- `parents: seq[Object]` - Direct parent objects (for inheritance)
- `subclasses: seq[Object]` - Direct children (for efficient invalidation)
- `name: string` - Object name for debugging

### Instance

The type for object instances with pure data:

- `class: Object` - Reference to the class object
- `slots: seq[NodeValue]` - Instance data indexed by allSlotNames position


### Basic Types

- `Integer` - Signed integers
- `Float` - Floating-point numbers
- `String` - Text strings
- `Boolean` - `true` or `false`
- `Symbol` - Canonicalized identifiers
- `UndefinedObject` - The class of nil (singleton instance represents absence of value)

## Object System

### Class Creation

```smalltalk
# Class with declared instance variables
Point := Object derive: #(x y)

# Create an instance
p := Point new
```

### Instance Variable Declaration

```smalltalk
# Declare with symbol literal
Person := Object derive: #(name age address)

# Direct slot access inside methods
Person>>greet [
  ^ "Hello, " , name
]

# For external access, use at:put: on collection instances
arr := #(1 2 3).
arr at: 2 put: 42.
```

### Inheritance

```smalltalk
# Single inheritance
Employee := Person derive: #(salary department)

# Multi-level inheritance
Manager := Employee derive: #(teamSize)

# Multiple inheritance (planned)
Enumerable := Object derive: #().
Employee := Person derive: #(salary) withParents: #(Enumerable)
```

**Note**: The internal class model supports multiple parents. The first parent defines the "kind" of class (Object, Array, Number, etc.) and determines the instance representation. Additional parents act as mixins/traits and are constrained based on compatibility with the primary parent. The `withParents:` syntax is not yet implemented - currently only single inheritance works via `derive:`.

### Conflict Detection

When creating a class with multiple parents, Nemo checks for conflicts:

- **Slot name conflicts**: If any slot name exists in multiple parent hierarchies, an error is raised
- **Method selector conflicts**: If directly-defined method selectors conflict between parents, an error is raised

```smalltalk
# This will raise an error:
Parent1 := Object derive: #(shared)
Parent2 := Object derive: #(shared)
try (
  Child := Object derive: #(x) parents: #(Parent1 Parent2)
  # Error: Slot name conflict: 'shared' exists in multiple parents
) catch (:err | err printString)
```

### Adding Parents After Creation (addParent:)

The `addParent:` message allows adding a parent to an existing class. This is useful for resolving method conflicts by overriding the conflicting method first, then adding the parent:

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

# Create child with override first
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Add conflicting parents - this works because child overrides
Child addParent: Parent1
Child addParent: Parent2

(Child new foo)  # Returns "child"
```

The `addParent:` message checks for conflicts but allows them if the child class overrides the conflicting method.

**Note**: Only directly-defined methods on each parent are checked for conflicts. Inherited methods (like `derive:` from Object) will not cause conflicts.

## Methods

### Method Definition (>> Syntax)

```smalltalk
# Unary method
Person>>greet [ ^ "Hello, " , name ]

# Method with one parameter
Person>>name: aName [ name := aName ]

# Method with multiple keyword parameters
Point>>moveX: dx y: dy [
  x := x + dx.
  y := y + dy.
  ^ self
]

# Multiple methods in sequence
Person>>id [ ^ 42 ].
Person>>label: text [ text ].
```

The `>>` syntax is parsed and transformed into standard `at:put:` message sends.

### Method Definition (Standard Syntax)

```smalltalk
Person at: #greet put: [ ^ "Hello, " , name ]
Person at: #name: put: [ :aName | name := aName ]
```

### Method Batching (extend:)

Define multiple methods in a single block with rebound self:

```smalltalk
Person extend: [
  self >> greet [ ^ "Hello, " , name ].
  self >> name: aName [ name := aName ].
  self >> printString [ ^ name ]
]
```

The `extend:` method evaluates the block with `self` temporarily bound to the target object, allowing clean method batching syntax. This is equivalent to:

```smalltalk
Person asSelfDo: [
  self >> greet [ ^ "Hello, " , name ].
  ...
]
```

### Combined Class Creation (derive:methods:)

Create a class with instance variables AND define methods in one expression:

```smalltalk
Person := Object derive: #(name age) methods: [
  self >> greet [ ^ "Hello, I am " , name ].
  self >> haveBirthday [ age := age + 1 ]
]
```

This is equivalent to:

```smalltalk
Person := Object derive: #(name age).
Person extend: [
  self >> greet [ ^ "Hello, I am " , name ].
  self >> haveBirthday [ age := age + 1 ]
]
```

### Class-side Methods (extendClass:)

Define factory methods on the class object itself:

```smalltalk
Person extendClass: [
  self >> newNamed: n aged: a [
    | person |
    person := self derive.
    person name: n.
    person age: a.
    ^ person
  ]
]

# Usage
p := Person newNamed: "Alice" aged: 30
```

### Dynamic Message Sending (perform:)

Send messages dynamically using symbols:

```smalltalk
# Send message by name
obj perform: #methodName

# Send with one argument
obj perform: #method: with: arg

# Send with two arguments
obj perform: #method:with: with: arg1 with: arg2
```

The `perform:` family enables dynamic dispatch and is used internally by methods like `extend:` to invoke primitives.

### Self-Rebinding (asSelfDo:)

Evaluate a block with `self` temporarily bound to a specific object:

```smalltalk
someObject asSelfDo: [
  self doSomething.    # self is someObject here
  self at: #key put: 42
]
```

This is the primitive that enables `extend:` and other DSL patterns.

### Method Dispatch

Method lookup uses merged tables for O(1) access:

1. Look up selector in `instance.class.allMethods`
2. If not found, trigger `doesNotUnderstand:`

For class methods:
1. Look up selector in `class.allMethods` (called on the class object itself)

### Super Send

Call a parent class method explicitly:

```smalltalk
# Unqualified super (uses first parent)
Employee>>calculatePay [
    base := super calculatePay.
    ^ base + self bonus
]

# Qualified super (explicit parent selection)
Employee>>calculatePay [
    base := super<Person> calculatePay.
    ^ base + self bonus
]
```

### self and super

```smalltalk
Person>>greet [
  ^ "Hello, I'm " , name    # self is implicit for instance variables
]

Employee>>greet [
  ^ super greet , " from " , department  # Calls parent's greet
]
```

- `self` - The receiver of the message (dynamic dispatch from receiver)
- `super` - The parent of the object where the method was defined

## Blocks

### Block Syntax

```smalltalk
# No parameters
[ 1 + 2 ]

# One or more parameters
[ :x | x * 2 ]

# Multiple parameters
[ :x :y | x + y ]

# Temporary variables (variables local to the block)
[ :block | index size |
  index := 0.
  size := self size
]

# Parameters and temporaries
[ :x :y | temp1 temp2 | code ]
```

**Temporary Variables**:
- Must be declared at the BEGINNING of a block: `| temp1 temp2 |`
- Come BEFORE any statements
- Provide local variable scope within the block

### Lexical Scoping

Blocks capture variables from their enclosing scope:

```smalltalk
value := 10
block := [ value + 1 ]  # Captures 'value'
block value             # Returns 11
```

## Control Flow

Conditional execution via message sends:

```smalltalk
# If-then-else
(x > 0) ifTrue: [ "positive" ] ifFalse: [ "negative" ]

# While loop
[ x < 10 ] whileTrue: [ x := x + 1 ]

# Until loop
[ x >= 10 ] whileFalse: [ x := x + 1 ]
```

**Multiline keyword messages are supported:**

```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

See [NEWLINE_RULES.md](NEWLINE_RULES.md) for complete newline handling rules.

## Assignment

```smalltalk
x := 42
name := "Alice"
obj := Object derive
```

## Built-in Messages

### Object

- `derive` - Create a new class
- `derive: #(ivar1 ivar2)` - Create with declared instance variables
- `at: #key` - Get property
- `at: #key put: value` - Set property
- `addParent: parentClass` - Add a parent to an existing class (useful for resolving conflicts by overriding first)

### Class Methods

- `new` - Create a new instance of the class
- `selector:put:block` - Add an instance method to the class
- `classSelector:put:block` - Add a class method to the class
- `addParent:parentClass` - Add a parent to this class (allows conflict resolution with overrides)

### Boolean

- `ifTrue: [block]` - Execute block if true
- `ifFalse: [block]` - Execute block if false
- `ifTrue: [a] ifFalse: [b]` - Conditional

### Collection Messages

- `at: index` - Get element
- `do: [ :each | ... ]` - Iterate
- `select: [ :each | ... ]` - Filter
- `collect: [ :each | ... ]` - Transform

### Green Threads (Process and Processor)

- `Processor fork: [block]` - Create a new green process, returns Process object
- `Processor yield` - Yield current process to scheduler

### Process Object

- `pid` - Get process ID (integer)
- `name` - Get process name (string)
- `state` - Get process state: "ready", "running", "blocked", "suspended", "terminated"
- `suspend` - Suspend the process
- `resume` - Resume a suspended process
- `terminate` - Terminate the process
- `yield` - Yield the process (only valid for current process)

### Nemo Global (GlobalTable)

The `Nemo` object provides access to the global namespace:

- `Nemo keys` - Get array of all global variable names
- `Nemo at: "name"` - Get the value of a global variable
- `Nemo at: "name" put: value` - Set a global variable
- `Nemo includesKey: "name"` - Check if a global exists

All processes share the same global namespace via `Nemo`, enabling inter-process communication.

## Execution Models

### Interpreter

AST-based interpreter for REPL and development:
- Parses source to Abstract Syntax Tree
- Evaluates AST nodes dynamically
- Provides live programming experience

### Compiler (In Development)

Translates Nemo to Nim source:
- Generates Nim procedures for methods
- Inline optimization for known operations
- Compiles to native binaries

## Tooling

### Command-Line

```bash
nemo                  # Interactive REPL
nemo script.nemo        # Run script
nemo -e "3 + 4"       # Evaluate expression
nemo --ast script.nemo  # Show AST
nemo --loglevel DEBUG # Debug output
```

### Logging

Both `nemo` supports `--loglevel`:
- `DEBUG` - Detailed execution trace
- `INFO` - General information
- `WARN` - Warnings only
- `ERROR` - Errors only (default)

### VSCode Extension

Syntax highlighting for `.nemo` files is available via the included VSCode extension. See [VSCODE.md](VSCODE.md) for installation instructions.

## Performance

### Instance Variable Access

| Method | Performance |
|--------|-------------|
| Direct slot access | 0.8ms per 100k ops |
| Named slot access | 67ms per 100k ops |
| Property bag access | 119ms per 100k ops |

Slot-based access is **149x faster** than property bag access.

## Related Documentation

- `NEWLINE_RULES.md` - Newline handling and statement separation
- `SYNTAX-QUICKREF-updated.md` - Syntax quick reference
- `TOOLS_AND_DEBUGGING.md` - Debugging guide
- `VSCODE.md` - VSCode extension documentation
- `GREENTHREADS.md` - Green threads and concurrency
- `PRIMITIVES.md` - Primitive syntax and direct invocation
- `PERFORM.md` - Dynamic message sending with perform:
