# Nimtalk Syntax Quick Reference - Object Model & Parsing

## Instance Variable Declaration

### Current (Property Bag - Being Replaced)
```smalltalk
person := Object derive.
person at: "name" put: "Alice"    # Arbitrary property addition
```

### New (Declared Instance Variables)
```smalltalk
# Declare instance variables when creating prototype
Person := Object derive: #(name age)

# Create and initialize object
person := Person derive initialize.
person name: "Alice"              # Uses generated setter (direct slot access)
person age: 30

# Access ivars
result := person name               # Uses generated getter (direct slot access)
```

## Inheritance

```smalltalk
# Single inheritance
Employee := Person derive: #(salary department)

# Multi-level inheritance
Manager := Employee derive: #(teamSize)
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
> Person := Object derive: #(name)
> Person at: "name:" put: [ :n | name := n ]
> person := Person derive initialize
> person name: "Alice"
```

### File Definition Mode
```smalltalk
# File: src/models/Person.nt
# Special parsing for method definitions

Person := Object derive: #(name age)                    # Executable

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
proto := Object derive                        # Empty prototype
obj   := proto derive initialize              # Create then init

#=== Instance Variables ======================
Proto := Object derive: #(ivar1 ivar2)        # Declare ivars
obj   := Proto derive initialize.
obj at: "ivar1" put: value                    # Old way (deprecated)
obj ivar1: value                              # New way (accessor)

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
Child := Parent derive: #(newIvar)            # Inherit + add
Child>>method [ super perform: "method" ]   # Call parent

#=== Control Flow ============================
expr ifTrue: [ block ] ifElse: [ block ].
[ condition ] whileTrue: [ block ].
collection do: [ :each | block ].

#=== Comments ================================
# This is a comment (line, to end)
"Inline comment" someCode                   # String as comment

#=== Strings =================================
"double quoted"                             # String literal
'c'                                         # Character
"""multiline"""                           # Multiline string
```

## Migration from Property Bag

### Old Code (Property Bag)
```smalltalk
person := Object derive.
person at: "name" put: "Alice".
person at: "age" put: 30.
result := person at: "name".
```

### New Code (Declared Ivars)
```smalltalk
# Define Person in Person.nt
Person := Object derive: #(name age).

# In your code
person := Person derive initialize.
person name: "Alice".
person age: 30.
result := person name.
```

## Key Differences Summary

1. **String Literals**: Use `"double quotes"` not `'single quotes'`
2. **Ivar Declaration**: `derive: #(ivar1 ivar2)` not property bags
3. **Method Definitions**: `>>` syntax in files, `at:put:` in REPL
4. **No Trailing Periods**: After method definitions (closing `]` is terminator)
5. **Direct Access**: Inside methods, access ivars directly by name
6. **Accessor Methods**: Used outside methods, compile to direct access

## Next Steps

1. Implement `derive:` syntax in parser
2. Add instance variable storage with direct access
3. Generate default accessors automatically
4. Implement `>>` method definition parsing (extended parser)
5. Add `super` and `self` support in methods
6. Support both REPL and File Definition parsing modes
7. Write comprehensive test suite

## Resources

- [FULL PROPOSAL](PROPOSAL-object-model.md) - Complete design proposal
- [EXAMPLES](proposal-examples/) - Example code files using new syntax
- [SPECIFICATION](SPECIFICATION.md) - Language specification details
- [DECISIONS NEEDED](DECISION-NEEDED.md) - Key design decisions
