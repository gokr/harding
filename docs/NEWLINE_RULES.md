# Newline Handling in Nimtalk

This document describes how Nimtalk handles newlines and statement separation.

## Overview

In Smalltalk, the period `.` is the only statement separator. However, Nimtalk takes a more pragmatic approach:

- **Periods** explicitly terminate statements
- **Line endings** act as statement separators (except when continuing a keyword message chain)
- **Multiline keyword messages** are supported

## Statement Separation

### Period (Explicit)

Use `.` to explicitly end a statement:

```smalltalk
x := 1.
y := 2.
z := x + y.
```

### Line Ending (Implicit)

A line ending also acts as a statement separator:

```smalltalk
x := 1
y := 2
z := x + y
```

Both forms are equivalent.

## Keyword Messages Can Span Lines

Keyword message chains can span multiple lines while forming a single statement:

```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

This is parsed as a single statement: `tags isNil ifTrue: [...] ifFalse: [...]`.

## Where Newlines Are NOT Allowed

### Binary Operators

Binary operators must be on the same line as their operands:

```smalltalk
# Valid
result := x + y

# Invalid (fails to parse)
result := x
  + y
```

### Unary Messages

Unary message chains must be on the same line:

```smalltalk
# Valid
array addFirst: item

# Invalid (fails to parse)
array
  addFirst: item
```

### Method Definitions

Method selectors must be on one line:

```smalltalk
# Valid
Integer>>to: end do: block [ | i |
  i := self
]

# Invalid (fails to parse)
Integer>>
  to: end do: block [ | i |
    i := self
  ]
```

## Temporary Variables in Blocks

Temporary variables must be declared at the beginning of a block, before any statements or comments:

```smalltalk
# Valid
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := 2
]

# Invalid - comment before temporaries
[ # some comment
  | temp1 |
  temp1 := 1
]

# Valid - comment after temporaries
[ | temp1 |
  # some comment
  temp1 := 1
]
```

## Comments

Nimtalk uses `#` for single-line comments:

```smalltalk
# This is a comment
#==== This header is also a comment

MyMethod>>doSomething [
  # This is a comment inside the method
  ^ result
]
```

String literals use double quotes:

```smalltalk
"This is a string literal"
```

## Summary

| Construct | Multiline? | Example |
|-----------|-----------|---------|
| Keyword message chain | Yes | `obj msg1: a\n msg2: b` |
| Binary operator | No | `x\n+\ny` fails |
| Unary message chain | No | `obj\nmsg` fails |
| Method selector | No | `Class>>\nselector` fails |
| Statement separator | Yes (newline or `.`) | `x := 1\ny := 2` |
| Block temporaries | Yes | `[ | t |\n t := 1 ]` |
