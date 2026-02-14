# Harding Tools and Debugging Guide

## Overview

Harding provides several command-line tools to support development, debugging, and deployment:

- `harding` - REPL and interpreter for interactive development
- `harding_debug` - REPL with debugger support for VSCode integration
- `harding-lsp` - Language Server for IDE support
- `granite` - Compiler for transforming Harding to Nim code
- `bona` - GTK-based graphical IDE (Bonadventure)
- `nimble` - Build automation and package management

## The REPL: harding

The `harding` command provides both interactive REPL and script execution capabilities.

### Usage

```bash
# Start interactive REPL
harding

# Run a script file
harding script.harding

# Evaluate an expression
harding -e "3 + 4"

# Show AST without executing (parse only)
harding --ast script.harding

# Run with debug logging
harding --loglevel DEBUG script.harding

# Combine flags
harding --ast --loglevel DEBUG -e "Object clone"
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
**--debugger-port <port>:** Start debugger server on specified port (requires `-d:debugger` build)

### Script Files

Harding script files (`.hrd` extension) are executed as blocks, enabling temporary variable declarations:

```smalltalk
# script.hrd
| counter total |
counter := 0
total := 0
1 to: 5 do: [:i |
  counter := counter + 1
  total := total + i
]
total  "Returns sum of 1+2+3+4+5 = 15"
```

**Script execution details:**
- Scripts are auto-wrapped in `[... ]` before parsing
- Temporary variables are declared with `| var1 var2 |` at the start
- Scripts execute with `self = nil` (Smalltalk workspace convention)
- No need for uppercase globals in simple scripts - use lowercase temporaries
- File extension can be `.hrd`, `.harding`, or no extension

### Debug Logging Output

When using `--loglevel DEBUG`, harding provides detailed execution tracing:

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

## The Debugger: harding_debug

The `harding_debug` command provides a REPL with integrated debugger support for VSCode.

### Building

```bash
# Build with debugger support
nimble harding_debug
```

### Usage

```bash
# Start with debugger server
harding_debug --debugger-port 9877

# Debug a script
harding_debug --debugger-port 9877 script.hrd

# Debug with other options
harding_debug --debugger-port 9877 --loglevel DEBUG script.hrd
```

### Debugger Protocol

The debugger communicates via TCP using the Harding Debug Protocol (HDP):

- **Port**: Configurable (default 9877)
- **Protocol**: JSON-RPC style messages
- **Features**: Breakpoints, stepping, call stack, variables

### VSCode Integration

The debugger integrates with VSCode via the Debug Adapter Protocol (DAP):

1. Build the extension: `nimble vsix`
2. Install: `code --install-extension vscode-harding/vscode-harding-0.4.0.vsix`
3. Set breakpoints in VSCode
4. Press F5 to debug

See [VSCODE.md](VSCODE.md) for full details.

## The Language Server: harding-lsp

The `harding-lsp` command provides IDE features via the Language Server Protocol (LSP).

### Building

```bash
nimble harding_lsp
```

### Usage

```bash
harding-lsp --stdio
```

### Features

- **Completions** - Context-aware selector suggestions
- **Hover** - Documentation and type information
- **Go to Definition** - Navigate to method definitions
- **Document Symbols** - Outline view
- **Workspace Symbols** - Global search

## The Compiler: granite

The `granite` command compiles Harding source to Nim code and optionally builds native binaries.

### Usage

```bash
# Compile .hrd to Nim source (output in build/ directory)
granite compile script.hrd

# Compile with custom output
granite compile script.hrd -o output.nim

# Compile and build native executable
granite build script.hrd

# Compile, build, and run
granite run script.hrd

# Build with optimizations (release mode)
granite run script.hrd --release

# Build with maximum optimizations (danger mode)
granite build script.hrd --danger

# Show AST before compiling
granite compile script.hrd --ast

# Compile with debug logging
granite compile script.hrd --loglevel DEBUG
```

### Commands

**compile**: Transform Harding to Nim source code
**build**: Compile to Nim and build executable
**run**: Compile, build, and execute the result
**help**: Show usage information
**version**: Show version information

### Options

**-o, --output <file>**: Output Nim file path (compile only)
**-d, --dir <dir>**: Output directory (default: ./build)
**-r, --release**: Build with `-d:release` optimization flags
**--danger**: Build with `-d:danger` (no runtime checks, maximum speed)
**--ast**: Dump AST before compiling
**--loglevel <level>**: Set logging verbosity
**-h, --help**: Show help
**-v, --version**: Show version

### What Gets Compiled

Granite compiles standalone `.hrd` scripts with inline control flow:
- `ifTrue:`, `ifFalse:`, `ifTrue:ifFalse:` → Nim `if/else`
- `whileTrue:`, `whileFalse:` → Nim `while`
- `timesRepeat:` → Nim `for`
- Arithmetic and comparisons → helper function calls
- Variables → direct Nim `var` declarations

## The IDE: bona

The `bona` command launches the Bonadventure IDE, a GTK-based graphical development environment.

### Usage

```bash
# Launch the IDE
bona

# With custom home directory
bona --home /path/to/harding/home

# With custom bootstrap file
bona --bootstrap /path/to/bootstrap.hrd

# With debug logging
bona --loglevel DEBUG
```

### IDE Features

- **Launcher** - Main IDE window with menu bar
- **Workspace** - Code editor with do-it/print-it/inspect-it functionality
- **Transcript** - Output console for logging and results
- **Inspector** - Object introspection tool (Ctrl+I in Workspace)

### IDE Keyboard Shortcuts

| Shortcut | Action | Description |
|----------|--------|-------------|
| Ctrl+D | Do It | Evaluate selection/line, print result to Transcript |
| Ctrl+P | Print It | Evaluate selection/line, insert result after selection |
| Ctrl+I | Inspect It | Evaluate selection/line, open Inspector on result |

### Building the IDE

```bash
# Build bona (GTK4 version, default)
nimble bona

# Build release version
nimble bona_release

# Build GTK3 version (if GTK4 not available)
nimble gui3
```

### Desktop Integration

For proper dock and Alt-Tab icons in Ubuntu/GNOME:

```bash
# Install .desktop file and icon
nimble install_bona
```

This installs:
- `~/.local/share/applications/bona.desktop` - Desktop entry
- `~/.local/share/icons/hicolor/256x256/apps/harding.png` - Application icon
- Updates desktop database

After installation:
- Launch Bona from the applications menu
- Icon appears correctly in dock and Alt-Tab switcher
- Window is identified as "Bonadventure IDE"

## Nimble Tasks

Nimble provides convenient build automation.

```bash
# Build both harding and granite (binaries in subdirectories)
nimble build

# Build and copy binaries to root directory
nimble local

# Build with debugger support
nimble harding_debug

# Build Language Server
nimble harding_lsp

# Build VSCode extension
nimble vsix

# Build with BitBarrel support
nimble harding_bitbarrel

# Build GUI IDE (debug)
nimble bona

# Build GUI IDE (release)
nimble bona_release

# Install desktop integration (.desktop and icon)
nimble install_bona

# Run tests
nimble test

# Clean build artifacts
nimble clean

# Install to ~/.local/bin/
nimble install
```

## Debugging Techniques

### 1. AST Inspection

Use `--ast` to understand how code is parsed:

```bash
# See AST for expression
harding --ast -e "3 + 4"

# See AST for complex code
harding --ast script.harding
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
harding --loglevel DEBUG script.harding

# Combine with AST output
harding --ast --loglevel DEBUG script.harding
```

### 3. Interactive Exploration

Use the REPL to test small pieces of code:

```bash
$ harding
nt> obj := Object derive
nt> obj at: #test put: 42
nt> obj at: #test
42
```

### 4. Test Cases

Create test files to isolate and reproduce issues:

```smalltalk
# test_debug.harding
test := Object derive.
test at: #value put: 3 + 4.
test at: #value  "Should be 7"
```

Then run: `harding --ast --loglevel DEBUG test_debug.harding`

## Common Issues and Solutions

### "Message not understood" Errors

This means the method doesn't exist on the receiver:

```bash
# Debug with --loglevel DEBUG
harding --loglevel DEBUG script.harding

# Check what the receiver actually is
harding -e "obj := Object clone. obj unknownMessage"
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
harding --ast script_with_error.harding

# Compare with working code
harding --ast working_script.harding
```

### Execution Differences

If interpreter and compiler behave differently:

```bash
# Test with interpreter
harding --loglevel DEBUG script.hrd

# Test AST (same for both)
harding --ast script.hrd
granite compile script.hrd --ast

# Compare output
harding script.hrd > interp_output.txt
granite run script.hrd > compiled_output.txt
diff interp_output.txt compiled_output.txt
```

## Best Practices

1. **Start with AST**: Use `--ast` to verify parsing before debugging execution
2. **Use DEBUG logging**: Add `--loglevel DEBUG` when behavior is unexpected
3. **Test incrementally**: Build test cases that isolate specific features
4. **Use REPL for exploration**: Test expressions interactively before writing scripts
5. **Check return values**: Use `-e` to test small expressions quickly

## Integration with Development Workflow

### Editor Integration

- Configure your editor to run `harding --ast` on current file
- Set up keyboard shortcuts for quick REPL access
- Use `--loglevel DEBUG` in build scripts for CI debugging

### Testing

```bash
# Run all tests
nimble test

# Test specific file with AST output
harding --ast tests/test_specific.nim
```

### Continuous Integration

```bash
# Example CI script
#!/bin/bash
set -e

# Verify AST parses correctly
harding --ast examples/*.harding

# Run all tests
nimble test

# Run any example scripts
harding examples/demo.harding
```

## Advanced Debugging

### Adding Custom Debug Logging

When developing Harding itself, add debug statements:

```nim
import std/logging

# In vm.nim or other components
debug("Custom trace: ", someValue)
```

These only appear with `--loglevel DEBUG`.

### Programmatic Logging Control

For tests and embedded usage, control logging programmatically:

```nim
import std/logging
import harding/core/types

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
harding --version
granite --version

# Verify installation
which harding
which granite

# Test minimal case
harding -e "42"
```

### Performance Profiling

```bash
# Use Nim's profiler with compiled code
granite compile script.harding -o profile_me.nim
nim c -r -d:release --profiler:on --stackTrace:on profile_me.nim
```

## Summary

Harding provides comprehensive debugging tools:
- `--ast` for parsing inspection
- `--loglevel DEBUG` for execution tracing
- REPL for interactive exploration
- `nimble` for build automation

Combine these tools to quickly identify and resolve issues during development.
