# Harding Application Structure Guide

This guide explains how to structure and build Harding applications as Nim packages.

## Table of Contents

1. [Overview](#overview)
2. [Dependencies](#dependencies)
3. [Pattern 1: Interpreter-Based Entry Point](#pattern-1-interpreter-based-entry-point)
4. [Pattern 2: Granite Compilation](#pattern-2-granite-compilation)
5. [Handling Dependencies](#handling-dependencies)
6. [Build Configuration](#build-configuration)
7. [Best Practices](#best-practices)

---

## Overview

There are two primary patterns for building Harding applications:

1. **Interpreter-Based**: Your Nim code creates a Harding interpreter, loads your Harding code, and executes it
2. **Granite Compilation**: Compile Harding code to Nim, then to native binary

Both patterns use Nimble for dependency management and can use Harding packages that bundle Nim primitives with Harding code.

---

## Dependencies

### Using Harding as a Dependency

Add Harding to your `.nimble` file using a direct git URL:

```nim
# myapp.nimble
version = "1.0.0"
author = "Your Name"
description = "My Harding Application"
license = "MIT"

srcDir = "src"

# Harding as a dependency (use direct git URL)
requires "https://github.com/gokr/harding.git >= 0.7.1"

# Optional: Other harding-* packages
requires "https://github.com/user/harding-foo.git >= 1.0.0"
```

**Why direct git URLs?**
- Keeps the ecosystem decentralized
- No need to publish to Nimble registry
- Still get version management via git tags
- Easy to fork and modify

---

## Pattern 1: Interpreter-Based Entry Point

In this pattern, your application is a Nim program that:
1. Creates a Harding interpreter
2. Loads your Harding packages
3. Loads and executes your Harding application code
4. Handles command-line arguments

### Directory Structure

```
myapp/
├── myapp.nimble              # Package manifest
├── src/
│   ├── myapp.nim            # Main entry point (Nim)
│   └── myapp/               # Your Nim modules (optional)
│       └── utils.nim
├── lib/
│   └── myapp/               # Your Harding source files
│       └── main.hrd         # Application logic
└── tests/
    └── test_myapp.nim
```

### Example: src/myapp.nim

```nim
##
## myapp.nim - Main entry point
##

import std/[os, logging]
import harding/interpreter/vm
import harding/packages/package_api

# Import your packages (if you have them as separate nimble packages)
# import harding_foo/package

proc main() =
  # Get command-line arguments
  let args = commandLineParams()
  
  # Create and initialize interpreter
  var interp = newInterpreter()
  initGlobals(interp)
  loadStdlib(interp)
  
  # Pass CLI args to interpreter (available as System arguments)
  interp.commandLineArgs = args
  
  # Install any Harding packages (if using the package model)
  # discard installFooPackage(interp)
  
  # Load your application's Harding code
  let appSource = readFile("lib/myapp/main.hrd")
  let (_, err) = interp.evalStatements(appSource)
  
  if err.len > 0:
    stderr.writeLine("Error: ", err)
    quit(1)

when isMainModule:
  main()
```

### Example: lib/myapp/main.hrd

```harding
#!/usr/bin/env harding
#
# Main application logic in Harding

# Access command-line arguments
args := System arguments

# Application logic
Stdout writeline: ("Arguments: " , (args size) asString)

args do: [:arg |
  Stdout writeline: arg
]

# Your application code here...
```

### Building

```bash
nimble build
./myapp arg1 arg2 arg3
```

---

## Pattern 2: Granite Compilation

In this pattern:
1. Write your application in Harding
2. Use Granite to compile to Nim
3. Compile Nim to native binary

### Directory Structure

```
myapp/
├── myapp.nimble              # Package manifest
├── src/
│   └── main.hrd             # Application entry point (Harding)
├── lib/                     # Additional Harding modules
│   └── myapp/
│       └── utils.hrd
└── tests/
    └── test_myapp.hrd
```

### Example: src/main.hrd

```harding
#!/usr/bin/env harding
#
# Granite-compiled application

# Import your modules
Harding load: "lib/myapp/utils.hrd"

# Access CLI args
args := System arguments

# Main logic
MyApp run: args
```

### Using Granite

Granite is built into Harding. From within Harding:

```harding
# Compile to Nim
Harding compile: [
    # Your application code
]

# Or use Granite directly
Granite compile: "src/main.hrd" output: "src/main.nim"
```

From the command line:

```bash
# Compile Harding to Nim
granite compile src/main.hrd -o src/main.nim

# Compile Nim to binary
nim c -o:myapp src/main.nim

# Or use Granite's build command
granite build src/main.hrd --release -o myapp
```

### nimble tasks for Granite

Add to your `.nimble`:

```nim
task build_app, "Build the application with Granite":
  # Compile Harding to Nim
  exec "granite compile src/main.hrd -o src/main_gen.nim"
  # Compile Nim to binary
  exec "nim c -d:release -o:myapp src/main_gen.nim"

task run_app, "Run the application":
  exec "./myapp"
```

---

## Handling Dependencies

### Using Harding Packages

If your app uses Harding packages that bundle Nim primitives:

```nim
# src/myapp.nim
import harding/interpreter/vm
import harding/packages/package_api
import harding_foo/package    # Your dependency
import harding_bar/package    # Another dependency

proc main() =
  var interp = newInterpreter()
  initGlobals(interp)
  loadStdlib(interp)
  
  # Install all packages
  discard installFooPackage(interp)
  discard installBarPackage(interp)
  
  # Now your Harding code can use Foo and Bar
  ...
```

### Pure Harding Libraries

For libraries that are just `.hrd` files (no Nim primitives):

```harding
# In your Harding code
Harding load: "vendor/some-library/main.hrd"
Standard load: "vendor/some-library/utils.hrd"
```

Or use `git submodule` / `git subtree` to vendor them:

```
myapp/
├── src/
├── lib/
│   └── myapp/
└── vendor/              # Vendored libraries
    ├── harding-foo/     # git submodule
    └── harding-bar/     # git submodule
```

---

## Build Configuration

### Complete nimble file example

```nim
# myapp.nimble
version = "1.0.0"
author = "Your Name"
description = "My Harding Application"
license = "MIT"

srcDir = "src"
bin = @["myapp"]              # Binary name

# Dependencies
requires "https://github.com/gokr/harding.git >= 0.7.1"
requires "https://github.com/user/harding-foo.git >= 1.0.0"

import os

# Pattern 1: Interpreter-based build
task build, "Build the application":
  exec "nim c -d:release -o:myapp src/myapp.nim"

task run, "Run the application":
  exec "./myapp"

task dev, "Build and run in development mode":
  exec "nim c -o:myapp src/myapp.nim"
  exec "./myapp"

# Pattern 2: Granite build (alternative)
task granite_build, "Build with Granite":
  exec "granite compile src/main.hrd -o src/main_gen.nim"
  exec "nim c -d:release -o:myapp src/main_gen.nim"

task test, "Run tests":
  exec "nim c -r tests/test_myapp.nim"
```

### Development vs Production

**Development:**
```bash
nimble dev           # Build debug version
nimble run           # Run with args
```

**Production:**
```bash
nimble build         # Build release version
./myapp --help       # Run the binary
```

---

## Best Practices

### 1. Separate Concerns

- **Nim**: System integration, performance-critical code, external libraries
- **Harding**: Application logic, domain models, user-facing features

### 2. Package Organization

For reusable packages:
```
harding-mypackage/
├── harding-mypackage.nimble
├── src/harding_mypackage/
│   ├── package.nim          # Registration
│   ├── primitives.nim       # Nim implementations
│   └── lib/harding/mypackage/
│       ├── Bootstrap.hrd
│       └── API.hrd
└── examples/
    └── demo.nim
```

### 3. Version Management

Use git tags for versions:
```bash
git tag -a v1.0.0 -m "Version 1.0.0"
git push origin v1.0.0
```

Reference in nimble:
```nim
requires "https://github.com/user/harding-foo.git >= 1.0.0"
```

### 4. Testing

Test both layers:
- **Nim tests**: Test primitives directly
- **Harding tests**: Test Harding-level functionality

```nim
# tests/test_primitives.nim
import unittest
import harding_mypackage/primitives

test "primitive works":
  # Test the Nim implementation
  ...
```

```harding
# tests/test_api.hrd
# Test the Harding API
result := MyPackage doSomething
self assert: result equals: expected
```

### 5. Documentation

Always include:
- README.md with usage examples
- API documentation in .hrd files (comments)
- Nim doc comments for primitives

### 6. Error Handling

In Nim primitives:
```nim
proc myPrimitive(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1:
    return nilValue()  # Graceful fallback
  
  try:
    # Do something
    return toValue(result)
  except:
    return nilValue()  # Or signal an exception
```

---

## Examples

See the `examples/harding-app-template/` directory for complete working templates:

- **Pattern1-Interpreter/**: Full interpreter-based example
- **Pattern2-Granite/**: Full Granite compilation example

Also see `examples/harding-echo/` for a complete package example.

---

## Summary

- Use Nimble with direct git URLs for dependencies
- Choose Pattern 1 (interpreter) for flexibility, Pattern 2 (Granite) for performance
- Structure packages consistently with `src/`, `lib/`, and `examples/`
- Test both Nim and Harding layers
- Document APIs for both Harding and Nim users
