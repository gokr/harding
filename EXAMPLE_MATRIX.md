# Example Compilation Test Matrix

## Summary

**Date:** 2025-02-24  
**Branch:** compiler-next  
**Total Examples:** 19

### Overall Results

| Status | Count | Description |
|--------|-------|-------------|
| ✅ Works Pure | 14 | Compiles without --mixed, runs correctly |
| 🔶 Works with Limitations | 3 | Compiles but falls back to interpreter for classes |
| ❌ Compilation Fails | 2 | Require extensions (BitBarrel, green threads) |

### Detailed Matrix

| Example | Pure Mode | Mixed Mode | Notes |
|---------|-----------|------------|-------|
| hello | ✅ PASS | ✅ PASS | Basic I/O works |
| arithmetic | ✅ PASS | ✅ PASS | All math/comparisons work |
| variables | ✅ PASS | ✅ PASS | - |
| objects | ✅ PASS | ✅ PASS | - |
| classes | ✅ PASS | ✅ PASS | - |
| methods | ✅ PASS | ✅ PASS | - |
| control_flow | ✅ PASS | ✅ PASS | - |
| inheritance | ✅ PASS | ✅ PASS | - |
| multiple_inheritance | ✅ PASS | ✅ PASS | Native Nim types generated |
| fibonacci | ✅ PASS | ✅ PASS | Inline `do:` works |
| benchmark_blocks | ✅ PASS | ✅ PASS | - |
| simple_test | ✅ PASS | ✅ PASS | - |
| compiler_examples | ✅ PASS | ✅ PASS | - |
| compiled_blocks | ✅ PASS | ✅ PASS | - |
| **blocks** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles, some features fall back |
| **collections** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles, Array literals work |
| **stdlib** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles, most features work |
| **bitbarrel_demo** | ❌ FAIL | ❌ FAIL | Requires BitBarrel extension |
| **process_demo** | ❌ FAIL | ❌ FAIL | Requires green threads |

## Recent Changes (2025-02-24)

### Native Nim Class Generation
- Generates native `ref object` types for Harding classes
- Slot fields use `NodeValue` for flexibility
- Slot accessors generated as Nim procs (getX/setX pattern)
- Fixed class detection for `:=` assignment syntax
- Fixed slot parsing for simple lists like `#(name owner breed)`

### Runtime Primitives
- Number: `abs`, `even`, `odd`, `negated` ✅
- Array (literals): `size`, `at:`, `last`, `do:`, `collect:`, `select:` ✅
- Table: `at:`, `at:put:`, `keys`, `size` ✅

### CLI
- `--mixed` flag: Embeds interpreter for fallback
- Default is pure compilation (no interpreter)

## Known Limitations

### Class Instances Fall Back to Interpreter
The compiled code uses `sendMessage` for class operations, falling back to interpreter. To fully support native classes, we need to generate:
- Direct calls to generated type constructors (`newClassName`)
- Direct slot accessor calls (`getX`/`setX` instead of message sends)
- Native method implementations

This is a significant integration effort - the types are being generated correctly, but the code generation for class usage hasn't been updated to use them directly.

### Test Automation
- `test_examples.sh` can compare interpreter vs compiled output
- Currently 14/19 examples compile and run
- Output mostly matches (differences are quote formatting)

## Recommendations

1. **High Priority**: Connect compiled code to native types
   - Generate direct constructor calls
   - Generate direct slot accessor calls  
   - This will make class examples truly "native"

2. **Medium Priority**: Add more inline handlers
   - `to:do:` for integer ranges
   - More collection methods

3. **Low Priority**: 
   - BitBarrel support
   - Green thread/process support

## Running Tests

```bash
# Compile an example
./granite compile examples/hello.hrd

# Compile with mixed mode (interpreter fallback)
./granite compile examples/hello.hrd --mixed

# Run test matrix
INTERPRETER_DIR=/home/gokr/tankfeud/nemo ./test_examples.sh
```