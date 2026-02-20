# Harding Examples

This directory contains example programs demonstrating Harding features.

## Running Examples

```bash
# Run an example
harding 01_hello.hrd

# Or with debug output
harding --loglevel DEBUG 02_arithmetic.hrd

# Show AST before execution
harding --ast 05_classes.hrd
```

## Example Overview

| File | Description |
|------|-------------|
| `01_hello.hrd` | Basic "Hello, World!" program |
| `02_arithmetic.hrd` | Numbers and arithmetic operations |
| `03_variables.hrd` | Variable assignment and usage |
| `04_objects.hrd` | Basic object creation and property access |
| `05_classes.hrd` | Class creation with instance variables |
| `06_methods.hrd` | Method definition and calling |
| `07_inheritance.hrd` | Inheritance and super sends |
| `08_collections.hrd` | Arrays and Tables |
| `09_control_flow.hrd` | Conditionals and loops |
| `10_blocks.hrd` | Blocks and closures |
| `11_fibonacci.hrd` | Fibonacci calculation (iterative) |
| `12_stdlib.hrd` | Complete standard library demonstration |
| `13_inheritance.hrd` | Single inheritance with proper slot declaration |
| `13_multiple_inheritance.hrd` | Multiple inheritance using addSuperclass: |
| `bitbarrel_demo.hrd` | BitBarrel database (requires -d:bitbarrel build) |
| `process_demo.hrd` | Green threads and process forking |

## Quick Start

Start with the first few examples to learn the basics:

```bash
harding 01_hello.hrd
harding 02_arithmetic.hrd
harding 05_classes.hrd
```

Then explore more advanced features:

```bash
harding 07_inheritance.hrd
harding 11_fibonacci.hrd
harding 12_stdlib.hrd
```
