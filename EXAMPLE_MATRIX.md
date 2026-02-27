# Example Compilation Test Matrix

## Summary (After slot assignment fix - 2025-02-27)

**Branch:** compiler-next  
**Status:** Most examples work! Method compilation with slots and inheritance functional.

### Overall Results

| Category | Count | Description |
|----------|-------|-------------|
| ✅ Works | 14 | Examples compile and run correctly |
| ⚠️ Partial | 2 | Works with some issues |
| ❌ Broken | 1 | Needs super call fix |

### Working Examples (14)

| Example | Status | Notes |
|---------|--------|-------|
| hello | ✅ | Basic I/O |
| arithmetic | ✅ | Math operations |
| variables | ✅ | Variable assignment |
| objects | ✅ | Object creation |
| methods | ✅ | Method definitions |
| classes | ✅ | Class with slots |
| control_flow | ✅ | Conditionals/loops |
| fibonacci | ⚠️ | Works but compiled methods return nil |
| benchmark_blocks | ✅ | Block closures |
| simple_test | ✅ | Assertions |
| multiple_inheritance | ✅ | Works with compiled methods |
| collections | ⚠️ | Partial - timeout issues |
| blocks | ✅ | Block literals |
| harding_main | ✅ | compile:/main: blocks work! |

### Broken/Partial Examples (3)

1. **inheritance** - Uses `super` calls incorrectly in method chains (super describe , "...")
2. **fibonacci** - Methods defined with `>>` return nil in compiled code
3. **collections** - Timeout issues

### What's Working

- ✅ **compile:/main: blocks** - Class/method definitions work
- ✅ **Method compilation** - Methods compile to Nim procs
- ✅ **Slot assignments in methods** - `name := value` generates setter call
- ✅ **Return self** - Last statement returns self for Smalltalk semantics
- ✅ **super calls** - Basic super method calls work (but not in chains)

### What Needs Work

- Super calls in expression chains (e.g., `super describe , "text"`)
- Method return value handling for different patterns
- collections example timeout

## Syntax Examples

### New Style (compile:/main: blocks)
```harding
Harding compile: [
    Dog := Object deriveWithAccessors: #(name)
    Dog>>speak [ ^ "Woof!" ]
]

Harding main: [
    dog := Dog new
    dog speak println
]
```

### Old Style (backward compatible)
```harding
Dog := Object deriveWithAccessors: #(name)
Dog>>speak [ ^ "Woof!" ]
dog := Dog new
dog speak println
```

Both styles work identically now!

## Running Tests

```bash
# Test the main working example
./granite run examples/harding_main.hrd

# Test other examples
./granite run examples/hello.hrd
./granite run examples/multiple_inheritance.hrd
./granite run examples/classes.hrd
```