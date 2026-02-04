# Exception Handling in Nemo

Nemo provides exception handling through the `on:do:` mechanism, which allows blocks of code to be protected with exception handlers.

## Basic Syntax

```nemo
[ protectedBlock ] on: ExceptionClass do: [ :ex | handlerBlock ]
```

Example:
```nemo
[ "Hello" / 3 ] on: Error do: [ :ex |
    Transcript showCr: "Error occurred: " + ex message
]
```

## How It Works

### Architecture

Nemo's exception handling is built directly on top of Nim's exception mechanism. The interpreter maintains a stack of `ExceptionHandler` records:

```nim
type
  ExceptionHandler = object
    exceptionClass: Class    # Exception class to catch
    handlerBlock: BlockNode  # Block to execute when caught
    activation: Activation   # Activation where handler installed
    stackDepth: int          # Stack depth at installation
```

### Handler Installation

When `on:do:` is executed:

1. The protected block is extracted from the receiver
2. A new `ExceptionHandler` is pushed onto the stack with:
   - The exception class to match against
   - The handler block to execute
   - Current activation and stack depth

### Exception Flow

The protected block executes inside a native Nim `try/except` block:

```nim
try:
    result = evalBlock(protectedBlock)
except ValueError as e:
    # Search handler stack from newest to oldest
    for handler in exceptionHandlers (reverse order):
        if handler matches exception and is in scope:
            - Create exception object with message + stack trace
            - Remove this handler and all above it
            - Execute handler block with exception as argument
            - Return handler's result
    if no handler found:
        re-raise the exception
finally:
    # Clean up handler if still present
```

## Benefits of Nim Integration

The protected block is executed inside a native Nim `try/except/finally` block. When Nemo code calls `error: 'message'`, it ultimately executes:

```nim
raise newException(EvalError, msg)
```

### 1. Seamless Interop

- Nim libraries that raise exceptions can be caught in Nemo with `on:do:`
- Nemo exceptions propagate naturally through Nim code
- No translation layer between exception systems

### 2. No Custom Unwinding Logic

- The interpreter doesn't need to manually unwind the activation stack
- Nim's exception handling does the heavy lifting

### 3. Resource Cleanup

The `finally` block ensures handlers are removed even if no exception occurs:

```nim
finally:
    if exceptionHandlers.len > 0:
        let lastIdx = exceptionHandlers.len - 1
        if exceptionHandlers[lastIdx].handlerBlock == handlerBlock:
            exceptionHandlers.setLen(lastIdx)
```

Works with Nim's deterministic exception handling.

### 4. Stack Traces

When an exception occurs, `formatStackTrace()` captures the current activation stack:

```
1: someMethod
2: callerMethod
3: main
```

Can access Nim's native stack trace info if needed.

## The Trade-off

The current implementation immediately unwinds the stack to the handler (standard Nim behavior). This differs from Smalltalk's more sophisticated mechanism where handlers could theoretically inspect the stack and decide to resume.

For integration with Nim libraries, this is the right choice - it matches Nim's semantics and lets exceptions flow naturally between Nemo and Nim code.

## Differences from Smalltalk

| Feature | Nemo | Smalltalk |
|---------|------|-----------|
| Implementation | Built on Nim exceptions | Custom VM mechanism |
| Stack unwinding | Immediate (Nim default) | Immediate |
| Resume capability | No | Yes (`resume:`, `retry`) |
| Handler execution | After full unwind | In handler context |
| Nim interop | Native | Not applicable |

Nemo trades Smalltalk's advanced features (resumable exceptions) for seamless integration with Nim's ecosystem.

## Raising Exceptions

Use `error:` to raise an exception:

```nemo
someCondition ifTrue: [
    Error error: "Something went wrong"
]
```

## Exception Objects

When caught, exception objects have:
- `message` - The error message string
- `stackTrace` - String representation of the call stack

Example:
```nemo
[ riskyOperation ] on: Error do: [ :ex |
    Transcript showCr: "Message: " + ex message.
    Transcript showCr: "Stack: " + ex stackTrace
]
```

## Best Practices

1. **Catch specific exceptions** - Use specific exception classes rather than catching all errors
2. **Clean up resources** - Use `on:do:` for resource cleanup (though Nemo doesn't have a direct equivalent to `ensure:` yet)
3. **Don't swallow exceptions** - Either handle properly or re-raise
4. **Provide context** - Include helpful messages when raising exceptions

## Implementation Notes

- Handlers are stored in `Interpreter.exceptionHandlers` (a `seq[ExceptionHandler]`)
- Class matching is currently simple equality check
- The activation stack is unwound to the handler's depth when an exception is caught
- Nim's `ValueError` is used as the underlying exception type for Nemo errors
