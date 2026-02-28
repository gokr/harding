# MyApp - Pattern 2: Granite Compilation

This example demonstrates building a Harding application using Granite compilation.

## How It Works

1. **Write Application in Harding** (`src/main.hrd`):
   - Application logic is written entirely in Harding
   - No separate Nim entry point needed

2. **Granite Compilation**:
   - Granite compiles `src/main.hrd` to `src/main_gen.nim`
   - Nim compiles the generated code to a native binary

3. **Result**:
   - Standalone native binary (`./myapp`)
   - No runtime dependency on the Harding interpreter

## Directory Structure

```
Pattern2-Granite/
├── myapp.nimble           # Package manifest
├── src/
│   └── main.hrd          # Main application (Harding)
└── tests/
    └── test_myapp.nim    # Tests
```

## Building

```bash
# Using nimble task (recommended)
nimble granite_build

# Manual steps
granite compile src/main.hrd -o src/main_gen.nim
nim c -d:release -o:myapp src/main_gen.nim

# Development build (debug)
nimble granite_dev
```

## Usage

```bash
# Simple greeting
./myapp
# Output: Hello, World!

# With name
./myapp Alice
# Output: Hello, Alice!

# With additional arguments
./myapp Alice Bob Charlie
# Output:
#   Hello, Alice!
#   Additional arguments:
#     1. Bob
#     2. Charlie
```

## How Granite Works

```
Your Harding code (.hrd)
         ↓
    Granite Compiler
         ↓
Generated Nim code (.nim)
         ↓
    Nim Compiler
         ↓
Native binary (no interpreter needed!)
```

Granite:
- Translates Harding AST to Nim code
- Generates efficient native code
- Handles the runtime setup automatically

## When to Use This Pattern

**Pros:**
- True native performance
- Standalone binary (no runtime dependencies)
- Smaller distribution size
- Faster startup time

**Cons:**
- Compilation step required
- Less runtime flexibility
- Harder to debug (generated code)

**Best for:**
- Production applications
- Performance-critical code
- Distribution to end users
- Standalone tools and utilities

## Mixing Patterns

You can combine both patterns:

```harding
# In your Granite-compiled app
# Load additional Harding modules at runtime
Harding load: "lib/extensions.hrd"
```

The core app is compiled, but can still load and execute Harding code dynamically.

## See Also

- [Application Structure Guide](../../docs/APPLICATION_STRUCTURE.md)
- [Pattern 1: Interpreter](../Pattern1-Interpreter/) - Alternative approach with more flexibility
- `granite --help` for compiler options
