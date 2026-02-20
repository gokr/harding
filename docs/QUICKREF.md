# Harding Syntax Quick Reference

## Literals

| Type | Example | Description |
|------|---------|-------------|
| Integer | `42`, `-10` | Signed integers |
| Float | `3.14`, `-0.5` | Floating point numbers |
| String | `"hello"`, `"world"` | Double quotes only |
| Symbol | `#symbol`, `#at:put:` | Used as selectors, keys |
| Array | `#(1 2 3)`, `#("a" "b")` | Sequences of values |
| Table | `#{"key" -> "value"}` | Key-value mappings |

## Comments

```smalltalk
# Single line comment
#==== Section header
```

Note: Hash `#` + whitespace = comment. Double quotes are strings, not comments.

## Assignment

```smalltalk
x := 1                           # Assign 1 to x
y := x + 1                       # Use value of x
```

## Message Passing

### Unary (no arguments)

```smalltalk
obj size                         # Get size
obj class                        # Get class
obj notNil                       # Check not nil
```

### Binary (one argument)

```smalltalk
3 + 4                            # Add
5 - 3                            # Subtract
x * y                            # Multiply
a / b                            # Divide
x > y                            # Greater than
x < y                            # Less than
x = y                            # Equality comparison
x == y                           # Identity comparison
x ~= y                           # Inequality
x <= y                           # Less than or equal
x >= y                           # Greater than or equal
a // b                           # Integer division
a \\ b                           # Modulo (remainder)
a ~~ b                           # Not identity
"a" , "b"                        # String concatenation
a & b                            # Logical AND
a | b                            # Logical OR
```

### Keyword (one or more arguments)

```smalltalk
dict at: key                     # Get value
dict at: key put: value          # Set value
obj moveBy: 10 and: 20           # Multiple keyword args
```

### Cascading (multiple messages to same receiver)

```smalltalk
obj
  at: #x put: 0;
  at: #y put: 0;
  at: #z put: 0
```

## Blocks

### Syntax

```smalltalk
[ code ]                         # No params, no temps
[ :x | x * 2 ]                   # With params
[ | t1 t2 | code ]               # With temps, no params
[ :x :y | | t1 t2 | code ]       # With params and temps
```

The `|` separates parameters/temporaries from body.

### Invocation

```smalltalk
block value                      # No args
block value: 5                   # One arg
block value: a value: b          # Two args
```

## Control Flow

### Conditionals

```smalltalk
(x > 0) ifTrue: ["positive"]

(x > 0) ifTrue: ["positive"] ifFalse: ["negative"]

(x isNil) ifTrue: ["is nil"]
```

### Loops

```smalltalk
5 timesRepeat: ["Hello" print]

1 to: 10 do: [:i | i print]

10 to: 1 by: -1 do: [:i | i print]

[condition] whileTrue: [body]

[condition] whileFalse: [body]

[body] repeat                    # Infinite loop
[body] repeat: 5                 # Repeat N times
```

### Collection Iteration

```smalltalk
arr do: [:each | each print]     # Iterate all
arr collect: [:each | each * 2]  # Transform
arr select: [:each | each > 5]   # Filter
arr detect: [:each | each = 10]  # Find first
arr inject: 0 into: [:sum :each | sum + each]  # Fold
```

## Returns

```smalltalk
Point>>x [ ^ x ]                 # Return x value
Point>>moveTo: newPoint [
    x := newPoint x.
    y := newPoint y.
    ^self                        # Return self
]
```

If no `^`, method returns `self`.

## Method Definition

### Syntax

```smalltalk
# Unary method
Person>>greet [ ^ "Hello, " + name ]

# One parameter
Person>>name: aName [ name := aName ]

# Multiple keyword parameters
Point>>moveX: dx y: dy [
    x := x + dx.
    y := y + dy.
    ^self
]
```

### Method Batching (extend:)

```smalltalk
Person extend: [
  self >> greet [ ^ "Hello, " + name ].
  self >> name: aName [ name := aName ].
  self >> haveBirthday [ age := age + 1 ]
]
```

### Class-side Methods (extendClass:)

```smalltalk
Person extendClass: [
  self >> newNamed: n aged: a [
    | person |
    person := self derive.
    person name: n.
    person age: a.
    ^person
  ]
]
```

### Combined Class Creation

```smalltalk
Person := Object derive: #(name age) methods: [
  self >> greet [ ^ "Hello, I am " + name ].
  self >> haveBirthday [ age := age + 1 ]
]
```

## Classes and Objects

### Creating Classes

```smalltalk
# Class without accessors (manual method definition required)
Point := Object derive: #(x y)

# Class with automatic accessors for all slots
Person := Object deriveWithAccessors: #(name age)

# Class with selective accessor generation
Account := Object derive: #(balance owner)
                       getters: #(balance owner)
                       setters: #(balance)

# Subclass
ColoredPoint := Point derive: #(color)
```

### Creating Instances

```smalltalk
p1 := Point new                    # Derives new class
p2 := Point clone                  # Shallow copy
```

### Instance Variables (Slots)

```smalltalk
# Direct slot access in methods (O(1))
Point>>moveBy: dx y: dy [
    x := x + dx.
    y := y + dy.
    ^self
]
```

### Automatic Accessors

```smalltalk
# Class with auto-generated getters and setters
Person := Object deriveWithAccessors: #(name age)
p := Person new
p name: "Alice"      # Setter
p age: 30            # Setter
p name               # Getter - returns "Alice"

# Selective accessor generation
Account := Object derive: #(balance owner)
                       getters: #(balance owner)
                       setters: #(balance)
acc := Account new
acc balance: 100     # Setter for balance
acc balance          # Getter - returns 100
acc owner            # Getter - returns nil (not set)
# acc owner: "Bob"   # Error - no setter for owner
```

### Property Access

```smalltalk
obj at: #name                      # Get property
obj at: #name put: "Alice"         # Set property
obj hasProperty: #name             # Check exists
obj properties                     # Get all properties
```

### Multiple Inheritance

```smalltalk
Child := Object derive: #(x)
Child addParent: Parent1
Child addParent: Parent2
```

## Green Processes

```smalltalk
# Fork a process
process := Processor fork: [
    1 to: 10 do: [:i | i print. Processor yield]
]

# Process control
process suspend
process resume
process terminate

# Check state
process state                      # ready, running, blocked, etc.
```

## Synchronization Primitives

### Monitor (Mutex with Condition Variable)

```smalltalk
monitor := Monitor new.

# Acquire lock
monitor critical: [
    # Protected code
    sharedResource := sharedResource + 1
]

# With timeout
acquired := monitor critical: [
    # Protected code
] ifTimedOut: ["timeout action"]
```

### SharedQueue

```smalltalk
queue := SharedQueue new.

# Producer
queue nextPut: "item"

# Consumer
item := queue next
item := queue nextOrNil  # Non-blocking
```

### Semaphore

```smalltalk
sem := Semaphore new.           # Binary semaphore (count=1)
sem := Semaphore forMutualExclusion.
sem := Semaphore newSignals: 5. # Counting semaphore

# Acquire/release
sem wait
sem signal
```

## Script Files

```smalltalk
# script.hrd - File with temporary variables
| counter total |
counter := 0
total := 0

1 to: 5 do: [:i |
  counter := counter + 1
  total := total + i
]

total  "Returns 15"
```

**Execution:**
```bash
harding script.hrd
chmod +x script.hrd  # For shebang: #!/usr/bin/env harding
./script.hrd
```

**Script features:**
- Auto-wrapped in `[ ... ]` before parsing
- Temporary variables: `| var1 var2 |` at file level
- Executed with `self = nil` (Smalltalk workspace style)
- File extension: `.hrd`, `.harding`, or none

## Exception Handling

```smalltalk
[riskyOperation] on: Error do: [:ex |
    Transcript showCr: "Error: " + ex message
]

# Handler actions
ex resume          # Resume execution from signal point (signal returns nil)
ex resume: value   # Resume from signal point (signal returns value)
ex retry           # Re-execute protected block
ex pass            # Delegate to next outer handler
ex return: value   # Return value from on:do: expression

# Resumable notifications (not errors)
[Notification signal: "info"] on: Notification do: [:ex | ex resume]

# Ensure cleanup always runs
[riskyOperation] ensure: [cleanup]
```

## Primitives

```smalltalk
# Declarative form (method body is just the primitive)
Object>>clone <primitive primitiveClone>

# Inline form (validation before primitive)
Array>>at: index [
    index < 1 ifTrue: [self error: "Index out of bounds"].
    ^ <primitive primitiveAt: index>
]
```

## Dynamic Message Sending

```smalltalk
obj perform: #clone                     # Same as: obj clone
obj perform: #at:put: with: #x with: 5  # Same as: obj at: #x put: 5
```

## Special Forms

### Method Definition Aliases

```smalltalk
# These are equivalent
Object at: #method put: [...]
Object>>method [...]
```

### Method Selection (for parents)

```smalltalk
# Unqualified super (uses first parent)
Employee>>calculatePay [
    base := super calculatePay.
    ^base + bonus
]

# Qualified super (specific parent)
Employee>>calculatePay [
    base := super<Person> calculatePay.
    ^base + bonus
]
```

## Statement Separation

```smalltalk
# Periods work (Smalltalk-compatible)
x := 1.
y := 2.

# Line endings also work (Harding-style)
x := 1
y := 2

# Mixed style is fine
x := 1.
y := 2
z := x + y.
```

### Important: Newlines in Expressions

**NOT allowed** (breaks expressions):
```smalltalk
x
+ y              # Bad - newline in binary expression
obj
message          # Bad - newline after receiver
```

**Allowed** (continues statements):
```smalltalk
tags isNil
  ifTrue: ["Object"]        # OK - multiline keyword msg
x := 1
y := 2                      # OK - separate statements
```

## Common Idioms

### Conditional Assignment

```smalltalk
value := dict at: key ifAbsentPut: [computeDefault]
```

### Guard Clauses

```smalltalk
Processor>>step [
    currentProcess isNil ifTrue: [^self].
    currentProcess step
]
```

### Builder Pattern

```smalltalk
obj := Person new
    name: "Alice";
    age: 30;
    yourself
```

### Collection Construction

```smalltalk
arr := Array new: 5
arr add: 1.
arr add: 2.

# Or
arr := #(1 2 3)
```

### Table Construction

```smalltalk
dict := #{"name" -> "Alice", "age" -> 30}
```

### Interval

```smalltalk
# Create numeric intervals
interval := 1 to: 10              # 1, 2, 3, ..., 10
interval := 1 to: 10 by: 2        # 1, 3, 5, 7, 9

# Iterate
interval do: [:i | i print]

# Reverse
interval := 10 to: 1 by: -1       # 10, 9, 8, ..., 1
```

### SortedCollection

```smalltalk
# Default sort (ascending)
sorted := SortedCollection new.
sorted add: 5.
sorted add: 2.
sorted add: 8.
sorted first  # Returns 2

# Custom sort block
sorted := SortedCollection sortBlock: [:a :b | a > b].  # Descending
sorted addAll: #(3 1 4 1 5).
sorted asArray  # Returns #(5 4 3 1 1)
```

### Set

```smalltalk
# Unordered collection of unique elements
set := Set new.
set add: 1.
set add: 2.
set add: 1.  # Duplicates ignored

# Union, intersection, difference
union := set1 union: set2
intersect := set1 intersection: set2
diff := set1 difference: set2
```

### Object Inspection

```smalltalk
# Open Inspector on any object
obj inspect

# In Workspace: select code and press Ctrl+I (Inspect It)
# Shows slots, properties, and class hierarchy
```

### Standard Library

The Standard Library provides additional collection and utility classes, auto-imported at startup:

- **Set** - Unordered unique-element collection
- **Interval** - Numeric range with iteration
- **SortedCollection** - Array maintaining sort order
- **FileStream** - File I/O operations
- **Exception hierarchy** - Error, MessageNotUnderstood, etc.

### BitBarrel (Optional)

Build with `-d:bitbarrel` flag. See [BitBarrel Integration](../../CLAUDE.md#bitbarrel-integration).

- **BarrelTable** - Persistent hash-based key-value storage
- **BarrelSortedTable** - Persistent ordered storage with range queries

---

## Type Checking Pattern

```smalltalk
# Check if object responds to message
obj respondsTo: #greet ifTrue: [obj greet]
```

## Libraries and Namespaces

### Creating a Library

```smalltalk
MyLib := Library new
MyLib at: "MyClass" put: SomeClass
MyLib at: "Constant" put: 42
```

### Library Operations

```smalltalk
MyLib at: "Constant"                # Get binding (returns 42)
MyLib at: "NewKey" put: "value"      # Set binding
MyLib includesKey: "MyClass"        # Check if key exists (true)
MyLib keys                           # Get all binding names
```

### Loading Code into a Library

```smalltalk
MyLib := Library new
MyLib load: "path/to/file.hrd"       # Loads code, captures new globals into MyLib
```

### Importing Libraries

```smalltalk
MyLib := Library new
MyLib load: "mylib.hrd"
Harding import: MyLib                # Make MyLib bindings accessible

# Now accessible by name
Instance := MyClass new
```

### Variable Lookup Order

1. Local scope (temporaries, parameters, block params)
2. Instance variables (slots on `self`)
3. Imported libraries (most recent first)
4. Global table (fallback)

Note: Methods cannot see calling method's locals (proper Smalltalk scoping).

### Most Recent Import Wins

```smalltalk
Lib1 at: "SharedKey" put: 1.
Lib2 at: "SharedKey" put: 2.
Harding import: Lib1.
Harding import: Lib2.
SharedKey  # Returns 2 (Lib2 was imported last)
```

### Load to Globals

```smalltalk
Harding load: "path/to/file.hrd"      # Loads directly into global namespace
```

---

## For More Information

- [MANUAL.md](MANUAL.md) - Complete language manual
- [GTK.md](GTK.md) - GTK integration
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - VM internals
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage
