# MyApp - Pattern 1: Interpreter-Based Entry Point

This example demonstrates building a Harding application using the interpreter pattern.

## How It Works

1. **Nim Entry Point** (`src/myapp.nim`):
   - Creates a Harding interpreter
   - Loads the stdlib
   - Passes CLI arguments
   - Loads and executes Harding code

2. **Harding Application** (`lib/myapp/main.hrd`):
   - Contains the actual application logic
   - Accesses arguments via `System arguments`
   - Implements a simple calculator

## Directory Structure

```
Pattern1-Interpreter/
├── myapp.nimble           # Package manifest
├── src/
│   └── myapp.nim         # Nim entry point
├── lib/
│   └── myapp/
│       └── main.hrd      # Harding application logic
└── tests/
    └── test_myapp.nim    # Tests
```

## Building

```bash
# Development build (debug)
nimble dev

# Release build
nimble build

# Run with arguments
./myapp add 5 3
./myapp mul 10 4
```

## Usage Examples

```bash
# Show help (no arguments)
./myapp

# Addition
./myapp add 10 5
# Output: Result: 15

# Subtraction
./myapp sub 10 5
# Output: Result: 5

# Multiplication
./myapp mul 10 5
# Output: Result: 50

# Division
./myapp div 10 5
# Output: Result: 2
```

## When to Use This Pattern

**Pros:**
- Full access to Harding's dynamic features
- Can load and execute Harding code at runtime
- Easier to debug and iterate
- Supports live coding/reloading

**Cons:**
- Requires the Harding runtime
- Slightly slower startup (interpreter initialization)
- Larger binary size (includes interpreter)

**Best for:**
- Applications that need runtime flexibility
- Development tools
- Scripting environments
- Applications that load user code

## See Also

- [Application Structure Guide](../../docs/APPLICATION_STRUCTURE.md)
- [Pattern 2: Granite](../Pattern2-Granite/) - Alternative compilation approach
