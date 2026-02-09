# Harding

Harding is a Smalltalk dialect written in Nim that preserves most of the distinguishing features of the Smalltalk language while fitting in with modern tooling and strong abilities to integrate with libraries from the Nim and C ecosystems. The language currently has a stackless AST based interpreter supporting green threads in classic Smalltalk style.

## Quick Example

```smalltalk
"Hello, World!" println

# Class with automatic accessors
Person := Object deriveWithAccessors: #(name age)
p := Person new
p name: "Alice"
p age: 30
("Hello, " , p name) println

# Class with manual method definition
Point := Object derive: #(x y)
Point>>distanceFromOrigin [ ^ ((x * x) + (y * y)) sqrt ]

p := Point new
p x: 3 y: 4
p distanceFromOrigin println  # Prints: 5.0
```

## Installation

```bash
git clone https://github.com/gokr/harding.git
cd harding
nimble local  # Build and copy binaries to root directory
```

Binaries: `harding` (REPL/interpreter), `granite` (compiler stub), `bona` (GTK IDE)

## Usage

```bash
harding                    # Interactive REPL
harding script.hrd         # Run a file
harding -e "3 + 4"         # Evaluate expression
harding --ast script.hrd   # Show AST, then execute
harding --loglevel DEBUG   # Verbose execution trace
```

### Script Execution

Script files are automatically wrapped in a block, enabling Smalltalk-style temporary variable declarations:

```smalltalk
# script.hrd
| counter total |
counter := 0
total := 0
1 to: 5 do: [:i |
  counter := counter + 1
  total := total + i
]
total  "Returns 15"
```

Scripts execute with `self = nil`, following the Smalltalk workspace convention.

### Environment Variables

- `HARDING_HOME` - Default home directory for loading libraries

### VSCode Extension

Syntax highlighting for `.hrd` files:

```bash
code --install-extension harding-lang-0.1.0.vsix
```

## For Smalltalkers

**What feels familiar:**

- Message syntax: unary `obj size`, binary `3 + 4`, keyword `dict at: key put: value`
- Cascade messages
- Classes and class methods
- String concatenation with comma: `"Hello" , " World"`
- Blocks are proper lexical closures with temporaries and can do early returns: `[ | temp | temp := 1 ]`
- Everything is an object, everything happens via message sends
- Live evaluation in the REPL with `harding`
- Collection messages: `do:`, `select:`, `collect:`, etc.

**What's different:**

| Smalltalk | Harding |
|-----------|---------|
| Required period end-of-statement | Optional - newline or period both work |
| Double quotes for comments | Hash `#` for comments |
| Single quotes for strings | Double quotes for strings |
| Classes define structure via class definition | Class construction using derive: `Object derive: #(ivars)` |
| Manual accessor definition | Auto-generated accessors via `deriveWithAccessors:` |
| Image-based persistence | Source files loaded on startup, git friendly source format, normal Unix workflow |
| VM execution | Interprets AST directly, native compiler via Nim (in development) |
| FFI via C bindings | Direct Nim interop: call Nim functions, use Nim types |

### Variable Naming Rule

Harding distinguishes globals from locals by capitalization and enforces this in parsing:

| Type | Convention | Example |
|------|------------|---------|
| Globals (class names, global variables) | Uppercase first | `Point`, `MyGlobal` |
| Locals (instance variables, temporaries, parameters, block params) | Lowercase first | `temp`, `index`, `value` |

### Key Syntax Differences

| Feature | Harding Syntax |
|---------|----------------|
| Comments | `# This is a comment` |
| Strings | `"Double quotes only"` |
| Create subclass | `Point := Object derive: #(x y)` |
| Create with accessors | `Point := Object deriveWithAccessors: #(x y)` |
| Create instance | `p := Point new` |
| Define method | `Point>>move: dx [ ... ]` |
| Batch methods | `Point extend: [ self >> foo [ ... ] ]` |

## Current Status

**Working:**
- Lexer, parser, stackless AST interpreter
- Class-based object system with slots
- REPL with file execution
- Block closures with lexical scoping and support for early returns
- Data structure literals
- Method definition (`>>`), `self` and `super` support
- Multi-character operators (`==`, `//`, `<=`, `>=`, `~=`, `~~`)
- Standard library (Object, Boolean, Block, Number, Collections, String)
- Green threads: `Processor fork:`, `Processor yield`
- Synchronization primitives: Monitor, SharedQueue, Semaphore
- Multiple inheritance with conflict detection and scoped super send
- Dynamic message sending: `perform:`, `perform:with:`
- Automatic accessor generation: `deriveWithAccessors:`, `derive:getters:setters:`
- Library/namespace system for modular code organization
- String concatenation with auto-conversion using `,`
- GTK-based IDE (`bona`) with Workspace and Transcript
- Smalltalk-style Print It - insert results in editor with selection

**In progress:**
- Compiler to Nim (granite is stub)
- FFI to Nim
- Standard library expansion

## Documentation

- [Quick Reference](docs/QUICKREF.md) - Syntax quick reference
- [Language Manual](docs/MANUAL.md) - Complete language manual
- [Implementation](docs/IMPLEMENTATION.md) - VM internals
- [Tools & Debugging](docs/TOOLS_AND_DEBUGGING.md) - Tool usage
- [Future Plans](docs/FUTURE.md) - Roadmap
- [GTK Integration](docs/GTK.md) - GUI development
- [VSCode Extension](docs/VSCODE.md) - VSCode editor support
- [GtkSourceView](docs/GTKSOURCEVIEW.md) - Gedit/GNOME Text Editor syntax highlighting

## Examples

```bash
harding examples/01_hello.hrd
harding examples/05_classes.hrd
harding examples/10_blocks.hrd
harding examples/process_demo.hrd

# Launch the GTK IDE
bona
```

See the `examples/` directory for more examples covering arithmetic, variables, objects, classes, methods, inheritance, collections, control flow, and blocks.

## License

MIT

---

*Smalltalk's semantics, modern implementation.*
