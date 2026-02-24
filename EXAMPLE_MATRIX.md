# Example Compilation Test Matrix

## Summary

**Date:** 2025-02-25  
**Branch:** compiler-next  
**Total Examples:** 13 core examples tested

### Overall Results

| Status | Pure Mode | Mixed Mode | Description |
|--------|-----------|------------|-------------|
| ✅ PASS | 13/13 | 13/13 | All examples compile and build |
| Run output | Most work | Full support | Native slot access works, methods need class registration |

### Detailed Matrix

| Example | Pure Mode | Mixed Mode | Notes |
|---------|-----------|------------|-------|
| hello | ✅ BUILD | ✅ PASS | Basic I/O works |
| arithmetic | ✅ BUILD | ✅ PASS | All math/comparisons work |
| variables | ✅ BUILD | ✅ PASS | - |
| objects | ✅ BUILD | ✅ PASS | - |
| classes | ✅ BUILD | ✅ PASS | Slot access native, methods fallback to Object |
| methods | ✅ BUILD | ✅ PASS | - |
| control_flow | ✅ BUILD | ✅ PASS | - |
| inheritance | ✅ BUILD | ✅ PASS | - |
| multiple_inheritance | ✅ BUILD | ✅ PASS | Native Nim types |
| fibonacci | ✅ BUILD | ✅ PASS | Inline `do:` works |
| benchmark_blocks | ✅ BUILD | ✅ PASS | - |
| simple_test | ✅ BUILD | ✅ PASS | - |
| compiler_examples | ✅ BUILD | ✅ PASS | - |
| compiled_blocks | ✅ BUILD | ✅ PASS | - |

## 2025-02-25 Changes

### Native Slot Optimization
- Slot getters/setters generate native proc calls (`getname`, `setname`)
- Variable type tracking enables slot optimization
- Constructor generates `newClass_Name()` directly

### toValue() Implementation
- Added `classRef` field to generated types for runtime interop
- `toValue()` converts native type to Instance wrapper
- Class reference from interpreter globals (bootstrap classes only)
- Non-slot methods use Object class as fallback

### Known Limitation
User-defined classes aren't registered in interpreter globals. Methods other than slot access use Object class as fallback instead of the actual class. This is a fundamental interpreter change needed.
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

### Native Constructor & Slot Access (NEW!)
- **Constructor**: `ClassName new` now generates `newClass_ClassName()` directly
- **Variable Tracking**: Tracks variable types when assigned from constructor
- **Slot Optimization**: 
  - `var name: "value"` → `setname(var, NodeValue(...))`  
  - `var name` → `getname(var)`
- Native getters/setters are used when:
  - Variable is assigned from `ClassName new`
  - Selector matches a slot in the class

### Runtime Primitives
- Number: `abs`, `even`, `odd`, `negated` ✅
- Array (literals): `size`, `at:`, `last`, `do:`, `collect:`, `select:` ✅
- Table: `at:`, `at:put:`, `keys`, `size` ✅

### CLI
- `--mixed` flag: Embeds interpreter for fallback
- Default is pure compilation (no interpreter)

## Known Limitations

### toValue() Required for Non-Slot Methods
Methods that aren't slot getters/setters (like `printString`) use `sendMessage`, which requires NodeValue. The native Class_* types need `toValue()` method to convert to NodeValue for runtime interop.

- **Pure mode**: Fails to compile for non-slot method calls on typed variables
- **Mixed mode**: Works - slot access uses native getters/setters, methods fall back to interpreter

**Solution**: Implement toValue() method on generated types to wrap native objects in Instance with nimValue pointer.

### Current Behavior
- Slot getters/setters: Native procs (`getname`, `setname`)
- Constructors: Native constructors (`newClass_Person()`)
- Other methods: Fall back to interpreter (mixed mode) or fail to compile (pure mode)

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