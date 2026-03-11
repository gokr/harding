# Harding Language Manual

## Table of Contents

1. [Introduction](#introduction)
2. [Tooling and Execution](#tooling-and-execution)
3. [Lexical Structure](#lexical-structure)
4. [Object System](#object-system)
5. [Multiple Inheritance](#multiple-inheritance)
6. [Methods and Message Sending](#methods-and-message-sending)
7. [Blocks and Closures](#blocks-and-closures)
8. [Control Flow](#control-flow)
9. [Exception Handling](#exception-handling)
10. [Libraries and Namespaces](#libraries-and-namespaces)
11. [Green Threads and Processes](#green-threads-and-processes)
12. [Primitives](#primitives)
13. [Smalltalk Compatibility](#smalltalk-compatibility)
14. [Grammar Reference](#grammar-reference)

---

## Introduction

Harding is a class-based Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing semantics and syntax while making pragmatic changes for a modern implementation.

### Key Features

- **Class-based object system** with multiple inheritance
- **Message-passing semantics** (unary, binary, keyword)
- **Block closures** with lexical scoping and non-local returns
- **Direct slot access** for declared slots (O(1) access)
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

## Tooling and Execution

Harding includes multiple tools for different workflows:

- `harding` - REPL and script execution
- `granite` - compile Harding source to Nim/native binaries
- `harding_debug` - interpreter build with debugger server support
- `harding-lsp` - Language Server Protocol support
- `bona` - GTK-based IDE

Typical workflows:

```bash
# Interactive REPL
harding

# Run a script
harding script.hrd

# Run a script with runtime arguments
harding script.hrd -- one two three

# Compile and run natively
granite run script.hrd --release
```

For full command options and debugging workflows, see [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md).

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

Shebang lines are supported for executable scripts. See [Script Files](#script-files) for details.

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
# Create a class with slots (no accessors)
Point := Object derive: #(x y)

# Create a class with automatic accessors (legacy API)
Person := Object deriveWithAccessors: #(name age)

# Create a class with public slots (auto accessors + :: access)
Person := Object derivePublic: #(name age)

# Canonical form with explicit read/write slot lists (v0.8.0+)
Account := Object derive: #(balance owner)
                       read: #(balance owner)
                       write: #(balance)

# With multiple inheritance (v0.8.0+)
ColoredPoint := Object derive: #(color x y)
                       read: #(color x y)
                       write: #(color x y)
                       superclasses: #(Point)

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

### Mixins

Mixin is a slotless class designed for behavior composition. It derives from Root (alongside Object) and carries no slots, which avoids diamond-problem conflicts when mixed into other classes.

```smalltalk
# Create a mixin
Comparable := Mixin derive

# Add methods to it
Comparable >> < other [ ^ (self compareTo: other) < 0 ]
Comparable >> > other [ ^ (self compareTo: other) > 0 ]
Comparable >> between: min and: max [
    ^ (self >= min) and: [ self <= max ]
]

# Mix into any class
Point := Object derive: #(x y)
Point addSuperclass: Comparable

# Implement the required method
Point >> compareTo: other [
    ^ ((x * x) + (y * y)) - ((other x * other x) + (other y * other y))
]

# Now Point supports <, >, between:and:, etc.
```

#### Class Hierarchy

Harding has a three-tier class hierarchy rooted in `Root`:

```
Root (top - zero methods, used for DNU proxies/wrappers)
  ├── Object    # The "working" base class with all standard methods
  │     └── All regular classes (String, Integer, Array, etc.)
  │
  └── Mixin     # Slotless sibling for behavior composition (no slots)
        └── Mixins like Comparable, Iterable, Printable
```

- **Root**: The absolute base of the hierarchy. Has zero methods. Only used internally for DNU proxies and as the parent of Object and Mixin.
- **Object**: The standard base class for all regular classes. Provides methods like `clone`, `printString`, `initialize`, `=`, `==`, etc.
- **Mixin**: A special sibling to Object for behavior composition. Can be added to any class via `addSuperclass:` without affecting instance type.

#### Built-in Mixins

The core and process libraries provide these mixins in `lib/core/Comparable.hrd`, `lib/core/Equatable.hrd`, `lib/core/Iterable.hrd`, `lib/core/Printable.hrd`, and `lib/process/Synchronizable.hrd`:

| Mixin | Requires | Provides |
|-------|----------|----------|
| `Comparable` | `compareTo:` | `<`, `<=`, `>`, `>=`, `between:and:`, `min:`, `max:`, `clampTo:max:` |
| `Equatable` | `compareTo:` | `=`, `~=` |
| `Iterable` | `do:` | `collect:`, `select:`, `reject:`, `detect:`, `inject:into:`, `anySatisfy:`, `allSatisfy:`, `noneSatisfy:`, `count:`, `sum` |
| `Printable` | `printOn:` | `printString`, `print`, `printCr`, `displayString` |
| `Synchronizable` | — | `critical:`, `acquire`, `release` |

**Combining Comparable and Equatable**: Use both mixins together when you need both ordering and equality. Comparable provides ordering operators (`<`, `>`, etc.) while Equatable provides equality operators (`=`, `~=`). Both require `compareTo:` to be implemented.

#### Using Multiple Mixins

```smalltalk
# Combine several mixins
MyCollection := Object derive: #(items)
MyCollection addSuperclass: Iterable
MyCollection addSuperclass: Printable

MyCollection >> do: block [
    items do: block
]

MyCollection >> printOn: stream [
    stream show: "MyCollection(".
    stream show: items size printString.
    stream show: " items)"
]
```

### Direct Slot Access

Inside methods, slots are accessed directly by name. This provides O(1) performance compared to named property access.

Performance comparison (per 100k ops):
- Direct slot access: ~0.8ms
- Named slot access: ~67ms
- Property bag access: ~119ms

Slot-based access is **149x faster** than property bag access.

### Named Access Syntax (::)

The `::` operator provides direct O(1) access to slots, table entries, and library bindings without method call overhead.

#### Slot Access

For slots declared in the `read:` or `write:` lists (or all slots with `derivePublic:`):

```smalltalk
# Reading slots
name := person::name
x := point::x

# Writing slots (only if declared writable)
person::name := "Alice"
point::x := 100

# Inside methods - direct slot access (no :: needed)
Person>>haveBirthday [
    age := age + 1    # Direct slot access within the class
]
```

#### Table/Dictionary Access

```smalltalk
table := #{"name" -> "Alice", "age" -> 30}

# Reading
name := table::name
age := table::"age"    # String keys work too

# Writing
table::name := "Bob"
table::city := "NYC"   # Creates new key if doesn't exist
```

#### Library Binding Access

```smalltalk
MyLib := Library new.
MyLib at: "MyClass" put: SomeClass.

# Access binding directly
cls := MyLib::MyClass
```

#### Benefits

1. **Performance**: O(1) direct access without method dispatch
2. **Conciseness**: `obj::slot` vs `obj slot` or `obj slot: value`
3. **Flexibility**: Works for slots, tables, and libraries uniformly

#### Canonical Derive APIs (v0.8.0+)

The canonical form for class creation uses explicit read/write slot lists:

```smalltalk
# All slots readable and writable (equivalent to derivePublic:)
Person := Object derive: #(name age)
                       read: #(name age)
                       write: #(name age)

# Read-only age, read-write name
Person := Object derive: #(name age)
                       read: #(name age)
                       write: #(name)

# With multiple inheritance
Child := Object derive: #(x)
                       read: #(x)
                       write: #(x)
                       superclasses: #(Parent1 Parent2)
```

**Note**: `derivePublic:` is shorthand for `derive:read:write:` with all slots in both lists.

### The Class Object

In Harding, **Class** is a regular class just like any other. It exists as a global binding and provides class-related functionality, but unlike Smalltalk-80, there are no metaclasses.

#### What is Class?

**Class** is the class that describes class objects themselves:

```smalltalk
Object class           # Returns: Object (a class)
Object class class     # Returns: Object (still Object, not a metaclass)

# Class is accessible as a global
Class                    # Returns: the Class class
Harding at: "Class"      # Also returns: the Class class
```

#### How Classes Work

Unlike Smalltalk-80 where every class is an instance of a unique metaclass, in Harding:

1. **Classes are objects** - They can receive messages and have methods
2. **No metaclasses** - Classes are not instances of Class; they are their own class
3. **Class methods** are stored directly on the class object itself

```smalltalk
# In Smalltalk-80:
#   Object is an instance of Object class (a metaclass)
#   Object class is an instance of Metaclass
#
# In Harding:
#   Object is a class object
#   Object's class is Object itself (not a separate metaclass)
#   Class methods are stored on Object directly
```

#### Class vs Instance Methods

Class methods (factory methods) are defined using `class>>` syntax but are simply methods on the class object:

```smalltalk
# Instance method - sent to instances
Person>>greet [ ^ "Hello, " , name ]

# Class method - sent to the class itself
Person class>>newNamed: aName [
    | person |
    person := self new.    # self is the Person class here
    person name: aName.
    ^ person
]
```

#### Why No Metaclasses?

Harding simplifies the object model by eliminating metaclasses:

1. **Simpler mental model** - Classes are objects with methods, period
2. **No metaclass explosion** - Creating a class doesn't create a parallel metaclass hierarchy
3. **Easier implementation** - No need to manage metaclass lifecycles

The trade-off is that you cannot override class behavior per-class (like you could with metaclasses in Smalltalk), but this is rarely needed in practice.

#### Class Introspection

While `isKindOf: Class` doesn't work as you might expect from Smalltalk (since classes aren't instances of Class), you can check if something is a class using:

```smalltalk
# Check if a value is a class by checking if it's in the global namespace
# and behaves like a class (can create instances, has methods, etc.)

# Get class name
Object className      # Returns: "Object"

# Check class relationship
obj isKindOf: Object  # Returns: true if obj inherits from Object
```

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
Child addSuperclass: Parent1
Child addSuperclass: Parent2

# Child now has access to both foo and bar
c := Child new
c foo  # Returns "foo1"
c bar  # Returns "bar2"
```

### Conflict Detection

When adding multiple parents (via `derive:` with multiple parents or `addSuperclass:`), Harding checks for:

**Slot name conflicts**: If any slot name exists in multiple parent hierarchies, an error is raised.

```smalltalk
Parent1 := Object derive: #(shared)
Parent2 := Object derive: #(shared)

Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2  # Error: Slot name conflict
```

**Method selector conflicts**: If directly-defined method selectors conflict between parents, an error is raised.

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2  # Error: Method selector conflict
```

### Resolving Conflicts

To work with conflicting parent methods, override the method in the child class first, then use `addSuperclass:`:

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

# Create child with override first
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Add conflicting parents - works because child overrides
Child addSuperclass: Parent1
Child addSuperclass: Parent2

(Child new foo)  # Returns "child"
```

**Note**: Only directly-defined methods on each parent are checked for conflicts. Inherited methods (like `derive:` from Object) will not cause false conflicts.

### Method Lookup Order (v0.8.0+)

As of v0.8.0, multiple inheritance uses **first-parent-wins** lookup order instead of failing on conflicts:

1. The class's own methods
2. First parent's methods (and its parents)
3. Second parent's methods (and its parents)
4. And so on...

If the same method exists in multiple parents, the first parent's version is used. A warning is printed for conflicting selectors.

```smalltalk
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "parent1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "parent2" ]

# No error - first parent wins
Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2

(Child new foo)  # Returns "parent1" (with warning about conflict)
```

To explicitly select which parent's method to use, define an override or use qualified super sends.

### Conflict Reflection (v0.8.0+)

Query selector conflicts programmatically:

```smalltalk
# Get conflicting selectors between this class and all parents
conflicts := Child conflictSelectors

# Get conflicting selectors with a specific parent class
conflicts := Child classConflictSelectors: Parent2
```

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

Create a class with slots AND define methods in one expression:

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
#(1 2 3 4) inject: 0 into: [:sum :each | sum + each]
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

Use `signal:` to raise an exception:

```smalltalk
someCondition ifTrue: [
    Error signal: "Something went wrong"
]
```

### Arithmetic Exceptions

Division by zero signals a `DivisionByZero` exception:

```smalltalk
# Integer division
result := [ 10 // 0 ] on: DivisionByZero do: [ :ex |
    ex resume: 0  # Return 0 instead
]

# Float division
result := [ 10.0 / 0.0 ] on: DivisionByZero do: [ :ex |
    "Cannot divide by zero!" println
    ex resume: 42
]
```

### Resumable Exceptions

Harding supports Smalltalk-style resumable exceptions. When an exception is signaled, the signal point is preserved so execution can be resumed from the handler:

```smalltalk
[ Error signal: "recoverable" ] on: Error do: [ :ex |
    ex resume          # Resume from signal point, signal returns nil
]

[ Error signal: "recoverable" ] on: Error do: [ :ex |
    ex resume: 42      # Resume from signal point, signal returns 42
]
```

Additional handler methods:
- `ex retry` - Re-execute the protected block from the beginning
- `ex return: value` - Return value from the `on:do:` expression
- `ex pass` - Delegate to the next matching outer handler
- `ex isResumable` - Returns true for resumable exceptions

### Uncaught Exceptions

If no handler matches, Harding runs the exception's default action, prints an uncaught-exception header and stack trace, and exits with a non-zero status.

`pass` follows the same behavior when there is no outer matching handler.

### Resumability Defaults

- `Error` and its subclasses are treated as non-resumable by default.
- `Notification` is intended for resumable signals.

### Signal Point Inspection

For debugging, exception handlers can inspect the signal point:

```smalltalk
[ Error signal: "oops" ] on: Error do: [ :ex |
    ex signaler                   # The object that signaled the exception
    ex signalContext              # The activation context at signal point
    ex signalActivationDepth      # Activation stack depth at signal point
]
```

### Ensure (Finally)

`ensure:` currently runs cleanup after normal completion of the protected block:

```smalltalk
[ riskyOperation ] ensure: [ cleanup ]
```

It does not yet guarantee cleanup after Harding exceptions or non-local returns.

### Convenience Methods

```smalltalk
# ifError: catches Error and its subclasses
[ riskyOperation ] ifError: [ :ex | "fallback" ]
```

### Exception Hierarchy

```
Exception
  ├── Error
  ├── Notification          # Resumable notification (not an error)
  ├── MessageNotUnderstood
  ├── SubscriptOutOfBounds
  └── DivisionByZero
```

Parent classes catch subclass exceptions: `on: Exception do:` catches `Error`.

`Notification` is used for resumable signals that represent notifications rather than errors. Handlers can resume from a Notification to continue normal execution.

### Differences from Smalltalk

| Feature | Harding | Smalltalk |
|---------|------|-----------|
| Implementation | VM work queue (stackless) | Custom VM mechanism |
| Stack unwinding | Signal point preserved via ExceptionContext | Immediate |
| Resume capability | Yes (`resume`, `resume:`) | Yes |

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

1. **Local scope** (temporaries, captured variables, method locals)
2. **Instance variables** (slots on `self`)
3. **Imported Libraries** (most recent first)
4. **Global table** (fallback)

**Important**: Each method activation has its own isolated local scope. Methods cannot see the local variables of their calling method (unlike some dynamic languages). This prevents accidental coupling and ensures proper encapsulation.

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
Harding load: "lib/core/Set.hrd"               # Set
Harding load: "lib/core/Exception.hrd"         # Exception hierarchy
Standard load: "lib/standard/Interval.hrd"     # Interval
Standard load: "lib/standard/File.hrd"         # File convenience API
Standard load: "lib/standard/FileStream.hrd"   # Stream I/O
```

Core and Standard are loaded at startup, so these classes are accessible by default:

```smalltalk
Set new                # Set collection (from Core)
1 to: 10               # Interval (from Standard)
File readAll: "README.md"
Error error: "oops"    # Exception class (from Core)
```

Global system utilities are also available by default:

```smalltalk
System arguments        # Array of CLI args passed after '--'
System cwd              # Current working directory
System stdin            # Standard input stream
System stdout           # Stdout stream
System stderr           # Stderr stream
```

### Packaging Nim-Backed Libraries

Harding supports packaging Nim primitive implementations together with embedded `.hrd` sources.

Use this flow:

1. Define Harding-facing methods in `.hrd` using `<primitive ...>` selectors.
2. Implement the selectors in Nim and register them on the target class.
3. Bundle all package `.hrd` files as embedded strings and install them with `HardingPackageSpec`.

For a full end-to-end example, see `docs/NIM_PACKAGE_TUTORIAL.md`.

### External Libraries (v0.8.0+)

Harding includes a library management system for installing third-party packages:

#### Listing Available Libraries

```bash
harding lib list           # List available libraries from registry
harding lib fetch          # Refresh metadata from remote repositories
harding lib info mysql     # Show detailed info about a library
```

#### Installing Libraries

```bash
harding lib install mysql           # Install latest version
harding lib install mysql@1.0.0    # Install specific version
```

Libraries are installed to the `external/` directory and compiled into Harding on the next build.

#### Managing Installed Libraries

```bash
harding lib installed      # List installed libraries
harding lib update mysql   # Update a specific library
harding lib update --all   # Update all libraries
harding lib remove mysql   # Remove a library
```

#### Building with External Libraries

After installing or updating libraries:

```bash
nimble harding             # Rebuild with new libraries
```

#### Creating External Libraries

External libraries are Nim packages that extend Harding:

1. Create a Git repository named `harding-<libname>`
2. Add a `<libname>.nimble` file with metadata
3. Implement Nim primitives in `src/harding_<libname>/`
4. Create Harding classes in `lib/<libname>/`
5. Add a `lib/<libname>/Bootstrap.hrd` file

See `external/README.md` for the full specification.

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

**Harding:** Classes are objects, but there are no metaclasses. Class methods are stored directly on the class object. The global `Class` exists for introspection but classes are not instances of it.

```smalltalk
# Instance method
Person>>greet [ ^ "Hello" ]

# Class method (no metaclass needed)
Person class>>newPerson [ ^ self new ]
```

See [The Class Object](#the-class-object) section for detailed explanation.

#### Multiple Inheritance

Harding supports multiple inheritance with conflict detection, unlike Smalltalk's single inheritance.

```smalltalk
Child := Object derive: #(x)
Child addSuperclass: Parent1
Child addSuperclass: Parent2
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

Harding includes a compiler called Granite that compiles Harding source to native binaries via Nim.

#### Standalone Script Compilation

Compile any `.hrd` script directly:

```bash
# Compile to Nim source
granite compile script.hrd

# Build native binary
granite build script.hrd

# Build and run
granite run script.hrd

# Build with optimizations
granite run script.hrd --release
```

Example script (`sieve.hrd`):
```smalltalk
primeCount := 0
i := 2
[ i <= 500 ] whileTrue: [
    isPrime := true
    d := 2
    [ d * d <= i ] whileTrue: [
        (i \\ d = 0) ifTrue: [
            isPrime := false
            d := i
        ].
        d := d + 1
    ].
    isPrime ifTrue: [
        primeCount := primeCount + 1
    ].
    i := i + 1
].
primeCount println
```

#### What Gets Compiled

The compiler generates Nim code with:
- Inline control flow: `ifTrue:`, `ifFalse:`, `whileTrue:`, `whileFalse:`, `timesRepeat:` become native Nim `if`/`while`/`for`
- Direct variable access (no hash table lookups for local variables)
- Runtime value boxing via `NodeValue` variant type
- Arithmetic and comparison helper functions

#### compile: and main: Blocks

Granite supports a special syntax for organizing compiled code:

```harding
Harding compile: [
    # Class and method definitions go here
    Dog := Object deriveWithAccessors: #(name age)
    Dog>>bark [ ^ "Woof!" ]
]

Harding main: [
    # Runtime code goes here  
    dog := Dog new
    dog name: "Buddy"
    dog bark println
]
```

**How it works:**

- `Harding compile:` - Code that runs at compile time to define classes and methods. These definitions are included in the generated Nim code.
- `Harding main:` - Code that becomes the main() procedure (executed at runtime).

**Why use this?**

1. **Organization** - Separates class definitions from runtime code
2. **Clarity** - Makes it explicit what's compile-time vs runtime
3. **Multiple inheritance** - Shows the order of addSuperclass: calls clearly

**Backward compatible:** You can also write without these blocks - all top-level code becomes main().

**Interpreter behavior:** In the interpreter, both `Harding compile:` and `Harding main:` evaluate their block immediately (normal block semantics).

**Granite behavior:** In Granite, `Harding compile:` is executed during compilation to construct classes/methods, while `Harding main:` is compiled into generated `main()` and executed at program runtime.

#### Application Class (In-VM)

For building applications from within the Harding VM:

```smalltalk
MyApp := Application derive: #()
MyApp>>main: args [
    Stdout writeline: "Hello from compiled app!"
    ^0
]

app := MyApp new
app name: "myapp"
Granite build: app
```

`args` receives host command-line arguments in both interpreter and compiled execution paths.

#### Performance

Compiled code runs significantly faster than interpreted. On a sieve of Eratosthenes benchmark (primes up to 5000):

| Mode | Time | Speedup |
|------|------|---------|
| Interpreter (debug) | ~23s | 1x |
| Interpreter (release) | ~2.3s | 10x |
| Compiled (release) | ~0.01s | 2300x |

#### Current Limitations

- First-class blocks (blocks assigned to variables or passed as arguments) are not yet compiled
- Non-local returns (`^`) from blocks are not yet supported in compiled code
- Class/method compilation from in-VM code is in progress

### Missing Features

Several Smalltalk-80 features are not implemented:

1. **Class Variables** - Use globals or closures as workarounds
2. **Class Instance Variables** - Not implemented
3. **Pool Dictionaries** - Use global tables or symbols
4. **Method Categories** - Methods stored in flat table
5. **Change Sets** - File-based source with git
6. **Refactoring Tools** - Basic text editing only
7. **Debugger** - VSCode DAP support implemented; GTK IDE debugger in progress

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

## Built-in Types

Harding provides several built-in types that form the foundation of the object system:

### Number Hierarchy

The number hierarchy follows Smalltalk conventions with a common base class:

```
Object
  └─ Number         # Base class for all numeric types
      ├─ Integer     # Whole numbers
      └─ Float       # Floating-point numbers
```

Both `Integer` and `Float` inherit common methods from `Number`:

```smalltalk
# Common Number methods (available on both Integer and Float)
abs              # Absolute value
negated          # Negation (0 - self)
squared          # Square (self * self)
between:and:     # Check if value is in range
isZero           # Self equals 0?
isPositive       # Self > 0?
isNegative       # Self < 0?
sign             # -1, 0, or 1
```

### Integer Methods

```smalltalk
# Arithmetic
i + j
i - j
i * j
i / j            # Regular division
i // j           # Integer division
i * 1.0          # Automatic promotion to Float

# Modulo
i % j            # Modulo operator
i \ j            # Alternative modulo

# Comparison
i = j
i < j
i > j
i <= j
i >= j
i <> j           # Not equal

# Parity
i even           # Is even?
i odd            # Is odd?

# Iteration
i timesRepeat: [ :k | k printString ]   # Execute block i times
i to: 10 do: [ :k | k printString ]    # Iterate from i to 10
1 to: 10 by: 2 do: [ :k | k printString ]  # Step iteration

# Special methods
i factorial       # i!
i gcd: j          # Greatest common divisor
i lcm: j          # Least common multiple
i sqrt            # Square root (returns Float)
```

### Float Methods

```smalltalk
# Arithmetic (same operators as Integer)
f + g
f - g
f * g
f / g
f // g           # Integer division of float values

# Comparison
f = g
f < g
f > g
f <= g
f >= g
f <> g

# Special methods
f abs
f negated
f sqrt            # Square root
```

### Boolean Hierarchy

```
Object
  └─ Boolean
      ├─ True
      └─ False
```

Both `True` and `False` inherit from `Boolean`, which supports common boolean operations:

```smalltalk
b ifTrue: [ ... ]
b ifFalse: [ ... ]
b ifTrue: [ ... ] ifFalse: [ ... ]
b ifFalse: [ ... ] ifTrue: [ ... ]
b and: [ ... ]           # Logical AND with short-circuit
b or: [ ... ]            # Logical OR with short-circuit
b not                    # Negation
```

### Other Built-in Types

```smalltalk
# Strings (double quotes only)
"hello"             # String literal
str size            # Length
str at: 0           # Character at index
str1 , str2         # Concatenation

# Arrays (0-based indexing)
#(1 2 3)            # Array literal
arr at: 0           # First element
arr at: 0 put: 99   # Set element
arr size
arr add: 42

# Tables (dictionaries)
#{"a" -> 1, "b" -> 2}
dict at: "key"
dict at: "new" put: value
dict keys

# Blocks
[ :x | x + 1 ]      # Block with parameter
block value: 10     # Invoke block
[ 1 + 2 ] value     # Block with no args
```

---

## Collections

### Arrays

```smalltalk
# Create array
arr := #(1 2 3)
arr := Array new: 5     # Empty array with 5 slots

# Access (0-based indexing)
arr at: 0               # First element
arr at: 0 put: 10       # Set first element

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

### Persistent Collections (BitBarrel)

Install the external `bitbarrel` library and rebuild Harding.

**BarrelTable** - Hash-based persistent key-value storage:

```smalltalk
# Load BitBarrel library
load: "lib/bitbarrel/Bootstrap.hrd".

# Create persistent table
users := BarrelTable create: "users".
users at: 'alice' put: 'Alice Smith'.
name := users at: 'alice'.

# Collection operations
users keys.                    # All keys
users size.                    # Number of entries
users includesKey: 'alice'.    # Check existence
users removeKey: 'alice'.    # Remove entry

# Iterate
users do: [:key :value |
    Transcript showCr: key + " => " + value
].

# Select/Collect (returns in-memory Table)
adults := users select: [:key :user | (user at: 'age') >= 18].
names := users collect: [:key :user | user at: 'name'].
```

**BarrelSortedTable** - Ordered storage with range queries:

```smalltalk
# Create ordered table (uses critbit index)
logs := BarrelSortedTable create: "logs".
logs at: '2024-01-01:001' put: 'System started'.

# Range queries (returns in-memory Table)
janLogs := logs rangeFrom: '2024-01-01' to: '2024-02-01'.

# Prefix queries
day1Logs := logs prefix: '2024-01-01:'.

# Ordered access
logs first.    # First entry
logs last.     # Last entry
logs keys.     # Keys in sorted order
```

**Install BitBarrel:**

```bash
./harding lib install bitbarrel
nimble harding
```

---

## For More Information

- [QUICKREF.md](QUICKREF.md) - Quick syntax reference
- [BOOTSTRAP.md](BOOTSTRAP.md) - Bootstrap architecture and core loading
- [GTK.md](GTK.md) - GTK integration and GUI development
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - VM internals and architecture
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage and debugging
- [COMPILATION_PIPELINE.md](COMPILATION_PIPELINE.md) - Granite pipeline architecture
- [ROADMAP.md](ROADMAP.md) - Active development roadmap
- [PERFORMANCE.md](PERFORMANCE.md) - Performance workflow and priorities
- [FUTURE.md](FUTURE.md) - Future plans and roadmap
- [VSCODE.md](VSCODE.md) - VSCode extension
- [research/](research/) - Historical design documents
