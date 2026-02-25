# Granite Compiler Improvement Plan

## Philosophy

**Incremental improvement over wholesale rewrite.** A working compiler exists with 3700 lines. The goal is to improve what exists, not redesign it into 20 new modules.

## What GLM4.7 Got Right

- Code duplication exists in runtime helpers
- Large files (expression.nim at 845 lines) are hard to maintain
- No test coverage for compiler
- Debug echoes in production code

## What GLM4.7 Got Wrong

- "Runtime coupling" - Actually fine, fast paths already generate inline code
- "Type system unused" - Actually incomplete but working for its scope
- "VM dependency is a problem" - Intentional design, hard to avoid
- 10-week timeline with 50+ new files - Excessive scope

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

**Tests added** (23 passing):
- Lexer tests (4): integer, string, identifier, keyword tokens
- Parser tests (7): literals, assignment, messages, blocks
- Context tests (4): compiler context, class info, slots
- Symbol tests (4): selector/class/slot name mangling
- Analyzer tests (3): derive chain extraction, class graph, type parsing
- Codegen tests (8): literals, block registry, captures

---

### 1.3 Complete Block Body Generation

**Status**: ✓ Completed

**Files**: `codegen/blocks.nim`

**Changes**: 
- Implemented `generateBlockProcBody()` to generate actual Nim code
- Handles literals (int, float, string, nil) directly
- Handles assignments with literal values
- Handles explicit returns with literal values
- Generates proper variable declarations for temporaries
- Handles implicit returns for last expression

---

## Priority 2: Real Improvements (This Month)

### 2.1 Improve Error Messages

**Files**: `compiler/granite.nim`, `parser/`

**Improvements**:
- Show line/column for parse errors
- Show context around error location
- Suggest fixes for common mistakes

**Estimated**: 1 day

---

### 2.2 Fix Known Parser/Compiler Issues

**Files**: Various

**Quick fixes**:
- Parser error recovery
- Missing method warnings
- Slot access edge cases

**Estimated**: 1-2 days

---

### 2.3 Enhance Block Compilation

**Current state**: Basic literal handling works

**Enhancements needed**:
- Support message sends in block bodies
- Support arithmetic expressions
- Support control flow (ifTrue:, whileTrue:, etc.)

**Estimated**: 2-3 days

---

## Priority 3: Nice to Have (Someday)

- Split expression.nim into sections (NOT new files)
- Type inference improvements
- Performance optimization
- Better debugging output

---

## File Changes Summary

### New Files
| File | Purpose | Status |
|------|---------|--------|
| `tests/test_compiler_basic.nim` | Basic compiler tests | ✓ Complete |

### Modified Files
| File | Changes | Status |
|------|---------|--------|
| `codegen/primitive.nim` | Removed unused genPrimitiveRuntimeHelper | ✓ Complete |
| `codegen/blocks.nim` | Implemented block body generation | ✓ Complete |

### No Changes Needed
- `compiler/analyzer.nim` - No debug echoes found (already cleaned)
- `codegen/control.nim` - Already generates inline fast paths
- `compiler/granite.nim` - VM initialization is intentional
- `codegen/expression.nim` - Works, just large

---

## Success Metrics (Updated)

| Metric | Before | After |
|--------|--------|-------|
| Debug echoes in code | 0 | 0 ✓ |
| Dead code in compiler | ~35 lines | 0 ✓ |
| Compiler test coverage | 0 tests | 23 tests ✓ |
| Block body generation | Stubbed | Basic working ✓ |

---

## Next Steps

1. **Improve error messages** - Better diagnostics for users
2. **Fix known bugs** - Parser/compiler edge cases
3. **Enhance block compilation** - More expression types

---

## Notes

- **Don't create golden tests** - Too fragile, use behavioral tests instead
- **Don't split files** - Better to add section headers within files
- **Don't over-engineer type system** - Current approach is appropriate for dynamic language
- **VM dependency is fine** - It's how the compiler accesses class information