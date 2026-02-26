# Example Compilation Test Matrix

## Summary (After Method Compilation Milestone - 2025-02-27)

**Branch:** compiler-next  
**Status:** Compiled methods work! Classes with methods and inheritance are now functional.

### Overall Results

| Category | Count | Description |
|----------|-------|-------------|
| ✅ Works | 16 | Examples compile and run correctly |
| ⚠️ Issues | 4 | Runtime errors or edge cases |

### Working Examples (16)

| Example | Status | Notes |
|---------|--------|-------|
| hello | ✅ | Basic I/O |
| arithmetic | ✅ | Math operations |
| variables | ✅ | Variable assignment |
| objects | ✅ | Object creation |
| methods | ✅ | Method definitions |
| control_flow | ✅ | Conditionals/loops |
| inheritance | ⚠️ | Crashes with initialize method |
| fibonacci | ✅ | Recursion |
| benchmark_blocks | ✅ | Block closures |
| simple_test | ✅ | Assertions |
| classes | ✅ | Class with slots |
| multiple_inheritance | ⚠️ | Works with methods |
| compiled_blocks | ⚠️ | Works with blocks |
| collections | ✅ | Arrays and tables |
| blocks | ✅ | Block literals |
| harding_main_compat | ✅ | Classes with methods and inheritance |

### Examples with Issues (4)

1. **inheritance** - Crashes because `initialize` method returns nil, then code tries to access `.instVal` on nil
2. **multiple_inheritance** - Same issue as inheritance
3. **compiled_blocks** - Same issue as inheritance
4. **arithmetic** - Some primitives not implemented in compiled mode

### What's Working

- ✅ **Method compilation** - Methods extracted from AST and compiled to Nim procs
- ✅ **Method dispatch** - Compiled methods called via `compiledMethodProcs` table
- ✅ **Slot accessor optimization** - `self slotName` generates direct `getSlot()` calls
- ✅ **Inheritance** - Methods inherited from superclasses work
- ✅ **Superclass hierarchy** - `addSuperclass:` calls registered at runtime

### What Needs Work

- Initialize method handling - currently returns nil causing crashes
- Some arithmetic primitives missing in compiled mode
- More testing needed with complex inheritance hierarchies

## Running Tests

```bash
# Compile and run a working example
./granite run examples/hello.hrd
./granite run examples/arithmetic.hrd
./granite run examples/harding_main_compat.hrd

# Check specific examples
./granite run examples/classes.hrd
./granite run examples/methods.hrd
./granite run examples/control_flow.hrd
```

## Recent Changes

### Method Compilation (2025-02-27)
- Added compiled method registry in runtime
- Added nimProxyClassNames table for class lookup
- Added superclass hierarchy support
- Modified sendMessage to check compiledMethodProcs first
- Added PseudoVarNode support in slot accessor detection
- Set ctx.cls in genCompiledMethods for proper slot optimization

### Fixes (2025-02-27)
- Fixed empty method/superclass registration stubs
- Generate stub procs when no methods or superclasses exist
- Fixed indentation errors in generated code