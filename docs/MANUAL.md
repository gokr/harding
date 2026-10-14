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
14. [JSON Support](#json-support)
15. [Grammar Reference](#grammar-reference)

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

Optional builds can enable the MummyX HTTP server bridge. See [MUMMYX.md](MUMMYX.md).

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

Builds require Nim 2.2.12 (`harding.nimble` pins that version). Use that compiler
on PATH for direct builds and Granite's generated-program builds as well.

This manual describes Harding's language semantics. Granite's native backend is
still being brought into parity with the interpreter; compilation does not imply
support for every language feature. See [GRANITE_STATUS.md](GRANITE_STATUS.md)
for tested coverage and remaining gaps, including activation-specific non-local
returns, multiple inheritance, resumable exceptions, processes, and mixed mode.

For full command options and debugging workflows, see [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md).

---

## Lexical Structure

### Literals

```smalltalk
42                  # Integer
3.14                # Float
 "hello"             # String (double quotes only)
"""
  hello
  world
"""               # Triple-quoted multiline string
#symbol             # Symbol
#"""
  multi
  line
"""               # Triple-quoted multiline symbol
#(1, 2, 3)            # Array
#{"key" -> "value"} # Table (dictionary)
json{"x": 10}       # JSON literal (returns JSON string)
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
#"""
  line 1
  line 2 with "quotes"
"""            # Multiline symbol string
```

### Triple-Quoted Strings

Harding supports triple-quoted string literals using `"""..."""`.

```smalltalk
text := """
  Hello
  He said "welcome"
  Literal #{name}
  Backslash-n: \n
"""
```

Triple-quoted strings behave as follows:

- They are **raw** strings. Backslashes are preserved literally, so `\n` stays two characters.
- A single `"` inside the string does not need escaping.
- If the opening delimiter is followed immediately by a newline, that first newline is removed.
- Common indentation is stripped from all non-empty lines, making indented source blocks easier to write.
- The trailing newline before the closing delimiter is preserved.

This differs slightly from Nim: Harding matches Nim's raw triple-quoted handling for quotes and backslashes, but also strips leading indentation to make indented multiline literals easier to embed in Harding code.

### JSON Literals

Harding supports prefix JSON literals using `json{...}`:

```smalltalk
json{"x": 10, "name": "Alice"}
```

This returns a JSON string, not a Table. The prefix is case-insensitive:

```smalltalk
json{"ok": true}
Json{"ok": true}
JSON{"ok": true}
```

All three forms normalize to the `Json` class internally.

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

Script blocks execute with `self = nil`, following the Smalltalk workspace convention (like a do-it in a Workspace). A file script, the REPL, and `harding -e` all compile their top-level code as the `#doIt` method on `UndefinedObject`, so they share one rule: a lowercase top-level assignment is a local of that do-it, `| x |` temporaries are legal, and `^` returns from it. Only uppercase names are globals.

```
# In script.hrd, the REPL, or `harding -e`: `self isNil` returns true, and
# `x := 1. x println` prints 1 without declaring a global.
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
Point := Object derive: #(x, y)

# Create a class with public slots (auto accessors + :: access)
Person := Object derivePublic: #(name, age)

# Canonical form with explicit read/write slot lists (v0.8.0+)
Account := Object derive: #(balance, owner)
                       read: #(balance, owner)
                       write: #(balance)

# With multiple inheritance (v0.8.0+)
ColoredPoint := Object derive: #(color, x, y)
                       read: #(color, x, y)
                       write: #(color, x, y)
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

### Accessor Generation

Harding provides several methods for generating getters and setters:

#### `derivePublic:`

Creates a class and auto-generates both getters and setters for all slots:

```smalltalk
Person := Object derivePublic: #(name, age)
p := Person new
p name: "Alice"    # Auto-generated setter
p age: 30          # Auto-generated setter
p name             # Auto-generated getter - returns "Alice"
p age              # Auto-generated getter - returns 30
```

For each slot `x`, two methods are generated:
- `x` - Getter method that returns the slot value
- `x:` - Setter method that assigns its argument to the slot and returns the receiver

Generated accessors are ordinary methods: explicit methods can override them,
and inherited sends use ordinary method lookup. `obj::x` is separate direct
access and does not invoke an overridden `x` or `x:` method. Selective `read:` and
`write:` lists generate only the requested directions.

Executed regressions: `class_factory`, `accessor_override`, and
`selective_accessors` in `scripts/test_granite_parity.py`; compiler registration
tests also check that disallowed directions are not generated.

#### `derive:read:write:`

Creates a class with selective accessor generation:

```smalltalk
# Generate getters for both slots, but setter only for 'name'
Person := Object derive: #(name, age)
                       read: #(name, age)
                       write: #(name)

p := Person new
p name: "Alice"    # Works - setter generated
p name             # Works - getter generated, returns "Alice"
p age              # Works - getter generated, returns nil
p age: 30          # Error - no setter generated for 'age'
```

This is useful when you want:
- Read-only slots (include in read but not write)
- Write-only slots (include in write but not read)
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
Point := Object derive: #(x, y)
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
Person := Object derive: #(name, age)
                       read: #(name, age)
                       write: #(name, age)

# Read-only age, read-write name
Person := Object derive: #(name, age)
                       read: #(name, age)
                       write: #(name)

# With multiple inheritance
Child := Object derive: #(x)
                       read: #(x)
                       write: #(x)
                       superclasses: #(Parent1, Parent2)
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
Person>>greet [ ^ "Hello, " & name ]

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

`super` keeps the current receiver but starts lookup at a parent of the class
that declared the executing method, not a parent of the receiver's most-derived
class. Inherited methods retain that declaring class. Class-side `super` searches
class methods; instance-side `super` searches instance methods. Blocks preserve
the enclosing method's lexical lookup context.

The qualifier in `super<Parent>` must name a direct parent of the class that
_declared_ the method, not an unrelated class or an indirect ancestor. Lookup
then searches that parent's inherited methods. Invalid qualifiers are evaluation
errors, not catchable Harding exception signals.

Executed regressions: `inherited_super`, `block_super`, `super_new`,
`qualified_super`, `invalid_qualified_super`, and `indirect_qualified_super` in
`scripts/test_granite_parity.py`.

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
Person>>greet [ ^ "Hello, " & name ]

# Method with one parameter
Person>>name: aName [ name := aName ]

# Method with multiple keyword parameters
Point>>moveX: dx y: dy [
  x := x + dx.
  y := y + dy.
  ^ self
]
```

### Method and Block Return Values

An instance method that reaches its end without `^` answers its receiver (`self`),
not the final expression's value. This applies to empty methods, setters, literal
expressions and methods ending in handled errors or cleanup. `^ expression`
explicitly supplies the method result. Blocks without `^` instead answer their
last expression.

```harding
Counter := Object derivePublic: #(value).
Counter>>set: item [ value := item ].       # answers the Counter
Counter>>answer [ ^ value ].              # answers the slot value
Counter>>ignored [ 42 ].                  # answers the Counter
[42] value.                              # answers 42
```

Executed interpreter/native coverage: `implicit_method_returns` and
`class_return_representation`. Class-side fallthrough answers the actual class
receiver, including inherited sends; subsequent chained sends retain class-side
lookup instead of accidentally invoking instance methods. Explicit `^ self` and
blocks returning self preserve that same receiver. Lexical `^` inside a block
still returns from its home method; it is not a local block-return shorthand.

### Method Batching (extend:)

Define multiple methods in a single block:

```smalltalk
Person extend: [
  self >> greet [ ^ "Hello, " & name ].
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
    person := self new.
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
Person := Object derive: #(name, age) methods: [
  self >> greet [ ^ "Hello, I am " & name ].
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
"a" & "b"          # String concatenation

# Keyword (one or more arguments)
dict at: key put: value
obj moveBy: 10 and: 20
```

Binary selectors are made from operator punctuation rather than identifier
characters. The common built-in forms are:

```text
+  -  *  /  <  >  =  ==  %  //  \\  <=  >=  ~=  <<  &  |
```

Preferred meanings in current Harding:

- `&` generic concatenation
- `and:` logical AND with short-circuit
- `|` logical OR

`,` is reserved for collection/object literal separators and is no longer used
as a binary message selector.

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

Parameters and declared temporaries are local to their method or block and shadow
same-named outer bindings or slots. Declared temporaries initially hold `nil`;
a closure created before a temporary's first assignment observes later updates.

### Mutable Shared State

Blocks capture bindings, not snapshots of their values. Sibling and nested blocks
share mutations to the same lexical binding, including assignments made by the
enclosing scope. A block may outlive its creating method: its captured bindings
remain available. Separate method calls create separate bindings.

```smalltalk
CounterMaker := Object derive: #().
CounterMaker>>counter: start [
  | count |
  count := start.
  ^ [count := count + 1. count]
].

counter := CounterMaker new counter: 0.
(counter value) println.  # 1
(counter value) println.  # 2
```

The final expression of a block is its ordinary result. Do not use `^` merely to
return a block result: `^` is a non-local return to the enclosing method.

Executed regressions in `scripts/test_granite_parity.py`: `shared_capture`,
`nested_capture`, `escaped_mutable_capture`, `captured_parameter`,
`forward_temporary`, `lexical_shadowing`, and the inline/collection/while scope
cases.

### Block Invocation

Blocks are invoked via the `value:` message family:

- `value` - invoke with no arguments
- `value:` - invoke with 1 argument
- `value:value:` - invoke with 2 arguments
- etc.

### Non-Local Returns

Use `^` within a block to return from the enclosing method:

```smalltalk
Finder := Object derive: #().
Finder>>first: values [
  values do: [:each |
    (each > 0) ifTrue: [^ each]
  ].
  ^ nil
].
(Finder new first: #(-5, -3, 7, 2)) println.  # 7
```

The return target is the particular invocation of the lexically enclosing
method, not whichever method happens to invoke the block. The ordinary result
of a block is its final expression. An escaped closure's retained variables do
not make its completed home method a valid non-local return target.

Granite captures a unique return target for each method invocation. Recursive
calls do not intercept returns aimed at another invocation of the same method.
The target becomes inactive when its invocation exits; a later non-local return
signals catchable Harding `BlockCannotReturn`, an `Error` subclass, in both
engines. Ordinary escaped closure evaluation remains valid. Deferred GUI or
process callbacks must use final expressions/conditional branches rather than
`^` to exit their own callback; their creating method may already have finished.

Executed parity: `non_local_return`, `recursive_return_target`,
`loop_non_local_return`, and `inactive_return_target` in
`scripts/test_granite_parity.py`. Cleanup runs before the non-local return leaves
its protected scopes.

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
#(1, 2, 3, 4) inject: 0 into: [:sum :each | sum + each]
```

---

## Application Logging and Stream Output

`Log` provides class-side `debug:`, `info:`, `warn:`, `error:` and `fatal:` sends
backed by Nim's `std/logging`. Messages use the value's string representation and
each send answers nil. `fatal:` **only records a message**; it does not exit or
signal an exception.

```harding
Log info: "Server started".
Log warn: "Connection pool nearly full".
Stdout print: "Hello ".
Stdout println: "World".
```

Host logging handlers and their level filters are preserved. When no handler is
installed, the first Log send installs a ConsoleLogger writing to stderr. The
interpreter's `--loglevel` filter applies (its default may suppress info/warn).
Pure compiled programs use the host/default Nim logging filter; compiled CLI
filter configuration is not yet a Harding API. Application debug/warn calls remain
available in release builds, unlike internal VM tracing compiled out in release.
No Bona Transcript logger is installed automatically.

FileStream `print:` and `println:` convert their argument to a string and return
the stream. `write:`/`writeline:` remain available. Printable's existing Transcript
routing is unchanged by these aliases.

## Exception Handling

**Harding does not support exception resumption.** There is no `resume`,
`resume:`, `return:`, or `isResumable`. A handler never transfers control back to
a saved point. Instead:

- a handler's **ordinary result is the value** — the result of `on:do:` for an
  error, and the value of the `signal` expression for a notification;
- **`pass`** delegates to the next matching outer handler;
- **`retry`** re-executes the protected block.

This is deliberate, not a gap. The primary reason is semantic: `resume:` and
`return:` are rarely used and obscure which computation continues, whereas a
handler's result already expresses the same value-passing with no control
transfer. Removing them also removes the last construct whose lowering requires
continuation capture, which keeps the native path simple — though note this is a
simplification we chose to take, not a hard requirement: a compiler with
continuation support could implement resumption. The language-level decision
stands on its own.

Handlers run **synchronously while the signaling computation is still active**,
so for a notification, statements after the signal still run. Errors instead
abandon the protected computation before the handler executes. Both engines
follow this contract; see [EXCEPTION_MODEL.md](EXCEPTION_MODEL.md) and
[GRANITE_STATUS.md](GRANITE_STATUS.md). Remaining custom-class, foreign/process,
and mixed-mode gaps are listed in the status document.

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
    0  # The handler supplies the on:do: result
]

# Float division
result := [ 10.0 / 0.0 ] on: DivisionByZero do: [ :ex |
    "Cannot divide by zero!" println
    42
]
```

All zero divisors signal `DivisionByZero`: integer `//`, `%` and `\`, and `/`
for integer/integer, integer/float, float/integer and float/float operands. Both
engines agree, including the exact `Integer division by zero` / `Float division by
zero` messages; executed parity: `arithmetic_zero_divisor`.

### Error Handling and Notifications

Errors abandon the protected computation before executing a handler. The
handler's ordinary result is the result of `on:do:`; statements after the failed
operation do not run. An executing handler cannot catch its own failures, which
are offered to outer matching handlers. Because errors are not resumable, there
is no way to continue the failed computation.

```smalltalk
result := [Error signal: "stop". "not reached"]
    on: Error do: [:ex | "fallback"].
result println.  # fallback
```

A handler for a notification supplies the signal's value without abandoning the
signaling computation, so code after the signal continues. `pass` delegates to an
outer handler. `retry` is not part of the notification protocol and signals a
normal `Error`.

```smalltalk
result := [Notification signal: "notice". "reached"] on: Notification do: [:ex | "handled"].
result println.  # reached
```

The handler's result becomes the signal's value — this is what `resume:` used to
spell, and it needs no control transfer. Installed handlers remain available for
later signals; currently executing handlers are excluded from nested signal
lookup. If no handler matches, the built-in default action prints the
notification, and signaling continues with nil.

```smalltalk
result := [1 + (Notification signal: "replacement")]
    on: Notification do: [:ex | 41].
result println.  # 42
```

Executed parity: `notification_dispatch`, `notification_lifetime`,
`notification_default`, and `notification_pass_cleanup`. Notification `pass`
exits the current handler's cleanup scopes before calling the outer handler;
the signaling body's scopes remain active. Error `pass` also cleans intervening
protected scopes, and `retry` cleans handler-local scopes before restarting.
A cleanup failure replaces the pending delegation/retry. Custom default-action
overrides, process yields, and mixed mode still need coverage; see
[GRANITE_STATUS.md](GRANITE_STATUS.md).

Executed native/interpreter regressions: `error_unwind`, `error_actions`,
`unhandled_error`, and `unhandled_pass` in `scripts/test_granite_parity.py`.
Custom exception subclasses, native arithmetic errors, stack-trace/default-action
parity and mixed mode still need coverage. Handler-local cleanup on transfers
is covered by `handler_transfer_cleanup`.

Handler actions:
- `ex retry` - Re-execute the protected block from the beginning
- `ex pass` - Delegate to the next matching outer handler

**Not supported:** `resume`, `resume:`, `return:`, `isResumable`. Harding has no
exception resumption; see the contract note at the top of this section.

### Uncaught Exceptions

If no handler matches, Harding runs the exception's default action, prints an uncaught-exception header and stack trace, and exits with a non-zero status.

`pass` follows the same behavior when there is no outer matching handler.

### Missing Messages

A missing selector invokes `doesNotUnderstand:` with the selector symbol. Custom
instance or class-side implementations may recover by returning a value, including
nil. Otherwise `MessageNotUnderstood`, an `Error` subclass, is signaled; an
`on: Error do:` or `on: MessageNotUnderstood do:` handler supplies the result.

```harding
answer := [1 unknownSelector] on: MessageNotUnderstood do: [:ex | 42].
answer println.  # 42
```

Both engines abandon failed protected work and run `ensure:` cleanup before the
handler or uncaught exit. Executed cases: `missing_message_results` and
`unhandled_missing_message`. Mixed-mode dispatch and wrong-type primitive calls
still need separate coverage.

### Notifications Are Synchronous

`Notification` handlers return to the still-active signaling computation. This is
an ordinary synchronous call, not exception resumption; no resume protocol exists.

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

`ensure:` runs cleanup exactly once when the protected block finishes, whether it
completes normally, fails, or leaves through a non-local return. Cleanup's result
is ignored and the body's result is preserved; nested `ensure:` blocks run
innermost-first, and a failure inside a cleanup is caught by the handler that
protects that scope.

```smalltalk
[ riskyOperation ] ensure: [ cleanup ]
```

Each retry attempt exits its own cleanup scope before restarting. If cleanup
signals an error or performs a non-local return, that transfer replaces the
pending result/error/return; outer cleanup still runs. Uncaught errors also run
cleanup before terminating. Executed parity cases: `ensure_retry`,
`ensure_transfer`, `ensure_cleanup_failure`, `ensure_uncaught`, and
`ensure_uncaught_override` in `scripts/test_granite_parity.py`.

Process boundaries and legacy re-entrant native invocation paths still need
cleanup coverage.

### Convenience Methods

```smalltalk
# ifError: catches Error and its subclasses
[ riskyOperation ] ifError: [ :ex | "fallback" ]
```

### Exception Hierarchy

```
Exception
  ├── Error
  │   ├── MessageNotUnderstood
  │   ├── SubscriptOutOfBounds
  │   ├── DivisionByZero
  │   └── BlockCannotReturn
  └── Notification          # Synchronous advisory signal
```

Parent classes catch subclass exceptions: `on: Exception do:` catches `Error`.
User-defined exception classes derive from `Error` or `Notification` and inherit
the `message`, `stackTrace` and `signaler` slots. `MyError signal: "text"` runs
the class's `initialize`; methods you define override the built-in protocol,
while `signal`/`pass`/`retry` keep it.

`Notification` is used for advisory signals rather than errors. Its handlers run synchronously while the signaling computation stays active, so execution continues after the signal.

### Differences from Smalltalk

| Feature | Harding | Smalltalk |
|---------|------|-----------|
| Implementation | VM work queue (stackless) | Custom VM mechanism |
| Stack unwinding | Errors abandon protected computation; notifications keep signaling computation active | Depends on handler action; resumption retains computation |
| Resumption (`resume:`, `return:`) | **Not supported** — no continuations | Supported by resumable exception protocols |

---

## Libraries and Namespaces

Harding provides a Library class for organizing code into isolated namespaces. Libraries allow you to group related classes and avoid polluting the global namespace.

### Creating Libraries

```smalltalk
# Create a new library
MyLib := Library new.

# Convenience constructor
MyLib := Library name: "MyLib".

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

Successive `load:` calls on the same library evaluate with that library's existing
bindings visible, so later files can reference names defined by earlier ones.

If the library defines `__sourceDir`, relative paths passed to `load:` are resolved
from that directory first.

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

`import:` currently adds the library to a lookup stack; it does not copy bindings
into the receiver. Importing a library that conflicts with an already imported
library now raises an error instead of silently changing lookup precedence.

### Variable Lookup Order

When resolving a variable name, Harding searches in this order:

1. **Local scope** (temporaries, captured variables, method locals)
2. **Instance variables** (slots on `self`)
3. **Imported Libraries** (most recent first, if there are no name conflicts)
4. **Global table** (fallback)

**Important**: Each method activation has its own isolated local scope. Methods cannot see the local variables of their calling method (unlike some dynamic languages). This prevents accidental coupling and ensures proper encapsulation.

Imports with overlapping exported names are rejected:

```smalltalk
Lib1 := Library new.
Lib1 at: "SharedKey" put: 1.

Lib2 := Library new.
Lib2 at: "SharedKey" put: 2.

Harding import: Lib1.
Harding import: Lib2.  # Error: import conflict between Lib2 and Lib1: SharedKey
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
harding lib info sqlite    # Show detailed info about SQLite support
```

#### Installing Libraries

```bash
harding lib install mysql           # Install latest version
harding lib install mysql@1.0.0    # Install specific version
harding lib install sqlite         # Install SQLite library
```

Libraries are installed to the `external/` directory and compiled into Harding on the next build.

#### Managing Installed Libraries

```bash
harding lib installed      # List installed libraries
harding lib update mysql   # Update a specific library
harding lib update sqlite  # Update the SQLite library
harding lib update --all   # Update all libraries
harding lib remove mysql   # Remove a library
harding lib remove sqlite  # Remove the SQLite library
```

#### Building with External Libraries

After installing or updating libraries:

```bash
nimble harding             # Rebuild with new libraries
```

SQLite is a good fit for local storage and tests because it works with file
paths and `":memory:"` databases instead of a separate database server.

```smalltalk
conn := SqliteConnection open: ":memory:".
conn execute: "CREATE TABLE players (name TEXT, score INTEGER)".
conn execute: "INSERT INTO players (name, score) VALUES ('Ada', 1200)".

result := conn query: "SELECT name, score FROM players ORDER BY score DESC".
row := result next.
((row at: 0) & " => " & (row at: 1)) println.

result close.
conn close.
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
    Dog := Object derivePublic: #(name, age)
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
"a" & "b"        # String concatenation (non-destructive, returns new string)
"Value: " & 42    # Auto-converts to string: "Value: 42"
s << "text"        # In-place append (mutates string, returns self)
a and: [ b ]        # Logical AND with short-circuit
a | b              # Logical OR
```

---

## String Operations

Harding provides two complementary ways to work with strings:

### Non-Destructive Concatenation (`&`)

The `&` operator creates new strings:

```smalltalk
str1 := "Hello".
str2 := str1 & " World".    # str1 is still "Hello", str2 is "Hello World"
result := "A" & "B" & "C". # Creates intermediate strings: "A" -> "AB" -> "ABC"
```

**Use for**: Simple concatenation, functional style, short strings.

### In-Place Appending (` << `)

The `<<` operator mutates the string efficiently and supports chaining:

```smalltalk
# Efficient string building with pre-allocated capacity
buffer := String withCapacity: 1000.
buffer << "<html>".
buffer << "<head><title>" << title << "</title></head>".
buffer << "<body>" << content << "</body>".
buffer << "</html>".
html := buffer.  # The string itself is the result (no .contents needed)
```

**Key differences:**
- `<<` mutates the string in-place (O(1) amortized with pre-allocated capacity)
- `&` creates new strings each time (O(n) per operation)
- `<<` returns `self` for method chaining
- `withCapacity:` hints the initial buffer size to avoid reallocations

**Use for**: Building large strings (HTML, JSON, logs), tight loops, streaming output.

---

## JSON Support

Harding currently provides three JSON entry points:

- `json{...}` / `Json{...}` / `JSON{...}` prefix literals for inline JSON strings
- `Json parse:` to parse JSON text into Harding values
- `Json stringify:` to convert Harding values into compact JSON text

The `Json` class is available by default.

### JSON Literals

Prefix JSON literals return JSON text directly:

```smalltalk
payload := json{"status": "ok", "count": 42}
payload class          # String
```

`json{}` supports full JSON syntax:

```smalltalk
# Objects with nested structures
json{
    "person": {
        "name": "Alice",
        "age": 30,
        "address": {"city": "NYC", "zip": "10001"}
    }
}

# Arrays using JSON [1, 2, 3] syntax
json{
    "items": [1, 2, 3],
    "tags": ["a", "b", "c"],
    "matrix": [[1, 2], [3, 4]]
}

# Arrays of objects
json{
    "users": [
        {"name": "Alice", "id": 1},
        {"name": "Bob", "id": 2}
    ]
}

# Mixed with variables
Name := "Todo API".
Count := 42.
json{
    "name": Name,
    "count": Count,
    "tags": ["api", "rest"]
}
```

**Key features:**
- Native JSON object syntax: `{"key": value}`
- JSON array syntax: `[1, 2, 3]` (not `#(1, 2, 3)`)
- Nested objects and arrays
- Dynamic values via variables and expressions
- Commas separate items (not `->` arrows)

These literals are useful for:

- inline API payloads
- tests and fixtures
- OpenAPI specifications
- small constant JSON documents

### Parsing JSON

`Json parse:` converts JSON text into Harding values:

```smalltalk
value := Json parse: "{\"name\":\"Alice\",\"age\":30,\"tags\":[\"a\",\"b\"]}"
```

Current conversions:

| JSON | Harding |
|------|---------|
| object | `Table` |
| array | `Array` |
| string | `String` |
| integer | `Integer` |
| float | `Float` |
| true / false | `Boolean` |
| null | `nil` |

Example:

```smalltalk
user := Json parse: "{\"name\":\"Alice\",\"admin\":true,\"scores\":[1,2,3]}".

user at: "name"          # "Alice"
user at: "admin"         # true
user at: "scores"        # #(1, 2, 3)
```

If parsing fails, `Json parse:` currently returns `nil`.

### Stringifying Harding Values

`Json stringify:` converts Harding values into compact JSON text:

```smalltalk
Json stringify: #{"a" -> 1, "b" -> #(2, 3, 4)}
```

Current supported inputs:

- Numbers
- Strings
- Booleans
- `nil`
- Arrays
- Tables
- ordinary Harding objects
- Array and Table instances

Example:

```smalltalk
payload := #{
    "name" -> "Alice".
    "age" -> 30.
    "roles" -> #("admin", "editor").
    "active" -> true
}.

jsonText := Json stringify: payload.
```

Output is compact JSON with no pretty-print formatting.

### Serializing Ordinary Objects

Ordinary Harding objects now serialize as JSON objects using slot order by default:

```smalltalk
Person := Object derivePublic: #(name, age).
person := Person new.
person::name := "Alice".
person::age := 30.

Json stringify: person
# => {"name":"Alice","age":30}
```

Inherited slots are included as well.

### Class-Side JSON Configuration

Harding supports declarative class-side JSON configuration for common cases:

```smalltalk
User := Object derivePublic: #(id, username, password, avatarUrl)
    ; jsonExclude: #(password)
    ; jsonRename: #{#username -> "userName"}
    ; jsonOmitNil: #(avatarUrl).
```

Supported class-side messages:

- `jsonExclude:`
- `jsonOnly:`
- `jsonRename:`
- `jsonOmitNil:`
- `jsonOmitEmpty:`
- `jsonFormat:`
- `jsonFieldOrder:`
- `jsonReset`
- `jsonSpec`

Supported built-in formatter symbols:

- `#string`
- `#rawJson`
- `#symbolName`
- `#className`

Example with formatting:

```smalltalk
Envelope := Object derivePublic: #(payload, kind).
Envelope jsonFormat: #{#payload -> #rawJson, #kind -> #symbolName}.
```

### Fallback Representation Hook

When declarative slot-based serialization is not enough, a class can define `jsonRepresentation`.

The method should return a Harding value that `Json stringify:` already understands, typically a Table, Array, primitive, or nested combination of those.

```smalltalk
Invoice := Object derivePublic: #(id, lines).

Invoice>>jsonRepresentation [
    ^ #{
        "id" -> id,
        "lineCount" -> lines size
    }
]
```

This path is more flexible, but slower than the compiled slot-plan path.

### Current Limitations

Also note:

- JSON table keys support Strings, Symbols, Numbers, Booleans, `nil`, Classes, and primitive wrapper instances; unsupported key types raise an error
- There is no built-in pretty printer yet
- Parse errors currently return `nil` rather than signaling a JSON-specific exception
- Arbitrary transformer blocks are not part of the current fast-path API

### Performance Notes

As of the current implementation, `Json stringify:` writes directly into a mutable string buffer inside the primitive and serializes ordinary objects through compiled class plans.

This improves the core serialization path for primitives, Arrays, Tables, and ordinary slot-based objects.

### Benchmarking JSON

There are benchmark scripts for the current JSON support:

```bash
nim c -r tests/benchmark_json_stringify.nim
nim c -r tests/benchmark_json_objects.nim
```

They compare:

- Harding `Json stringify:` on a reasonably complex nested Table/Array payload
- Harding `Json stringify:` on a reasonably complex nested object graph
- an equivalent pure Nim direct string writer
- an equivalent pure Nim `std/json` builder

Recent release-build results on the current implementation were approximately:

- Table/Array payload: Harding ~129.72 ms, Nim direct ~19.75 ms, Nim `std/json` ~91.40 ms
- Object graph payload: Harding ~34.48 ms, Nim direct ~11.40 ms, Nim `std/json` ~37.92 ms

The object-graph case is the more relevant comparison for the new slot-plan serializer. In that benchmark, Harding is already slightly faster than Nim `std/json`, while still behind a hand-written direct Nim encoder.

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
"hello"                          # String literal
str size                         # Length
str at: 0                        # Character at index
str1 & str2                      # Non-destructive concatenation (returns new String)
buffer := String withCapacity: 100.   # Pre-allocated string for efficient building
buffer << "part1" << "part2".       # In-place append (returns self for chaining)

# Arrays (0-based indexing)
#(1, 2, 3)            # Array literal
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
arr := #(1, 2, 3)
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
