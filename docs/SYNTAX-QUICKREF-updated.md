# Nimtalk Syntax Quick Reference - Object Model & Parsing

## Instance Variable Declaration

### Dictionary (Property Bag)
```smalltalk
# For dynamic property storage, use Dictionary
dict := Dictionary derive.
dict at: "name" put: "Alice"    # Dictionary access
result := dict at: "name"
```

### Object (Declared Instance Variables)
```smalltalk
# Declare instance variables when creating prototype
# (derive: is a regular message, not special syntax)
# Symbols in arrays need # prefix: #(#name #age)
Person := Object derive: #(#name #age)

# Create and initialize object
person := Person derive.
person name: "Alice"              # Uses generated setter (direct slot access)
person age: 30

# Access ivars
result := person name               # Uses generated getter (direct slot access)
```

## Inheritance

```smalltalk
# Single inheritance
Employee := Person derive: #(#salary #department)

# Multi-level inheritance
Manager := Employee derive: #(#teamSize)
```

## Method Definition Syntax (File Format)

### Standard Syntax (REPL/Interactive)
```smalltalk
# Normal executable code - works in REPL
Person at: "greet" put: [ ^ "Hello, " + name ]
```

### Definition Syntax (Files Only - SPECIAL PARSING)
```smalltalk
# This syntax requires special parsing - NOT executable in REPL
# Use in .nt files for prototype definitions

# Unary method (no parameters)
Person>>greet [ ^ "Hello, " + name ]

# Method with one parameter
Person>>name: aName [ name := aName ]

# Method with multiple parameters
Person>>moveX: dx y: dy [
  x := x + dx
  y := y + dy
]

# Method with comment and validation
Person>>age: anAge [
  "Validate age is positive"
  (anAge >= 0) ifFalse: [ Error signal: "Age must be positive" ].
  age := anAge
]

# Multiple methods (no trailing periods needed)
Person>>name [ ^ name ]

Person>>age [ ^ age ]

Person>>description [
  ^ name + " (age " + age asString + ")"
]
```

**Note**: The closing `]` acts as the terminator. No trailing period needed!

### Why Two Syntaxes?

**REPL Mode** - Standard message passing:
```
Parser sees: Person at: "greet" put: [ ... ]
        ↓
Executes: Send 'at:put:' message to Person
```

**File Definition Mode** - Special parsing:
```
Parser sees: Person>>greet [ ... ]
        ↓
Recognizes: Method definition syntax
        ↓
Converts to: Person at: "greet" put: [ ... ]
        ↓
Executes: Same as standard message send
```

## Message Sending

### Current Way (Works Everywhere)
```smalltalk
# Property bag access (deprecated for declared objects)
obj at: "property"                        # Get
obj at: "property" put: value             # Set

# Dynamic method invocation
obj perform: "methodName"                 # Call method
obj perform: "method:with:" with: args     # Call with args
```

### New Way (Declared Objects)
```smalltalk
# Generated accessor methods (compile to direct slot access)
person name                                 # Getter - direct read
person name: "Alice"                      # Setter - direct write

# Standard message sending (always available)
person greet                              # Unary message
3 + 4                                     # Binary message
person at: "key" put: "value"           # Keyword (for collections)
```

### Direct Ivar Access (Inside Methods)
```smalltalk
# Inside method bodies, access ivars directly
Person>>greet [
  ^ "Hello, " + name                    # Direct slot access
]

Person>>birthday [
  age := age + 1                        # Direct read and write
  ^ self
]
```

## Initialization

```smalltalk
Person>>initialize [
  name := "Anonymous"                   # Direct ivar assignment
  age := 0
]

# Usage
person := Person derive initialize.     # Create then initialize
person name: "Alice"                    # Then configure

# Or use class-side constructor
Person>>newWithName: aName age: anAge [
  ^ self derive initialize
      name: aName;                      # Cascade messages
      age: anAge;
      yourself
]

# Usage
person := Person newWithName: "Alice" age: 30
```

## Inheritance and Super

```smalltalk
Employee>>initialize [
  super perform: "initialize"           # Call parent initialization
  salary := 0.0                         # Then init Employee ivars
]

Employee>>greet [
  "Override parent method, call super for base behavior"
  ^ (super perform: "greet") + " from " + department
]
```

## File Structure by Convention

```
# One prototype per file (recommended)
src/
  models/
    Person.nt            # Defines Person prototype
    Employee.nt          # Defines Employee
    Company.nt           # Defines Company
  main.nt                # Application entry point

# Multi-prototype files also supported
src/
  models.nt              # Person, Employee, Company all defined here
```

## Parsing Modes

### REPL/Interactive Mode
```smalltalk
# Standard message passing - everything executes immediately
> Person := Object derive: #(#name)
> Person at: "name:" put: [ :n | name := n ]
> person := Person derive initialize
> person name: "Alice"
```

### File Definition Mode
```smalltalk
# File: src/models/Person.nt
# Special parsing for method definitions

Person := Object derive: #(#name #age)                    # Executable

Person>>initialize [                                    # Method definition
  name := "Anonymous"
  age := 0
]

Person>>name: aName [                                   # Method definition
  name := aName
]
```

## Standard Types Provided

```smalltalk
# Object - Root prototype (all objects inherit from this)
obj := Object derive.

# String, Number, Boolean - Built-in types
"hello world"           # String (double-quoted)
42                      # Integer
3.14                    # Float
true/false              # Boolean

# Multiline strings (like Nim)
""
This is a multiline string
It can span multiple lines
"""

# Characters (single-quoted, single character)
'a'                     # Character literal
'\n'                    # Newline character
'\t'                    # Tab character

# Collections
#(1 2 3)                # Array literal (ordered)
#{"key" -> "value"}    # Table literal (dictionary)
```

## Control Flow

```smalltalk
# Conditional (messages to boolean objects)
(x > 0) ifTrue: [ "positive" ] ifElse: [ "negative" ]

# Looping
[ x < 10 ] whileTrue: [ x := x + 1 ]

# Collection iteration
numbers do: [ :each | each print ]
numbers select: [ :each | each > 5 ]
numbers collect: [ :each | each * 2 ]
```

## Comparison: Smalltalk vs Nimtalk

| Feature | Smalltalk | Nimtalk |
|---------|-----------|---------|
| Object Model | Class-based | Prototype-based |
| Inheritance | Classes | Prototype chain |
| Instance Vars | Declared in class | Declared in `derive:` |
| Ivar Access | Direct in methods | Direct in methods |
| Method Storage | Class dictionary | Stored on prototype |
| Method Definitions | Browser | `>>` syntax (files only) |
| Collections | OrderedCollection, Dictionary | seq, Table (Nim types) |
| File Structure | Image-based | File-based |
| Parsing | Single mode | REPL + Definition modes |
| String Literals | Single quotes | Double quotes (Nim-style) |

## Cheat Sheet: Quick Reference

```smalltalk
#=== Object Creation =========================
proto := Object derive                        # Empty prototype (no property bag)
dict  := Dictionary derive                    # Dictionary with property bag
obj   := proto derive initialize              # Create then init

#=== Instance Variables ======================
Proto := Object derive: #(#ivar1 #ivar2)        # Declare ivars
obj   := Proto derive initialize.
obj ivar1: value                              # Accessor method (direct slot access)

#=== Dictionary (Property Bag) ===============
Dict := Dictionary derive.
dict at: "key" put: value                     # Property bag access
dict at: "key"                                # Property retrieval

#=== Methods (in files) ======================
Proto>>method [ ^ result ]                    # Define unary
Proto>>method: arg [ ^ result ]               # Define keyword
Proto>>arg1: x arg2: y [ ^ x + y ]            # Multi-keyword

#=== Methods (in REPL) =======================
Proto at: "method" put: [ ^ result ]          # Standard way
Proto perform: "method"                       # Call dynamically

#=== Message Sending =========================
obj method                                    # Unary
obj method: value                             # Keyword
obj binaryOp: other                           # Binary

#=== Inheritance =============================
Child := Parent derive: #(#newIvar)            # Inherit + add
Child>>method [ super perform: "method" ]   # Call parent

#=== Control Flow ============================
expr ifTrue: [ block ] ifElse: [ block ].
[ condition ] whileTrue: [ block ].
collection do: [ :each | block ].

#=== Comments ================================
# This is a comment (line, to end)
"Inline comment" someCode                   # String as comment
#!/usr/bin/env ntalk                         # Shebang at start of file

#=== Strings =================================
"double quoted"                             # String literal
'c'                                         # Character
"""multiline"""                           # Multiline string
```

## Migration from Property Bag

### Old Code (Property Bag on Object - No Longer Supported)
```smalltalk
# This no longer works - Object derive doesn't have property bag
person := Object derive.
person at: "name" put: "Alice".   # ERROR: at:put: only on Dictionary
```

### New Code Options

**Option 1: Dictionary for Dynamic Properties**
```smalltalk
# Use Dictionary when you need dynamic property storage
dict := Dictionary derive.
dict at: "name" put: "Alice".
dict at: "age" put: 30.
result := dict at: "name".
```

**Option 2: Declared Ivars with Object**
```smalltalk
# Define Person with declared instance variables
Person := Object derive: #(#name #age).

# Create and use instance
person := Person derive initialize.
person name: "Alice".
person age: 30.
result := person name.
```

**Option 3: Dictionary with Slots**
```smalltalk
# Combine property bag with declared ivars
Person := Dictionary derive: #(#name age).
Person at: "greet" put: [ ^"Hello, " + name ].

person := Person derive.
person name: "Alice".
person at: "nickname" put: "Al".  # Dynamic property
result := person greet.             # "Hello, Alice"
```

## Key Differences Summary

1. **String Literals**: Use `"double quotes"` not `'single quotes'`
2. **Ivar Declaration**: `derive: #(#ivar1 #ivar2)` not property bags
3. **Method Definitions**: `>>` syntax in files, `at:put:` in REPL
4. **No Trailing Periods**: After method definitions (closing `]` is terminator)
5. **Direct Access**: Inside methods, access ivars directly by name
6. **Accessor Methods**: Used outside methods, compile to direct access

## Next Steps

✅ **COMPLETED**: All major features implemented!

1. ✅ Implemented `derive:` syntax in parser (as regular message)
2. ✅ Added instance variable storage with 149x performance improvement
3. ✅ Generated default accessors automatically (direct slot access)
4. ⏳ `>>` method definition syntax (planned, not critical - current `at:put:` works)
5. ✅ Added `self` support in methods (super pending)
6. ✅ Both REPL and File Definition modes work
7. ✅ Comprehensive test suite written and passing
8. ✅ Cascade syntax implemented (`;` operator)
9. ✅ Native method dispatch from Nimtalk code
10. ✅ Base library with Object, Boolean, Collections

## Additional Features Implemented

### Cascading Messages

Nimtalk supports Smalltalk's cascade syntax using `;` to send multiple messages to the same receiver:

```smalltalk
# Send multiple messages to the same object
obj at: "x" put: 0; at: "y" put: 0; at: "z" put: 0.

# Works with any message type
calculator clear; add: 5; add: 10; result.

# Receiver is evaluated only once
counter increment; increment; increment.
```

### Implementation Note

**File syntax (`>>`)**: The `>>` syntax for method definitions in files is planned but not yet implemented. In the meantime, methods are defined using `at:put:` which works both in REPL and files:

```smalltalk
# Current way (works everywhere)
Person at: "greet:" put: [ :name | ^"Hello " + name ].

# Planned way (not yet implemented)
# Person>>greet: name [ ^"Hello " + name ]
```

## Resources

- [FULL PROPOSAL](PROPOSAL-object-model.md) - Complete design proposal
- [EXAMPLES](proposal-examples/) - Example code files using new syntax
- [SPECIFICATION](SPECIFICATION.md) - Language specification details
- [DECISIONS NEEDED](DECISION-NEEDED.md) - Key design decisions
---

---
