# Nemo User Manual

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Running Nemo](#running-nemo)
4. [Basic Syntax](#basic-syntax)
5. [Object System](#object-system)
6. [Methods](#methods)
7. [Control Flow](#control-flow)
8. [Collections](#collections)
9. [Processes and Concurrency](#processes-and-concurrency)
10. [File I/O](#file-io)
11. [Global Namespace](#global-namespace)
12. [Command Line Options](#command-line-options)

## Introduction

Nemo is a Smalltalk dialect that compiles to Nim. It preserves Smalltalk's message-passing syntax and live programming feel while adding native compilation, Nim ecosystem access, and familiar Unix tooling.

## Installation

```bash
git clone https://github.com/gokr/nemo.git
cd nemo
nimble build
nimble local   # Copies binaries to current directory
```

Binaries: `nemo` (REPL/interpreter), `nemoc` (compiler stub), `nemo-ide` (GTK IDE)

## Running Nemo

### Interactive REPL

```bash
nemo
```

Type expressions and see results immediately. Use `:help` for commands, `:quit` to exit.

### Run a Script

```bash
nemo script.nemo
```

### Evaluate Expression

```bash
nemo -e "3 + 4"
```

### Debug Output

```bash
nemo --loglevel DEBUG script.nemo
```

## Basic Syntax

### Comments

```smalltalk
# This is a comment
#==== Section header
```

### Literals

```smalltalk
42                  # Integer
3.14                # Float
"hello"             # String
#symbol             # Symbol
#(1 2 3)            # Array
#{"key" -> "value"} # Table (dictionary)
```

### Variables

Global variables must start with uppercase:
```smalltalk
MyGlobal := 42      # Valid global
myVar := 42         # Error: must start with uppercase
```

### Assignment

```smalltalk
x := 42             # Assignment
```

### Message Sending

Unary (no arguments):
```smalltalk
obj size
obj class
```

Binary (one argument, operator):
```smalltalk
3 + 4
5 > 3
"a" , "b"          # String concatenation
```

Keyword (one or more arguments):
```smalltalk
dict at: key put: value
obj moveBy: 10 and: 20
```

## Object System

### Creating Classes

```smalltalk
# Create a class with instance variables
Point := Object derive: #(x y)

# Create an instance
p := Point new
p x: 100
p y: 200
```

### Instance Variables

Instance variables declared with `derive:` are accessed by name within methods:

```smalltalk
Point>>moveBy: dx and: dy [
    x := x + dx      # Direct slot access
    y := y + dy
    ^ self
]
```

### Inheritance

Single inheritance:
```smalltalk
ColoredPoint := Point derive: #(color)
```

Multiple inheritance (with conflict resolution):
```smalltalk
# Create child that overrides conflicting methods first
Child := Object derive: #(x)
Child >> foo [ ^ "child" ]

# Now add conflicting parents
Child addParent: Parent1
Child addParent: Parent2
```

## Methods

### Defining Methods

```smalltalk
Class>>methodName [
    # Method body
    ^ returnValue
]

Class>>methodWith: arg1 and: arg2 [
    # Use arg1 and arg2
    ^ arg1 + arg2
]
```

### Return Values

Use `^` (caret) to return a value:
```smalltalk
Point>>x [ ^ x ]
```

If no `^` is used, the method returns `self`.

### Blocks

Blocks are closures with lexical scoping:

```smalltalk
# Block with parameter
[:param | param + 1]

# Block with temporaries
[ | temp | temp := 1. temp + 2 ]

# Block with non-local return
[:n | ^ n * 2]      # Return from enclosing method
```

### Cascading

Send multiple messages to the same receiver:
```smalltalk
obj 
    at: #x put: 0;
    at: #y put: 0;
    at: #z put: 0
```

## Control Flow

### Conditionals

```smalltalk
(x > 0) ifTrue: ["positive"] ifFalse: ["negative"]

(x isNil) ifTrue: ["nil"]
```

### Loops

```smalltalk
# Times repeat
5 timesRepeat: [Stdout writeline: "Hello"]

# To:do:
1 to: 10 do: [:i | Stdout writeline: i]

# To:by:do:
10 to: 1 by: -1 do: [:i | Stdout writeline: i]

# While
[condition] whileTrue: [body]
[condition] whileFalse: [body]

# Repeat
[body] repeat           # Infinite loop
[body] repeat: 5        # Repeat N times
```

### Iteration

```smalltalk
# Do: - iterate over collection
collection do: [:each | each print]

# Collect: - transform each element
collection collect: [:each | each * 2]

# Select: - filter elements
collection select: [:each | each > 5]

# Detect: - find first matching
collection detect: [:each | each > 5]
```

## Collections

### Arrays

```smalltalk
# Create array
arr := #(1 2 3)
arr := Array new: 5     # Empty array with 5 slots

# Access
arr at: 1               # First element (1-based indexing)
arr at: 1 put: 10       # Set first element

# Methods
arr size                # Number of elements
arr add: 4              # Append element
arr join: ","           # Join with separator
```

### Tables (Dictionaries)

```smalltalk
# Create table
dict := #{"key" -> "value", "foo" -> "bar"}

# Access
dict at: "key"
dict at: "newKey" put: "newValue"

# Methods
dict keys               # All keys
dict includesKey: "key" # Check if key exists
```

## Processes and Concurrency

Nemo supports cooperative green threads:

```smalltalk
# Fork a new process
process := Processor fork: [
    1 to: 10 do: [:i |
        Stdout writeline: i
        Processor yield      # Yield to other processes
    ]
]

# Process introspection
process pid               # Process ID
process name              # Process name
process state             # State: ready, running, blocked, suspended, terminated

# Process control
process suspend
process resume
process terminate

# Yield current process
Processor yield
```

All processes share the same globals and class hierarchy, enabling inter-process communication.

## File I/O

### Stdout

```smalltalk
Stdout write: "Hello"
Stdout writeline: "Hello, World"
```

### FileStream

```smalltalk
# Open file
file := FileStream openRead: "input.txt"
file := FileStream openWrite: "output.txt"
file := FileStream openAppend: "log.txt"

# Read
line := file readLine
contents := file readAll

# Write
file write: "text"
file writeline: "line with newline"

# Check
file atEnd              # True if at end of file

# Close
file close
```

## Global Namespace

The `Nemo` object provides access to the global namespace:

```smalltalk
# List all globals
Nemo keys

# Get a global
Nemo at: "Object"
Nemo at: "MyClass"

# Set a global
Nemo at: "myVar" put: 42

# Check if exists
Nemo includesKey: "myVar"

# Load a file
Nemo load: "lib/core/MyLibrary.nemo"
```

### NEMO_HOME

Files loaded via `Nemo load:` are resolved relative to `NEMO_HOME`:

```bash
# Set via environment variable
export NEMO_HOME=/opt/nemo
nemo script.nemo

# Or via CLI option
nemo --home /opt/nemo script.nemo
```

## Command Line Options

```bash
nemo [options] [file.nemo]
nemo [options] -e "expression"

Options:
  --home <path>       Set NEMO_HOME directory (default: current directory)
  --bootstrap <file>  Use custom bootstrap file (default: lib/core/Bootstrap.nemo)
  --loglevel <level>  Set log level: DEBUG, INFO, WARN, ERROR (default: ERROR)
  --stack-depth <n>   Set maximum stack depth (default: 10000)
  --ast               Dump AST after parsing and continue execution
  --help              Show help
  --version           Show version
  --test              Run built-in tests
```

### Environment Variables

- `NEMO_HOME` - Default home directory for loading libraries

---

For more information, see the other documentation files in the `docs/` directory.
