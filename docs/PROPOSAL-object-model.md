# Object Model Proposal for Nimtalk

*This file consolidates the object model design proposals from other documents.*

## Overview

This document describes the proposed evolution of Nimtalk's object model from a pure property bag system to a hybrid model supporting both dynamic properties and declared instance variables (slots).

## Current Implementation Status

The slot-based instance variable system is partially implemented:

### ✅ Implemented
- `ProtoObject` type extended with `hasSlots`, `slots`, `slotNames` fields
- `initSlotObject`, `getSlot`, `setSlot`, `hasSlotIVars`, `getSlotNames` procs
- `deriveWithIVars:` method added to root object
- Test file `tests/test_slot_ivars.nim` created

### ⏳ Pending Implementation
- Parser support for `derive: #(ivar1 ivar2)` syntax
- Direct slot access syntax (like Smalltalk's instance variable access)
- `>>` method definition syntax for files
- Accessor generation for declared instance variables

## Design Principles

1. **Backwards Compatibility**: Property bag model remains for dynamic objects
2. **Performance**: Slot-based access is faster than hash table lookup
3. **Encapsulation**: Declared structure enables better encapsulation
4. **Smalltalk Compatibility**: Move toward traditional Smalltalk semantics

## Syntax Examples

### Instance Variable Declaration
```smalltalk
# New syntax (proposed)
Person := Object derive: #(name age)

# Current workaround (implemented)
Person := Object derive
Person deriveWithIVars: #(name age)
```

### Method Definition
```smalltalk
# Proposed syntax for files (not yet implemented)
Person>>greet [
  ^ "Hello, " + name
]

# Current syntax (works)
Person at: "greet" put: [ ^ "Hello, " + (self at: "name") ]
```

## Migration Path

1. Support both property bags and slots simultaneously
2. Gradually migrate core objects to use slots
3. Add syntax sugar for slot access
4. Eventually make slots the default for performance-critical code

## Related Documents

- `NIMTALK-NEW-OBJECT-MODEL.md` - Detailed technical design
- `IMPLEMENTATION-PLAN.md` - Implementation roadmap
- `SYNTAX-QUICKREF-updated.md` - Syntax reference
- `CLASSES-AND-INSTANCES.md` - Class-based design exploration

*Last updated: 2026-01-26*