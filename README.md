# Nemo

Smalltalk semantics, Nim performance, modern tooling.

Nemo is a Smalltalk dialect written in Nim. It preserves Smalltalk's message-passing syntax and live programming feel while adding native compilation, Nim ecosystem access, and familiar Unix tooling.

## Quick Example

```smalltalk
#!/usr/bin/env nemo

# Create a class with instance variables
Point := Object derive: #(x y)

# Add a method using >> syntax
Point>>moveBy: dx and: dy [
    x := x + dx
    y := y + dy
    self
]

# Create an instance and use it
p := Point new
p x: 100 y: 200
p moveBy: 10 and: 20
p x  # Returns 110
```

## For Smalltalkers

**What feels familiar:**

- Message syntax is identical: unary `obj size`, binary `3 + 4`, keyword `dict at: key put: value`
- String concatenation with comma: `"Hello" , " World"`
- Blocks work as expected with temporary variables: `[ | temp | temp := 1 ]`
- Everything is an object, everything happens via message sends
- Live evaluation in the REPL: `nemo` gives you an interactive prompt
- Familiar collection messages: `do:`, `select:`, `collect:`, etc

**What's different:**

| Smalltalk | Nemo |
|-----------|---------|
| Period required at end of statements | Optional - newline or period both work |
| Comments in double quotes | Hash `#` comments |
| Single or double quotes for strings | Double quotes only for strings |
| Classes define structure via class definition | Classes derive from parents: `Object derive: #(ivars)` |
| Instance variables declared in class | Declare in class with `derive: #(x y)`, inherited by derived |
| Methods compiled to method dictionary | Methods stored on class tables, inherited via class hierarchy |
| Image-based persistence | Source files, git, normal Unix workflow |
| VM execution | Interprets AST directly, compiles to Nim (in development) |
| FFI via C bindings | Direct Nim interop: call Nim functions, use Nim types |

### Syntax Notes

**Comments:**
```smalltalk
# This is a hash comment - the standard comment style
#==== Section headers also use hash style
```

**Strings:**
```smalltalk
"Hello, World"           # Double quotes for strings
```

**Statements:**
```smalltalk
# Both styles work - newline or period:
x := 1
y := 2

x := 1.
y := 2.
```

**The class system:**

Classes inherit from parent classes via `derive:`, and instances are created via `new`:

```smalltalk
# Create a class with automatic accessors for x and y
Point := Object derive: #(x y)

# Add methods using >> syntax
Point>>printString [
    ^ '(' , (x asString) , ', ' , (y asString) , ')'
]

# Create an instance
p := Point new
p x: 42
p y: 99
p printString  # Returns '(42, 99)'
```

Key differences to understand:
- `Object derive: #(x y)` - Creates a **class** (a subclass of Object) with instance variables
- `Point new` - Creates an **instance** of the Point class
- `Point new x: 42` - You can cascade initialization after `new`

Instance variables declared with `derive:` are stored in slots (fast array access). Classes have merged method tables for fast O(1) lookup. Slot access within methods is via direct slot access. For external slot manipulation, use `at:/at:put:` on collection instances (Array, Table).

### Method Definition Approaches

Nemo supports multiple ways to define methods:

**Approach 1: Individual method definition (>> syntax)**
```smalltalk
Point>>moveBy: dx and: dy [
    x := x + dx
    y := y + dy
    ^ self
]
```

**Approach 2: Batched method definition (extend:)**
```smalltalk
Point extend: [
    self >> moveBy: dx and: dy [
        x := x + dx
        y := y + dy
    ]
    self >> distanceFromOrigin [
        ^ ((x * x) + (y * y)) sqrt
    ]
]
```

**Approach 3: Combined class creation with methods (derive:methods:)**
```smalltalk
Person := Object derive: #(name age) methods: [
    self >> greet [ ^ "Hello, I am " , name ]
    self >> haveBirthday [ age := age + 1 ]
]
```

**Approach 4: Class-side (factory) methods (extendClass:)**
```smalltalk
Person extendClass: [
    self >> newNamed: n aged: a [
        | person |
        person := self derive
        person name: n
        person age: a
        ^ person
    ]
]

# Usage
p := Person newNamed: "Alice" aged: 30
```

The `extend:` and `extendClass:` methods use `asSelfDo:` internally, which temporarily rebinds `self` to the target object during block evaluation. This enables clean method batching syntax.

### Multiple Inheritance and Conflict Resolution

Nemo's class model supports multiple parents. When creating a class with multiple parents, the system checks for conflicts:

- **Slot name conflicts**: If two parents define the same slot name, an error is raised
- **Method selector conflicts**: If two parents define the same method selector, an error is raised

However, you can resolve conflicts by overriding methods in the child class, then using `addParent:` to add the conflicting parents:

```smalltalk
# Define two classes with conflicting methods
Parent1 := Object derive: #(a)
Parent1 >> foo [ ^ "foo1" ]

Parent2 := Object derive: #(b)
Parent2 >> foo [ ^ "foo2" ]

# Create a child class that overrides the conflicting method
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Now add the conflicting parents - this works because child overrides
Child addParent: Parent1
Child addParent: Parent2

result := Child new foo  # Returns "child" (child's override takes precedence)
```

**Important**: Only directly-defined methods on parents are checked for conflicts. Inherited methods (like `derive:` from Object) will not cause false conflicts.

### Green Threads (Cooperative Processes)

Nemo supports cooperative green threads for concurrent execution with first-class Process objects:

```smalltalk
# Fork a new process - returns a Process object
process := Processor fork: [
  1 to: 10 do: [:i |
    Stdout writeline: i
    Processor yield  # Yield to other processes
  ]
]

# Query process properties
process pid       # Returns process ID (integer)
process name      # Returns process name (string)
process state     # Returns state: "ready", "running", "blocked", "suspended", "terminated"

# Control processes
process suspend   # Suspend execution
process resume    # Resume suspended process
process terminate # Terminate the process

# Yield current process
Processor yield
```

Each process has its own interpreter with an isolated activation stack, but all processes share the same globals and class hierarchy. The scheduler uses round-robin scheduling with explicit yields.

### Nemo Global (GlobalTable)

The `Nemo` object is a GlobalTable instance that provides access to the global namespace:

```smalltalk
# List all globals
Nemo keys         # Returns array of global variable names

# Get a global
Nemo at: "Object" # Returns the Object class

# Set a global
Nemo at: "myVar" put: 42

# Check if global exists
Nemo includesKey: "myVar"  # Returns true/false
```

Multiple processes can share globals via the `Nemo` GlobalTable, enabling inter-process communication.

## Installation

```bash
git clone https://github.com/gokr/nemo.git
cd nemo
nimble build
nimble local   # Copies binaries to current directory
```

Binaries: `nemo` (REPL/interpreter), `nemoc` (compiler stub)

### VSCode Extension

Syntax highlighting for `.nemo` files is available via the included VSCode extension. To install:

```bash
# From command line
code --install-extension nemo-lang-0.1.0.vsix

# Or from VSCode:
# 1. Press Ctrl+Shift+P (Cmd+Shift+P on Mac)
# 2. Type "Extensions: Install from VSIX..."
# 3. Select nemo-lang-0.1.0.vsix
# 4. Reload VSCode when prompted
```

Or manually rebuild the extension after making changes to the grammar:

```bash
npm install -g @vscode/vsce
vsce package
```

## Usage

```bash
nemo                    # Interactive REPL
nemo script.nemo          # Run a file
nemo -e "3 + 4"         # Evaluate expression
nemo --ast script.nemo    # Show AST, then execute
nemo --loglevel DEBUG   # Verbose execution trace
```

### Debugging

Use `--loglevel DEBUG` for detailed execution tracing.

## Language Basics

**Literals:**
```smalltalk
42                  # integer
3.14                # float
"hello"             # string
#(1 2 3)            # array (seq)
#{"key" -> "value"} # table (dictionary)
{| x: 1 y: 2 |}    # object literal
#symbol             # symbol literal
```

**Assignment and messages:**
```smalltalk
x := 42
obj := Object derive
obj at: #foo put: #bar
obj at: #foo
```

**Blocks and control flow:**
```smalltalk
[ :param | param + 1 ]     # block with parameter
[ | temp | temp := 1 ]     # block with temporary variable

(x > 0) ifTrue: ["positive"] ifFalse: ["negative"]
numbers do: [:each | each print]
```

**Multiline keyword messages:**
```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

See [docs/NEWLINE_RULES.md](docs/NEWLINE_RULES.md) for details on newline handling.

## Current Status

**Working:**
- Lexer, parser, AST interpreter
- Class-based object system with slot-based instance variables
- REPL with file execution
- Block closures with lexical scoping, environment capture, and non-local returns
- Closure variable isolation and sibling block sharing
- Data structure literals (arrays, tables, object literals)
- Method definition syntax (`>>`)
- `self` and `super` support (unqualified and qualified `super<Parent>`)
- Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`, `&`, `|`)
- Enhanced comment handling (`#` followed by special chars)
- Standard library (Object, Boolean, Block, Number, Collections, String, FileStream, Exception, TestCase)
- All stdlib files load successfully
- Dynamic message sending: `perform:`, `perform:with:`, `perform:with:with:`
- Method batching: `extend:`, `extendClass:`, `derive:methods:`
- Self-rebinding: `asSelfDo:` for evaluating blocks with modified self
- Green threads: cooperative processes with `Processor yield`, `Processor fork:`
- Per-process interpreters with shared globals
- Conflict detection for multiple inheritance (slot names, method selectors)
- `addParent:` message for adding parents after class creation
- `nil` as singleton instance of UndefinedObject (not a primitive)
- `Stdout` global for console output
- String `repeat:` for repeating strings
- Array `join:` for concatenating elements
- String concatenation with comma operator `,`

**In progress:**
- Compiler to Nim (nemoc is stub)
- FFI to Nim
- Standard library expansion

## Architecture

Nemo uses AST interpretation for REPL and rapid prototyping. The compiler (in development) will enable deployment as native single binary executables with better performance.

## Differences from Standard Smalltalk

**Syntax additions:**
- `#( )` array literals (like Smalltalk, but maps to Nim `seq`)
- `#{ }` table literals (key-value dictionaries, maps to Nim `table`)
- `{| |}` object literals
- `# comment` (Nim-style comments) and `#====` section headers
- `| temp |` for temporary variables in blocks (Smalltalk-style)
- Newline as implicit statement separator (period still works explicitly)

**Multi-character binary operators:**
```smalltalk
a == b      # Equality comparison
a ~= b      # Not equal
a <= b      # Less than or equal
a >= b      # Greater than or equal
a // b      # Integer division
a \ b       # Modulo (single backslash)
a ~~ b      # Not identity
a & b       # Logical AND
a | b       # Logical OR
```

**Collections:**
Uses Nim's data structures directly: `seq` instead of `OrderedCollection`, `Table` instead of `Dictionary`. The literal syntax is familiar but the underlying types are Nim's implementations.

**No images:**
Nemo uses source files. You use git, your regular editor, and standard build tools. The REPL provides live evaluation during development, but persistence is through source code.

## Newline Handling

Nemo supports newline-based statement separation while allowing keyword messages to span lines:

- Line endings act as statement separators
- Periods also terminate statements explicitly
- Keyword message chains can span multiple lines
- Binary operators cannot span lines
- Method selectors must be on a single line

See [docs/NEWLINE_RULES.md](docs/NEWLINE_RULES.md) for complete details.

## License

MIT

---

*Smalltalk's semantics, without the image.*
