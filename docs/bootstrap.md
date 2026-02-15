# Harding Bootstrap: The Foundation for Loading the Stdlib

This document describes the "bootstrap Harding" - the absolute minimum that is hard-coded into the VM to allow it to parse and load the standard library (`.hrd` files).

## Architecture Overview

Harding uses a two-phase bootstrap process:

1. **Nim Bootstrap Phase**: VM initialization creates core classes and registers essential methods
2. **Stdlib Loading Phase**: Bootstrap.hrd is evaluated, defining methods using primitive syntax

The key insight is that **only what's absolutely needed for the VM to start and parse `.hrd` files** is hard-coded in Nim. Everything else is defined in Harding code (`.hrd` files) using the primitive syntax.

## Core Class Hierarchy

The `initCoreClasses()` procedure in `src/harding/interpreter/objects.nim` creates the core class hierarchy:

```
Root (empty - for DNU proxies/wrappers)
  └── Object (core methods)
        ├── Integer
        ├── Float
        ├── String
        ├── Array
        ├── Table
        ├── Block
        ├── Boolean (parent for True and False)
        ├── Library
        └── Set
```

### Classes Created in `initCoreClasses()`

| Class | Purpose | Location of Methods |
|-------|---------|---------------------|
| `Root` | Empty base class for DNU proxies/wrappers | None |
| `Object` | Root of all user-defined classes | `lib/core/Object.hrd` |
| `Integer` | Integer numbers | `lib/core/Integer.hrd` |
| `Float` | Floating-point numbers | `lib/core/Float.hrd` |
| `String` | String values | `lib/core/String.hrd` |
| `Array` | Ordered collections | `lib/core/Array.hrd` |
| `Table` | Hash-based dictionaries | `lib/core/Table.hrd` |
| `Block` | Closures/anonymous functions | `lib/core/Block.hrd` |
| `Boolean` | Base class for true/false | `lib/core/Boolean.hrd` |
| `Library` | FFI library bindings | various .hrd files |
| `Set` | Unordered collections | `lib/core/Collections.hrd` |
| `Symbol` | Interned strings | `lib/core/Symbol.hrd` (in stdlib) |

## Bootstrap Methods (Required in Nim)

These are the methods that MUST be defined in Nim because they're needed **before** `.hrd` files can be loaded:

### Class Definition Methods (Object, class-side)

| Selector | Purpose | Why Bootstrap? |
|----------|---------|---------------|
| `selector:put:` | Define instance method (used by `>>` syntax) | Needed to parse method definitions in .hrd files |
| `classSelector:put:` | Define class method (used by `class>>` syntax) | Needed to parse class method definitions |
| `derive:` | Create subclass with slots | Needed to define new classes |
| `deriveWithAccessors:` | Create subclass with slots + accessors | Needed to define classes with convenient API |
| `derive` | Create subclass without slots | Needed to define new classes |
| `new` | Create instance | Needed before `.hrd` files can define initialization |
| `basicNew` | Core object creation primitive | Underlying implementation for `new` |

### Evaluation and Loading Methods

| Selector | Purpose | Location |
|----------|---------|----------|
| `load:` | Load and evaluate a `.hrd` file | `vm.nim` - required to load stdlib |
| `import:` | Import a foreign library | `vm.nim` - FFI support |
| `eval:` | Evaluate Harding code string | `vm.nim` - REPL support |

### Primitive Selector for Declarative Syntax

| Selector | Purpose | Location |
|----------|---------|----------|
| `primitiveClone` | Clone an instance | `objects.nim`, `registerPrimitivesOnObjectClass()` |

**Note**: The above primitive selector is registered so that the declarative primitive syntax can work via standard method lookup.

## Primitives vs Bootstrap Methods

It's important to understand the distinction:

### Bootstrap Methods
- **Required** for VM to start and parse `.hrd` files
- Cannot be defined in `.hrd` files (chicken-and-egg problem)
- Registered directly on classes in `objects.nim` and `vm.nim`

### Primitive Selectors
- **Not required**, but provide efficient implementations
- Defined in `.hrd` files using `<primitive>` syntax
- The Nim-registered primitive selector (`primitivePlus:`, `primitiveMinus:`, etc.) is what actually executes
- Methods like `+`, `-`, `*` call these primitive selectors

### Example Flow

```harding
# In Integer.hrd:
Integer>>+ other <primitive primitivePlus: other>

# What happens when evaluating "3 + 4":
1. Parser creates MessageNode for "+" with arg "4"
2. VM looks up method "+" on Integer class
3. Returns method from Integer.hrd (a BlockNode with primitive selector)
4. VM executes primitive by looking up `primitivePlus:` selector
5. Finds Nim implementation in `integerClass["primitivePlus:"]`
6. Calls the native implementation directly
```

## Stdlib Loading Order

The `lib/core/Bootstrap.hrd` file loads the core library in the correct order:

```harding
load: "lib/core/Object.hrd"
load: "lib/core/Boolean.hrd"
load: "lib/core/Number.hrd"
load: "lib/core/Integer.hrd"
load: "lib/core/Float.hrd"
load: "lib/core/String.hrd"
load: "lib/core/Symbol.hrd"
load: "lib/core/Table.hrd"
load: "lib/core/Array.hrd"
load: "lib/core/Block.hrd"
load: "lib/core/Collections.hrd"
# ... additional files
```

Loading order matters because:
1. `Object.hrd` must define the base class methods before subclasses can inherit
2. `Number.hrd` defines shared numeric behavior before `Integer` and `Float`
3. Primitives must be registered in `vm.nim` BEFORE the `.hrd` file that uses them is loaded

## Primitive Selector Registration in `initGlobals()`

The `initGlobals()` procedure in `src/harding/interpreter/vm.nim` registers primitive selectors:

```nim
# Integer arithmetic primitives
let intPlusMethod = createCoreMethod("primitivePlus:")
intPlusMethod.setNativeImpl(plusImpl)
intCls.methods["primitivePlus:"] = intPlusMethod
```

These registrations happen **after** class creation but **during** VM initialization, so when `.hrd` files are loaded, the primitive selectors are available.

## Comparison: What's Where

| Category | Location | Count | Example |
|----------|----------|-------|---------|
| **Bootstrap Methods** | `objects.nim`, `vm.nim` | ~10 | `selector:put:`, `new`, `load:` |
| **Primitive Selectors** | Registered in `vm.nim`, used by `.hrd` | ~70 | `primitivePlus:`, `primitiveStringSize` |
| **User-Facing Methods** | `.hrd` files | ~200 | `+`, `-`, `printString`, `size`, `at:put:` |

The user-facing methods (what users actually call) are defined in `.hrd` files. The primitive selectors are the backing implementations.

## What's in `initGlobals()` vs `initCoreClasses()`

### `initCoreClasses()` (`objects.nim`)
- **Creates the class objects** (Class instances)
- Sets up the class hierarchy
- Registers bootstrap methods needed to define other classes/methods
- Registers a few essential primitives (`primitiveClone`)
- Called once at VM startup

### `initGlobals()` (`vm.nim`)
- **Registers primitive selectors** for efficient implementations
- Sets up global values (true, false, nil)
- Registers I/O methods (print, println)
- Registers special operators (backslash \\ for modulo)
- Can be called to re-initialize globals for testing

## Extending Harding

When adding new features:

1. **If it requires loading `.hrd` files**: Define primitive selector in `vm.nim`, use in `.hrd` files
2. **If it's needed for bootstrapping**: Define bootstrap method in `objects.nim` or `vm.nim`
3. **If it's just new functionality**: Define method directly in `.hrd` file using primitive syntax or Harding code

## Summary

The bootstrap Harding is minimal by design:

- **~10 bootstrap methods** in Nim (required to start and parse)
- **6 core classes** created in Nim (Object, Integer, Float, String, Array, Table, Block, Boolean, Library, Set)
- **~70 primitive selectors** registered in Nim (efficient implementations)
- **~200 user-facing methods** defined in `.hrd` files (what users actually call)

This provides a clean separation:
- **Nim code**: Foundation mechanism (bootstrapping and performance-critical primitives)
- **Harding code (`.hrd`)**: Language definition and user-facing API
