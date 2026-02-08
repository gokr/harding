# Harding Future Plans and Roadmap

## Overview

This document outlines planned features, architectural decisions under consideration, and the development roadmap for Harding.

---

## Concurrency Models

Harding aims to support multiple concurrency approaches for different use cases:

### Green Threads (Current Foundation)

**Status**: Partially implemented

Green threads are cooperative lightweight threads managed by a VM-level scheduler:

```smalltalk
process := Processor fork: [ body ]
process suspend; process resume; process terminate
Processor yield
```

**Current Implementation:**
- Basic process forking with `Processor fork:`
- Explicit yield with `Processor yield`
- Process state introspection (pid, name, state)
- Process control (suspend, resume, terminate)
- Shared globals for inter-process communication

**Planned:**
- Monitor synchronization primitive
- SharedQueue for producer-consumer patterns
- Semaphore for counting/binary locks

### Future Extensions

**Native Thread Compilation** - When compiling to Nim:
- Each Process becomes a Nim `Thread`
- Message sends to other Processes become channel operations
- Shared objects use Nim's `Lock` for multi-thread access

**Channels** - Provide typed communication:
```smalltalk
ch := Channel new: 10.
ch send: 42.
value := ch receive.
```

---

## GUI IDE Development

### Current Status

The GTK bridge provides basic widget support. GUI tools can be written in Harding and modified at runtime.

**Implemented:**
- Basic widget wrappers (Window, Button, Box, Label, Entry)
- TextView with buffer
- ScrolledWindow
- Base signal handling with safe evaluation
- Two-table system for GC safety

**In Progress:**
- TreeView for hierarchical data
- HeaderBar
- Menu system

### Planned IDE Tools

#### Minimal Viable IDE (MVP)

1. **Transcript** - Output console
2. **Workspace** - Code editor with Do It/Print It/Inspect It
3. **Basic navigation** - Between tools

**Estimated:** 7-9 weeks

#### Full IDE

After MVP, add:
1. **Inspector** - Object inspector with slot tree, drill-down
2. **System Browser** - Class/method browsing, editing, saving
3. **Debugger** - Stack frame display, step over/into/out/continue

**Estimated:** 10-15 additional weeks

### Key Design Principle

All GUI tools are written in Harding code, making them malleable at runtime. Only a thin Nim wrapper (~20 core GTK widgets) is static.

---

## Smalltalk-80 Compatibility Gaps

### High Priority Missing Features

1. **`OrderedCollection`** - Growable arrays
   - `add:`, `addFirst:`, `addLast:`, `addAll:`
   - `removeFirst`, `removeLast`, `remove:ifAbsent:`

2. **`between:and:`** on Number - Common idiom
   ```smalltalk
   (x between: 1 and: 10) ifTrue: [...]
   ```

3. **`species`** - Required for Collection methods
   - Ensures `collect:` returns same collection type

### Already Implemented (in Collections.hrd)

- `withIndexDo:` on Array
- `at:ifAbsent:`, `at:ifAbsentPut:`, `at:ifPresent:`, `at:ifPresent:ifAbsent:` on Table
- `copyFrom:to:` on Array
- `with:do:` for parallel iteration on Array
- `addFirst:`, `addLast:`, `removeFirst`, `removeLast`, `addAll:`, `removeAll` on Array

### Medium Priority

- **`SortedCollection`** with configurable sort blocks
- **`Bag`** for counting occurrences
- **`Interval`** to replace `to:do:` with collection iteration
- **Stream hierarchy** (ReadStream, WriteStream)
- **`hash`** method on Object

### Lower Priority

- **Character** as distinct type
- **Date/Time** classes (Can use Nim FFI)
- **Trigonometric and advanced math`
- **LinkedList**
- **MappedCollection**

---

## Test Framework

### Planned sUnit-Based Framework

Follow the xUnit family pattern:

```smalltalk
MyTest := TestCase derive

MyTest>>testAddition [
    self assert: 2 + 2 equals: 4
]
```

### Core Classes

- **TestCase** - Base class for tests with `assert:`, `deny:`, `assert:equals:`, `should:raise:`
- **TestSuite** - Collection of tests
- **TestResult** - Pass/fail/error counts
- **TestRunner** - Test execution with multiple output formats

### Implementation Phases

1. **Core**: TestCase with basic assertions, TestResult, TestRunner
2. **Complete**: `should:raise:`, setUp/tearDown, TestSuite
3. **Advanced**: Categories, multiple output formats, test discovery

---

## Advanced Language Features

### Continuations

Capture and resume execution state:

```smalltalk
continuation := self callcc: [:cont |
    saved := cont.
    42
]
saved value: 100
```

**Use cases:**
- Live migration (serialize, send to another node, resume)
- Fault tolerance (snapshot periodically)
- Generators

### Actors (Erlang-inspired)

Entities with identity, state, and mailbox:

```smalltalk
pid := [self receive: [:msg | msg process]] spawn.
pid send: #compute with: 42.
```

---

## Development Roadmap

### Near Term (0-3 months)

- Complete green threads (Monitor, SharedQueue, Semaphore)
- Fill high-priority Smalltalk gaps
- Start test framework implementation

### Medium Term (3-6 months)

- MVP IDE (Transcript + Workspace)
- Channels and goroutines
- Initial actor model

### Long Term (6-12 months)

- Full IDE (Inspector, Browser, Debugger)
- Continuations (research phase)
- Native thread compilation

---

## Historical Decisions

### Why Multiple Inheritance?

Harding supports multiple inheritance for flexibility, unlike Smalltalk's single inheritance with mixins approach. This enables:
- Sharing behavior from multiple sources
- Clearer separation of concerns
- Easier integration with Nim's type system

Trade-off: Potential naming conflicts, mitigated by conflict detection at class definition time.

### Why Double Quote Strings?

Double quotes for strings align with most modern languages and avoids confusion with comments (which use hash).

### Why Class Methods Without Metaclasses?

Classes are objects, but metaclasses add significant complexity to the implementation. Class methods are stored directly on the class object, which is simpler and sufficient.

### Why Unified Primitive Syntax?

Single `<<primitive>>` syntax for both declarative and inline forms:
- Simpler to learn
- Explicit arguments visible
- Better validation
- Consistent with keyword message syntax

---

## For More Information

- [MANUAL.md](MANUAL.md) - Core language manual
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - VM internals
- [GTK.md](GTK.md) - GTK integration
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage
- [research/](research/) - Historical design documents
