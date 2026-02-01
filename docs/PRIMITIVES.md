# Primitive Syntax in Nimtalk

This document describes the syntax for direct primitive invocation in Nimtalk, which eliminates the overhead of going through `perform:` while maintaining clean, readable code.

## Overview

Nimtalk provides two related syntax forms for calling primitives:

1. **Declarative form** `<primitive: #selector>` - for methods that ARE primitives
2. **Inline form** `<primitive #selector args>` - for calling primitives within method bodies

Both forms bypass the `perform:` machinery, eliminating an extra method lookup and activation record.

## Declarative Form

Use when a method's entire purpose is to invoke a primitive with no Nimtalk code before or after.

### Syntax

```smalltalk
Receiver>>selector <primitive: #primitiveSelector>
Receiver>>selector: arg <primitive: #primitiveSelector:>
Receiver>>selector: arg1 with: arg2 <primitive: #primitiveSelector:with:>
```

### Examples

```smalltalk
# No arguments
Object>>clone <primitive: #primitiveClone>

# One argument
Object>>at: key <primitive: #primitiveAt:>
String>>size <primitive: #primitiveStringSize>

# Multiple arguments
Object>>at: key put: value <primitive: #primitiveAt:put:>
String>>replace: old with: new <primitive: #primitiveReplace:with:>

# Class methods
Array class>>new: size <primitive: #primitiveNew:>
String class>>with: character <primitive: #primitiveStringWith:>
```

### Benefits

- No method body block needed
- No activation record for wrapper method
- Clear intent: "this method IS that primitive"
- Parser validates that argument counts match

## Inline Form

Use when you need to execute Nimtalk code before or after the primitive call.

### Syntax

```smalltalk
<primitive #primitiveSelector>
<primitive #primitiveSelector: argument>
<primitive #primitiveSelector:with: arg1 arg2>
```

Arguments are provided directly after the selector, separated by spaces.

### Examples

```smalltalk
# Validation before primitive
Array>>at: index [
  (index < 1 or: [index > self size]) ifTrue: [
    self error: "Index out of bounds: " , index asString
  ].
  ^ <primitive #primitiveAt: index>
]

# Logging before primitive
Object>>shallowCopy [
  self log: "Creating shallow copy".
  ^ <primitive #primitiveClone>
]

# Multiple arguments
String>>replace: old with: new [
  old isEmpty ifTrue: [ ^ self ].
  ^ <primitive #primitiveReplace:with: old new>
]

# Post-processing result
FileStream>>readLine [
  | line |
  line := <primitive #primitiveFileReadLine>.
  line isNil ifTrue: [ ^ nil ].
  ^ line withoutTrailingNewline
]
```

## Comparison with perform:

### Old Approach (with perform:)

```smalltalk
Object>>clone [
  ^ self perform: #primitiveClone
]

Object>>at: key [
  ^ self perform: #primitiveAt: with: key
]

Object>>at: key put: value [
  ^ self perform: #primitiveAt:put: with: key with: value
]
```

**Call chain:** `clone` → `perform:` → `primitiveClone` (3 activations)

### New Approach (with primitive syntax)

```smalltalk
# Declarative
Object>>clone <primitive: #primitiveClone>
Object>>at: key <primitive: #primitiveAt:>
Object>>at: key put: value <primitive: #primitiveAt:put:>

# Or inline when needed
Object>>at: key [
  key isNil ifTrue: [ self error: "Key cannot be nil" ].
  ^ <primitive #primitiveAt: key>
]
```

**Call chain:** `clone` → `primitiveClone` (2 activations, or 1 if inlined)

## Validation

The parser and compiler verify:

1. **Primitive exists**: The referenced primitive must be registered
2. **Arity matches**: The number of arguments must match the number of colons in the primitive selector
3. **Valid syntax**: Proper use of `<primitive:>` vs `<primitive>`

## Error Messages

| Error | Example |
|-------|---------|
| Primitive not found | `Primitive not found: #primitiveFoo` |
| Arity mismatch | `Method takes 2 arguments but #primitiveAt: expects 1` |
| Invalid syntax | `Expected symbol after 'primitive:'` |

## Migration Guide

### Converting Existing perform: Calls

1. **Simple delegation** (no Nimtalk code):
   ```smalltalk
   # Before
   Object>>clone [ ^ self perform: #primitiveClone ]

   # After
   Object>>clone <primitive: #primitiveClone>
   ```

2. **With validation** (needs Nimtalk code):
   ```smalltalk
   # Before
   Array>>at: index [
     ^ self perform: #primitiveAt: with: index
   ]

   # After
   Array>>at: index [
     (index < 1 or: [index > self size]) ifTrue: [
       self error: "Out of bounds"
     ].
     ^ <primitive #primitiveAt: index>
   ]
   ```

## Backward Compatibility

The `perform:` mechanism remains available for:

- Dynamic message sending (selector determined at runtime)
- Backward compatibility with existing code
- Cases where the selector is not known statically

```smalltalk
# Still works - selector is a variable
selector := #primitiveClone.
obj perform: selector
```

## Implementation Notes

### Parser Handling

The parser treats `<primitive:` and `<primitive` as special tokens that trigger primitive-specific parsing:

1. **Declarative**: `Object>>selector <primitive: #foo>`
   - Parse method header normally
   - Check for `<primitive:` token
   - Parse the primitive selector symbol
   - Validate arity matches method parameters
   - No method body block expected

2. **Inline**: `<primitive #foo arg1 arg2>`
   - Parse `<primitive` token
   - Parse the primitive selector symbol
   - Count colons in selector to determine argument count
   - Parse that many expressions as arguments
   - Expect closing `>`

### Runtime Behavior

Both forms result in direct primitive invocation:

1. Look up the primitive method in the root object's method dictionary
2. Execute the native implementation directly
3. Skip the `perform:` machinery entirely

This eliminates:
- One method lookup (the `perform:` lookup)
- One activation record (the `perform:` call)
- Argument wrapping in LiteralNode objects

## Examples by Category

### Object Primitives

```smalltalk
Object>>clone <primitive: #primitiveClone>
Object>>derive <primitive: #primitiveDerive>
Object>>at: key <primitive: #primitiveAt:>
Object>>at: key put: value <primitive: #primitiveAt:put:>
Object>>== other <primitive: #primitiveEquals:>
Object>>properties <primitive: #primitiveProperties>
```

### String Primitives

```smalltalk
String>>+ other <primitive: #primitiveConcat:>
String>>size <primitive: #primitiveStringSize>
String>>at: index <primitive: #primitiveStringAt:>
String>>from: start to: end <primitive: #primitiveFromTo:>
String>>indexOf: substring <primitive: #primitiveIndexOf:>
String>>replace: old with: new <primitive: #primitiveReplaceWith:>
String>>uppercase <primitive: #primitiveUppercase>
String>>lowercase <primitive: #primitiveLowercase>
String>>trim <primitive: #primitiveTrim>
String>>split: delimiter <primitive: #primitiveSplit:>
```

### Collection Primitives

```smalltalk
Array>>add: element <primitive: #primitiveAdd:>
Array>>size <primitive: #primitiveSize>
Array>>at: index put: value <primitive: #primitiveAt:put:>
Array>>removeAt: index <primitive: #primitiveRemoveAt:>
Array>>includes: element <primitive: #primitiveIncludes:>

Table>>at: key put: value <primitive: #primitiveTableAt:put:>
Table>>keys <primitive: #primitiveKeys>
Table>>includesKey: key <primitive: #primitiveIncludesKey:>
```

### Block Primitives

```smalltalk
Block>>value <primitive: #primitiveValue>
Block>>value: arg <primitive: #primitiveValue:>
Block>>value: arg1 value: arg2 <primitive: #primitiveValue:value:>
Block>>whileTrue: bodyBlock <primitive: #primitiveWhileTrue:>
```

### Exception Primitives

```smalltalk
Exception>>signal <primitive: #primitiveSignal>
Exception class>>on: exceptionClass do: handlerBlock <primitive: #primitiveOnDo:>
```

### File Stream Primitives

```smalltalk
FileStream class>>open: filename mode: mode <primitive: #primitiveFileOpen:mode:>
FileStream>>close <primitive: #primitiveFileClose>
FileStream>>readLine <primitive: #primitiveFileReadLine>
FileStream>>write: string <primitive: #primitiveFileWrite:>
FileStream>>atEnd <primitive: #primitiveFileAtEnd>
```

## See Also

- [PERFORM.md](PERFORM.md) - Documentation on the `perform:` mechanism
- [SYNTAX-REALITY.md](SYNTAX-REALITY.md) - Current syntax implementation details
