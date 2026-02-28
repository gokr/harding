# Harding Application Templates

This directory contains complete working templates for building Harding applications.

## Templates

### Pattern 1: Interpreter-Based Entry Point

**Directory:** `Pattern1-Interpreter/`

Your application is a Nim program that:
1. Creates a Harding interpreter
2. Loads your Harding code
3. Executes it

**Best for:** Development tools, applications needing runtime flexibility, scenarios where you want to load user code.

**See:** [Pattern1-Interpreter/README.md](Pattern1-Interpreter/README.md)

### Pattern 2: Granite Compilation

**Directory:** `Pattern2-Granite/`

Your application is written in Harding and:
1. Compiled to Nim using Granite
2. Compiled to native binary

**Best for:** Production applications, performance-critical code, standalone distribution.

**See:** [Pattern2-Granite/README.md](Pattern2-Granite/README.md)

## Quick Comparison

| Feature | Pattern 1 (Interpreter) | Pattern 2 (Granite) |
|---------|------------------------|---------------------|
| Performance | Good | Excellent |
| Startup Time | Slower | Fast |
| Binary Size | Larger | Smaller |
| Runtime Flexibility | High | Lower |
| Debuggability | Easier | Harder |
| Distribution | Needs runtime | Standalone |
| Best For | Dev tools, scripts | Production apps |

## Getting Started

1. Choose your pattern based on your needs
2. Copy the template directory
3. Modify the code for your application
4. Update `myapp.nimble` with your package details
5. Build and run!

## Dependencies

Both templates require Harding as a dependency:

```nim
# In your .nimble file
requires "https://github.com/gokr/harding.git >= 0.7.0"
```

## Additional Resources

- [Application Structure Guide](../docs/APPLICATION_STRUCTURE.md) - Complete guide
- [harding-echo example](../harding-echo/) - Package example with Nim primitives
- [Nim Package Tutorial](../docs/NIM_PACKAGE_TUTORIAL.md) - Creating Harding packages

## Questions?

- Check the individual README files in each pattern directory
- See the [Application Structure Guide](../docs/APPLICATION_STRUCTURE.md)
- Open an issue on GitHub
