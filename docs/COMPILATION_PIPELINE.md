# Granite Compilation Pipeline Architecture

## Overview

Granite is the Harding-to-Nim compiler. There are two entry points:

1. **CLI Granite** (`granite` binary) - Command-line tool for compiling `.hrd` files
2. **Harding Granite** (`Granite` class) - In-VM compiler accessed via primitives

**Goal**: Both paths must use the same core compilation pipeline to ensure consistent behavior.

## Current State

### CLI Granite (standalone) - Working
- Entry: `src/harding/compiler/granite.nim`
- Compiles standalone `.hrd` scripts to native binaries via Nim
- Supports `compile`, `build`, and `run` commands
- Inline control flow compilation (ifTrue:, whileTrue:, timesRepeat:, etc.)
- Does NOT initialize Harding VM or load stdlib
- Produces binaries 30-200x faster than interpreted code

### Harding Granite (in-VM)
- Entry: `lib/core/Granite.hrd` with primitives
- Primitives: `primitiveGraniteCompile:`, `primitiveGraniteBuild:`
- Has full access to loaded classes, methods, and object graph
- Located in: `src/harding/compiler/compiler_primitives.nim`

### Block Compilation (implemented)
- Block registry: `src/harding/codegen/blocks.nim`
- Inline control flow: `src/harding/codegen/expression.nim` (statement and expression context)
- Block procedure generation infrastructure in place
- Capture analysis stub ready for implementation
- Works at AST level - applicable to both paths

## Design Principles

### 1. Shared Core Pipeline

Both entry points should use the same core pipeline:

```
Harding Source
     ↓
Parser (lexer.nim, parser.nim)  ← shared
     ↓
AST (types.nim)                  ← shared
     ↓
Analyzer (compiler/analyzer.nim) ← shared (optional for CLI)
     ↓
Code Generator (codegen/*.nim)   ← shared
     ↓
Nim Source
     ↓
Nim Compiler (system nim)
     ↓
Binary
```

### 2. Pipeline Phases

| Phase | CLI Path | Harding Path | Notes |
|-------|----------|--------------|-------|
| Parse | Direct | Via primitive | Same parser |
| Analyze | Optional | Always | Harding has full class model |
| Generate | Direct | Via primitive | Same codegen |
| Compile Nim | System nim | System nim | Same |

### 3. Convergence Strategy

**Short term (current)**:
- CLI granite uses direct AST → codegen path
- Harding granite uses primitive wrapper around same codegen
- Both use same `genModule()` function in `module.nim`

**Medium term**:
- CLI granite should initialize minimal Harding VM to access class model
- This enables accurate method lookup, slot analysis, etc.
- Add `--analyze` flag to CLI for full analysis

**Long term**:
- Unified entry point: `compileSource(source, options)` in `compiler/compiler.nim`
- CLI is thin wrapper around this
- Harding primitives call same function
- Both benefit from:
  - Introspection of loaded code
  - Dead code elimination
  - Cross-module optimization

## Code Organization

### Shared Components (already shared)
- `src/harding/parser/` - Lexer and parser
- `src/harding/core/types.nim` - AST node types
- `src/harding/codegen/` - All code generation
- `src/harding/compiler/context.nim` - Compiler context
- `src/harding/compiler/analyzer.nim` - Class/method analysis

### CLI-Specific
- `src/harding/compiler/granite.nim` - CLI entry point
- Command-line argument parsing
- File I/O operations

### Harding-Specific
- `src/harding/compiler/compiler_primitives.nim` - Primitive implementations
- `lib/core/Granite.hrd` - Harding-side API

## Block Compilation Implementation

### Inline Control Flow (Completed)

Literal blocks in control flow messages are compiled directly to Nim constructs:

| Harding Pattern | Generated Nim |
|----------------|--------------|
| `cond ifTrue: [body]` | `if isTruthy(cond): body` |
| `cond ifTrue: [a] ifFalse: [b]` | `if isTruthy(cond): a else: b` |
| `[cond] whileTrue: [body]` | `while isTruthy(cond): body` |
| `[cond] whileFalse: [body]` | `while not isTruthy(cond): body` |
| `n timesRepeat: [body]` | `for i in 0..<toInt(n): body` |

Both statement context (no value needed) and expression context (value required) are handled.

### Block Registry Infrastructure (In Place)

1. **Block Registry** (`codegen/blocks.nim`):
   - Collects all non-inline blocks from AST before generation
   - Assigns unique Nim procedure names
   - Tracks captures for closures (stub ready for implementation)

2. **Generated Output**:
   - Block procedure definitions at module level
   - Environment structs for captured variables
   - `createBlock()` calls with procedure references
   - Runtime helpers (`sendMessage`, `isTruthy`, `toInt`, operator functions)

## IDE Integration Considerations

When the IDE needs to:

- **Compile file**: Use CLI granite directly
- **Query codebase**: Use Harding-side Granite (has full class model)
- **Navigate symbols**: Needs Harding VM loaded
- **Build application**: Can use either path

Recommendation: IDE should primarily use Harding-side Granite for consistency.

## Action Items

1. **Document current divergence** (this file) ✓
2. **Standalone script compilation with inline control flow** ✓
3. **Block registry and procedure generation infrastructure** ✓
4. **First-class block compilation** with captures and `value:` dispatch
5. **Non-local return** from blocks via Nim exceptions
6. **Refactor CLI granite** to use shared `compileSource()` function
7. **Add optional VM initialization** to CLI for advanced analysis
8. **Create unified compiler API** in `compiler/compiler.nim`
9. **Update primitives** to use same unified API
10. **Add tests** ensuring both paths produce identical output

## Nim Metaprogramming Opportunities

Research into Nim's metaprogramming capabilities reveals several techniques that could enhance Granite's code generation:

### 1. quote/do - Hygienic AST Generation

Instead of string concatenation for code generation:
```nim
result.add("  result = " & genExpression(ctx, stmt) & "\n")
```

We could use hygienic AST generation:
```nim
quote do:
  result = `stmtCode`
```

Benefits:
- Generates proper Nim AST with hygiene (avoids name collisions)
- Compile-time validation of generated code structure
- Better error messages pointing to actual source locations

### 2. Compile-Time Execution (static: blocks)

Pre-compute method tables, slot layouts, and class hierarchies at compile time:
```nim
static:
  # Build method dispatch tables at compile time
  let methodTable = buildMethodTable(parsedClasses)
```

Benefits:
- Move expensive computations to compile time
- Generate optimized dispatch tables
- Validate code structure before runtime

### 3. Templates for Inline Operations

Instead of procedure calls for every binary operation, use templates:
```nim
template fastAdd(a, b: NodeValue): NodeValue =
  if a.kind == vkInt and b.kind == vkInt:
    NodeValue(kind: vkInt, intVal: a.intVal + b.intVal)
  else:
    slowPathAdd(a, b)
```

Benefits:
- Inline expansion at call sites (no function call overhead)
- Type-specialized code paths
- Zero-cost abstractions for common operations

### 4. AST Construction API

Build Nim AST directly from Harding AST:
```nim
newCall(ident"NodeValue",
  newAssignment(ident"kind", ident"vkInt"),
  newAssignment(ident"intVal", newIntLitNode(42)))
```

Benefits:
- Type-safe AST construction
- No string parsing/generation overhead
- Direct manipulation of NimNode structures

### 5. parseExpr/parseStmt

Convert Harding-generated Nim code strings to validated AST:
```nim
let nimAst = parseStmt(generatedCode)
```

Benefits:
- Validate generated code at compile time
- Catch syntax errors in generated code early
- Integrate with Nim's macro system

### Current Approach vs. Metaprogramming

**Current (String-Based)**:
- Simple and debuggable (can print intermediate Nim code)
- Easy to understand and modify
- Works with standard Nim compilation

**Metaprogramming (AST-Based)**:
- Type-safe and hygienic
- Better compile-time validation
- More complex to debug
- Harder to read generated code

**Recommendation**: Keep string-based generation for now (simplicity, debuggability), but design the architecture so AST-based generation could be added later. The `codegen/` module structure already supports this - we just swap out the string building for AST building.

## Related Files

- `src/harding/compiler/granite.nim` - CLI entry point
- `src/harding/compiler/compiler_primitives.nim` - Primitive implementations
- `lib/core/Granite.hrd` - Harding-side Granite class
- `lib/core/Application.hrd` - Application build support
- `src/harding/codegen/module.nim` - Main code generation
- `src/harding/codegen/blocks.nim` - Block compilation
- `src/harding/codegen/expression.nim` - Expression generation with inline control flow
