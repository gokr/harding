# Nimtalk Language Specification

Nimtalk is a class-based Smalltalk dialect that compiles to Nim code. This document specifies the complete language syntax, semantics, and behavior.

## Overview

Nimtalk combines Smalltalk's message-passing semantics with Nim's compilation and performance characteristics. Key features include:

- Class-based object system with multiple inheritance
- Message-passing semantics (unary, binary, keyword)
- Block closures with lexical scoping
- Direct slot access for declared instance variables (O(1) access)
- Method definition syntax using `>>` operator
- `self` and `super` keywords for method dispatch
- Merged method tables for fast O(1) method lookup
- Symbol canonicalization for identity-based method lookup

## Lexical Structure

### Literals

```nimtalk
42              # Integer literal
3.14            # Float literal
'hello'         # String literal (single quotes)
'\n'            # Escape sequences (\n, \t, \r, \', \\\)
```

**Note**: Double quotes are used for comments.

### Symbols

```nimtalk
#symbol         # Symbol literal
#'with spaces'  # Symbol with spaces (single quotes)
```

### Comments

```nimtalk
"This is a comment - double quotes for comments"
"==== Section header
"---------- Also works with dashes
```

**Note**: Double quotes mark comments. Hash `#` followed by whitespace or special characters (`=`, `-`, `*`, `/`, `.`, `|`, `&`, `@`, `!`) also marks a comment for section headers.

### Arrays and Tables

```smalltalk
#(1 2 3)                    # Array literal (ordered collection)
#{'key' -> 'value'}        # Table literal (key-value pairs)
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
'a' , 'b'        # String concatenation (comma operator)
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
- `Nil` - Absence of value

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

# Access via automatically generated accessors
person := Person new.
person name: 'Alice'.       # Generated setter
result := person name       # Generated getter
```

### Inheritance

```smalltalk
# Single inheritance
Employee := Person derive: #(salary department)

# Multi-level inheritance
Manager := Employee derive: #(teamSize)

# Multiple inheritance (traits pattern)
Enumerable := Object derive: #().
Employee := Person derive: #(salary) withParents: #(Enumerable)
```

## Methods

### Method Definition (>> Syntax)

```smalltalk
# Unary method
Person>>greet [ ^ 'Hello, ' , name ]

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
p := Person newNamed: 'Alice' aged: 30
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

1. Look up selector in `instance.proto.allMethods`
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
- Come BEFORE any statements or comment strings
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
(x > 0) ifTrue: [ 'positive' ] ifFalse: [ 'negative' ]

# While loop
[ x < 10 ] whileTrue: [ x := x + 1 ]

# Until loop
[ x >= 10 ] whileFalse: [ x := x + 1 ]
```

**Multiline keyword messages are supported:**

```smalltalk
tags isNil
  ifTrue: [ ^ 'Object' ]
  ifFalse: [ ^ tags first ]
```

See [NEWLINE_RULES.md](NEWLINE_RULES.md) for complete newline handling rules.

## Assignment

```smalltalk
x := 42
name := 'Alice'
obj := Object derive
```

## Built-in Messages

### Object

- `derive` - Create a new class
- `derive: #(ivar1 ivar2)` - Create with declared instance variables
- `at: "key"` - Get property
- `at: "key" put: value` - Set property (only on Dictionary)

### Boolean

- `ifTrue: [block]` - Execute block if true
- `ifFalse: [block]` - Execute block if false
- `ifTrue: [a] ifFalse: [b]` - Conditional

### Collection Messages

- `at: index` - Get element
- `do: [ :each | ... ]` - Iterate
- `select: [ :each | ... ]` - Filter
- `collect: [ :each | ... ]` - Transform

## Execution Models

### Interpreter

AST-based interpreter for REPL and development:
- Parses source to Abstract Syntax Tree
- Evaluates AST nodes dynamically
- Provides live programming experience

### Compiler

Translates Nimtalk to Nim source:
- Generates Nim procedures for methods
- Inline optimization for known operations
- Compiles to native binaries

## Tooling

### Command-Line

```bash
ntalk                  # Interactive REPL
ntalk script.nt        # Run script
ntalk -e "3 + 4"       # Evaluate expression
ntalk --ast script.nt  # Show AST
ntalk --loglevel DEBUG # Debug output
```

### Logging

Both `ntalk` and `ntalkc` support `--loglevel`:
- `DEBUG` - Detailed execution trace
- `INFO` - General information
- `WARN` - Warnings only
- `ERROR` - Errors only (default)

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
- `NIMTALK-NEW-OBJECT-MODEL.md` - Object model design
- `IMPLEMENTATION-PLAN.md` - Implementation roadmap
- `TOOLS_AND_DEBUGGING.md` - Debugging guide

*Last updated: 2026-01-30 (Complete specification of implemented language features)*
