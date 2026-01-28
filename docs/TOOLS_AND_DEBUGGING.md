# Nimtalk Tools and Debugging Guide

## Overview

Nimtalk provides several command-line tools to support development, debugging, and deployment:

- `ntalk` - REPL and interpreter for interactive development
- `ntalkc` - Compiler for transforming Nimtalk to Nim code
- `build.nims` - Build automation script

## The REPL: ntalk

The `ntalk` command provides both interactive REPL and script execution capabilities.

### Usage

```bash
# Start interactive REPL
ntalk

# Run a script file
ntalk script.nt

# Evaluate an expression
ntalk -e "3 + 4"

# Show AST without executing (parse only)
ntalk --ast script.nt

# Run with debug logging
ntalk --loglevel DEBUG script.nt

# Combine flags
ntalk --ast --loglevel DEBUG -e "Object clone"
```

### Command-Line Options

**--ast**: Dump the Abstract Syntax Tree after parsing and continue execution
- Useful for understanding how code is parsed
- Shows the hierarchical structure of expressions
- Execution continues after displaying the AST

**--loglevel <level>**: Set logging verbosity
- DEBUG: Detailed tracing of execution flow
- INFO: General operation information
- WARN: Warnings about potential issues
- ERROR: Error messages only (default)

**-e "<code>":** Evaluate an expression directly
**--test:** Run built-in tests
**--version:** Show version information
**--help:** Display usage information

### Debug Logging Output

When using `--loglevel DEBUG`, ntalk provides detailed execution tracing:

```
DEBUG Evaluating node: nkMessage
DEBUG Message send: +
DEBUG Message receiver: 3
DEBUG Looking up method: +
DEBUG Found method, executing
DEBUG Executing method with 1 arguments
DEBUG Pushing activation, stack depth: 1
DEBUG Evaluating node: nkLiteral
DEBUG Returning from method: 7
DEBUG Popping activation, stack depth: 0
```

This shows:
- AST node types being evaluated
- Message sends with receivers and selectors
- Method lookup and execution
- Activation stack operations
- Return values

### Interactive REPL Commands

Inside the REPL, these commands are available:

- `:help` - Show REPL help
- `:globals` - Display global variables
- `:quit` or `^D` - Exit REPL
- `:clear` - Clear the screen
- `:trace` - Toggle execution tracing

## The Compiler: ntalkc

The `ntalkc` command compiles Nimtalk source to Nim code.

### Usage

```bash
# Compile to Nim source
ntalkc compile input.nt -o output.nim

# Compile and build executable
ntalkc build input.nt -d build/

# Compile, build, and run
ntalkc run input.nt --release

# Show AST before compiling
ntalkc compile input.nt --ast

# Compile with debug logging
ntalkc compile input.nt --loglevel DEBUG
```

### Commands

**compile**: Transform Nimtalk to Nim source code
**build**: Compile to Nim and build executable
**run**: Compile, build, and execute the result
**help**: Show usage information
**version**: Show version information

### Options

**-o, --output <file>**: Output Nim file path (compile only)
**-d, --dir <dir>**: Output directory (default: ./build)
**-r, --release**: Build with optimization flags
**--ast**: Dump AST before compiling
**--loglevel <level>**: Set logging verbosity
**-h, --help**: Show help
**-v, --version**: Show version

## Build System: build.nims

The build.nims script provides convenient build automation.

```bash
# Build both ntalk and ntalkc (copies to root directory)
nim e build.nims repl

# Run tests
nim e build.nims test

# Clean build artifacts
nim e build.nims clean

# Install to ~/.local/bin/
nim e build.nims install
```

## Debugging Techniques

### 1. AST Inspection

Use `--ast` to understand how code is parsed:

```bash
# See AST for expression
ntalk --ast -e "3 + 4"

# See AST for complex code
ntalk --ast script.nt
```

AST output shows the structure:
```
Message(+)
  receiver:
    Literal(3)
  arg:
    Literal(4)
```

### 2. Execution Tracing

Use `--loglevel DEBUG` to trace execution:

```bash
# Trace message sends and method execution
ntalk --loglevel DEBUG script.nt

# Combine with AST output
ntalk --ast --loglevel DEBUG script.nt
```

### 3. Interactive Exploration

Use the REPL to test small pieces of code:

```bash
$ ntalk
nt> obj := Object derive
nt> obj at: 'test' put: 42
nt> obj at: 'test'
42
```

### 4. Test Cases

Create test files to isolate and reproduce issues:

```smalltalk
# test_debug.nt
test := Object derive.
test at: 'value' put: 3 + 4.
test at: 'value'  # Should be 7
```

Then run: `ntalk --ast --loglevel DEBUG test_debug.nt`

## Common Issues and Solutions

### "Message not understood" Errors

This means the method doesn't exist on the receiver:

```bash
# Debug with --loglevel DEBUG
ntalk --loglevel DEBUG script.nt

# Check what the receiver actually is
ntalk -e "obj := Object clone. obj unknownMessage"
```

Debug output shows:
```
DEBUG Looking up method: unknownMessage
DEBUG Method not found, sending doesNotUnderstand:
```

### Parse Errors

Use `--ast` to see if code is parsed correctly:

```bash
# See parse error details
ntalk --ast script_with_error.nt

# Compare with working code
ntalk --ast working_script.nt
```

### Execution Differences

If interpreter and compiler behave differently:

```bash
# Test with interpreter
ntalk --loglevel DEBUG script.nt

# Test AST (same for both)
ntalk --ast script.nt
ntalkc compile script.nt --ast
```

## Best Practices

1. **Start with AST**: Use `--ast` to verify parsing before debugging execution
2. **Use DEBUG logging**: Add `--loglevel DEBUG` when behavior is unexpected
3. **Test incrementally**: Build test cases that isolate specific features
4. **Use REPL for exploration**: Test expressions interactively before writing scripts
5. **Check return values**: Use `-e` to test small expressions quickly

## Integration with Development Workflow

### Editor Integration

- Configure your editor to run `ntalk --ast` on current file
- Set up keyboard shortcuts for quick REPL access
- Use `--loglevel DEBUG` in build scripts for CI debugging

### Testing

```bash
# Run all tests with debug logging
nim e build.nims test --loglevel DEBUG

# Test specific file with AST output
ntalk --ast tests/test_specific.nim
```

### Continuous Integration

```bash
# Example CI script
#!/bin/bash
set -e

# Verify AST parses correctly
ntalk --ast examples/*.nt

# Run all tests with info logging
nim e build.nims test --loglevel INFO

# Run any example scripts
ntalk examples/demo.nt
```

## Advanced Debugging

### Adding Custom Debug Logging

When developing Nimtalk itself, add debug statements:

```nim
import std/logging

# In evaluator or other components
debug("Custom trace: ", someValue)
```

These only appear with `--loglevel DEBUG`.

### Programmatic Logging Control

For tests and embedded usage, control logging programmatically:

```nim
import std/logging
import nimtalk/core/types

# Configure logging with specific level
configureLogging(lvlError)  # Suppress debug output
configureLogging(lvlDebug)  # Enable debug output

# Or just set the level
setLogLevel(lvlWarn)
```

Available levels: `lvlDebug`, `lvlInfo`, `lvlWarn`, `lvlError`, `lvlFatal`

This is used in the test suite to keep test output clean while allowing debug output when needed.

### Debugging the Debugger

If debugging tools themselves have issues:

```bash
# Check tool versions
ntalk --version
ntalkc --version

# Verify installation
which ntalk
which ntalkc

# Test minimal case
ntalk -e "42"
```

### Performance Profiling

```bash
# Use Nim's profiler with compiled code
ntalkc compile script.nt -o profile_me.nim
nim c -r -d:release --profiler:on --stackTrace:on profile_me.nim
```

## Summary

Nimtalk provides comprehensive debugging tools:
- `--ast` for parsing inspection
- `--loglevel DEBUG` for execution tracing
- REPL for interactive exploration
- `build.nims` for automation

Combine these tools to quickly identify and resolve issues during development.
