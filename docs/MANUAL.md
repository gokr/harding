# Harding Language Manual

## Table of Contents

1. [Introduction](#introduction)
2. [Lexical Structure](#lexical-structure)
3. [Object System](#object-system)
4. [Multiple Inheritance](#multiple-inheritance)
5. [Methods and Message Sending](#methods-and-message-sending)
6. [Blocks and Closures](#blocks-and-closures)
7. [Control Flow](#control-flow)
8. [Exception Handling](#exception-handling)
9. [Libraries and Namespaces](#libraries-and-namespaces)
10. [Green Threads and Processes](#green-threads-and-processes)
11. [Primitives](#primitives)
12. [Smalltalk Compatibility](#smalltalk-compatibility)
13. [Grammar Reference](#grammar-reference)

---

## Introduction

Harding is a class-based Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing semantics and syntax while making pragmatic changes for a modern implementation.

### Key Features

- **Class-based object system** with multiple inheritance
- **Message-passing semantics** (unary, binary, keyword)
- **Block closures** with lexical scoping and non-local returns
- **Direct slot access** for declared instance variables (O(1) access)
- **Method definition syntax** using `>>` operator
- **Libraries** for namespace isolation and modular code organization
- **Green threads** for cooperative multitasking
- **Nim integration** via primitive syntax

### Quick Comparison with Smalltalk-80

| Feature | Smalltalk-80 | Harding |
|---------|-------------|---------|
| Object model | Classes + metaclasses | Classes only (no metaclasses) |
| Statement separator | Period (`.`) only | Period or newline |
| String quotes | Single quote (`'`) | Double quote (`"`) only |
| Class methods | Metaclass methods | Methods on class object |
| Class variables | Shared class state | Not implemented |
| Instance variables | Named slots | Indexed slots (faster) |
| Multiple inheritance | Single only | Multiple with conflict detection |
| Primitives | VM-specific | Nim code embedding |
| nil | Primitive value | Instance of UndefinedObject class |

---

## Lexical Structure

### Literals

```smalltalk
42                  # Integer
3.14                # Float
"hello"             # String (double quotes only)
#symbol             # Symbol
#(1 2 3)            # Array
#{"key" -> "value"} # Table (dictionary)
```

### Comments

```smalltalk
# This is a comment
#==== Section header
```

**Note**: Hash `#` followed by whitespace or special characters marks a comment. Double quotes are for strings, not comments.

### Symbol Literals

```smalltalk
#symbol         # Simple symbol
#at:put:        # Keyword symbol
#"with spaces"  # Symbol with spaces (double quotes)
```

### Shebang Support

Harding scripts can include shebang lines at the beginning:

```smalltalk
#!/usr/bin/env harding
# This script can be made executable and run directly
```

When the kernel executes the script, the shebang line is automatically skipped by the lexer.

### Statement Separation

Harding takes a pragmatic approach to statement separation:

```smalltalk
# Periods work (Smalltalk-compatible)
x := 1.
y := 2.

# Line endings also work (Harding-style)
x := 1
y := 2

# Mixed style is fine
x := 1.
y := 2
z := x + y.
```

**Multiline keyword messages** can span multiple lines while forming a single statement:

```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

This is parsed as: `tags isNil ifTrue: [...] ifFalse: [...]` - a single statement.

### Where Newlines Are NOT Allowed

| Construct | Multiline? | Example |
|-----------|-----------|---------|
| Binary operators | No | `x` followed by newline then `+ y` fails |
| Unary message chains | No | `obj` followed by newline then `msg` fails |
| Method selectors | No | `Class>>` followed by newline then `selector` fails |
| Keyword message chain | Yes | `obj msg1: a\n msg2: b` works |
| Statement separator | Yes | `x := 1\ny := 2` works |

---

## Script Files

Harding scripts are stored in `.hrd` or `.harding` files and executed with:

```bash
harding script.hrd
```

### Temporary Variables in Scripts

Scripts are automatically wrapped in a block, enabling Smalltalk-style temporary variable declarations at the file level:

```smalltalk
# script.hrd
| counter total |
counter := 0
total := 0
1 to: 5 do: [:i |
  counter := counter + 1
  total := total + i
]
total  "Returns 15"
```

This eliminates the need to use uppercase global variables (`Counter`, `Total`) for simple scripts.

### Execution Context

Script blocks execute with `self = nil`, following the Smalltalk workspace convention (like a do-it in a Workspace). This provides consistent behavior between the REPL and script execution.

```
# In script.hrd or REPL do-it:
self printString  "Returns: 'an UndefinedObject'"
self isNil         "Returns: true"
```

### Shebang Support

Scripts can be made executable with a shebang line:

```smalltalk
#!/usr/bin/env harding
| sum |
sum := 0
1 to: 100 do: [:i | sum := sum + i]
sum
```

```bash
chmod +x script.hrd
./script.hrd
```

---

## Object System

### Creating Classes

```smalltalk
# Create a class with instance variables (no accessors)
Point := Object derive: #(x y)

# Create a class with automatic accessors
Person := Object deriveWithAccessors: #(name age)

# Create a class with selective accessors
Account := Object derive: #(balance owner)
                       getters: #(balance owner)
                       setters: #(balance)

# Create an instance
p := Point new
p x: 100
p y: 200
```

### Instance Variables

Instance variables declared with `derive:` are accessed by name within methods:

```smalltalk
Point>>moveBy: dx and: dy [
    x := x + dx      # Direct slot access
    y := y + dy
    ^ self
]
```

### Automatic Accessor Generation

Harding provides convenience methods for generating getters and setters automatically:

#### `deriveWithAccessors:`

Creates a class and auto-generates both getters and setters for all slots:

```smalltalk
Person := Object deriveWithAccessors: #(name age)
p := Person new
p name: "Alice"    # Auto-generated setter
p age: 30          # Auto-generated setter
p name             # Auto-generated getter - returns "Alice"
p age              # Auto-generated getter - returns 30
```

For each slot `x`, two methods are generated:
- `x` - Getter method that returns the slot value
- `x:` - Setter method that takes one argument and assigns it to the slot

#### `derive:getters:setters:`

Creates a class with selective accessor generation:

```smalltalk
# Generate getters for both slots, but setter only for 'name'
Person := Object derive: #(name age)
                       getters: #(name age)
                       setters: #(name)

p := Person new
p name: "Alice"    # Works - setter generated
p name             # Works - getter generated, returns "Alice"
p age              # Works - getter generated, returns nil
p age: 30          # Error - no setter generated for 'age'
```

This is useful when you want:
- Read-only slots (include in getters but not setters)
- Write-only slots (include in setters but not getters)
- Public getters with private setters (convention: only generate setters for internal use)

#### Performance

Generated accessors use `SlotAccessNode` for O(1) direct slot access:
- Getter: Direct slot read by index
- Setter: Direct slot write by index

This provides the same performance as manually written accessor methods that use direct slot access.

### Inheritance

```smalltalk
# Single inheritance
ColoredPoint := Point derive: #(color)

# Multi-level inheritance
Shape3D := ColoredPoint derive: #(depth)
```

### Direct Slot Access

Inside methods, instance variables are accessed directly by name. This provides O(1) performance compared to named property access.

Performance comparison (per 100k ops):
- Direct slot access: ~0.8ms
- Named slot access: ~67ms
- Property bag access: ~119ms

Slot-based access is **149x faster** than property bag access.

---

## Multiple Inheritance

### Adding Parents

A class can have multiple parent classes:

```smalltalk
# Create two parent classes
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> bar [ ^ "bar2" ]

# Create a child that inherits from both
Child := Object derive: #(x)
Child addParent: Parent1
Child addParent: Parent2

# Child now has access to both foo and bar
c := Child new
c foo  # Returns "foo1"
c bar  # Returns "bar2"
```

### Conflict Detection

When adding multiple parents (via `derive:` with multiple parents or `addParent:`), Harding checks for:

**Slot name conflicts**: If any slot name exists in multiple parent hierarchies, an error is raised.

```smalltalk
Parent1 := Object derive: #(shared)
Parent2 := Object derive: #(shared)

Child := Object derive: #(x)
Child addParent: Parent1
Child addParent: Parent2  # Error: Slot name conflict
```

**Method selector conflicts**: If directly-defined method selectors conflict between parents, an error is raised.

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

Child := Object derive: #(x)
Child addParent: Parent1
Child addParent: Parent2  # Error: Method selector conflict
```

### Resolving Conflicts

To work with conflicting parent methods, override the method in the child class first, then use `addParent:`:

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

# Create child with override first
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Add conflicting parents - works because child overrides
Child addParent: Parent1
Child addParent: Parent2

(Child new foo)  # Returns "child"
```

**Note**: Only directly-defined methods on each parent are checked for conflicts. Inherited methods (like `derive:` from Object) will not cause false conflicts.

### Super Sends

Harding supports both qualified and unqualified super sends for multiple inheritance:

```smalltalk
# Unqualified super (uses first parent)
Employee>>calculatePay [
    base := super calculatePay.
    ^ base + bonus
]

# Qualified super (explicit parent selection)
Employee>>calculatePay [
    base := super<Person> calculatePay.
    ^ base + bonus
]
```

---

## Methods and Message Sending

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
```

### Method Batching (extend:)

Define multiple methods in a single block:

```smalltalk
Person extend: [
  self >> greet [ ^ "Hello, " , name ].
  self >> name: aName [ name := aName ].
  self >> haveBirthday [ age := age + 1 ]
]
```

### Class-side Methods (extendClass:)

Define factory methods on the class object:

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

### Combined Class Creation (derive:methods:)

Create a class with instance variables AND define methods in one expression:

```smalltalk
Person := Object derive: #(name age) methods: [
  self >> greet [ ^ "Hello, I am " , name ].
  self >> haveBirthday [ age := age + 1 ]
]
```

### Message Sending

```smalltalk
# Unary (no arguments)
obj size
obj class

# Binary (one argument, operator)
3 + 4
5 > 3
"a" , "b"          # String concatenation

# Keyword (one or more arguments)
dict at: key put: value
obj moveBy: 10 and: 20
```

### Cascading

Send multiple messages to the same receiver:

```smalltalk
obj
  at: #x put: 0;
  at: #y put: 0;
  at: #z put: 0
```

### Return Values

Use `^` (caret) to return a value:

```smalltalk
Point>>x [ ^ x ]
```

If no `^` is used, the method returns `self`.

### Dynamic Message Sending (perform:)

Send messages dynamically using symbols:

```smalltalk
obj perform: #clone                    # Same as: obj clone
obj perform: #at:put: with: #x with: 5  # Same as: obj at: #x put: 5
```

---

## Blocks and Closures

### Basic Syntax

```smalltalk
# Block with no parameters
[ statements ]

# Block with parameters
[ :param | param + 1 ]

# Block with temporaries
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := temp1 + 1 ].

# Block with parameters and temporaries
[ :param1 :param2 | temp1 temp2 | code ]
```

The `|` separator marks the boundary between parameters/temporaries and the body.

**Harding-specific feature**: Unlike most Smalltalk implementations, Harding allows you to omit the `|` when a block has parameters but no temporaries:

```smalltalk
# Harding - valid and concise
[ :x | x * 2 ]

# Traditional style also works
[ :x | | x * 2 ]
```

### Lexical Scoping

Blocks capture variables from their enclosing scope:

```smalltalk
value := 10
block := [ value + 1 ]  # Captures 'value'
block value             # Returns 11
```

### Mutable Shared State

Blocks that capture the same variable share access to it:

```smalltalk
makeCounter := [ |
  count := 0.
  ^[ count := count + 1. ^count ]
].

counter := makeCounter value.
counter value.  # Returns 1
counter value.  # Returns 2
counter value.  # Returns 3
```

### Block Invocation

Blocks are invoked via the `value:` message family:

- `value` - invoke with no arguments
- `value:` - invoke with 1 argument
- `value:value:` - invoke with 2 arguments
- etc.

### Non-Local Returns

Use `^` within a block to return from the enclosing method:

```smalltalk
findFirst: [ :arr :predicate |
  1 to: arr do: [ :i |
    elem := arr at: i.
    (predicate value: elem) ifTrue: [ ^elem ]  "Returns from findFirst:"
  ].
  ^nil
]
```

---

## Control Flow

### Conditionals

```smalltalk
(x > 0) ifTrue: ["positive"] ifFalse: ["negative"]

(x isNil) ifTrue: ["nil"]
```

### Loops

```smalltalk
# Times repeat
5 timesRepeat: [Stdout writeline: "Hello"]

# To:do:
1 to: 10 do: [:i | Stdout writeline: i]

# To:by:do:
10 to: 1 by: -1 do: [:i | Stdout writeline: i]

# While
[condition] whileTrue: [body]
[condition] whileFalse: [body]

# Repeat
[body] repeat           # Infinite loop
[body] repeat: 5        # Repeat N times
```

### Iteration

```smalltalk
# Do: - iterate over collection
collection do: [:each | each print]

# Collect: - transform each element
collection collect: [:each | each * 2]

# Select: - filter elements
collection select: [:each | each > 5]

# Detect: - find first matching
collection detect: [:each | each > 5]

# Inject:into: - fold/reduce
[1, 2, 3, 4] inject: 0 into: [:sum :each | sum + each]
```

---

## Exception Handling

Harding provides exception handling through the `on:do:` mechanism:

### Basic Syntax

```smalltalk
[ protectedBlock ] on: ExceptionClass do: [ :ex | handlerBlock ]
```

Example:
```smalltalk
[ "Hello" / 3 ] on: Error do: [ :ex |
    Transcript showCr: "Error occurred: " + ex message
]
```

### Exception Objects

When caught, exception objects have:
- `message` - The error message string
- `stackTrace` - String representation of the call stack

```smalltalk
[ riskyOperation ] on: Error do: [ :ex |
    Transcript showCr: "Message: " + ex message.
    Transcript showCr: "Stack: " + ex stackTrace
]
```

### Raising Exceptions

Use `error:` to raise an exception:

```smalltalk
someCondition ifTrue: [
    Error error: "Something went wrong"
]
```

### Differences from Smalltalk

| Feature | Harding | Smalltalk |
|---------|------|-----------|
| Implementation | Built on Nim exceptions | Custom VM mechanism |
| Stack unwinding | Immediate (Nim default) | Immediate |
| Resume capability | No | Yes |

Harding trades Smalltalk's advanced features (resumable exceptions) for seamless integration with Nim's ecosystem.

---

## Libraries and Namespaces

Harding provides a Library class for organizing code into isolated namespaces. Libraries allow you to group related classes and avoid polluting the global namespace.

### Creating Libraries

```smalltalk
# Create a new library
MyLib := Library new.

# Add bindings (classes, constants, etc.)
MyLib at: "MyClass" put: SomeClass.
MyLib at: "Constant" put: 42.

# Retrieve bindings
MyLib at: "Constant"           # Returns 42
MyLib includesKey: "MyClass"   # Returns true
MyLib keys                     # Returns array of all binding names
```

### Loading Code into Libraries

The `Library>>load:` message loads a file and captures new global definitions into the library's bindings, rather than polluting the global namespace:

```smalltalk
# mylib.hrd - defines classes like MyClass, UtilityClass, etc.
MyLib := Library new.
MyLib load: "mylib.hrd"

# The classes from mylib.hrd are in MyLib's bindings
MyLib at: "MyClass"             # Returns the class
MyLib at: "UtilityClass"        # Returns the class

# They are NOT in the global namespace
Harding includesKey: "MyClass"  # Returns false
```

### Importing Libraries

Import a library to make its bindings accessible for name resolution:

```smalltalk
MyLib := Library new.
MyLib load: "mylib.hrd"
Harding import: MyLib

# Now classes from MyLib are accessible by name
Instance := MyClass new.
Value := UtilityClass doSomething.
```

### Variable Lookup Order

When resolving a variable name, Harding searches in this order:

1. **Local scope** (temporaries, captured variables)
2. **Activation chain** (method locals)
3. **Imported Libraries** (most recent first)
4. **Global table** (fallback)

Most recently imported libraries take precedence for conflict resolution:

```smalltalk
Lib1 := Library new.
Lib1 at: "SharedKey" put: 1.

Lib2 := Library new.
Lib2 at: "SharedKey" put: 2.

Harding import: Lib1.
Harding import: Lib2.

SharedKey  # Returns 2 (Lib2 was imported last)
```

### The Standard Library

The Standard Library is pre-loaded with common classes and utilities:

```smalltalk
Standard load: "lib/core/Collections.hrd"      # Set
Standard load: "lib/core/Interval.hrd"         # Interval
Standard load: "lib/core/Exception.hrd"        # Exception hierarchy
```

The Standard Library is automatically imported at startup, so these classes are accessible by default:

```smalltalk
Set new                # Set collection (from Standard)
1 to: 10               # Interval (from Standard)
Error error: "oops"    # Exception class (from Standard)
```

### Loading Code into Global Scope

To load code directly into the global namespace (for method extensions, etc.):

```smalltalk
 Harding load: "lib/core/Object.hrd"
```

This is used in `lib/core/Bootstrap.hrd` to load core method extensions before loading new classes into the Standard Library.

---

## Green Threads and Processes

Harding supports cooperative green processes:

### Forking Processes

```smalltalk
# Fork a new process
process := Processor fork: [
    1 to: 10 do: [:i |
        Stdout writeline: i
        Processor yield
    ]
]
```

### Process Control

```smalltalk
# Process introspection
process pid               # Process ID
process name              # Process name
process state             # State: ready, running, blocked, suspended, terminated

# Process control
process suspend
process resume
process terminate

# Yield current process
Processor yield
```

### Process States

- `ready` - Ready to run
- `running` - Currently executing
- `blocked` - Blocked on synchronization
- `suspended` - Suspended for debugging
- `terminated` - Finished execution

### Current Status

**Implemented:**
- Basic process forking with `Processor fork:`
- Explicit yield with `Processor yield`
- Process state introspection (pid, name, state)
- Process control (suspend, resume, terminate)
- Shared globals via `Harding` GlobalTable for inter-process communication

**Synchronization Primitives:**
- Monitor - Mutual exclusion with condition variables
- SharedQueue - Producer-consumer communication
- Semaphore - Counting and binary locks

See examples in lib/core/Monitor.hrd, lib/core/SharedQueue.hrd, and lib/core/Semaphore.hrd

All processes share the same globals and class hierarchy, enabling inter-process communication.

---

## Primitives

Harding provides a unified syntax for direct primitive invocation.

### Unified Syntax

Both declarative and inline forms use the same keyword message syntax:

```smalltalk
# No arguments
<primitive primitiveClone>

# One argument
<primitive primitiveAt: key>

# Multiple arguments
<primitive primitiveAt: key put: value>
```

### Declarative Form

Use `<<primitive>>` as the entire method body when a method's sole purpose is to invoke a primitive. Argument names in the primitive tag MUST match the method parameter names exactly, in the same order.

```smalltalk
# No arguments
Object>>clone <primitive primitiveClone>

# One argument - parameter name 'key' must match
Object>>at: key <primitive primitiveAt: key>

# Multiple arguments - parameter names must match
Object>>at: key put: value <primitive primitiveAt: key put: value>
```

### Inline Form

Use `<<primitive>>` within a method body when you need to execute Harding code before or after the primitive call. Arguments can be any variable reference: method parameters, temporaries, slots, or computed values.

```smalltalk
# Validation before primitive
Array>>at: index [
  (index < 1 or: [index > self size]) ifTrue: [
    self error: "Index out of bounds: " + index asString
  ].
  ^ <primitive primitiveAt: index>
]

# Using temporary variable
Object>>double [
  | temp |
  temp := self value.
  ^ <primitive primitiveAt: #value put: temp * 2>
]
```

### Benefits

1. **Single syntax to learn** - No confusing distinction between `primitive:>` and `primitive`
2. **Explicit arguments** - Arguments are visible in both declarative and inline forms
3. **Consistent with Smalltalk** - Uses keyword message syntax everywhere
4. **Better validation** - Argument names and counts are validated for declarative forms
5. **More efficient** - Bypasses `perform:` machinery

### Validation Rules

For declarative primitives:
- Argument names in the primitive tag must match method parameter names exactly
- Argument order must match parameter order
- Argument count must match the number of colons in the primitive selector

---

## Smalltalk Compatibility

### Syntactic Differences

#### Statement Separation

**Smalltalk:**
```smalltalk
x := 1.
y := 2.
```

**Harding:**
```smalltalk
x := 1.
y := 2.
# OR
x := 1
y := 2
```

#### String Literals

**Smalltalk:**
```smalltalk
'Hello World'       "Single quotes"
```

**Harding:**
```smalltalk
"Hello World"       "Double quotes only"
```

**Note**: Single quotes are reserved for future use.

#### Comments

**Smalltalk:**
```smalltalk
"Double quotes for comments"
```

**Harding:**
```smalltalk
# Hash for comments
```

### Semantic Differences

#### No Metaclasses

**Smalltalk:** Every class is an instance of a metaclass.

**Harding:** Classes are objects, but there are no metaclasses. Class methods are stored directly on the class object.

```smalltalk
# Instance method
Person>>greet [ ^ "Hello" ]

# Class method (no metaclass needed)
Person class>>newPerson [ ^ self new ]
```

#### Multiple Inheritance

Harding supports multiple inheritance with conflict detection, unlike Smalltalk's single inheritance.

```smalltalk
Child := Object derive: #(x)
Child addParent: Parent1
Child addParent: Parent2
```

#### Primitives

**Smalltalk:** Primitives are VM-specific numbered operations.

**Harding:** Primitives embed Nim code directly using unified syntax.

```smalltalk
Object>>at: key <primitive primitiveAt: key>
```

#### nil as UndefinedObject

**Smalltalk:** `nil` is a special primitive value.

**Harding:** `nil` is a singleton instance of `UndefinedObject`:

```smalltalk
nil class           # Returns UndefinedObject
nil isNil           # Returns true
```

### Compiler (Granite)

Harding includes a compiler called Granite that can build Harding applications into native binaries:

```smalltalk
# Create an application
MyApp := Application derive: #().
MyApp>>main: args [
    Stdout writeLine: "Hello from compiled app!".
    Stdout writeLine: ("2 + 3 = ", (2 + 3) asString).
    ^0
].

# Build it
app := MyApp new.
app name: "myapp".
Granite build: app
```

The compiler:
- Collects transitive class dependencies
- Generates Nim code from Harding AST
- Compiles method bodies to Nim procedures
- Compiles to native binary using Nim compiler

**Note:** The `main: args` method accepts an array parameter, but command-line arguments from the OS are not yet passed (currently receives empty array).

Build with granite support:
```bash
nim c -d:granite -o:harding_granite src/harding/repl/harding.nim
```

### Missing Features

Several Smalltalk-80 features are not implemented:

1. **Class Variables** - Use globals or closures as workarounds
2. **Class Instance Variables** - Not implemented
3. **Pool Dictionaries** - Use global tables or symbols
4. **Method Categories** - Methods stored in flat table
5. **Change Sets** - File-based source with git
6. **Refactoring Tools** - Basic text editing only
7. **Debugger** - Basic error messages only

---

## Grammar Reference

### Precedence and Associativity

| Precedence | Construct | Associativity |
|------------|-----------|---------------|
| 1 (highest) | Primary expressions (literals, `()`, blocks) | - |
| 2 | Unary messages | Left-to-right |
| 3 | Binary operators | Left-to-right |
| 4 | Keyword messages | Right-to-left (single message) |
| 5 (lowest) | Cascade (`;`) | Left-to-right |

### Operators

```smalltalk
# Binary operators
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
"a" , "b"        # String concatenation
"Value: " , 42    # Auto-converts to string: "Value: 42"
a & b            # Logical AND
a | b            # Logical OR
```

---

## Collections

### Arrays

```smalltalk
# Create array
arr := #(1 2 3)
arr := Array new: 5     # Empty array with 5 slots

# Access (1-based indexing)
arr at: 1               # First element
arr at: 1 put: 10       # Set first element

# Methods
arr size                # Number of elements
arr add: 4              # Append element
arr join: ","           # Join with separator
```

### Tables (Dictionaries)

```smalltalk
# Create table
dict := #{"key" -> "value", "foo" -> "bar"}

# Access
dict at: "key"
dict at: "newKey" put: "newValue"

# Methods
dict keys               # All keys
dict includesKey: "key" # Check if key exists
```

---

## For More Information

- [QUICKREF.md](QUICKREF.md) - Quick syntax reference
- [GTK.md](GTK.md) - GTK integration and GUI development
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - VM internals and architecture
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage and debugging
- [FUTURE.md](FUTURE.md) - Future plans and roadmap
- [VSCODE.md](VSCODE.md) - VSCode extension
- [research/](research/) - Historical design documents
