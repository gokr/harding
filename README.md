# Nimtalk

Smalltalk semantics, Nim performance, modern tooling.

Nimtalk is a prototype-based Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing syntax and live programming feel while adding native compilation, Nim ecosystem access, and familiar Unix tooling.

## Quick Example

```smalltalk
#!/usr/bin/env ntalk

"Create a prototype with instance variables"
Point := Object derive: #(x y).

"Add a method"
Point at: "moveBy:and:" put: [ :dx :dy |
    x := x + dx.
    y := y + dy.
    self
].

"Create an instance and use it"
p := Point derive.
p x: 100 y: 200.
p moveBy: 10 and: 20.
p x  "Returns 110"
```

## For Smalltalkers

**What feels familiar:**

- Message syntax is identical: unary `obj size`, binary `3 + 4`, keyword `dict at: key put: value`
- Blocks work as expected: `[:x | x * 2]` with proper lexical scoping and non-local returns
- Everything is an object, everything happens via message sends
- Live evaluation in the REPL: `ntalk` gives you an interactive prompt
- Familiar collection messages: `do:`, `select:`, `collect:`, etc

**What's different:**

| Smalltalk | Nimtalk |
|-----------|---------|
| Classes define structure | Prototypes derive from other objects: `Object derive` or `Object derive: #(ivars)` |
| Instance variables declared in class | Declare per prototype with `derive: #(x y)` or use property bags |
| Methods compiled to method dictionary | Methods stored as properties: `Proto at: "selector" put: [ ... ]` |
| Image-based persistence | Source files, git, normal Unix workflow |
| VM execution | Compiles to Nim, then to native code |
| FFI via C bindings | Direct Nim interop: call Nim functions, use Nim types |

**The prototype system:**

Instead of classes, you create prototypes and derive instances from them:

```smalltalk
"Create a prototype with automatic accessors for x and y"
Point := Object derive: #(x y).

"Add methods by storing blocks"
Point at: "printString" put: [
    '(' + (x asString) + ', ' + (y asString) + ')'
].

"Derive an instance"
p := Point derive.
p x: 42.
p y: 99.
p printString  "Returns '(42, 99)'"
```

Instance variables declared with `derive:` are stored in slots (fast array access). Undeclared properties use a dictionary. The `derive:` syntax creates both the prototype and generates accessor methods `x`, `x:`, `y`, `y:`.

## Installation

```bash
git clone https://github.com/gokr/nimtalk.git
cd nimtalk
nimble build
nimble setup   # Copies binaries to current directory
```

Binaries: `ntalk` (REPL/interpreter), `ntalkc` (compiler stub)

## Usage

```bash
ntalk                    # Interactive REPL
ntalk script.nt          # Run a file
ntalk -e "3 + 4"         # Evaluate expression
ntalk --ast script.nt    # Show AST, then execute
ntalk --loglevel DEBUG   # Verbose execution trace

ntalkc compile file.nt   # Compile to Nim
ntalkc run file.nt       # Compile and run
```

### Debugging

Use `--loglevel DEBUG` for detailed execution tracing, or control logging programmatically in tests:

```nim
import nimtalk/core/types
configureLogging(lvlError)  # Suppress debug output
```

## Language Basics

**Literals:**
```smalltalk
42 "integer"
3.14 "float"
'hello' "string"
#(1 2 3) "array (seq)"
#{'key' -> 'value'} "table (dictionary)"
{| x: 1 y: 2 |} "object literal"
```

**Assignment and messages:**
```smalltalk
x := 42.
obj := Object derive.
obj at: 'foo' put: 'bar'.
obj at: 'foo'.
```

**Blocks and control flow:**
```smalltalk
[:param | param + 1] "block with parameter"

(x > 0) ifTrue: ['positive'] ifFalse: ['negative'].
numbers do: [:each | each print].
```

## Current Status

Working:
- Lexer, parser, AST interpreter
- Prototype object system with property bags and slot-based instance variables
- REPL with file execution
- Block closures with lexical scoping
- Data structure literals (arrays, tables, object literals)
- Base library (collections, core objects)

In progress:
- Compiler to Nim (basic infrastructure in place)
- FFI to Nim
- Standard library expansion

## Architecture

Nimtalk uses a dual execution model:

1. **Interpreter**: AST evaluation for REPL and rapid prototyping
2. **Compiler**: Translates Nimtalk to Nim source, then compiles to native binaries

The interpreter provides full Smalltalk semantics. The compiler (in development) will enable deployment as native single binary executables with better performance.

## Differences from Standard Smalltalk

**Syntax additions:**
- `#( )` array literals (like Smalltalk, but maps to Nim `seq`)
- `#{ }` table literals (key-value dictionaries, maps to Nim `table`)
- `{| |}` object literals (property bags)
- `# comment` (Nim-style comments, in addition to `"comments"`)

**Collections:**
Uses Nim's data structures directly: `seq` instead of `OrderedCollection`, `Table` instead of `Dictionary`. The literal syntax is familiar but the underlying types are Nim's high-performance implementations.

**No images:**
Nimtalk uses source files and compiles to native binaries. You use git, your regular editor, and standard build tools. The REPL provides live evaluation during development, but persistence is through source code.

## License

MIT

---

*Smalltalk's semantics, without the image.*
