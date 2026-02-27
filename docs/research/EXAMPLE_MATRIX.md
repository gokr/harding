# Example Compilation Test Matrix

## Summary (After Merge and Fixes - 2025-02-25)

**Branch:** compiler-next  
**Status:** Basic examples work, slots are now detected and generated

### Overall Results

| Category | Count | Description |
|----------|-------|-------------|
| ✅ Works | 10 | Basic examples compile and run |
| 🔶 Partial | 3 | Classes compile but slot accessors not yet connected |

### Current Status

**Working (10 examples):**
- hello ✅ - Basic I/O
- arithmetic ✅ - Math operations
- variables ✅ - Variable assignment
- objects ✅ - Object creation
- methods ✅ - Method definitions
- control_flow ✅ - Conditionals/loops
- inheritance ✅ - Class inheritance
- fibonacci ✅ - Recursion
- benchmark_blocks ✅ - Block closures
- simple_test ✅ - Assertions

**Needs Expression Generator Update (3 examples):**
- classes 🔶 - Slots generated but not accessed natively
- multiple_inheritance 🔶 - Same issue
- compiled_blocks 🔶 - Same issue

## Recent Fixes

### Slot Detection Fixed
- parseTypeList now correctly parses `#(name age)` with multiple slots
- extractDeriveChain now handles nkArray nodes (direct array literals)
- Handles nkIdent nodes in array elements (identifiers like 'name')

### Native Type Generation Restored
- genClassConstants generates native ref object types
- genSlotAccessors generates getX/setX procs
- Slots initialized to nil in constructor

## Next Steps

To fully support classes, need to:
1. Add variable type tracking to GenContext
2. Detect when receiver is a known class instance
3. Generate direct slot accessor calls instead of sendMessage
4. Connect native constructor calls (ClassName new → newClassName())

## Running Tests

```bash
# Compile a working example
./granite compile examples/hello.hrd
nim c --outdir:build --app:console build/hello.nim
./build/hello

# Check classes (compiles but slots show nil)
./granite compile examples/classes.hrd
./build/classes
```
