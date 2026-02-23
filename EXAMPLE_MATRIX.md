# Example Compilation Test Matrix

## Summary

**Date:** 2025-02-23  
**Branch:** compiler-next  
**Total Examples:** 19

### Overall Results

| Status | Count | Description |
|--------|-------|-------------|
| ✅ Works Pure | 14 | Compiles without --mixed, runs correctly |
| 🔶 Works with Limitations | 3 | Compiles but some features need Array/Table objects vs literals |
| ❌ Compilation Fails | 2 | Require extensions (BitBarrel, green threads) |

### Detailed Matrix

| Example | Pure Mode | Mixed Mode | Issue | Priority |
|---------|-----------|------------|-------|----------|
| hello | ✅ PASS | ✅ PASS | - | - |
| arithmetic | ✅ PASS | ✅ PASS | - | - |
| variables | ✅ PASS | ✅ PASS | - | - |
| objects | ✅ PASS | ✅ PASS | - | - |
| classes | ✅ PASS | ✅ PASS | - | - |
| methods | ✅ PASS | ✅ PASS | - | - |
| control_flow | ✅ PASS | ✅ PASS | - | - |
| inheritance | ✅ PASS | ✅ PASS | - | - |
| multiple_inheritance | ✅ PASS | ✅ PASS | - | - |
| fibonacci | ✅ PASS | ✅ PASS | `do:` now compiled inline | - |
| benchmark_blocks | ✅ PASS | ✅ PASS | - | - |
| simple_test | ✅ PASS | ✅ PASS | - | - |
| compiler_examples | ✅ PASS | ✅ PASS | - | - |
| compiled_blocks | ✅ PASS | ✅ PASS | - | - |
| **blocks** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles! Some Array methods need object support | MEDIUM |
| **collections** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles! Array literals work; `Array new` needs object support | MEDIUM |
| **stdlib** | 🔶 PARTIAL | 🔶 PARTIAL | Compiles! Most features work | MEDIUM |
| **bitbarrel_demo** | ❌ FAIL | ❌ FAIL | `BarrelTable` class undefined | LOW |
| **process_demo** | ❌ FAIL | ❌ FAIL | Green threads not supported | LOW |

### Recent Fixes

#### ✅ Comparison Operators Fixed
- `==` now returns `true` for equal values (was returning `false`)
- Both `=` and `==` map to Nim's `==` operator

#### ✅ Number Primitives Added
All number methods now work correctly:
- `abs` - returns absolute value ✅
- `even` - returns true for even numbers ✅
- `odd` - returns true for odd numbers ✅
- `negated` - returns negated value ✅

#### ✅ Array Primitives Added (for Array Literals)
Array primitives work with literal syntax `#(1 2 3)`:
- `size` - returns array length ✅
- `at:` - returns element at 1-based index ✅
- `last` - returns last element ✅
- `do:` - iterates over elements ✅
- `collect:` - transforms and collects ✅
- `select:` - filters based on condition ✅

#### ✅ Table Primitives Added
- `at:` - works with string keys ✅
- `at:put:` - stores values ✅
- `keys` - returns array of keys ✅
- `size` - returns number of entries ✅

### Known Limitations

#### Array Objects vs Array Literals
**Issue:** `Array new` creates an object, not a native array.

**Works:**
```harding
numbers := #(1 2 3 4 5)  # Array literal - creates vkArray
numbers at: 1             # Returns 1 ✅
numbers size              # Returns 5 ✅
```

**Needs Object Support:**
```harding
arr := Array new          # Creates Array object
arr add: 10               # Works at runtime via interpreter
arr at: 1                 # Returns nil (needs Array object support)
```

**Workaround:** Use array literals `#(...)` instead of `Array new` in compiled code.

### Compilation Errors

#### 1. Runtime Primitives - MOSTLY FIXED ✅
**Status:** Core primitives implemented.

**Working:**
- ✅ Number: abs, even, odd, negated
- ✅ Array literals: size, at:, last, do:, collect:, select:
- ✅ Table: at:, at:put:, keys, size
- ✅ Comparison: =, ==, ~=, <, <=, >, >=

**Needs Object Support:**
- Array objects created with `Array new` and `add:`

#### 2. Missing Classes (2 examples)

**bitbarrel_demo:**
- Requires `BarrelTable` class from BitBarrel extension
- Only available when compiled with `-d:bitbarrel`

**process_demo:**
- Uses `Processor`, green threads
- Requires full interpreter runtime
- Not supported in compiled mode

### Runtime Behavior

#### Working Examples Output
All 14 passing examples produce correct output.

#### Collections Example
**Status:** 🔶 Compiles and runs with limitations

**Working:**
- Array literals: `#(1 2 3 4 5)` ✅
- `collect:`: `#(1 4 9 16 25)` ✅
- `select:`: `#(2 4)` ✅
- `at:` with literals: Returns correct value ✅
- `size` with literals: Returns correct size ✅
- `last` with literals: Returns correct value ✅

**Needs Object Support:**
- `Array new` created arrays: `at:`, `size`, `last` return nil

### Recommendations

### Completed ✅
1. ✅ Fix `==` operator
2. ✅ Add Number primitives (abs, even, odd, negated)
3. ✅ Add Array primitives for literals
4. ✅ Add Table primitives
5. ✅ Fix inline collection iteration (do:, collect:, select:)

### Next Steps
6. Add Array object support (Array new, add:)
7. Test all examples with array literals
8. Document use of literals vs objects in compiled mode

## Next Steps

**Current Status:** 17/19 examples compile (up from 14)

The compiler is working well! The main remaining work is:
1. Supporting Array objects (not just literals) - MEDIUM priority
2. BitBarrel support - LOW priority
3. Green thread support - LOW priority

For practical use, recommend using array literals `#(...)` instead of `Array new` in compiled code.
