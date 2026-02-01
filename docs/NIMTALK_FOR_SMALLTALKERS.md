# Nimtalk for Smalltalkers

A guide for experienced Smalltalk programmers coming to Nimtalk. This document covers the key differences in syntax, semantics, and available features.

## Quick Summary

Nimtalk is a class-based Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing semantics and syntax feel while making pragmatic changes for a modern implementation.

| Feature | Smalltalk-80 | Nimtalk |
|---------|-------------|---------|
| Object model | Classes + metaclasses | Classes only (no metaclasses) |
| Statement separator | Period (`.`) only | Period or newline |
| String quotes | Single quote (`'`) | Double quote (`"`) only |
| Class methods | Metaclass methods | Methods on class object |
| Class variables | Shared class state | Not implemented |
| Pool dictionaries | Shared constants | Not implemented |
| Instance variables | Named slots | Indexed slots (faster) |
| Multiple inheritance | Single only | Supported |
| Primitives | VM-specific | Nim code embedding |

## Syntactic Differences

### 1. Statement Separation

**Smalltalk:**
```smalltalk
x := 1.
y := 2.
z := x + y.
```

**Nimtalk:**
```nimtalk
* Periods work (Smalltalk-compatible)
x := 1.
y := 2.

* Line endings also work (Nimtalk-style)
x := 1
y := 2

* Mixed style is fine
x := 1.
y := 2
z := x + y.
```

### 2. String Literals

**Smalltalk:**
```smalltalk
'Hello World'       "Single quotes only"
```

**Nimtalk:**
```nimtalk
"Hello World"       # Double quotes only
```

**Note**: Single quotes are reserved for future use. Use double quotes for all strings.

### 3. Comments

**Smalltalk:**
```smalltalk
"This is a comment - double quotes"
```

**Nimtalk:**
```nimtalk
# This is a comment - hash style
#==== Section header
```

**Note**: Hash-style comments are the only comment syntax. Double quotes are for strings.

### 4. Block Syntax

**Smalltalk:**
```smalltalk
[ :x :y | | temp1 temp2 |
  temp1 := x.
  temp2 := y.
  temp1 + temp2
]
```

**Nimtalk:**
```nimtalk
# Optional | after parameters (Nimtalk-specific)
[ :x :y
  x + y
]

# Traditional style also works
[ :x :y | | temp1 temp2 |
  temp1 := x.
  temp2 := y.
  temp1 + temp2
]

# Parameters with temporaries
[ :x :y | temp1 temp2 |
  temp1 := x.
  temp2 := y.
  temp1 + temp2
]
```

The vertical bar `|` is optional after parameters if there are no temporaries.

### 5. Method Definition Syntax

**Smalltalk:**
```smalltalk
Object subclass: #Person
    instanceVariableNames: 'name age'
    classVariableNames: ''
    poolDictionaries: ''
    category: 'Examples'!

!Person methodsFor: 'accessing'!
name: aName
    name := aName
! !
```

**Nimtalk:**
```nimtalk
# Define class with slots
Person := Object derive: #(#name #age).

# Define method using >> syntax
Person>>name: aName [
    name := aName
].

# Or using at:put: syntax
Person at: #name: put: [ :aName |
    name := aName
].
```

### 6. Multiline Keyword Messages

**Smalltalk:**
```smalltalk
dictionary
    at: #key
    put: value
    ifAbsent: [ default ]
```

**Nimtalk:**
```nimtalk
# Same syntax, but note that newlines act as separators
# except when continuing a keyword message chain
dictionary
  at: #key
  put: value
```

## Semantic Differences

### 1. No Metaclasses

**Smalltalk:** Every class is an instance of a metaclass. Class methods are defined on the metaclass.

**Nimtalk:** Classes are objects, but there are no metaclasses. Class methods are stored directly on the class object.

```nimtalk
# Instance method
Person>>greet [ ^ "Hello" ].

# Class method (no metaclass needed)
Person class>>newPerson [ ^ self new ].
# Or equivalently:
Person at: #newPerson put: [ ^ self new ].
```

The `class` message returns the class object itself, and methods can be stored there.

### 2. Instance Variable Implementation

**Smalltalk:** Instance variables are named slots accessed by name.

**Nimtalk:** Instance variables are indexed slots for O(1) access. The class maintains `slotNames` (declared on class) and `allSlotNames` (inherited layout).

```nimtalk
Person := Object derive: #(#name #age).

# Inside methods, access by name (converted to slot index at compile time)
Person>>name: aName [
    name := aName   # Direct slot access - O(1)
].

Person>>name [
    ^ name           # Direct slot read - O(1)
].
```

Performance comparison (per 100k ops):
- Direct slot access: ~0.8ms
- Named slot access: ~67ms
- Property bag access: ~119ms

### 3. Multiple Inheritance

**Smalltalk:** Single inheritance only. Traits provide code sharing.

**Nimtalk:** Multiple inheritance is supported:

```nimtalk
# Single inheritance (default)
Employee := Person derive: #(salary).

# Multiple inheritance
Enumerable := Object derive: #().
Employee := Person derive: #(salary) withParents: #(Enumerable).
```

Method lookup uses merged method tables (`allMethods`, `allClassMethods`) for O(1) dispatch.

### 4. Super Sends

**Smalltalk:** `super` starts method lookup in the parent class.

**Nimtalk:** `super` works similarly, but supports qualified super for multiple inheritance:

```nimtalk
# Unqualified super (uses first parent)
Employee>>calculatePay [
    base := super calculatePay.
    ^ base + bonus
].

# Qualified super (explicit parent selection)
Employee>>calculatePay [
    base := super<Person> calculatePay.
    ^ base + bonus
].
```

### 5. Primitives

**Smalltalk:** Primitives are VM-specific numbered operations (e.g., `<primitive: 1>`).

**Nimtalk:** Primitives embed Nim code directly:

```nimtalk
Object>>primitiveClone [
    <primitive>
    ## Create a shallow copy in Nim
    result = clone(self)
    </primitive>
].
```

The Nim code has access to the interpreter context and can manipulate objects directly.

## Missing Features

### 1. Class Variables

**Smalltalk:** Variables shared among all instances and subclasses:
```smalltalk
Object subclass: #MyClass
    instanceVariableNames: ''
    classVariableNames: 'SharedVar'    "Not in Nimtalk"
```

**Nimtalk:** Not implemented. Use class methods with captured state or global objects:

```nimtalk
# Workaround: Store in class method closure
MyClass>>sharedCounter [
    | count |
    count := 0.
    ^ [ count := count + 1. count ]
].

# Or use a global registry
Registry at: #MyClassCounter put: 0.
```

### 2. Class Instance Variables

**Smalltalk:** Instance variables on the class object (metaclass instance variables):
```smalltalk
Object class>>initialize
    classInstVar := 0.    "Not in Nimtalk"
```

**Nimtalk:** Not implemented. Classes don't have instance variables separate from their instances.

### 3. Pool Dictionaries

**Smalltalk:** Shared dictionaries for constants:
```smalltalk
Object subclass: #MyClass
    poolDictionaries: 'MyPool'    "Not in Nimtalk"
```

**Nimtalk:** Not implemented. Use global tables or symbols:

```nimtalk
# Workaround: Global table
Constants := #{
  #MaxSize -> 100
  #DefaultName -> "Unknown"
}.

# Access as: Constants at: #MaxSize
```

### 4. Metaclass Hierarchy

**Smalltalk:** Rich metaclass hierarchy with `Class`, `ClassDescription`, `Behavior`, etc.

**Nimtalk:** Classes are simple objects. The hierarchy is flat:
- `Class` - defines structure and behavior
- `Instance` - pure data with reference to class

No `Behavior`, `ClassDescription`, or metaclass chain.

### 5. Method Categories

**Smalltalk:** Methods organized into categories/protocols:
```smalltalk
!MyClass methodsFor: 'accessing'!
```

**Nimtalk:** Not implemented. Methods are stored in a flat table. Organization is by convention only.

### 6. Change Sets and Version Control

**Smalltalk:** Image-based with change sets, versions, and Monticello.

**Nimtalk:** File-based source code (`.nt` files) with traditional version control (git).

### 7. Refactoring Tools

**Smalltalk:** Rich refactoring browser with rename, extract method, push up/down, etc.

**Nimtalk:** Basic text editing. No specialized refactoring tools yet.

### 8. Debugger

**Smalltalk:** Full debugger with stack inspection, variable examination, step-through.

**Nimtalk:** Basic error messages with line numbers. Stack traces available but limited.

## Additional Nimtalk Features

### 1. Cascade Operator

Nimtalk implements Smalltalk's cascade using `;`:

```nimtalk
obj
  at: #x put: 0;
  at: #y put: 0;
  at: #z put: 0.
# Equivalent to:
obj at: #x put: 0.
obj at: #y put: 0.
obj at: #z put: 0.
```

### 2. Object Literals

Create objects with literal syntax:

```nimtalk
point := {| x: 10 y: 20 |}.
```

### 3. Table Literals

Hash table literals with arrow syntax:

```nimtalk
dict := #{ "name" -> "Alice" "age" -> 30 }.
```

### 4. FFI Integration

Direct access to Nim types and functions via primitives.

## Migration Tips

### Converting Smalltalk Code

1. **Remove metaclass references** - Use `class` message or direct class method storage
2. **Replace class variables** - Use globals or closures
3. **Update string quotes** - Use double quotes `"..."` (single quotes are reserved)
4. **Update comments** - Use `#` for comments (double quotes are for strings now)
5. **Simplify method definitions** - Use `>>` syntax
6. **Check statement separators** - Ensure periods/newlines are correct
7. **Update block syntax** - Optional `|` after parameters

### Common Patterns

**Smalltalk singleton:**
```smalltalk
Singleton class>>instance
    Instance isNil ifTrue: [ Instance := self new ].
    ^ Instance
```

**Nimtalk singleton:**
```nimtalk
# Using captured variable
Singleton class>>instance [
    | inst |
    inst := nil.
    ^ [
        inst isNil ifTrue: [ inst := self new ].
        inst
    ] value
].

# Or using global
Singleton class>>instance [
    (Registry at: #SingletonInstance) isNil ifTrue: [
        Registry at: #SingletonInstance put: self new
    ].
    ^ Registry at: #SingletonInstance
].
```

## Summary

Nimtalk preserves the essence of Smalltalk (message passing, blocks, live programming) while simplifying the object model and adding modern conveniences. The main adjustments for Smalltalkers are:

1. No metaclasses - classes are just objects
2. No class variables - use globals or closures
3. Multiple inheritance - supported natively
4. Nim primitives - embed native code directly
5. Flexible syntax - optional separators, quote styles

The trade-off is simplicity over completeness - Nimtalk is smaller and compiles to native code through Nim, but lacks some of Smalltalk's advanced reflective features.
