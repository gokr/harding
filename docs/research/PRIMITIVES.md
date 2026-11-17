# Primitive Syntax in Harding

This document describes the unified syntax for direct primitive invocation in Harding.

## Overview

Harding provides a single unified syntax for calling primitives that works for both declarative method bodies and inline usage:

```smalltalk
<primitive selector: arg1 keyword2: arg2>
```

This syntax eliminates the overhead of going through `perform:` while maintaining clean, readable code. Arguments are provided using keyword message syntax, making the code self-documenting.

## Syntax

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

# Class methods
Array class>>new: size <primitive primitiveNew: size>
```

**Validation Rules for Declarative Primitives:**

1. Argument names in the primitive tag must match method parameter names exactly
2. Argument order must match parameter order
3. Argument count must match the number of colons in the primitive selector

Error messages when validation fails:

```smalltalk
# Wrong argument names
Object>>at: key put: value <primitive primitiveAt: x put: y>
# Error: Primitive argument names must match parameters: expected 'key' and 'value', got 'x' and 'y'

# Wrong argument count
Object>>at: key put: value <primitive primitiveAt: key>
# Error: Method has 2 parameters but primitive 'primitiveAt:' defines 1
```

### Inline Form

Use `<<primitive>>` within a method body when you need to execute Harding code before or after the primitive call. Arguments can be any variable reference: method parameters, temporaries, slots, or computed values.

```smalltalk
# Validation before primitive
Array>>at: index [
  (index < 1 or: [index > self size]) ifTrue: [
    self error: "Index out of bounds: " , index asString
  ].
  ^ <primitive primitiveAt: index>
]

# Logging before primitive
Object>>shallowCopy [
  self log: "Creating shallow copy".
  ^ <primitive primitiveClone>
]

# Using temporary variable
Object>>double [
  | temp |
  temp := self value.
  ^ <primitive primitiveAt: #value put: temp * 2>
]

# Post-processing result
FileStream>>readLine [
  | line |
  line := <primitive primitiveFileReadLine>.
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

### New Approach (with unified primitive syntax)

```smalltalk
# Declarative
Object>>clone <primitive primitiveClone>
Object>>at: key <primitive primitiveAt: key>
Object>>at: key put: value <primitive primitiveAt: key put: value>

# Inline when needed
Object>>at: key [
  key isNil ifTrue: [ self error: "Key cannot be nil" ].
  ^ <primitive primitiveAt: key>
]
```

**Call chain:** `clone` → `primitiveClone` (2 activations, or 1 if inlined)

## Benefits

1. **Single syntax to learn** - No confusing distinction between `primitive:>` and `primitive`
2. **Explicit arguments** - Arguments are visible in both declarative and inline forms
3. **Consistent with Smalltalk** - Uses keyword message syntax everywhere
4. **Better validation at parse time** - Argument names and counts are validated for declarative forms
5. **More efficient** - Bypasses `perform:` machinery, eliminating one activation record

## Validation

The parser verifies:

1. **Primitive syntax is valid** - Proper use of `<primitive>` tag
2. **Selector is well-formed** - Keywords properly separated by arguments
3. **Argument count matches** - For declarative forms, the number of arguments must match method parameter count
4. **Argument names match** - For declarative forms, argument names must match method parameters (for clarity and validation)

## Error Messages

| Error | Example |
|-------|---------|
| Primitive not found (runtime) | `Primitive not found: #primitiveFoo` |
| Argument count mismatch | `Method has 2 parameters but primitive 'primitiveAt:' defines 1` |
| Argument name mismatch | `Primitive argument names must match parameters: expected 'key', got 'x'` |

## Migration Guide

### Using Declarative Primitives

```smalltalk
# Declarative - method body is just the primitive
Object>>clone <primitive primitiveClone>
Object>>at: key <primitive primitiveAt: key>
Object>>at: key put: value <primitive primitiveAt: key put: value>
```

### Using Inline Primitives

```smalltalk
# Inline - within method body
Object>>at: key [
  key isNil ifTrue: [ self error: "Key cannot be nil" ].
  ^ <primitive primitiveAt: key>
]

Object>>at: key put: value [
  ^ <primitive primitiveAt: key put: value>
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

## Examples by Category

### Object Primitives

```smalltalk
Object>>clone <primitive primitiveClone>
Object>>at: key <primitive primitiveAt: key>
Object>>at: key put: value <primitive primitiveAt: key put: value>
Object>>== other <primitive primitiveEquals: other>
Object>>properties <primitive primitiveProperties>
```

### String Primitives

```smalltalk
String>>, other <primitive primitiveConcat:>
String>>size <primitive primitiveStringSize>
String>>at: index <primitive primitiveStringAt: index>
String>>from: start to: end <primitive primitiveFromTo: start to: end>
String>>indexOf: substring <primitive primitiveIndexOf: substring>
String>>replace: old with: new <primitive primitiveReplace: old with: new>
String>>uppercase <primitive primitiveUppercase>
String>>lowercase <primitive primitiveLowercase>
String>>trim <primitive primitiveTrim>
String>>split: delimiter <primitive primitiveSplit: delimiter>
```

### Collection Primitives

```smalltalk
Array>>add: element <primitive primitiveAdd: element>
Array>>size <primitive primitiveSize>
Array>>at: index put: value <primitive primitiveAt: index put: value>
Array>>removeAt: index <primitive primitiveRemoveAt: index>
Array>>includes: element <primitive primitiveIncludes: element>
Array>>join: separator <primitive primitiveJoin: separator>

Table>>at: key put: value <primitive at: key put: value>
Table>>keys <primitive primitiveKeys>
```

## Implementation Notes

### Parser Handling

The parser treats `<primitive` as a special token that triggers primitive parsing:

1. Parse the opening `<primitive`
2. Parse the selector and arguments as keyword message syntax
3. Parse the closing `>`
4. For declarative forms, validate against method parameters

### Runtime Behavior

Both declarative and inline forms result in direct primitive invocation:

1. Look up the primitive method in the receiver's method dictionary
2. Execute the native implementation directly
3. Skip the `perform:` machinery entirely

This eliminates:
- One method lookup (the `perform:` lookup)
- One activation record (the `perform:` call)

## See Also

- [current syntax reference](../QUICKREF.md) - General syntax reference
- [current implementation guide](../IMPLEMENTATION.md) - Runtime behavior details
