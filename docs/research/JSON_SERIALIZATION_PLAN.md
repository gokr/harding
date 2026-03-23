# JSON Serialization Plan: Fast Nim + Declarative Harding Control

## Goal
Enable high-performance JSON serialization (Nim primitive) with declarative customization from Harding.

## Key Constraints
- **Speed**: Core traversal must happen in Nim (not message sends)
- **Flexibility**: Harding code must control serialization behavior
- **Simplicity**: Easy to use, easy to customize

## Proposed Architecture

### Option 1: Metadata-Driven Serialization (Recommended)

Store serialization configuration as class-level metadata that's read by the Nim primitive.

#### Harding API

```harding
# Default: serialize all slots
Person := Object derive: #(name email age).

# Exclude sensitive slots
Person := Object derive: #(name email age) jsonExclude: #(email).

# Include only specific slots  
Person := Object derive: #(name email age internalId) jsonOnly: #(name email).

# Rename slots in JSON
Person := Object derive: #(firstName lastName) jsonMap: #{#firstName -> "first", #lastName -> "last"}.

# Custom transformer per slot
Person := Object derive: #(name birthDate) jsonTransform: #{
    #birthDate -> [:date | date format: "yyyy-MM-dd"]
}.

# Combined configuration
Person := Object derive: #(name email age password) 
    jsonExclude: #(password)
    jsonMap: #{#email -> "emailAddress"}.
```

#### Implementation

**Nim Side (vm.nim)**:
```nim
proc primitiveSerializeToJson(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Serialize object to JSON with metadata-driven customization
    let targetClass = self.class
    
    # Read serialization metadata from class
    let excludedSlots = targetClass.jsonExcludedSlots  # seq[string]
    let includedOnly = targetClass.jsonIncludedOnly     # Option[seq[string]]
    let slotNameMap = targetClass.jsonSlotMapping      # Table[string, string]
    
    var jsonObj = newJObject()
    
    for slotName in targetClass.allSlotNames:
        # Check exclusions
        if slotName in excludedSlots:
            continue
            
        # Check inclusions (if specified, only include listed slots)
        if includedOnly.isSome and slotName notin includedOnly.get:
            continue
            
        # Get slot value using fast primitive access
        let slotValue = fastSlotAccess(self, slotName)
        
        # Map slot name if configured
        let jsonKey = if slotName in slotNameMap:
            slotNameMap[slotName]
        else:
            slotName
            
        # Check for custom transformer
        if targetClass.hasJsonTransformer(slotName):
            # Call Harding transformer (slower path)
            let transformed = callHardingTransformer(interp, self, slotName, slotValue)
            jsonObj[jsonKey] = hardingToJson(transformed)
        else:
            # Fast path: direct serialization
            jsonObj[jsonKey] = fastHardingToJson(slotValue)
    
    return NodeValue(kind: vkString, strVal: $jsonObj)
```

**Class Metadata Extension (types.nim)**:
```nim
Class* = ref object
    # ... existing fields ...
    jsonExcludedSlots*: seq[string]      # Slots to exclude
    jsonIncludedOnly*: Option[seq[string]] # If set, only these slots
    jsonSlotMapping*: Table[string, string] # slotName -> jsonKey
    jsonTransformers*: Table[string, Method] # slotName -> Harding transformer method
```

#### Derivation API Extension

```harding
Object class>>derive: slots jsonExclude: excludedSlots [
    | cls |
    cls := self derive: slots.
    cls setJsonExcludedSlots: excludedSlots.
    ^ cls
]

Object class>>derive: slots jsonOnly: includedSlots [
    | cls |
    cls := self derive: slots.
    cls setJsonIncludedOnly: includedSlots.
    ^ cls
]

Object class>>derive: slots jsonMap: mapping [
    | cls |
    cls := self derive: slots.
    cls setJsonSlotMapping: mapping.
    ^ cls
]

Object class>>derive: slots jsonExclude: excluded jsonMap: mapping [
    | cls |
    cls := self derive: slots.
    cls setJsonExcludedSlots: excluded.
    cls setJsonSlotMapping: mapping.
    ^ cls
]
```

### Option 2: Protocol-Based with Fast Path

Objects can implement a `jsonRepresentation` method that returns a Dictionary/Table, which the Nim primitive then serializes.

```harding
Person := Object derive: #(name email age).

Person>>jsonRepresentation [
    ^ #{
        "name" -> self name.
        "email" -> self email.
        "ageGroup" -> (self age > 65 ifTrue: ["senior"] ifFalse: ["adult"])
    }
]
```

**Nim primitive checks**:
1. Does object have `jsonRepresentation` method?
2. If yes: call it, get Table, serialize that (slower)
3. If no: use fast metadata-driven serialization (fast)

This gives full control when needed, fast path by default.

### Option 3: Annotation/Pragma Style

Use Harding's comment/pragma syntax to annotate slots:

```harding
Person := Object deriveWithAccessors: #(name email age #<json: ignore> password).

# Or using slot configuration
Person := Object derive: #(
    name 
    email 
    age
    #(password json: false)
).
```

This is more declarative but requires parser changes.

### Option 4: JsonSerializable Mixin + Configuration Object

Mixin provides the method, configuration is separate:

```harding
JsonSerializable := Mixin derive.

JsonSerializable>>toJson [
    ^ Json serialize: self with: self class jsonSerializationConfig
]

# Configure on class
Person := Object derive: #(name email age) superclasses: #(JsonSerializable).
Person class>>jsonSerializationConfig [
    ^ JsonConfig new
        exclude: #(password);
        map: #{#email -> "emailAddress"};
        transform: #{
            #birthDate -> [:d | d format: "ISO8601"]
        }
]
```

The `JsonConfig` object stores the configuration that the Nim primitive reads.

## Recommended Approach: Option 1 + Option 2 Hybrid

### Phase 1: Metadata-Driven (Fast Default)

1. Add serialization metadata to Class type
2. Extend `derive:` family with JSON configuration methods
3. Update Nim primitive to respect metadata
4. Default behavior: serialize all slots, no transformations

### Phase 2: Custom Representation (Full Control)

1. Add `jsonRepresentation` protocol method
2. Primitive checks for this method first
3. Falls back to metadata-driven if not implemented

### Phase 3: JsonSerializable Mixin

1. Create `JsonSerializable` mixin that uses metadata approach
2. Provides `toJson` method
3. Integrates with `Json stringify:`

## Implementation Plan

1. **Add metadata fields to Class** (types.nim)
2. **Add derive: extensions** (Object.hrd or new Json.hrd)
3. **Enhance primitiveSerializeToJson** (vm.nim)
4. **Add JsonSerializable mixin** (Json.hrd or new file)
5. **Add Json>>serialize:with:** method
6. **Update tests** (test_json_literal.nim)

## Performance Characteristics

- **Fast path**: Metadata-driven Nim loop, no message sends → ~O(n) where n=slots
- **Custom path**: One message send to get representation → ~O(n) + 1 dispatch
- **Transformer path**: Message send per transformed slot → ~O(n) + m dispatches

## Example Usage

```harding
# Basic usage - includes all slots
User := Object derive: #(id name email).
user := User new id: 1; name: "Alice"; email: "alice@example.com".
user toJson.  # {"id": 1, "name": "Alice", "email": "alice@example.com"}

# Exclude sensitive data
User := Object derive: #(id name email password) jsonExclude: #(password).
user toJson.  # {"id": 1, "name": "Alice", "email": "alice@example.com"}

# Custom mapping
User := Object derive: #(firstName lastName) jsonMap: #{#firstName -> "first", #lastName -> "last"}.
user toJson.  # {"first": "Alice", "last": "Smith"}

# Using mixin
User := Object derive: #(id name) superclasses: #(JsonSerializable).
user toJson.
```

## Future Enhancements

- Nested object serialization strategies (shallow vs deep)
- Type coercion rules (Date/Time serialization formats)
- JSON Schema generation from class metadata
- Validation hooks
