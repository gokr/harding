# Nimtalk Classes and Instances - Design Document

## Core Concept

In Nimtalk, we maintain **Smalltalk-style conventions** where:
- **Classes** are prototypes that start with capital letters and serve as templates
- **Instances** are objects created from classes that represent actual data/entities
- **The distinction is purely conventional** - technically everything is a prototype

This gives us the clarity of traditional OOP while keeping the flexibility of prototypes.

## Terminology

### "Classes" (Prototypes Used as Classes)
```smalltalk
# These are "classes" - capitalized, serve as templates
Person := Object derive
Employee := Person derive
Company := Object derive
```

**Characteristics:**
- Start with capital letter (convention)
- Stored in global `Nimtalk` table
- Define structure and behavior
- Typically don't hold instance data
- Used to create instances

### "Instances" (Objects Created from Classes)
```smalltalk
# These are instances - lowercase, hold actual data
alice := Person derive
charlie := Employee derive
acme := Company derive
```

**Characteristics:**
- Typically lowercase (convention)
- Hold instance-specific data
- Inherit behavior from their class
- Created by sending messages to classes

## Global Storage

### Nimtalk Global Table
```smalltalk
# All "classes" get stored in Nimtalk global
Nimtalk := Table new.

# When we assign to a capitalized variable at top level:
Person := Object derive

# It's automatically added to Nimtalk
Nimtalk at: "Person" put: Person

# Can reference as:
Nimtalk Person
# or just
Person
```

**Implementation:**
```nim
# When parser sees assignment to capitalized identifier at module level:
# Person := Object derive
#
# It generates:
# 1. var Person = derive(Object)
# 2. Nimtalk["Person"] = Person
```

## Instance Creation

### Method 1: Direct Derivation
```smalltalk
# Simplest - just derive from the class
alice := Person derive.
alice name: "Alice".
alice age: 30.
```

### Method 2: Custom Factory Methods (Recommended)
```smalltalk
# Define factory method on the "class"
Person>>newWithName: aName age: anAge [
  ^ self derive
      name: aName;
      age: anAge;
      yourself
]

# Use it to create instances
alice := Person newWithName: "Alice" age: 30.
bob := Person newWithName: "Bob" age: 25.
```

### Method 3: Standard `new` (with initialize)
```smalltalk
# Similar to Smalltalk pattern
Person>>initializeWithName: aName age: anAge [
  name := aName.
  age := anAge
]

Person>>new: aName age: anAge [
  ^ self derive initializeWithName: aName age: anAge
]

# Usage
alice := Person new: "Alice" age: 30.
```

### Method 4: Cascading Initialization
```smalltalk
# After creation, use cascaded messages
alice := Person derive
  name: "Alice";
  age: 30;
  address: "123 Main St";
  yourself.
```

## Syntactic Sugar Support

### The `>>` Syntax (Parser Sugar)

The parser can convert this cleaner syntax:
```smalltalk
Person>>greet: otherPerson [
  ^ "Hello " + otherPerson name + ", I'm " + name
]
```

Into the equivalent:
```smalltalk
Person at: "greet:" put: [ :otherPerson |
  ^ "Hello " + otherPerson name + ", I'm " + name
].
```

**Requirements for Parser:**
1. Recognize `IDENTIFIER>>IDENTIFIER pattern`
2. Accept keyword selectors: `name:arg:`
3. Parse method body in `[]`
4. **Optionally accept trailing `.`**
5. Generate `at:put:` AST node

### Trailing Period Support

```smalltalk
# Both should work (parser makes trailing . optional)
Person>>greet [ ^ "Hello" ]        # No period

Person>>greet [ ^ "Hello" ].       # With period (for familiarity)
```

## Example: Complete Class Definition

### File: src/Person.nt
```smalltalk
#!/usr/bin/env ntalk
#
# Person - Represents a person
#

# Derive from Object with instance variables
Person := Object deriveWithIVars: #(name age address)

#----------------------------------------------------------------
# Instance creation methods (on the "class")
#----------------------------------------------------------------
Person at: "newWithName:age:" put: [ :aName :anAge |
  ^ self derive
      name: aName;
      age: anAge;
      yourself
].

Person at: "newWithName:age:address:" put: [ :aName :anAge :anAddr |
  ^ self derive
      name: aName;
      age: anAge;
      address: anAddr;
      yourself
].

#----------------------------------------------------------------
# Instance methods (on instances)
#----------------------------------------------------------------
Person at: "initialize" put: [
  "Default initialization"
  name := "Anonymous"
  age := 0
  address := nil
].

Person at: "name" put: [ ^ name ].

Person at: "name:" put: [ :aName | name := aName ].

Person at: "age" put: [ ^ age ].

Person at: "age:" put: [ :anAge | age := anAge ].

Person at: "address" put: [ ^ address ].

Person at: "address:" put: [ :anAddr | address := anAddr ].

Person at: "greet" put: [
  ^ "Hello, I'm " + name
].

Person at: "greet:" put: [ :other |
  ^ "Hello " + other name + ", I'm " + name
].

Person at: "birthday" put: [
  age := age + 1.
  ^ self
].

Person at: "description" put: [
  ^ name + " (age " + age asString + ")"
].
```

### Alternative: Using Parser Sugar
```smalltalk
#!/usr/bin/env ntalk
#
# Person - Using >> syntax
#

Person := Object deriveWithIVars: #(name age address).

# Class methods (instance creation)
Person>>newWithName: aName age: anAge [                    # <--- keyword with args!
  ^ self derive
      name: aName;
      age: anAge;
      yourself
].

# Instance methods
Person>>initialize [
  name := "Anonymous"
  age := 0
  address := nil
].

Person>>name [ ^ name ].

Person>>name: aName [                                     # <--- colon indicates setter
  name := aName
].

Person>>age [ ^ age ].

Person>>age: anAge [
  age := anAge
].

Person>>greet: otherPerson [                              # <--- keyword message
  ^ "Hello " + otherPerson name + ", I'm " + name
].

Person>>birthday [
  age := age + 1.
  ^ self
].

Person>>description [
  ^ name + " (age " + age asString + ")"
].
```

### Usage: main.nt
```smalltalk
#!/usr/bin/env ntalk
#
# Main application

# Load Person (future: will auto-register in Nimtalk global)
load: "src/Person.nt".

# Create instances (from Nimtalk global)
alice := Nimtalk Person newWithName: "Alice" age: 30.

# Or just (since Person is in scope)
bob := Person newWithName: "Bob" age: 25.

# Use instances
alice greet print.                         # "Hello, I'm Alice"
alice greet: bob print.                    # "Hello Bob, I'm Alice"

# State change
alice birthday.
alice age print.                           # 31

# Description
alice description print.                   # "Alice (age 31)"
```

## Inheritance Example

### Employee extends Person
```smalltalk
#!/usr/bin/env ntalk
#
# Employee extends Person

# Load parent
load: "src/Person.nt".

# Derive with additional ivars
Employee := Person deriveWithIVars: #(employeeID department salary).

# Instance creation
Employee>>newWithName: aName age: anAge id: anID dept: aDept salary: aSalary [
  ^ self derive
      name: aName;
      age: anAge;
      employeeID: anID;
      department: aDept;
      salary: aSalary;
      yourself
].

# Override parent method
Employee>>greet [
  ^ (super perform: "greet") + " from " + department + " department"
].

# New method
Employee>>giveRaise: amount [
  salary := salary + amount.
  ^ self
].
```

## Parser Implementation Details

### Recognizing `>>` Syntax

The parser needs to:

1. **Tokenize `>>`** as a single token
2. **Parse method signature** after `>>`:
   - Unary: `IDENTIFIER` (e.g., `greet`)
   - Binary: `OPERATOR` (e.g., `+`)
   - Keyword: `IDENTIFIER:` (e.g., `name:`) or `IDENTIFIER: IDENTIFIER:` (e.g., `moveX:y:`)
3. **Accept optional trailing `.`**: `.] | ] .`
4. **Generate**: `at:put:` AST node

### Grammar

```ebnf
methodDefinition := receiver ">>" methodSelector methodBody ["."]
receiver := identifier
methodSelector := unarySelector | binarySelector | keywordSelector
unarySelector := identifier
binarySelector := operator
keywordSelector := identifier ":" { identifier ":" }
methodBody := "[" statements "]"
```

### Conversion Example

```smalltalk
# Input (file definition mode)
Person>>moveX: x y: y [
  x := x + dx
  y := y + dy
].

# Parser generates AST equivalent to:
MessageSendNode(
  receiver: Identifier("Person"),
  selector: "at:put:",
  arguments: [
    StringNode("moveX:y:"),
    BlockNode([
      AssignmentNode(
        left: Identifier("x"),
        right: MessageSendNode(
          receiver: Identifier("x"),
          selector: "+",
          arguments: [Identifier("dx")]
        )
      ),
      AssignmentNode(
        left: Identifier("y"),
        right: MessageSendNode(
          receiver: Identifier("y"),
          selector: "+",
          arguments: [Identifier("dy")]
        )
      )
    ])
  ]
)
```

## Summary

### Key Points

1. **No new parser for derivation** - `deriveWithIVars:` is just a message
2. **Optional `>>` syntax** - Parser sugar that converts to `at:put:`
3. **Conventional distinction** - Classes (capitalized) vs instances (lowercase)
4. **Global Nimtalk table** - Stores all "classes"
5. **Multiple creation patterns** - direct, factory methods, new, cascading
6. **Full keyword support** - `Person>>moveX: x y: y [...]`
7. **Optional trailing `.`** - Flexible syntax

### Benefits of This Approach

✅ **No special parsing for derivation** - Pure message passing
✅ **Flexible instance creation** - Multiple patterns supported
✅ **Familiar conventions** - Matches Smalltalk style
✅ **Optional sugar** - `>>` syntax is just convenience
✅ **Encapsulated classes** - Stored in Nimtalk global
✅ **Clear structure** - Class vs instance distinction

This gives us the best of both worlds: the flexibility of prototypes with the clarity of conventional OOP patterns!

---

**Next**: Should we update the implementation plan to reflect this approach? Or are we ready to start coding Phase 1 (adding deriveWithIVars: to Object)?
