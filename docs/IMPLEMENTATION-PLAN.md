# Nimtalk Object Model - Implementation Plan

## Overview
This document outlines the implementation steps for the new object model with declared instance variables and the `>>` method definition syntax.

## Design Decisions (Final)

✅ **Instance Variable Declaration**: `Proto := Object derive: #(ivar1 ivar2)`
✅ **Method Definition Syntax**: `Proto>>method [ ... ]` (in files only)
✅ **Parsing**: Option B - Extended Parser (no preprocessing)
✅ **No Trailing Periods**: After method definitions
✅ **Direct Slot Access**: Inside methods for performance
✅ **Auto-generated Accessors**: Override with custom behavior when needed
✅ **String Literals**: Double quotes `""` (not single quotes)
✅ **Two Parsing Modes**: REPL mode and File Definition mode

## Implementation Phases

### Phase 1: Parser Support for `derive:` Sytanx
**Week 1**

#### Tasks:
1. Modify lexer to accept `#( ... )` syntax for instance variable arrays
2. Modify parser to recognize `derive:` keyword with array literal
3. Add AST node for prototype creation with declared ivars
4. Update grammar documentation

#### Code Modifications:
- `src/parser/lexer.nim` - Add token for `#(` and `)`
- `src/parser/parser.nim` - Add rule for `derive:` with array
- `src/core/types.nim` - Add struct for IvarDeclaration

#### Example:
```nim
# Parser sees:
Person := Object derive: #(name age)

# Creates AST:
AssignmentNode(
  left: Identifier("Person"),
  right: DeriveNode(
    prototype: Identifier("Object"),
    ivars: ArrayNode([Identifier("name"), Identifier("age")])
  )
)
```

### Phase 2: Instance Variable Storage
**Week 2**

#### Tasks:
1. Modify object representation to store instance variables as slots
2. Implement slot offset calculation
3. Add direct memory access for ivars
4. Maintain backward compatibility for property bag objects

#### Code Modifications:
- `src/core/object.nim` - Add slot-based storage
- `src/interpreter/evaluator.nim` - Handle direct ivar access

#### Object Structure:
```nim
# Current (property bag):
type ProtoObject = object
  properties: Table[string, NodeValue]
  prototype: ProtoObject

# New (with slots):
type ProtoObject = object
  properties: Table[string, NodeValue]  # For property bag objects
  slots: seq[NodeValue]                 # For declared ivars
  slotNames: seq[string]                # Map names to indices
  prototype: ProtoObject
```

### Phase 3: Accessor Generation
**Week 3**

#### Tasks:
1. Generate default accessor methods for each declared ivar
2. Implement direct slot access (no dictionary lookup)
3. Support custom accessor overrides
4. Add error handling for undeclared ivar access

#### Code Modifications:
- `src/interpreter/objects.nim` - Add accessor generation
- `src/compiler/codegen.nim` - Optimize direct access

#### Generated Accessors:
```smalltalk
# When compiler sees:
Person := Object derive: #(name age)

# It generates (at compile time or runtime):
Person>>name [ ^ self getSlot: 0 ]
Person>>name: aName [ self setSlot: 0 to: aName ]
Person>>age [ ^ self getSlot: 1 ]
Person>>age: anAge [ self setSlot: 1 to: anAge ]

# Or more likely, direct memory access in compiled code
```

### Phase 4: Extended Parser for `>>` Syntax
**Week 4**

#### Tasks:
1. Add `>>` token to lexer
2. Add grammar rule for method definitions
3. Create MethodDefinition AST node
4. Generate appropriate `at:put:` code
5. Support both REPL and File modes

#### Code Modifications:
- `src/parser/lexer.nim` - Add `>>` token
- `src/parser/parser.nim` - Add method definition rule
- `src/parser/ast.nim` - Add MethodDefinitionNode

#### Grammar:
```nim
methodDefinition := identifier ">>" methodSelector methodBody
methodSelector := identifier | keywordSelector
keywordSelector := identifier ":" { identifier ":" }
methodBody := "[" { statement } "]"
```

#### Parsing Example:
```nim
# Parser sees:
Person>>greet [ ^ "Hello" ]

# Creates AST:
MethodDefinitionNode(
  receiver: Identifier("Person"),
  selector: "greet",
  body: BlockNode([ReturnNode("Hello")])
)

# At evaluation:
# Send "at:put:" message to Person
```

### Phase 5: Super and Self Support
**Week 5**

#### Tasks:
1. Implement `self` implicit receiver in methods
2. Add `super perform:` message sends
3. Support method overriding with super calls
4. Test inheritance chains

#### Code Modifications:
- `src/interpreter/activation.nim` - Add self binding
- `src/interpreter/evaluator.nim` - Handle super sends

### Phase 6: Dual Parsing Modes
**Week 5-6**

#### Tasks:
1. Create `ParserMode` enum (repl or definition)
2. Add mode parameter to parser
3. In definition mode, recognize `>>` syntax
4. In repl mode, only accept standard syntax
5. Add `load:` primitive for loading files

#### Code Modifications:
- `src/parser/parser.nim` - Add mode parameter
- `src/repl/main.nim` - Set parser mode based on context
- `src/core/primitives.nim` - Add load primitive

### Phase 7: Integration and Testing
**Week 6**

#### Tasks:
1. Write comprehensive tests for new features
2. Update examples to use new syntax
3. Update documentation
4. Performance benchmarks
5. Integration testing

#### Test Coverage:
- Instance variable declaration
- Direct slot access performance
- Accessor generation and override
- Method definition parsing
- Inheritance with super
- REPL vs File mode differences

## File Format Specification

### .nt Files (Nimtalk Definition Files)

```smalltalk
#!/usr/bin/env ntalk
#
# Comments can use single #

"Module imports (future)"
# import: stdlib

"Instance variables declaration"
Person := Object derive: #(name age address)

"Method definitions (special parsing)"
Person>>initialize [
  name := "Anonymous"
  age := 0
  address := nil
]

Person>>name [ ^ name ]

Person>>name: aName [
  name := aName
]

Person>>age [ ^ age ]

Person>>age: anAge [
  (anAge >= 0) ifFalse: [ Error signal: "Age must be positive" ].
  age := anAge
]

Person>>description [
  ^ name + " (" + age asString + " years old)"
]

"Class-side methods"
Person>>newWithName: aName age: anAge [
  ^ self derive initialize
      name: aName;
      age: anAge;
      yourself
]
```

**Key Rules:**
- No trailing periods after method definitions
- Empty lines between methods (recommended)
- Comments with `#` or `"comment"`
- Instance variables declared once per prototype
- Inheritance: `Child := Parent derive: #(newIvars)`

### Execution Flow

```
.nt file
    ↓
Parser (File Definition Mode)
    ↓
MethodDefinition AST nodes
    ↓
Evaluation
    ↓
Person at: "greet" put: block
```

## API Reference

### For Users

```smalltalk
"Define prototype with ivars"
Person := Object derive: #(name age)

"Inherit and extend"
Employee := Person derive: #(salary department)

"Define methods (in files)"
Person>>greet [ ^ "Hello" ]

"Use objects"
person := Person derive initialize
person name: "Alice"
person greet

"Load other files (future)"
Person := load: "models/Person.nt"
```

### For Implementers

```nim
# Create prototype with ivars
proc deriveWithIVars(proto: ProtoObject, ivars: seq[string]): ProtoObject

# Access ivar by name
proc getIvar(obj: ProtoObject, name: string): NodeValue
proc setIvar(obj: ProtoObject, name: string, value: NodeValue)

# Access ivar by slot index (fast)
proc getSlot(obj: ProtoObject, index: int): NodeValue
proc setSlot(obj: ProtoObject, index: int, value: NodeValue)

# Generate default accessors
proc generateAccessor(prototype: ProtoObject, ivarName: string)

# Check if ivar is declared
proc hasIvar(proto: ProtoObject, name: string): bool
```

## Performance Considerations

### Current Property Bag
```
person at: "name"
  → Hash table lookup
  → O(n) or O(1) with good hash
  → Indirect memory access
```

### New Slot Access
```
person name
  → Slot index calculation (at compile time)
  → Direct memory access
  → O(1) with no overhead
```

**Expected Performance Improvements:**
- Ivar access: 10-100x faster (no hash lookup)
- Method dispatch: Same or better (prototype chain still used)
- Memory: More compact (sequential slots vs hash table)

## Backward Compatibility

### Property Bag Objects Still Work
```smalltalk
# Old style (still supported)
dynamic := Object derive
dynamic at: "anything" put: "value"    # Arbitrary properties

# New style (recommended)
structured := Person derive: #(name age)
structured name: "Alice"                 # Declared ivars only
```

### Migration Path
```smalltalk
# Phase 1: Both models work
# Phase 2: Deprecation warnings for property bag on structured objects
# Phase 3: Only property bag on plain Object, not on derived prototypes
```

## Testing Strategy

### Unit Tests
```nim
# test_object_model.nim
test "can declare instance variables":
  let person = parseAndEval("Person := Object derive: #(name age)")
  check person.hasIvar("name")
  check person.hasIvar("age")

test "direct ivar access in methods":
  let code = """
    Person := Object derive: #(name)
    Person>>getName [ ^ name ]
    person := Person derive initialize
    person setSlot: 0 value: "Alice"
    person getName
  """
  check eval(code) == "Alice"

test "generated accessors":
  eval("Person := Object derive: #(name)")
  let person = eval("Person derive initialize")
  eval("person name: 'Bob'")
  check eval("person name") == "Bob"
```

### Integration Tests
```nim
# Load and execute .nt files
let result = loadAndRun("examples/Person.nt")
check result.isPrototype()
check result.hasMethod("greet")
```

## Timeline

| Phase | Duration | Tasks |
|-------|----------|-------|
| Phase 1: Parser for `derive:` | 1 week | Lexer, parser, AST |
| Phase 2: Slot storage | 1 week | Object representation, direct access |
| Phase 3: Accessors | 1 week | Generate, override, optimize |
| Phase 4: `>>` syntax | 1 week | Extended parser, dual modes |
| Phase 5: Super/Self | 1 week | Method lookup, inheritance |
| Phase 6: Integration | 1 week | Tests, examples, docs |
| **Total** | **6 weeks** | **Full implementation** |

## Risks and Mitigations

### Risk 1: Breaking Existing Code
**Mitigation**: Maintain backward compatibility with property bag model

### Risk 2: Performance Regression
**Mitigation**: Keep property bag for dynamic use cases, optimize slot access

### Risk 3: Parser Complexity
**Mitigation**: Clear separation between REPL and File modes, comprehensive tests

### Risk 4: Learning Curve
**Mitigation**: Update all examples, provide migration guide, clear error messages

## Success Criteria

✅ All phases complete in 6 weeks
✅ Parser correctly handles `derive:` and `>>` syntax
✅ Direct ivar access is 10x+ faster than property bag
✅ All existing tests pass
✅ New tests cover 100% of new code
✅ Examples updated to use new syntax
✅ Documentation is clear and complete
✅ REPL and file modes both work correctly

## Call to Action

**Ready to start implementation?**

1. ✅ Review this plan
2. ✅ Approve approach
3. 🚀 Start Phase 1 (parser modifications)
4. 🧪 Write tests alongside implementation
5. 📚 Keep documentation in sync

## References

- [OBJECT-MODEL-README.md](OBJECT-MODEL-README.md) - Problem statement
- [PROPOSAL-objcet-model.md](PROPOSAL-objcet-model.md) - Full proposal
- [SYNTAX-QUICKREF-updated.md](SYNTAX-QUICKREF-updated.md) - Syntax reference
- [DECISION-NEEDED.md](DECISION-NEEDED.md) - Design decisions

## Next Steps

**Immediate Actions:**
1. Create feature branch for object model changes
2. Start Phase 1 implementation (parser)
3. Set up performance benchmarks
4. Begin writing tests

**Milestone 1 (End of Week 1):**
- Parser recognizes `derive:` syntax
- Can create prototypes with declared ivars
- Basic slot storage working

**Milestone 2 (End of Week 2):**
- Direct slot access implemented
- Performance benchmarks showing improvement
- All tests passing

Let's build this! 🚀
