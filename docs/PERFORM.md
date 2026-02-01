# The `perform:` Mechanism in Nimtalk

This document explains how `perform:` works for dynamic message sending in Nimtalk, including its implementation details and performance characteristics.

## Overview

`perform:` enables dynamic message sending where the selector (method name) is determined at runtime rather than at parse time. This is essential for:

- Forwarding unknown messages (`doesNotUnderstand:`)
- Implementing proxy objects
- Dynamic method invocation from symbols or strings
- Metaprogramming and reflection

## Usage

```nimtalk
"object perform: #selector"
"object perform: #selector with: arg"
"object perform: #selector with: arg1 with: arg2"
```

Examples:

```nimtalk
obj perform: #clone                    "Same as: obj clone"
obj perform: #at:put: with: #x with: 5  "Same as: obj at: #x put: 5"
```

## Implementation

### Parser Level

`perform:` is **not** handled specially by the parser. It is parsed as a regular keyword message via `parseKeywordMessage()` in `src/nimtalk/parser/parser.nim`. There is no special AST node type for `perform:` - it creates a standard `MessageNode` with the selector `"perform:"`, `"perform:with:"`, etc.

### Runtime Level

The implementation involves a two-level message send:

#### Level 1: The `perform:` Message

When `obj perform: #selector with: arg` is evaluated:

1. The evaluator looks up `perform:with:` in the receiver's class (O(1) lookup in the `allMethods` table)
2. Finds the native implementation `performWithImpl` (registered in `src/nimtalk/interpreter/evaluator.nim:92-95`)
3. Calls this native method with the interpreter as a parameter

#### Level 2: Dynamic Dispatch

Inside `performWithImpl` (`src/nimtalk/interpreter/evaluator.nim:1318-1346`):

1. Extracts the selector from the first argument (must be a symbol or string)
2. Calls `lookupMethod()` again to find the target method
3. Wraps remaining arguments in `LiteralNode` objects
4. Calls `executeMethod()` to invoke the target method

```nim
proc performWithImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Send a message to self with arguments: self perform: #selector with: arg
  if args.len < 1:
    return nilValue()

  # Get the selector from first argument
  var selector: string
  if args[0].kind == vkSymbol:
    selector = args[0].symVal
  elif args[0].kind == vkString:
    selector = args[0].strVal
  else:
    return nilValue()

  # Look up the method
  let methodResult = lookupMethod(interp, self, selector)
  if not methodResult.found:
    return nilValue()

  # Prepare arguments (skip the selector, take remaining args)
  var messageArgs: seq[Node] = @[]
  if args.len >= 2 and args[1].kind != vkNil:
    messageArgs.add(LiteralNode(value: args[1]))
  if args.len >= 3 and args[2].kind != vkNil:
    messageArgs.add(LiteralNode(value: args[2]))

  # Execute the method
  return executeMethod(interp, methodResult.currentMethod, self, messageArgs, methodResult.definingClass)
```

## Registration

The `perform:` methods are registered on the root object during interpreter initialization (`src/nimtalk/interpreter/evaluator.nim:85-101`):

```nim
# Add perform: method to root object (interpreter-aware)
let performMethod = createCoreMethod("perform:")
performMethod.nativeImpl = cast[pointer](performWithImpl)
performMethod.hasInterpreterParam = true
addMethod(result.rootObject.RuntimeObject, "perform:", performMethod)

# Add perform:with: method to root object (interpreter-aware)
let performWithMethod = createCoreMethod("perform:with:")
performWithMethod.nativeImpl = cast[pointer](performWithImpl)
performWithMethod.hasInterpreterParam = true
addMethod(result.rootObject.RuntimeObject, "perform:with:", performWithMethod)

# Add perform:with:with: method to root object (interpreter-aware)
let performWithWithMethod = createCoreMethod("perform:with:with:")
performWithWithMethod.nativeImpl = cast[pointer](performWithImpl)
performWithWithMethod.hasInterpreterParam = true
addMethod(result.rootObject.RuntimeObject, "perform:with:with:", performWithWithMethod)
```

## Primitives and `perform:`

Primitives (native methods) can be invoked via `perform:` using their internal selector names. These are registered in `src/nimtalk/interpreter/objects.nim:247-282`:

| Primitive | Internal Selector |
|-----------|-------------------|
| `clone` | `primitiveClone` |
| `derive` | `primitiveDerive` |
| `derive:` | `primitiveDeriveWithIVars:` |
| `at:` | `primitiveAt:` |
| `at:put:` | `primitiveAt:put:` |
| `hasProperty:` | `primitiveHasProperty:` |
| `respondsTo:` | `primitiveRespondsTo:` |
| `=` | `primitiveEquals:` |
| `error:` | `primitiveError:` |
| `properties` | `primitiveProperties` |

Example:

```nimtalk
obj perform: #primitiveClone    "Same as: obj clone (primitive version)"
```

## Performance Characteristics

### Overhead Compared to Direct Calls

| Aspect | Direct Call | Via `perform:` |
|--------|-------------|----------------|
| Method lookup | Single `lookupMethod` | Two `lookupMethod` calls |
| Method execution | Direct `executeMethod` | Native wrapper + `executeMethod` |
| Argument handling | Evaluated once | Wrapped in `LiteralNode` objects |

### No Special Optimizations

There is currently no special optimization for `perform:`:

- No inline caching
- No selector-to-method cache
- No special-case handling in the evaluator

Every `perform:` goes through the full two-level dispatch. This is a straightforward implementation typical of early interpreters.

## Use Cases

### Message Forwarding

```nimtalk
Object extend: [
  doesNotUnderstand: message withArgs: args [
    "Forward to another object"
    delegate perform: message with: args
  ]
]
```

### Dynamic Method Invocation

```nimtalk
"Invoke a method based on user input"
selector := #someMethod.
obj perform: selector with: argument
```

### Proxy Objects

```nimtalk
Proxy extend: [
  "Intercept all messages and log them"
  doesNotUnderstand: selector withArgs: args [
    self log: selector.
    ^target perform: selector with: args
  ]
]
```

## Summary

`perform:` is implemented as a native method that performs dynamic dispatch. While it provides powerful metaprogramming capabilities, it comes with the overhead of an extra method lookup and argument wrapping. For performance-critical code, direct message sends should be preferred over `perform:`.
