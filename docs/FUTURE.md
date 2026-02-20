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

**Implemented:**
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

**Granite Compiler** (Partially Implemented):
- ✅ Standalone `.hrd` script compilation to native binaries
- ✅ Inline control flow: `ifTrue:`, `ifFalse:`, `whileTrue:`, `whileFalse:`, `timesRepeat:`
- ✅ Block registry and procedure generation infrastructure
- First-class block compilation with captures
- Non-local return from blocks via exceptions
- Class/method compilation from in-VM code

**Performance Optimizations** (Partially Implemented):
- ✅ Monomorphic Inline Cache (MIC) - caches single method lookup per call site
- ✅ Polymorphic Inline Cache (PIC) - caches up to 4 class/method pairs with LRU promotion
- ✅ Version-based cache invalidation - class version counters detect stale entries
- ✅ Compiled code 30-200x faster than interpreted (sieve benchmark)
- Type specialization for compiled methods
- Unboxed arithmetic in compiled code
- Escape analysis for stack allocation

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
- IDE Launcher with Transcript, Workspace
- Print It functionality (inserts results in editor)
- Window icon support (`iconName:`, `setWmClass:`)
- Desktop integration (dock/Alt-Tab icons via icon themes)
- System Browser (four-pane class/method browser)
- Inspector (object slot/property viewer)
- BrowserPane (reusable list component)

**In Progress:**
- TreeView for hierarchical data
- HeaderBar
- Menu system

### Planned IDE Tools

#### Minimal Viable IDE (MVP) ✅ Completed

1. **Transcript** - Output console
2. **Workspace** - Code editor with Do It/Print It/Inspect It
3. **Inspector** - Object inspector with slot viewing
4. **Launcher** - Main IDE window with navigation
5. **Desktop integration** - Proper dock/Alt-Tab icons

#### System Browser ✅ Completed (2026-02-08)

- Four-pane class/method browser
- Class library selection (Core, Collections, GUI, IDE)
- Method listing and viewing

#### Enhanced Inspector ✅ Completed (2026-02-11)

- Slot inspection for object instances
- Property viewing
- Drilling down into nested objects

#### Full IDE (Future)

Remaining tools:
1. **Enhanced Debugger** - Stack frame display within IDE
2. **Source Editor** - Class/method editing with save capability

### Key Design Principle

All GUI tools are written in Harding code, making them malleable at runtime. Only a thin Nim wrapper (~20 core GTK widgets) is static.

---

## VSCode Extension

**Status**: ✅ Completed (2026-02-13)

Full IDE support for `.hrd` files via VSCode extension:

**Features:**
- **Syntax highlighting** - TextMate grammar with comprehensive scopes
- **Language Server Protocol (LSP)**:
  - Completions - Context-aware selector suggestions
  - Hover - Documentation and type information
  - Go to Definition - Navigate to method definitions
  - Document Symbols - Outline view
  - Workspace Symbols - Global search
- **Debug Adapter Protocol (DAP)**:
  - Breakpoints - Conditional and standard breakpoints
  - Stepping - Step over, into, out
  - Call Stack - Stack frame inspection
  - Variables - Locals, arguments, self inspection
  - Watch Expressions - Evaluate expressions
  - Debug Console - Interactive evaluation

**Building:**
```bash
nimble vsix  # Builds extension as .vsix package
```

**Architecture:**
- LSP implemented in Nim (`harding-lsp`)
- DAP adapter in TypeScript
- Harding Debug Protocol (HDP) via TCP for VM debugging

## BitBarrel Integration

**Status**: ✅ Implemented (2026-02-13)

BitBarrel provides first-class persistent key-value storage for Harding:

```smalltalk
# Connect to BitBarrel server
users := BarrelTable create: "users".
users at: 'alice' put: 'Alice Smith'.
name := users at: 'alice'.

# Range queries with BarrelSortedTable
logs := BarrelSortedTable create: "logs".
janLogs := logs rangeFrom: '2024-01-01' to: '2024-02-01'.
prefixLogs := logs prefix: '2024-01-'.
```

**Features:**
- WebSocket client for BitBarrel server communication
- Hash-based storage (`BarrelTable`) with O(1) lookups
- Ordered storage (`BarrelSortedTable`) with critbit indexing
- Range queries and prefix matching
- Collection protocol support (do:, select:, collect:)
- Conditional compilation via `-d:bitbarrel` flag

**Build:**
```bash
nimble harding_bitbarrel  # Build with BitBarrel support
```

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

- **`SortedCollection`** with configurable sort blocks ✅ (implemented)
- **`Bag`** for counting occurrences
- **`Interval`** to replace `to:do:` with collection iteration ✅ (implemented)
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

- ✅ Complete green threads (Monitor, SharedQueue, Semaphore)
- ✅ Fill high-priority Smalltalk gaps (Interval, SortedCollection)
- ✅ Complete GTK IDE tools (Workspace, Transcript, Launcher)
- ✅ Desktop integration with proper icons
- ✅ Granite compiler: standalone script compilation with inline control flow
- ✅ BitBarrel integration: persistent collections with range queries
- ✅ VSCode extension with LSP and DAP
- ✅ Phase 1 & 2 VM optimizations (MIC/PIC, Work Frame pooling, Quick Primitives)
- ✅ Smalltalk-style resumable exceptions (resume, resume:, retry, pass, return:)
- First-class block compilation with captures and non-local returns
- Start test framework implementation (all 28 tests passing)

### Medium Term (3-6 months)

- Full IDE (Source Editor, enhanced Debugger)
- Granite: class/method compilation from in-VM code
- Granite: unboxed arithmetic optimization
- Channels and goroutines
- Initial actor model

### Long Term (6-12 months)

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
