# Harding Echo Package Example

This is a complete example demonstrating how to create a Harding package with Nim primitives.

## Overview

The `harding-echo` package provides a simple echo service that demonstrates:

- Creating a Harding class with primitive methods
- Implementing primitives in Nim
- Embedding `.hrd` files using `staticRead`
- Registering primitives with `HardingPackageSpec`
- Installing packages into the Harding interpreter

## Structure

```
harding-echo/
├── harding-echo.nimble          # Package metadata
├── src/
│   └── harding_echo/
│       ├── package.nim          # Package registration & install
│       ├── primitives.nim       # Nim primitive implementations
│       └── lib/
│           └── harding/
│               └── echo/
│                   ├── Bootstrap.hrd   # Package setup
│                   └── Echo.hrd        # Harding API definitions
├── examples/
│   └── demo.nim                 # Usage example
└── tests/
    └── test_echo.nim            # Package tests
```

## Harding API

```harding
# Basic echo
Echo echo: "Hello, World!"           # Returns: "Hello, World!"

# Echo with prefix
Echo echo: "World!" withPrefix: "Hello, "   # Returns: "Hello, World!"

# Counter
Echo count                           # Returns number of calls
Echo reset                           # Reset counter
```

## Usage from Nim

```nim
import harding/interpreter/vm
import harding_echo/package

# Create and initialize interpreter
var interp = newInterpreter()
initGlobals(interp)
loadStdlib(interp)

# Install the echo package
discard installEchoPackage(interp)

# Now use it from Harding code
let (_, err) = interp.evalStatements("""
  result := Echo echo: "Hello from Harding!"
  result println
""")
```

## Building

```bash
# Build the example
cd examples/harding-echo
nimble example

# Run tests
nimble test
```

## How It Works

1. **Echo.hrd** defines the Harding-side API with `<primitive>` declarations
2. **primitives.nim** implements the actual functionality in Nim
3. **Bootstrap.hrd** loads the Harding files and creates a Library
4. **package.nim** uses `staticRead` to embed the `.hrd` files
5. `installPackage()` registers the sources and primitives

## Key Concepts

### Primitive Naming Convention

Primitives follow the pattern: `primitive<ClassName><MethodName>`
- `Echo>>echo:` → `primitiveEchoEcho:`
- `Echo>>echo:withPrefix:` → `primitiveEchoWithPrefix:message:`

### Embedding Sources

```nim
const EchoHrd = staticRead("lib/echo/Echo.hrd")
```

This embeds the Harding source file into the compiled Nim binary.

### Package Registration

```nim
let spec = HardingPackageSpec(
  name: "harding-echo",
  version: "0.1.0",
  bootstrapPath: "lib/echo/Bootstrap.hrd",
  sources: @[...],
  registerPrimitives: registerEchoPrimitives
)
```

The `registerPrimitives` proc is called after loading the Harding code, allowing it to find classes and bind primitives.

## See Also

- [Nim Package Tutorial](../../docs/NIM_PACKAGE_TUTORIAL.md) - Full tutorial
- [Application Structure Guide](../../docs/APPLICATION_STRUCTURE.md) - Building Harding apps
