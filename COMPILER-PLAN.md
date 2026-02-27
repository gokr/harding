# Granite Compiler Improvement Plan

## Philosophy

**Incremental improvement over wholesale rewrite.** A working compiler exists with 3700 lines. The goal is to improve what exists, not redesign it into 20 new modules.

## What We Got Right

- Working method compilation system
- Slot accessor optimization in method bodies
- Inheritance with superclass hierarchy
- compile:/main: block syntax support

## What Still Needs Work

- Super calls in expression chains
- Method return value patterns
- Some examples have edge case issues

---

## Completed Items ✓

### 1.1 Remove Dead Code

**Status**: ✓ Completed

**Files**: `codegen/primitive.nim`

**Changes**: Removed unused `genPrimitiveRuntimeHelper` function (~35 lines of dead code).

---

### 1.2 Add Basic Compiler Tests

**Status**: ✓ Completed

**Files**: `tests/test_compiler_basic.nim` (new)

**Tests added** (23 passing)

---

### 1.3 Complete Block Body Generation

**Status**: ✓ Completed

**Files**: `codegen/blocks.nim`

**Changes**: Implemented `generateBlockProcBody()` to generate actual Nim code.

---

### 1.4 Method Compilation (NEW)

**Status**: ✓ Completed

**Files**: `codegen/module.nim`, `codegen/expression.nim`, `runtime/runtime.nim`

**Changes**:
- Extract method definitions from AST (selector:put: pattern)
- Generate Nim procs from method bodies
- Add method registration system (compiledMethodProcs table)
- Implement method dispatch in sendMessage
- Add slot accessor optimization in method bodies (self slotName → getSlot())
- Add inheritance support via superclass hierarchy
- Add compile:/main: block syntax support
- Fix slot assignments in methods (generate setter calls)
- Fix return semantics (return self for last statement)
- Add super call support (nkSuperSend)
- Document compile:/main: in MANUAL.md
- Note: compile:/main: is compiler-only (not supported in interpreter)

---

## Working Examples (14)

| Example | Status |
|---------|--------|
| hello | ✅ |
| arithmetic | ✅ |
| variables | ✅ |
| objects | ✅ |
| methods | ✅ |
| classes | ✅ |
| control_flow | ✅ |
| fibonacci | ⚠️ Works but returns nil |
| benchmark_blocks | ✅ |
| simple_test | ✅ |
| multiple_inheritance | ✅ |
| collections | ⚠️ Partial |
| blocks | ✅ |
| harding_main | ✅ |

---

## Remaining Issues

### High Priority

1. **Super calls in chains** - `super method , "suffix"` doesn't work
   - The super call returns self, but it's not used as receiver for comma

2. **fibonacci methods return nil** - Different pattern than working examples
   - Methods defined differently in that example

### Medium Priority

3. **collections timeout** - Some infinite loop issue
4. **inheritance example** - Uses super in chains

---

## File Changes Summary

### New Files
| File | Purpose | Status |
|------|---------|--------|
| `tests/test_compiler_basic.nim` | Basic compiler tests | ✓ Complete |

### Modified Files
| File | Changes | Status |
|------|---------|--------|
| `codegen/primitive.nim` | Removed unused function | ✓ Complete |
| `codegen/blocks.nim` | Block body generation | ✓ Complete |
| `codegen/module.nim` | Method compilation, class gen | ✓ Complete |
| `codegen/expression.nim` | Slot optimization, super calls | ✓ Complete |
| `runtime/runtime.nim` | Method dispatch | ✓ Complete |

---

## Next Steps

1. **Fix super calls in expression chains** - Make super call return value used as receiver
2. **Fix fibonacci example** - Different method pattern
3. **Test all examples** - Ensure edge cases work
4. **Add more test coverage** - Behavioral tests for compilation

---

## Notes

- **Don't create golden tests** - Too fragile, use behavioral tests instead
- **Don't split files** - Better to add section headers within files
- **Don't over-engineer type system** - Current approach is appropriate for dynamic language
- **VM dependency is fine** - It's how the compiler accesses class information