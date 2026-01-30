# Nimtalk Syntax Quick Reference - Object Model & Parsing

## Instance Variable Declaration

### Class with Declared Instance Variables
```smalltalk
# Declare instance variables when creating prototype
# (derive: is a regular message, not special syntax)
# Symbols in arrays need # prefix: #(#name #age)
Person := Object derive: #(#name #age)

# Create and initialize instance
person := Person new.
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

# Multiple inheritance (traits pattern)
Enumerable := Object derive: #().
Employee := Person derive: #(#salary) withParents: #(Enumerable)
```

## Method Definition Syntax (File Format)

### Standard Syntax (REPL/Interactive)
```smalltalk
# Normal executable code - works in REPL
Person selector: #greet put: [ ^ "Hello, " , name ]
```

### Definition Syntax (Files Only - SPECIAL PARSING)
```smalltalk
# This syntax requires special parsing - NOT executable in REPL
# Use in .nt files for prototype definitions

# Unary method (no parameters)
Person>>greet [ ^ "Hello, " , name ]

# Method with one parameter
Person>>name: aName [ name := aName ]

# Method with multiple parameters
Person>>moveX: dx y: dy [
  x := x + dx
  y := y + dy
]

# Method with comment and validation
Person>>age: anAge [
  | age |
  "Validate age is positive"
  (anAge >= 0) ifFalse: [ Error signal: "Age must be positive" ].
  age := anAge
]

# Multiple methods (no trailing periods needed)
Person>>name [ ^ name ]

Person>>age [ ^ age ]

Person>>description [
  ^ name , " (age " , age asString , ")"
]
```

**Note**: The closing `]` acts as the terminator. No trailing period needed!
**Note**: Temporary variables (`| temp1 temp2 |`) must come BEFORE any statement comment strings.

**Note on `super`**: Use `super` to call parent methods. Inside a method, `super` refers to the parent of the prototype where the method was defined, enabling proper inheritance chaining.

### Why Two Syntaxes?

**REPL Mode** - Standard message passing:
```
Parser sees: Person at: "greet" put: [ ... ]
        ↓
Executes: Send 'at:put:' message to Person
```

**File Definition Mode** - Special parsing with `>>`:
```
Parser sees: Person>>greet [ ... ]
        ↓
Recognizes: Method definition syntax
        ↓
Converts to: Person at: "greet" put: [ ... ]
        ↓
Executes: Same as standard message send
```

Both `self` and `super` are available inside methods:
- `self` - The receiver of the message (dynamic dispatch from receiver's prototype)
- `super` - Lookup method in parent prototype (unqualified uses first parent, qualified uses explicit parent)

### Super Send Examples
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

## Message Sending

### Current Way (Works Everywhere)
```smalltalk
# Property bag access (deprecated for declared prototypes)
obj at: "property"                        # Get
obj at: "property" put: value             # Set

# Dynamic method invocation
obj perform: "methodName"                 # Call method
obj perform: "method:with:" with: args     # Call with args
```

### New Way (Declared Prototypes)
```smalltalk
# Generated accessor methods (compile to direct slot access)
person name                                 # Getter - direct read
person name: "Alice"                      # Setter - direct write

# Standard message sending (always available)
person greet                              # Unary message
3 + 4                                     # Binary message
person at: #key put: "value"           # Keyword (for collections)
```

### Direct Ivar Access (Inside Methods)
```smalltalk
# Inside method bodies, access ivars directly
Person>>greet [
  ^ "Hello, " , name                    # Direct slot access
]

Person>>birthday [
  | age |
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
  super initialize.                     # Call parent initialization
  salary := 0.0                         # Then init Employee ivars
]

Employee>>greet [
  "Override parent method, call super for base behavior"
  ^ super greet , " from " , department
]
```

The `super` keyword refers to the parent of the prototype where the current method was defined. This ensures that when you override a method, you can call the parent implementation using `super methodName`.

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
  | name age |
  name := "Anonymous".
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

# Collection access
arr at: 2              # Get element from array (1-based indexing)
tab at: "key"          # Get value from table
```

## Control Flow

```smalltalk
# Conditional (messages to boolean objects)
(x > 0) ifTrue: [ "positive" ] ifFalse: [ "negative" ]

# Looping
[ x < 10 ] whileTrue: [ x := x + 1 ]

# Collection iteration
numbers do: [ :each | each print ]
numbers select: [ :each | each > 5 ]
numbers collect: [ :each | each * 2 ]

# Multiline keyword messages (no period needed between lines)
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

See [NEWLINE_RULES.md](NEWLINE_RULES.md) for complete newline handling rules.

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
| String Concat | `,` (comma) | `,` (comma) - same as Smalltalk |
| File Structure | Image-based | File-based |
| Parsing | Single mode | REPL + Definition modes |
| String Literals | Single quotes | Double quotes only |

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
dict at: #key put: value                     # Property bag access
dict at: #key                                # Property retrieval

#=== Methods (in files) ======================
Proto>>method [ ^ result ]                    # Define unary
Proto>>method: arg [ ^ result ]               # Define keyword
Proto>>arg1: x arg2: y [ ^ x + y ]            # Multi-keyword

#=== Methods (in REPL) =======================
Proto at: #method put: [ ^ result ]          # Standard way
Proto perform: #method                       # Call dynamically

#=== Method Batching (extend:) ===============
Proto extend: [
  self >> method [ ^ result ]                # Batch instance methods
].

Proto extendClass: [
  self >> new [ ^ self derive ]              # Batch class-side methods
].

#=== Combined Creation (derive:methods:) =====
Proto := Object derive: #(#ivar) methods: [
  self >> method [ ^ result ]                # Create class with methods
].

#=== Self-Rebinding (asSelfDo:) ==============
obj asSelfDo: [
  self doSomething                           # self is obj here
]

#=== Message Sending =========================
obj method                                    # Unary
obj method: value                             # Keyword
obj binaryOp: other                           # Binary

#=== Inheritance =============================
Child := Parent derive: #(#newIvar)            # Inherit + add
Child>>method [ super perform: #method ]   # Call parent

#=== Control Flow ============================
expr ifTrue: [ block ] ifFalse: [ block ].
[ condition ] whileTrue: [ block ].
collection do: [ :each | block ].

#=== Comments ================================
# This is a comment (line, to end)
#==== Section header (no space needed after #)
"Inline comment" someCode                   # String as comment
#!/usr/bin/env ntalk                         # Shebang at start of file

#=== Strings =================================
"double quoted"                             # String literal
"""multiline"""                            # Multiline string
# Note: Character literals not yet implemented

#=== Temporary Variables =====================
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := 2
]                                            # Block with temps (no params)

[ :x | temp |
  temp := x * 2.
  ^ temp
]                                            # Block with param and temp

#=== Multi-char Binary Operators ============
a == b                                      # Equality
a ~= b                                      # Not equal
a <= b                                      # Less than or equal
a >= b                                      # Greater than or equal
a // b                                      # Integer division
a \ b                                       # Modulo
a ~~ b                                      # Not identity
```

## Method Definition Approaches

Nimtalk supports multiple approaches for defining methods:

### Approach 1: Individual Definition (>> syntax)
```smalltalk
# In .nt files only - transformed by parser
Person>>greet [ ^ "Hello, " , name ]
Person>>name: aName [ name := aName ]
```

### Approach 2: Batched Definition (extend:)
```smalltalk
# Works in both files and REPL
Person extend: [
  self >> greet [ ^ "Hello, " , name ].
  self >> name: aName [ name := aName ].
  self >> printString [ ^ name ]
]
```

### Approach 3: Combined Creation (derive:methods:)
```smalltalk
# Create class with ivars AND methods in one expression
Person := Object derive: #(name age) methods: [
  self >> greet [ ^ "Hello, I am " , name ].
  self >> haveBirthday [ age := age + 1 ]
]
```

### Approach 4: Class-side Methods (extendClass:)
```smalltalk
# Factory methods on the class object
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
```smalltalk
# Send message dynamically using symbols
obj perform: #methodName
obj perform: #method: with: arg
obj perform: #method:with: with: arg1 with: arg2

# Get all methods or properties
obj methods        # Returns array of symbols
obj properties     # Returns array of symbols
```

## Key Differences Summary

1. **String Literals**: Use `"double quotes"` only - single quotes are reserved
2. **Symbol Literals**: Use `#symbol` for selectors and keys
3. **Ivar Declaration**: `derive: #(#ivar1 #ivar2)` not property bags
4. **Method Definitions**: `>>` syntax in files, `at:put:` in REPL, `extend:` in both
5. **No Trailing Periods**: After method definitions (closing `]` is terminator)
6. **Direct Access**: Inside methods, access ivars directly by name
7. **Accessor Methods**: Used outside methods, compile to direct access
8. **Temporary Variables**: Must be first in block after `[` before any comments
9. **Multiline Keywords**: Keyword messages can span lines without periods

## Next Steps

✅ **COMPLETED**: All major features implemented!

1. ✅ Implemented `derive:` syntax in parser (as regular message)
2. ✅ Added instance variable storage with 149x performance improvement
3. ✅ Generated default accessors automatically (direct slot access)
4. ✅ `>>` method definition syntax (parser support completed)
5. ✅ Added `self` and `super` support in methods
6. ✅ Both REPL and File Definition modes work
7. ✅ Comprehensive test suite written and passing
8. ✅ Cascade syntax implemented (`;` operator)
9. ✅ Native method dispatch from Nimtalk code
10. ✅ Base library with Object, Boolean, Collections
11. ✅ Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`)
12. ✅ Enhanced comment handling (`#====` section headers)
13. ✅ Smalltalk-style temporary variables in blocks
14. ✅ Multiline keyword message support
15. ✅ `asSelfDo:` for self-rebinding blocks
16. ✅ `extend:` and `extendClass:` for method batching
17. ✅ `derive:methods:` for combined class creation
18. ✅ `perform:` family for dynamic message sending

## Additional Features Implemented

### Multi-Character Binary Operators

Nimtalk supports multi-character binary operators, matched longest-first:

```smalltalk
a == b      # Equality comparison
a ~= b      # Not equal
a <= b      # Less than or equal
a >= b      # Greater than or equal
a // b      # Integer division (double slash)
a \ b       # Modulo (single backslash)
a ~~ b      # Not identity
```

### Cascading Messages

Nimtalk supports Smalltalk's cascade syntax using `;` to send multiple messages to the same receiver:

```smalltalk
# Send multiple messages to the same object
obj at: #x put: 0; at: #y put: 0; at: #z put: 0

# Works with any message type
calculator clear; add: 5; add: 10; result

# Receiver is evaluated only once
counter increment; increment; increment
```

### Implementation Note

**File syntax (`>>`)**: The `>>` syntax for method definitions in files is now fully implemented. You can use either syntax:

```smalltalk
# New way (cleaner, file-only)
Person>>greet: name [ ^ "Hello " , name ]

# Standard way (works in REPL and files)
Person at: #greet: put: [ :name | ^ "Hello " , name ]
```

The `>>` syntax is transformed by the parser into the standard `at:put:` message send, so both approaches are functionally equivalent.

## Resources

- [NEWLINE_RULES.md](NEWLINE_RULES.md) - Newline handling rules
- [SPECIFICATION.md](SPECIFICATION.md) - Language specification details
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Debugging guide
- [closures.md](closures.md) - Closure implementation details
