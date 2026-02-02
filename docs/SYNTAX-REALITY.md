# Nimtalk Syntax - Current Implementation

This document describes the **actual implemented syntax** in the current Nimtalk interpreter. Key updates:
- ✅ Slot-based instance variable system fully implemented (149x performance improvement)
- ✅ Binary operators implemented as regular messages
- ✅ Cascade syntax working (`;` operator)
- ✅ Direct ivar access inside methods
- ✅ `>>` method definition syntax fully implemented
- ✅ `super` keyword for method chaining
- ✅ `self` keyword for receiver reference

## String Literals

**Double quotes** for string literals:

```nimtalk
"This is a string"
```

Single quotes are reserved for future use.

## Comments

Nimtalk uses **hash-style comments**:

```nimtalk
# This is a comment

# Create a shallow copy of this object
^ self perform: #primitiveClone

# Array literal - the # is followed by (, not whitespace
#(1 2 3)

# Table literal - the # is followed by {, not whitespace
#{"key" -> "value"}

# Symbol - the # is followed by a letter
#symbol
```

**Note**: Double quotes are for strings, not comments. Hash-style `# comment` is the comment syntax.

## Shebang Support

Nimtalk scripts can include shebang lines at the beginning:

```smalltalk
#!/usr/bin/env ntalk
# This script can be made executable and run directly

calculator := Object derive.
calculator value: 3 + 4.
calculator value
```

When the kernel executes the script, the shebang line is automatically skipped by the lexer.

## Block Syntax

### Basic Blocks

Blocks are enclosed in square brackets `[]`:

```smalltalk
# Block without arguments
[ 1 + 2 ]

# Block with one argument
[ :x | x * 2 ]

# Block with multiple arguments
[ :x :y | x + y ]
```

### The `|` Separator

The vertical bar `|` **only appears when you have block parameters or temporaries**:

```smalltalk
# WITHOUT parameters or temporaries - no | needed
[ 1 + 2 ]

# WITH parameters but no temporaries - single | separates params from code
[ :x | x * 2 ]

[ :x :y | x + y ]

# WITHOUT params but WITH temporaries - | | encloses temporaries
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := 2
]

# WITH parameters AND temporaries - two | separators
[ :block | index size |
  index := 0.
  size := self size
]
```

**Nimtalk-specific feature**: Unlike most Smalltalk implementations, Nimtalk allows you to omit the `|` when a block has parameters but no temporaries. This is more concise while remaining unambiguous:

```smalltalk
# Nimtalk - valid and concise
Object at: #error: put: [
  :message
  self error: "Message not understood: " + message asString
].

# Traditional Smalltalk would require:
# Object at: #error: put: [
#   :message |
#   self error: "Message not understood: " + message asString
# ].
```

**Pattern**: `[:param1 :param2 | temporary1 temporary2 | code...]`

When there's no second `|` block (temporaries), the first `|` acts as the separator between parameters and code.

### Block Parameters and Temporaries

- **Parameters**: Start with colon `:`, listed before any `|`
- **Temporaries**: Listed between `|` and `|`, separated by spaces
- **Code**: After the final `|`

**Complete pattern examples:**

```smalltalk
# No params, no temps
[ code ]

# Params, no temps (Nimtalk style - optional |)
[ :x :y | code ]

# Params, no temps (explicit - also valid)
[ :x :y | | code ]

# No params, temps
[ | temp1 temp2 | code ]

# Params and temps
[ :x :y | temp1 temp2 | code ]
```

## Method Definition Syntax

### >> Syntax (Implemented)

Nimtalk supports the `>>` method definition syntax for cleaner method declarations:

```smalltalk
# Unary method (no parameters)
Person>>greet [ ^ "Hello, " + name ]

# Method with one parameter
Person>>name: aName [ name := aName ]

# Method with multiple keyword parameters
Point>>moveX: dx y: dy [
  x := x + dx.
  y := y + dy.
  ^ self
]

# Multiple definitions work in both REPL and files
Person>>id [ ^ 42 ].
Person>>label: text [ text ].
```

The `>>` syntax is parsed and transformed into standard `at:put:` message sends. Works in both interactive REPL mode and file mode.

### Standard Syntax (Also Implemented)

Methods can also be defined using explicit message passing:

```smalltalk
# Define a method on Object
Object at: #printString put: [
  ^ "<" + (self className) + ">"
].

# Keyword method
Array at: #inject:into: put: [
  :initialValue
  :block
  | result |
  result := initialValue.
  self do: [ :each |
    result := block value: result value: each
  ].
  ^ result
].
```

Both `>>` syntax and `at:put:` syntax are equivalent - the parser transforms `>>` into `at:put:`.

## Assignment

Use `:=` for assignment:

```smalltalk
obj := Object derive.
x := 5.
name := "Alice".
```

## Literals

```smalltalk
# Numbers
42
3.14159
-10

# Strings
"hello"
"world"

# Symbols
#symbol
#"symbol with spaces"

# Arrays (use Nim's seq)
#(1 2 3 "four")

# Tables (use Nim's Table) - use -> for key-value pairs
#{"key1" -> "value1" "key2" -> 42}
#{#symbolKey -> "value"}     # Symbol keys also supported
```

## Message Passing

Nimtalk uses Smalltalk-style message passing:

```smalltalk
# Unary messages
self printString

# Binary messages (✅ implemented as regular messages)
3 + 4
5 - 3
x > y
"Hello" , " World"   # string concatenation (comma operator)

# Keyword messages
obj at: #key put: value           # set property
obj at: #key                       # get property (also works on arrays/tables)
array inject: 0 into: [ :sum :each | sum + each ]

# Instance variable access (via generated accessors)
person name           # Generated getter - direct slot access
person name: "Alice"  # Generated setter - direct slot write

# Collection access with at:
arr := #(1 2 3).
arr at: 2             # returns 2 (1-based indexing, Smalltalk-style)

tab := #{"name" -> "Alice"}.
tab at: #name        # returns "Alice"
```

## Cascading

Nimtalk implements the Smalltalk cascade syntax using `;` to send multiple messages to the same receiver:

```smalltalk
# Send multiple messages to the same object
obj at: #x put: 0; at: #y put: 0; at: #z put: 0.

# Use with any message type
person name: "Alice"; age: 30; address: "123 Main St".

# The receiver is evaluated only once
counter increment; increment; increment; value
```

The receiver is evaluated once, then each message in the cascade is sent to that receiver in sequence.

---

## Primitive Syntax

Nimtalk supports three forms for working with primitives:

### Declarative Primitives

For methods that directly delegate to a primitive with no additional logic:

```smalltalk
Object>>clone <primitive: #primitiveClone>
Object>>at: key <primitive: #primitiveAt:>
Object>>at: key put: value <primitive: #primitiveAt:put:>
```

### Inline Primitives

For calling primitives within method bodies using keyword message syntax:

```smalltalk
Object>>at: key [
  key isNil ifTrue: [ self error: "Key cannot be nil" ].
  ^ <primitive primitiveAt: key>
]

Object>>at: key put: value [
  ^ <primitive primitiveAt: key put: value>
]
```

### Nim Code Embedding (Legacy)

Use `<primitive>` tags for native Nim implementations:

```smalltalk
Object at: #primitiveClone put: <primitive>
  ## Create a shallow copy in Nim
  result = clone(self)
</primitive>.
```

## Key Files Reference

- **Lexer**: `src/nimtalk/parser/lexer.nim` - Tokenization rules
- **Parser**: `src/nimtalk/parser/parser.nim` - Syntax parsing
- **Examples**: `examples/*.nt` - Working syntax examples
- **Core objects**: `lib/core/*.nt` - Standard library implementations

---

**Note**: This reflects the syntax as of the current implementation (2026-02-01). Key features like slot-based instance variables and multiline keyword messages are fully implemented. Check [NEWLINE_RULES.md](NEWLINE_RULES.md) for newline handling details.
