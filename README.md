# Nimtalk

Smalltalk semantics, Nim performance, modern tooling.

Nimtalk is a prototype-based Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing syntax and live programming feel while adding native compilation, Nim ecosystem access, and familiar Unix tooling.

## Quick Example

```smalltalk
#!/usr/bin/env ntalk

"Create a class with instance variables"
Point := Object derive: #(x y).

"Add a method using >> syntax"
Point>>moveBy: dx and: dy [
    x := x + dx.
    y := y + dy.
    self
].

"Create an instance and use it"
p := Point new.
p x: 100 y: 200.
p moveBy: 10 and: 20.
p x  "Returns 110"
```

## For Smalltalkers

**What feels familiar:**

- Message syntax is identical: unary `obj size`, binary `3 + 4`, keyword `dict at: key put: value`
- String concatenation with comma: `"Hello" , " World"`
- Blocks work as expected with temporary variables: `[ | temp | temp := 1 ]`
- Everything is an object, everything happens via message sends
- Live evaluation in the REPL: `ntalk` gives you an interactive prompt
- Familiar collection messages: `do:`, `select:`, `collect:`, etc

**What's different:**

| Smalltalk | Nimtalk |
|-----------|---------|
| Classes define structure | Prototypes derive from parents: `Object derive: #(ivars)` |
| Instance variables declared in class | Declare in prototype with `derive: #(x y)`, inherited by derived |
| Methods compiled to method dictionary | Methods stored on prototype tables, inherited via prototype chain |
| Image-based persistence | Source files, git, normal Unix workflow |
| VM execution | Interprets AST directly, compiles to Nim (in development) |
| FFI via C bindings | Direct Nim interop: call Nim functions, use Nim types |

**The prototype system:**

Prototypes inherit from parent prototypes and instances are created via `new`:

```smalltalk
"Create a prototype with automatic accessors for x and y"
Point := Object derive: #(x y).

"Add methods using >> syntax"
Point>>printString [
    ^ '(' , (x asString) , ', ' , (y asString) , ')'
].

"Create an instance"
p := Point new.
p x: 42.
p y: 99.
p printString  "Returns '(42, 99)'"
```

Instance variables declared with `derive:` are stored in slots (fast array access). Prototypes have merged method tables for fast O(1) lookup. The `derive:` syntax creates a prototype and generates accessor methods `x`, `x:`, `y`, `y:` for O(1) direct slot access.

### Method Definition Approaches

Nimtalk supports multiple ways to define methods:

**Approach 1: Individual method definition (>> syntax)**
```smalltalk
Point>>moveBy: dx and: dy [
    x := x + dx.
    y := y + dy.
    ^ self
]
```

**Approach 2: Batched method definition (extend:)**
```smalltalk
Point extend: [
    self >> moveBy: dx and: dy [
        x := x + dx.
        y := y + dy
    ].
    self >> distanceFromOrigin [
        ^ ((x * x) + (y * y)) sqrt
    ]
]
```

**Approach 3: Combined class creation with methods (derive:methods:)**
```smalltalk
Person := Object derive: #(name age) methods: [
    self >> greet [ "Hello, I am " , name ].
    self >> haveBirthday [ age := age + 1 ]
]
```

**Approach 4: Class-side (factory) methods (extendClass:)**
```smalltalk
Person extendClass: [
    self >> newNamed: n aged: a [
        | person |
        person := self derive.
        person name: n.
        person age: a.
        ^ person
    ]
]

# Usage
p := Person newNamed: "Alice" aged: 30.
```

The `extend:` and `extendClass:` methods use `asSelfDo:` internally, which temporarily rebinds `self` to the target object during block evaluation. This enables clean method batching syntax.

### Green Threads (Cooperative Processes)

Nimtalk supports cooperative green threads for concurrent execution:

```smalltalk
"Fork a new process"
process := Processor fork: [
  1 to: 10 do: [:i |
    Stdout writeline: i.
    Processor yield  "Yield to other processes"
  ]
]

"Yield current process"
Processor yield
```

Each process has its own interpreter with an isolated activation stack, but all processes share the same globals and class hierarchy. The scheduler uses round-robin scheduling with explicit yields.

## Installation

```bash
git clone https://github.com/gokr/nimtalk.git
cd nimtalk
nimble build
nimble local   # Copies binaries to current directory
```

Binaries: `ntalk` (REPL/interpreter), `ntalkc` (compiler stub)

## Usage

```bash
ntalk                    # Interactive REPL
ntalk script.nt          # Run a file
ntalk -e "3 + 4"         # Evaluate expression
ntalk --ast script.nt    # Show AST, then execute
ntalk --loglevel DEBUG   # Verbose execution trace
```

### Debugging

Use `--loglevel DEBUG` for detailed execution tracing.

## Language Basics

**Literals:**
```smalltalk
42 "integer"
3.14 "float"
"hello" "string"
#(1 2 3) "array (seq)"
#{"key" -> "value"} "table (dictionary)"
{| x: 1 y: 2 |} "object literal"
#symbol "symbol literal"
```

**Assignment and messages:**
```smalltalk
x := 42.
obj := Object derive.
obj at: "foo" put: "bar".
obj at: "foo".
```

**Blocks and control flow:**
```smalltalk
[ :param | param + 1 ] "block with parameter"
[ | temp | temp := 1 ] "block with temporary variable"

(x > 0) ifTrue: ["positive"] ifFalse: ["negative"].
numbers do: [:each | each print].
```

**Multiline keyword messages:**
```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

See [docs/NEWLINE_RULES.md](docs/NEWLINE_RULES.md) for details on newline handling.

## Current Status

Working:
- Lexer, parser, AST interpreter
- Prototype object system with slot-based instance variables
- REPL with file execution
- Block closures with lexical scoping, environment capture, and non-local returns
- Closure variable isolation and sibling block sharing
- Data structure literals (arrays, tables, object literals)
- Method definition syntax (`>>`)
- `self` and `super` support (unqualified and qualified `super<Parent>`)
- Multi-character binary operators (`==`, `//`, `\`, `<=`, `>=`, `~=`, `~~`)
- Enhanced comment handling (`#` followed by special chars)
- Standard library (Object, Boolean, Block, Number, Collections, String, FileStream, Exception, TestCase)
- All stdlib files load successfully
- Dynamic message sending: `perform:`, `perform:with:`, `perform:with:with:`
- Method batching: `extend:`, `extendClass:`, `derive:methods:`
- Self-rebinding: `asSelfDo:` for evaluating blocks with modified self
- Green threads: cooperative processes with `Processor yield`, `Processor fork:`
- Per-process interpreters with shared globals

In progress:
- Compiler to Nim (ntalkc is stub)
- FFI to Nim
- Standard library expansion

## Architecture

Nimtalk uses AST interpretation for REPL and rapid prototyping. The compiler (in development) will enable deployment as native single binary executables with better performance.

## Differences from Standard Smalltalk

**Syntax additions:**
- `#( )` array literals (like Smalltalk, but maps to Nim `seq`)
- `#{ }` table literals (key-value dictionaries, maps to Nim `table`)
- `{| |}` object literals
- `# comment` (Nim-style comments) and `#====` section headers
- `| temp |` for temporary variables in blocks (Smalltalk-style)

**Multi-character binary operators:**
```smalltalk
a == b      # Equality comparison
a ~= b      # Not equal
a <= b      # Less than or equal
a >= b      # Greater than or equal
a // b      # Integer division
a \ b       # Modulo (single backslash)
a ~~ b      # Not identity
```

**Collections:**
Uses Nim's data structures directly: `seq` instead of `OrderedCollection`, `Table` instead of `Dictionary`. The literal syntax is familiar but the underlying types are Nim's implementations.

**No images:**
Nimtalk uses source files. You use git, your regular editor, and standard build tools. The REPL provides live evaluation during development, but persistence is through source code.

## Newline Handling

Nimtalk supports newline-based statement separation while allowing keyword messages to span lines:

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
