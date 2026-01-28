# Nimtalk Syntax - Current Implementation

This document describes the **actual implemented syntax** in the current Nimtalk interpreter. Key updates:
- ✅ Slot-based instance variable system fully implemented (149x performance improvement)
- ✅ Binary operators implemented as regular messages
- ✅ Cascade syntax working (`;` operator)
- ✅ Direct ivar access inside methods

## String Literals

**Both single and double quotes work** for string literals:

```smalltalk
"This is a string"
'This is also a string'
```

The lexer (`src/nimtalk/parser/lexer.nim`) accepts both `'` and `"` as valid string delimiters. Use whichever style you prefer.

## Comments

Nimtalk supports **two comment styles**:

### 1. Smalltalk-style (double-quoted)
```smalltalk
"This is a comment"

"Create a shallow copy of this object"
^ self perform: 'primitiveClone'
```

### 2. Nim-style (hash)
```smalltalk
# This is a Nim-style comment (to end of line)
# They work anywhere, including at the start of files

# Array literal - the # is followed by (, not whitespace
#(1 2 3)

# Table literal - the # is followed by {, not whitespace
#{key: value}

# Symbol - the # is followed by a letter
#symbol
```

**Important**: The comment syntax `"comment"` (with double quotes) is distinct from string literals `"string"` by context. In practice, comments appear where statements would be, while strings appear as values.

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
Object at: 'error:' put: [
  :message
  self error: 'Message not understood: ' + message asString
].

# Traditional Smalltalk would require:
# Object at: 'error:' put: [
#   :message |
#   self error: 'Message not understood: ' + message asString
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

### Current Syntax (Implemented)

Methods are defined using explicit message passing:

```smalltalk
# Define a method on Object
Object at: 'printString' put: [
  ^ '<' + (self className) + '>'
].

# Keyword method
Array at: 'inject:into:' put: [
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
'world'

# Symbols
#symbol
#'symbol with spaces'

# Arrays (use Nim's seq)
#(1 2 3 "four")

# Tables (use Nim's Table)
#{key1: "value1" key2: 42}
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
obj at: "key" put: value           # set property
obj at: "key"                       # get property (also works on arrays/tables)
array inject: 0 into: [ :sum :each | sum + each ]

# Instance variable access (via generated accessors)
person name           # Generated getter - direct slot access
person name: "Alice"  # Generated setter - direct slot write

# Collection access with at:
arr := #(1 2 3).
arr at: 2             # returns 2 (1-based indexing, Smalltalk-style)

tab := #{"name" -> "Alice"}.
tab at: "name"        # returns "Alice"
```

## Cascading

Nimtalk implements the Smalltalk cascade syntax using `;` to send multiple messages to the same receiver:

```smalltalk
# Send multiple messages to the same object
obj at: "x" put: 0; at: "y" put: 0; at: "z" put: 0.

# Use with any message type
person name: "Alice"; age: 30; address: "123 Main St".

# The receiver is evaluated only once
counter increment; increment; increment; value
```

The receiver is evaluated once, then each message in the cascade is sent to that receiver in sequence.

## Differences from Smalltalk

1. **Cascading**: Implemented using `;` operator for sending multiple messages to same receiver
2. **Binary operators**: `+`, `-`, etc. are regular messages (not special syntax)
3. **No metaclasses**: Class methods are defined on the class object itself
4. **Nim integration**: Can embed Nim code using `<primitive>` tags
5. **Dual storage**: Property bags for dynamic objects + slots for performance (149x faster)
6. **No `>>` syntax yet**: Methods defined via `at:put:` (planned parser support)
7. **Direct ivar access**: Inside methods, access ivars by name without `at:`

## Embedding Nim Code

Use `<primitive>` tags for native Nim implementations:

```smalltalk
Object at: 'primitiveClone' put: <primitive>
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

**Note**: This reflects the syntax as of the current implementation (2026-01-28). Key features like slot-based instance variables are fully implemented. Check other documents for design decisions and future plans.
