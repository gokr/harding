# Nimtalk GUI IDE Implementation Plan

## Executive Summary

Build a classic Smalltalk-style GUI IDE where **the GUI tools themselves are written in Nimtalk**, making them malleable at runtime. Use gintro (Salewski's GTK4 binding) as a thin wrapper layer to expose GTK objects to Nimtalk.

**Why this approach wins:**
- GUI tools are modifiable from within the system (true Smalltalk philosophy)
- Only the low-level GTK binding is static Nim code
- Future evolution: GTK wrapper can be reimplemented in Nimtalk via FFI

---

## Part 1: gintro vs Owlkettle Comparison

### Option A: gintro (Recommended for this project)

**What it is:** Direct, semi-automated GTK4 binding via gobject-introspection

**Code style (imperative):**
```nim
import gintro/[gtk4, gobject, gio]

proc activate(app: Application) =
  let window = newApplicationWindow(app)
  window.title = "Hello"
  window.defaultSize = (800, 600)

  let box = newBox(Orientation.vertical, 0)
  window.setChild(box)

  let button = newButton("Click me")
  button.connect("clicked", proc(btn: Button) =
    echo "Clicked!"
  )
  box.append(button)

  window.show
```

**Pros:**
- Direct GTK4 access - full API coverage, no limitations
- Go directly from Nim to GTK without abstraction layers
- Easier to expose to Nimtalk: just wrap gintro objects
- Signals use standard GTK connect mechanism
- No compile-time macro magic - straightforward Nim code
- Smaller runtime overhead

**Cons:**
- Imperative style (more verbose than declarative)
- Manual memory management for some patterns
- No automatic state management - you wire signals manually

---

### Option B: Owlkettle

**What it is:** Declarative UI framework that generates GTK4 widgets

**Code style (declarative):**
```nim
import owlkettle

viewable App:
  counter: int

method view(app: AppState): Widget =
  result = gui:
    Window:
      title = "Counter"
      defaultSize = (200, 60)
      Box(orient = OrientX, spacing = 6):
        Button:
          text = "-"
          proc clicked() =
            app.counter -= 1
        Label(text = $app.counter)
        Button:
          text = "+"
          proc clicked() =
            app.counter += 1

brew(gui(App()))
```

**Pros:**
- Beautiful, readable declarative syntax
- Automatic state management and re-rendering
- Less boilerplate for simple UIs
- Good for static, pre-defined interfaces

**Cons:**
- Compile-time DSL (macros) - cannot be generated at runtime from Nimtalk
- Harder to bridge to Nimtalk: the `gui:` macro and `viewable` types are compile-time constructs
- Limited by what Owlkettle supports (subset of GTK)
- Views are static Nim code - not malleable from Nimtalk

---

### Comparison Summary

| Aspect | gintro | Owlkettle |
|--------|--------|-----------|
| **Style** | Imperative | Declarative |
| **GTK Coverage** | Complete (~100k functions) | Subset (common widgets) |
| **Runtime Malleability** | Can wrap and expose | Compile-time macros |
| **Bridge to Nimtalk** | Straightforward | Complex/abstraction mismatch |
| **State Management** | Manual | Automatic |
| **Boilerplate** | More | Less |
| **IDE Tools in Nimtalk** | Yes | Tools must be in Nim |

**Verdict for Nimtalk IDE:** gintro is the clear choice because it enables the core requirement - **GUI tools written in malleable Nimtalk code**.

---

## Part 2: Revised Architecture

### Core Insight

Instead of:
```
Nimtalk Model -> Nim Bridge -> Owlkettle View (static Nim)
```

We do:
```
Nimtalk GUI Tool -> gintro Wrapper -> GTK4
     ^                              |
     +------  Nimtalk code  --------+
```

The GUI tools (Transcript, Workspace, Inspector, Browser, Debugger) are **all written in Nimtalk**. Only the thin gintro wrapper layer is static Nim code.

### Architecture Diagram

```
+-----------------------------------------------------------------+
|                      NIMTALK LAYER                               |
|                   (All Malleable Code)                           |
|  +--------------+  +--------------+  +--------------+           |
|  | Transcript   |  |  Workspace   |  |  Inspector   |           |
|  |   (GUI)      |  |    (GUI)     |  |    (GUI)     |           |
|  +------+-------+  +------+-------+  +------+-------+           |
|  +--------------+  +--------------+  +--------------+           |
|  |   Browser    |  |   Debugger   |  |  Launcher    |           |
|  |    (GUI)     |  |    (GUI)     |  |   (GUI)      |           |
|  +--------------+  +--------------+  +--------------+           |
|                                                                  |
|  All written in Nimtalk (.nt files)                              |
|  Can be edited live from within the IDE                          |
+--------------------------+---------------------------------------+
                           |
           +---------------+---------------+
           |      GTK4 BRIDGE (Nim)        |
           |   Thin wrapper around gintro   |
           |                                |
           |  - GtkWindow wrapper           |
           |  - GtkButton wrapper           |
           |  - GtkTextView wrapper         |
           |  - GtkTreeView wrapper         |
           |  - Signal connection helpers   |
           +---------------+---------------+
                           |
+--------------------------+---------------------------------------+
|                         GTK4                                     |
|                   (System Library)                               |
+------------------------------------------------------------------+
```

### Key Design Decision

**The Bridge Layer is THIN.**

Instead of implementing widget behavior in Nim, we only expose:
1. GTK widget constructors (create window, button, textview, etc.)
2. Property getters/setters (set text, get text, etc.)
3. Signal connection (when button clicked, call this Nimtalk block)
4. Container operations (add child, remove child)

All the **logic** (layout, event handling, state management) lives in Nimtalk.

---

## Part 3: Directory Structure

```
src/nimtalk/gui/
├── gtk4/                       # GTK4 bridge layer
│   ├── bridge.nim              # Main bridge initialization
│   ├── widget.nim              # Base Widget wrapper
│   ├── window.nim              # GtkWindow wrapper
│   ├── button.nim              # GtkButton wrapper
│   ├── textview.nim            # GtkTextView wrapper
│   ├── entry.nim               # GtkEntry wrapper
│   ├── box.nim                 # GtkBox layout wrapper
│   ├── scrolledwindow.nim      # GtkScrolledWindow wrapper
│   ├── treeview.nim            # GtkTreeView wrapper
│   ├── listbox.nim             # GtkListBox wrapper
│   ├── headerbar.nim           # GtkHeaderBar wrapper
│   ├── signal.nim              # Signal handling utilities
│   └── application.nim         # GtkApplication wrapper
│
└── ide.nim                     # IDE entry point - loads Nimtalk GUI code

lib/nimtalk/gui/                # GUI tools written in Nimtalk
├── Gtk4/                       # GTK4 wrapper classes (Nimtalk)
│   ├── Widget.nt               # Base widget class
│   ├── Window.nt               # Window wrapper
│   ├── Button.nt               # Button wrapper
│   ├── TextView.nt             # TextView wrapper
│   ├── Box.nt                  # Box layout
│   ├── ScrolledWindow.nt       # Scrolled container
│   ├── TreeView.nt             # Tree view wrapper
│   ├── ListBox.nt              # List box wrapper
│   ├── HeaderBar.nt            # Header bar wrapper
│   └── Application.nt          # Application wrapper
│
├── Ide/                        # IDE tool implementations
│   ├── BaseTool.nt             # Base class for all tools
│   ├── Launcher.nt             # Main launcher window
│   ├── Transcript.nt           # Transcript tool
│   ├── Workspace.nt            # Workspace tool
│   ├── Inspector.nt            # Inspector tool
│   ├── Browser.nt              # System browser
│   └── Debugger.nt             # Debugger tool
│
└── main.nt                     # IDE startup script
```

---

## Part 4: The GTK4 Bridge Layer (Nim)

This is the only static Nim code. It's a thin wrapper that:
1. Creates gintro GTK objects
2. Exposes them to Nimtalk as proxy objects
3. Forwards signals from GTK to Nimtalk

### 4.1 Widget Wrapper Base

**File:** `src/nimtalk/gui/gtk4/widget.nim`

```nim
## Base widget wrapper - exposes GTK widget to Nimtalk

import gintro/[gtk4, gobject]
import ../../core/types
import ../../interpreter/objects

type
  GtkWidgetProxy* = ref object
    ## Wraps a GTK widget for Nimtalk access
    widget*: gtk4.Widget
    interp*: ptr Interpreter  # For calling back to Nimtalk
    signalHandlers*: Table[string, seq[BlockNode]]  # signal -> blocks
    destroyed*: bool  # Track if GTK widget was destroyed

# Type-safe proxy extraction with validation
proc asWidgetProxy*(obj: ProtoObject): GtkWidgetProxy =
  ## Safely extract GtkWidgetProxy with type checking
  if not obj.isNimProxy:
    raise newException(TypeError, "Expected GTK widget proxy")
  if obj.nimType notin ["GtkWidget", "GtkWindow", "GtkButton", "GtkBox",
                         "GtkTextView", "GtkEntry", "GtkLabel", "GtkTreeView",
                         "GtkScrolledWindow", "GtkHeaderBar", "GtkPaned"]:
    raise newException(TypeError, "Expected GTK widget, got: " & obj.nimType)
  result = cast[GtkWidgetProxy](obj.nimValue)
  if result.destroyed:
    raise newException(ValueError, "GTK widget has been destroyed")

proc createWidgetProxy*(widget: gtk4.Widget, interp: ptr Interpreter): NodeValue =
  ## Create a Nimtalk object that wraps a GTK widget
  let proxy = GtkWidgetProxy(widget: widget, interp: interp, destroyed: false)

  # Create Nimtalk object
  let obj = ProtoObject()
  obj.isNimProxy = true
  obj.nimType = "GtkWidget"
  obj.nimValue = cast[pointer](proxy)

  # Add methods
  addMethod(obj, "show", createNativeMethod(showMethodImpl))
  addMethod(obj, "hide", createNativeMethod(hideMethodImpl))
  addMethod(obj, "setSizeRequest:", createNativeMethod(setSizeRequestImpl))
  addMethod(obj, "connect:do:", createNativeMethod(connectDoImpl))
  addMethod(obj, "destroy", createNativeMethod(destroyMethodImpl))

  # Track destruction - when GTK widget is destroyed, mark proxy
  widget.connect("destroy", proc(w: gtk4.Widget) =
    proxy.destroyed = true
    proxy.signalHandlers.clear()
  )

  return NodeValue(kind: vkObject, objVal: obj)

proc showMethodImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = self.asWidgetProxy()
  proxy.widget.show
  return nilValue()

proc destroyMethodImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Explicitly destroy the GTK widget
  let proxy = self.asWidgetProxy()
  proxy.widget.destroy()
  proxy.destroyed = true
  return nilValue()

# Safe block evaluation wrapper - catches exceptions to prevent GTK crashes
proc safeEvalBlock(interp: ptr Interpreter, blockNode: BlockNode,
                   args: seq[NodeValue] = @[]): NodeValue =
  ## Evaluate a Nimtalk block safely within a GTK signal handler.
  ## Exceptions are caught and reported to the Transcript instead of crashing.
  try:
    result = interp[].evalBlock(blockNode, args)
  except EvalError as e:
    # Report error to Transcript (don't crash GTK)
    stderr.writeLine("Error in signal handler: ", e.msg)
    # Also try to show in Transcript if available
    try:
      discard interp[].doit("Transcript showLine: 'Signal handler error: " & e.msg & "'")
    except:
      discard
    result = nilValue()
  except Exception as e:
    stderr.writeLine("Unexpected error in signal handler: ", e.msg)
    result = nilValue()

proc connectDoImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Connect a GTK signal to a Nimtalk block
  ## args[0] = signal name (string)
  ## args[1] = block to execute
  let proxy = self.asWidgetProxy()
  let signalName = args[0].toString()
  let blockNode = args[1].toBlock()

  # Store the block
  if not proxy.signalHandlers.hasKey(signalName):
    proxy.signalHandlers[signalName] = @[]
  proxy.signalHandlers[signalName].add(blockNode)

  # Connect GTK signal with safe evaluation
  proxy.widget.connect(signalName, proc(widget: gtk4.Widget) =
    # Call all Nimtalk blocks for this signal
    for handler in proxy.signalHandlers[signalName]:
      discard safeEvalBlock(proxy.interp, handler)
  )

  return nilValue()
```

### 4.2 Window Wrapper

**File:** `src/nimtalk/gui/gtk4/window.nim`

```nim
## GtkWindow wrapper

import gintro/[gtk4, gobject]
import ../../core/types
import ../../interpreter/objects
import ./widget

proc createWindowWrapper*(interp: ptr Interpreter, app: Application): NodeValue =
  ## Create a Nimtalk Window object
  let window = newApplicationWindow(app)
  let proxy = GtkWidgetProxy(widget: window, interp: interp)

  let obj = ProtoObject()
  obj.isNimProxy = true
  obj.nimType = "GtkWindow"
  obj.nimValue = cast[pointer](proxy)

  # Parent methods from Widget
  addMethod(obj, "show", createNativeMethod(showMethodImpl))
  addMethod(obj, "setTitle:", createNativeMethod(setTitleImpl))
  addMethod(obj, "setChild:", createNativeMethod(setChildImpl))
  addMethod(obj, "present", createNativeMethod(presentImpl))

  return NodeValue(kind: vkObject, objVal: obj)

proc setChildImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = cast[GtkWidgetProxy](self.nimValue)
  let childProxy = cast[GtkWidgetProxy](args[0].objVal.nimValue)
  let window = cast[ApplicationWindow](proxy.widget)
  window.setChild(childProxy.widget)
  return nilValue()

proc setTitleImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = cast[GtkWidgetProxy](self.nimValue)
  let window = cast[ApplicationWindow](proxy.widget)
  window.title = args[0].toString()
  return nilValue()

proc presentImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = cast[GtkWidgetProxy](self.nimValue)
  let window = cast[ApplicationWindow](proxy.widget)
  window.present()
  return nilValue()
```

### 4.3 Button Wrapper

**File:** `src/nimtalk/gui/gtk4/button.nim`

```nim
## GtkButton wrapper

import gintro/[gtk4, gobject]
import ../../core/types
import ../../interpreter/objects
import ./widget

type
  ButtonProxy* = ref object of GtkWidgetProxy

proc newButtonWrapper*(interp: ptr Interpreter, label: string): NodeValue =
  ## Create a Nimtalk Button object
  let button = newButton(label)
  let proxy = ButtonProxy(widget: button, interp: interp)

  let obj = ProtoObject()
  obj.isNimProxy = true
  obj.nimType = "GtkButton"
  obj.nimValue = cast[pointer](proxy)

  addMethod(obj, "setLabel:", createNativeMethod(setLabelImpl))
  addMethod(obj, "getLabel", createNativeMethod(getLabelImpl))
  addMethod(obj, "connectClicked:", createNativeMethod(connectClickedImpl))

  return NodeValue(kind: vkObject, objVal: obj)

proc setLabelImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = cast[ButtonProxy](self.nimValue)
  let button = cast[gtk4.Button](proxy.widget)
  button.setLabel(args[0].toString())
  return nilValue()

proc getLabelImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  let proxy = cast[ButtonProxy](self.nimValue)
  let button = cast[gtk4.Button](proxy.widget)
  return wrapString(button.getLabel())

proc connectClickedImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Connect "clicked" signal to a Nimtalk block
  let proxy = cast[ButtonProxy](self.nimValue)
  let button = cast[gtk4.Button](proxy.widget)
  let blockNode = args[0].toBlock()

  # Connect GTK signal -> Nimtalk callback
  button.connect("clicked", proc(btn: Button) =
    discard proxy.interp[].evalBlock(blockNode)
  )

  return nilValue()
```

### 4.4 Typed Signal Handlers

GTK signals have varying signatures. The generic `connect:do:` works for simple signals, but signals like `motion-notify` pass coordinates. Provide typed helpers for common patterns:

**File:** `src/nimtalk/gui/gtk4/signal.nim`

```nim
## Typed signal connection helpers

# Simple signal (no args) - clicked, activate, destroy
proc connectSimple*(proxy: GtkWidgetProxy, signalName: string, blockNode: BlockNode) =
  proxy.widget.connect(signalName, proc(w: gtk4.Widget) =
    discard safeEvalBlock(proxy.interp, blockNode)
  )

# Motion signal - passes x, y coordinates
proc connectMotion*(proxy: GtkWidgetProxy, blockNode: BlockNode) =
  let controller = newEventControllerMotion()
  proxy.widget.addController(controller)
  controller.connect("motion", proc(ctrl: EventControllerMotion, x, y: float) =
    let args = @[wrapFloat(x), wrapFloat(y)]
    discard safeEvalBlock(proxy.interp, blockNode, args)
  )

# Key press signal - passes keyval, keycode, modifiers
proc connectKeyPressed*(proxy: GtkWidgetProxy, blockNode: BlockNode) =
  let controller = newEventControllerKey()
  proxy.widget.addController(controller)
  controller.connect("key-pressed", proc(ctrl: EventControllerKey,
                                          keyval, keycode: uint, state: ModifierType): bool =
    let args = @[wrapInt(keyval.int), wrapInt(keycode.int), wrapInt(state.int)]
    let result = safeEvalBlock(proxy.interp, blockNode, args)
    return result.kind == vkBool and result.boolVal  # Return true to stop propagation
  )

# TreeView row activated - passes path
proc connectRowActivated*(proxy: GtkWidgetProxy, blockNode: BlockNode) =
  let treeView = cast[TreeView](proxy.widget)
  treeView.connect("row-activated", proc(tv: TreeView, path: TreePath, col: TreeViewColumn) =
    let pathStr = path.toString()
    let args = @[wrapString(pathStr)]
    discard safeEvalBlock(proxy.interp, blockNode, args)
  )
```

**Nimtalk usage:**
```smalltalk
button connectClicked: [ self doSomething ].
canvas connectMotion: [ :x :y | self drawAt: x @ y ].
treeView connectRowActivated: [ :path | self selectPath: path ].
entry connectKeyPressed: [ :keyval :keycode :mods |
    (keyval = 65293) "Enter key"
        ifTrue: [ self submit ]
        ifFalse: [ false ]  "Don't consume other keys"
].
```

---

## Part 5: Critical Design Considerations

### 5.1 Widget Lifecycle and Memory Management

GTK widgets are reference-counted via GObject. When a Nimtalk `GtkWidget` object is garbage collected, the underlying GTK widget must be properly released.

**Strategy:** Track widget ownership and destruction state:

```nim
type
  GtkWidgetProxy* = ref object
    widget*: gtk4.Widget
    destroyed*: bool
    # ... other fields

# When GTK widget is destroyed (window closed, etc.), mark proxy
widget.connect("destroy", proc(w: gtk4.Widget) =
  proxy.destroyed = true
  proxy.signalHandlers.clear()  # Release Nimtalk blocks
)

# When Nimtalk object is GC'd, the proxy ref drops
# GTK's refcount handles the rest - we DON'T explicitly destroy
# because user might still have GTK references
```

**Rules:**
1. GTK owns widget lifetime (via refcount)
2. Nimtalk proxy tracks destroyed state
3. Methods check `destroyed` flag before operating
4. Explicit `widget destroy` available for manual cleanup
5. Closing a window destroys child widgets automatically

### 5.2 Event Loop Integration

The GTK main loop and Nimtalk evaluation must cooperate. When a signal handler runs Nimtalk code, the UI is blocked until evaluation completes.

**Approach:** Run Nimtalk in the GTK main thread (simple, predictable):

```
GTK Main Loop
    ↓
Signal Emitted (e.g., button clicked)
    ↓
Signal Handler Called
    ↓
Nimtalk Block Evaluated (UI blocked)
    ↓
Handler Returns
    ↓
GTK Processes Next Event
```

**Implications:**
- Short operations: Fine, no user-visible delay
- Long operations: UI freezes

**Mitigation for long operations:**

Option A: Chunked evaluation with `idle_add`:
```nim
proc longOperationChunked(interp: ptr Interpreter, chunks: seq[Node]) =
  var idx = 0
  proc processChunk(): bool =
    if idx < chunks.len:
      discard interp[].eval(chunks[idx])
      inc idx
      return SOURCE_CONTINUE  # Keep calling
    return SOURCE_REMOVE  # Done
  discard g_idle_add(processChunk)
```

Option B: Background thread with channel (future enhancement):
```nim
# Worker thread evaluates Nimtalk
# Results sent via channel
# Main thread picks up via idle callback
```

**Recommendation:** Start with simple main-thread execution. Add chunking for known long operations (file loading, search). Background threads are a future optimization.

### 5.3 Error Handling in Signal Callbacks

GTK signal handlers cannot propagate exceptions. If a Nimtalk block raises an error, we must catch it and report gracefully.

**Implementation:** (shown in 4.1 `safeEvalBlock`)

- Wrap all block evaluations in try/except
- Log errors to stderr
- Attempt to show in Transcript
- Never crash the GTK event loop

**Nimtalk-level error handling:**

```smalltalk
button clicked: [
    [ self riskyOperation ]
        on: Error
        do: [ :e | Transcript showLine: 'Error: ', e message ]
].
```

---

## Part 6: The Nimtalk GUI Layer

This is where the actual IDE tools live. All written in Nimtalk - fully malleable!

### 6.1 GTK4 Base Classes (Nimtalk)

**File:** `lib/nimtalk/gui/Gtk4/Widget.nt`

```smalltalk
"Base class for all GTK widgets
 This is a Nimtalk wrapper around the Nim GTK proxy"

GtkWidget := Object derive: #(
    proxy           "The underlying Nim GTK proxy object"
).

GtkWidget at: #proxy: put: [ :aProxy |
    proxy := aProxy.
    ^self
].

GtkWidget at: #proxy put: [ ^proxy ].

GtkWidget at: #show put: [
    proxy show.
    ^self
].

GtkWidget at: #hide put: [
    proxy hide.
    ^self
].

GtkWidget at: #setSizeRequest: put: [ :size |
    "size is a Point (x@y)"
    proxy setSizeRequest: size.
    ^self
].

GtkWidget at: #connect:do: put: [ :signalName :aBlock |
    "Connect a signal to a block"
    proxy connect: signalName do: aBlock.
    ^self
].

"Style and CSS"
GtkWidget at: #addCssClass: put: [ :className |
    proxy addCssClass: className.
    ^self
].
```

### 6.2 Window Class (Nimtalk)

**File:** `lib/nimtalk/gui/Gtk4/Window.nt`

```smalltalk
"GTK Window - top-level window"

GtkWindow := GtkWidget derive: #(
    title           "Window title string"
    child           "Child widget"
    defaultWidth    "Default width"
    defaultHeight   "Default height"
).

"Class method - create new window"
GtkWindow at: #new put: [
    | instance proxy |
    instance := self basicNew.
    proxy := GtkBridge createWindow.
    instance proxy: proxy.
    ^instance initialize
].

GtkWindow at: #initialize put: [
    title := 'Untitled Window'.
    defaultWidth := 800.
    defaultHeight := 600.
    ^self
].

GtkWindow at: #title put: [ ^title ].

GtkWindow at: #title: put: [ :aTitle |
    title := aTitle.
    proxy setTitle: aTitle.
    ^self
].

GtkWindow at: #setChild: put: [ :aWidget |
    child := aWidget.
    proxy setChild: aWidget proxy.
    ^self
].

GtkWindow at: #present put: [
    proxy present.
    ^self
].

GtkWindow at: #defaultSize: put: [ :aPoint |
    defaultWidth := aPoint x.
    defaultHeight := aPoint y.
    proxy setDefaultSize: aPoint.
    ^self
].
```

### 6.3 Button Class (Nimtalk)

**File:** `lib/nimtalk/gui/Gtk4/Button.nt`

```smalltalk
"GTK Button widget"

GtkButton := GtkWidget derive: #(
    label           "Button label"
    clickedBlocks   "OrderedCollection of blocks to run on click"
).

"Class method"
GtkButton at: #new put: [
    ^self newLabel: ''
].

GtkButton at: #newLabel: put: [ :aLabel |
    | instance proxy |
    instance := self basicNew.
    proxy := GtkBridge createButton: aLabel.
    instance proxy: proxy.
    ^instance initialize
].

GtkButton at: #initialize put: [
    clickedBlocks := OrderedCollection new.
    ^self
].

GtkButton at: #label put: [
    ^proxy getLabel
].

GtkButton at: #label: put: [ :aLabel |
    label := aLabel.
    proxy setLabel: aLabel.
    ^self
].

"Signal handling"
GtkButton at: #clicked: put: [ :aBlock |
    "Add a block to run when clicked"
    clickedBlocks add: aBlock.
    proxy connectClicked: [
        clickedBlocks do: [ :each | each value ]
    ].
    ^self
].
```

### 6.4 Box Layout (Nimtalk)

**File:** `lib/nimtalk/gui/Gtk4/Box.nt`

```smalltalk
"GTK Box - layout container"

GtkBox := GtkWidget derive: #(
    orientation     "#horizontal or #vertical"
    spacing         "Int - spacing between children"
    children        "OrderedCollection of child widgets"
).

GtkBox at: #new put: [
    ^self newOrientation: #vertical spacing: 0
].

GtkBox at: #newOrientation:spacing: put: [ :orient :space |
    | instance proxy orientValue |
    instance := self basicNew.
    orientValue := (orient = #horizontal) ifTrue: [0] ifFalse: [1].
    proxy := GtkBridge createBoxOrientation: orientValue spacing: space.
    instance proxy: proxy.
    ^instance initialize
].

GtkBox at: #initialize put: [
    children := OrderedCollection new.
    ^self
].

GtkBox at: #append: put: [ :aWidget |
    children add: aWidget.
    proxy append: aWidget proxy.
    ^self
].

GtkBox at: #prepend: put: [ :aWidget |
    children addFirst: aWidget.
    proxy prepend: aWidget proxy.
    ^self
].

GtkBox at: #remove: put: [ :aWidget |
    children remove: aWidget.
    proxy remove: aWidget proxy.
    ^self
].
```

---

## Part 7: IDE Tool Implementations (All in Nimtalk!)

### 7.1 Launcher Window

**File:** `lib/nimtalk/gui/Ide/Launcher.nt`

```smalltalk
"Main IDE launcher window with Transcript"

IdeLauncher := GtkWindow derive: #(
    transcript      "TextView for output"
    menuBar         "HeaderBar with menus"
    transcriptModel "Transcript model for buffer"
).

IdeLauncher at: #initialize put: [
    super initialize.
    self title: 'Nimtalk IDE'.
    self defaultSize: 800 @ 600.
    self buildUI.
    ^self
].

IdeLauncher at: #buildUI put: [
    | mainBox menuBar scrolledWindow |

    "Create main vertical layout"
    mainBox := GtkBox newOrientation: #vertical spacing: 0.

    "Add header bar with menus"
    menuBar := self buildMenuBar.
    mainBox append: menuBar.

    "Add transcript (scrolled text view)"
    scrolledWindow := GtkScrolledWindow new.
    transcript := GtkTextView new.
    transcript editable: false.
    transcript monospace: true.
    scrolledWindow setChild: transcript.
    mainBox append: scrolledWindow.

    "Set as window content"
    self setChild: mainBox.
    ^self
].

IdeLauncher at: #buildMenuBar put: [
    | headerBar |
    headerBar := GtkHeaderBar new.

    "File menu"
    headerBar packStart: (GtkButton newLabel: 'New Workspace'
        clicked: [ self openWorkspace ]).

    headerBar packStart: (GtkButton newLabel: 'Browser'
        clicked: [ self openBrowser ]).

    "Clear button"
    headerBar packEnd: (GtkButton newLabel: 'Clear'
        clicked: [ self clearTranscript ]).

    ^headerBar
].

IdeLauncher at: #openWorkspace put: [
    | workspace |
    workspace := IdeWorkspace new.
    workspace present.
    ^self
].

IdeLauncher at: #openBrowser put: [
    | browser |
    browser := IdeBrowser new.
    browser present.
    ^self
].

IdeLauncher at: #clearTranscript put: [
    transcriptModel clear.
    transcript buffer text: ''.
    ^self
].

IdeLauncher at: #show: put: [ :text |
    "Show text in transcript"
    transcriptModel show: text.
    transcript buffer text: transcriptModel contents.
    transcript scrollToEnd.
    ^self
].

IdeLauncher at: #showLine: put: [ :text |
    "Show line in transcript"
    transcriptModel showLine: text.
    transcript buffer text: transcriptModel contents.
    transcript scrollToEnd.
    ^self
].
```

### 7.2 Workspace Window

**File:** `lib/nimtalk/gui/Ide/Workspace.nt`

```smalltalk
"Workspace - code editor with Do It / Print It / Inspect It"

IdeWorkspace := GtkWindow derive: #(
    textView        "TextView for code editing"
    resultLabel     "Label for showing results"
    selectionStart  "Selection start"
    selectionEnd    "Selection end"
).

IdeWorkspace at: #initialize put: [
    super initialize.
    self title: 'Workspace'.
    self defaultSize: 700 @ 500.
    self buildUI.
    ^self
].

IdeWorkspace at: #buildUI put: [
    | mainBox headerBar scrolledWindow |

    mainBox := GtkBox newOrientation: #vertical spacing: 0.

    "Header bar with Do It / Print It / Inspect It"
    headerBar := GtkHeaderBar new.
    headerBar title: 'Workspace'.

    headerBar packStart: (GtkButton newLabel: 'Do It'
        clicked: [ self doIt ]).

    headerBar packStart: (GtkButton newLabel: 'Print It'
        clicked: [ self printIt ]).

    headerBar packStart: (GtkButton newLabel: 'Inspect It'
        clicked: [ self inspectIt ]).

    headerBar packEnd: (GtkButton newLabel: 'Clear'
        clicked: [ self clear ]).

    mainBox append: headerBar.

    "Text editor"
    scrolledWindow := GtkScrolledWindow new.
    textView := GtkTextView new.
    textView monospace: true.
    scrolledWindow setChild: textView.
    mainBox append: scrolledWindow.

    "Result label (hidden by default)"
    resultLabel := GtkLabel new.
    resultLabel visible: false.
    mainBox append: resultLabel.

    self setChild: mainBox.
    ^self
].

IdeWorkspace at: #selectedText put: [
    "Get selected text or all text"
    selectionStart = selectionEnd
        ifTrue: [ ^textView buffer text ]
        ifFalse: [
            ^textView buffer text copyFrom: selectionStart to: selectionEnd
        ]
].

IdeWorkspace at: #doIt put: [
    "Evaluate selected code"
    | code |
    code := self selectedText.

    "Call interpreter"
    IdeBridge evaluate: code mode: #doIt.

    resultLabel visible: false.
    ^self
].

IdeWorkspace at: #printIt put: [
    "Evaluate and show result"
    | code result |
    code := self selectedText.
    result := IdeBridge evaluate: code mode: #printIt.

    resultLabel text: result displayString.
    resultLabel visible: true.
    ^self
].

IdeWorkspace at: #inspectIt put: [
    "Evaluate and inspect result"
    | code result inspector |
    code := self selectedText.
    result := IdeBridge evaluate: code mode: #inspectIt.

    inspector := IdeInspector on: result.
    inspector present.
    ^self
].

IdeWorkspace at: #clear put: [
    textView buffer text: ''.
    resultLabel visible: false.
    ^self
].
```

### 7.3 Inspector Window

**File:** `lib/nimtalk/gui/Ide/Inspector.nt`

```smalltalk
"Inspector - view object internals"

IdeInspector := GtkWindow derive: #(
    treeView        "TreeView showing slots"
    inspectedObject "The object being inspected"
    slotValues      "Dictionary of slot name -> value"
).

IdeInspector at: #on: put: [ :anObject |
    ^self new object: anObject; yourself
].

IdeInspector at: #object: put: [ :anObject |
    inspectedObject := anObject.
    ^self refresh
].

IdeInspector at: #initialize put: [
    super initialize.
    self title: 'Inspector'.
    self defaultSize: 500 @ 600.
    self buildUI.
    ^self
].

IdeInspector at: #buildUI put: [
    | paned leftBox rightBox |

    paned := GtkPaned newOrientation: #horizontal.

    "Left: Tree of slots"
    leftBox := self buildSlotTree.
    paned setStartChild: leftBox.

    "Right: Detail view"
    rightBox := self buildDetailView.
    paned setEndChild: rightBox.

    self setChild: paned.
    ^self
].

IdeInspector at: #buildSlotTree put: [
    | scrolled treeView |
    scrolled := GtkScrolledWindow new.
    treeView := GtkTreeView new.

    "Add columns"
    treeView addColumn: (GtkTreeViewColumn title: 'Slot'
        renderer: [ :slotName | slotName ]).

    treeView addColumn: (GtkTreeViewColumn title: 'Value'
        renderer: [ :slotName | (slotValues at: slotName) displayString ]).

    "Double-click to inspect slot"
    treeView rowActivated: [ :path |
        | slotName value |
        slotName := treeView itemAt: path.
        value := slotValues at: slotName.
        (IdeInspector on: value) present
    ].

    scrolled setChild: treeView.
    ^scrolled
].

IdeInspector at: #refresh put: [
    "Get all slots from object"
    slotValues := Dictionary new.
    inspectedObject slotNames do: [ :name |
        slotValues at: name put: (inspectedObject slotAt: name)
    ].
    treeView items: slotValues keys asOrderedCollection.
    ^self
].
```

---

## Part 8: IDE Entry Point

**File:** `src/nimtalk/gui/ide.nim`

```nim
## IDE Entry Point
## Loads Nimtalk GUI code and starts the application

import gintro/[gtk4, gobject, gio]
import ../core/types
import ../interpreter/evaluator
import ../interpreter/objects
import gtk4/[bridge, widget, window, button, textview, box]

proc initGtkBridge(interp: var Interpreter) =
  ## Register GTK wrapper functions with interpreter

  # Create GtkBridge object in Nimtalk globals
  let bridgeObj = ProtoObject()
  addMethod(bridgeObj, "createWindow", createWindowNative)
  addMethod(bridgeObj, "createButton:", createButtonNative)
  addMethod(bridgeObj, "createBoxOrientation:spacing:", createBoxNative)
  addMethod(bridgeObj, "createTextView", createTextViewNative)
  addMethod(bridgeObj, "evaluate:mode:", evaluateNative)

  interp.globals["GtkBridge"] = NodeValue(kind: vkObject, objVal: bridgeObj)
  interp.globals["IdeBridge"] = NodeValue(kind: vkObject, objVal: createIdeBridge())

proc loadGuiCode(interp: var Interpreter) =
  ## Load all Nimtalk GUI files
  let guiFiles = [
    "lib/nimtalk/gui/Gtk4/Widget.nt",
    "lib/nimtalk/gui/Gtk4/Window.nt",
    "lib/nimtalk/gui/Gtk4/Button.nt",
    "lib/nimtalk/gui/Gtk4/Box.nt",
    "lib/nimtalk/gui/Gtk4/TextView.nt",
    "lib/nimtalk/gui/Gtk4/TreeView.nt",
    "lib/nimtalk/gui/Ide/BaseTool.nt",
    "lib/nimtalk/gui/Ide/Launcher.nt",
    "lib/nimtalk/gui/Ide/Workspace.nt",
    "lib/nimtalk/gui/Ide/Inspector.nt",
    "lib/nimtalk/gui/Ide/Browser.nt",
    "lib/nimtalk/gui/Ide/Debugger.nt",
    "lib/nimtalk/gui/main.nt"  # Entry point
  ]

  for file in guiFiles:
    let (_, err) = interp.doit(readFile(file))
    if err.len > 0:
      stderr.writeLine("Error loading ", file, ": ", err)
      quit(1)

proc main =
  # Create interpreter
  var interp = newInterpreter()
  initGlobals(interp)
  initSymbolTable()

  # Initialize GTK bridge
  initGtkBridge(interp)

  # Load Nimtalk GUI code
  loadGuiCode(interp)

  # Launch the IDE by calling Nimtalk entry point
  discard interp.doit("IdeLauncher new present")

  # Run GTK main loop
  gtk4.main()

when isMainModule:
  main()
```

---

## Part 9: Implementation Phases

The implementation is divided into two milestones: a Minimal Viable IDE (MVP) and the Full IDE.

### Milestone 1: Minimal Viable IDE (MVP)

Ship a usable Transcript + Workspace first, then iterate.

**Phase 1: GTK Bridge Foundation (2 weeks)**
- Basic widget wrapper architecture with type safety
- Window, Button, Box wrappers
- Signal connection mechanism with error handling
- Widget lifecycle management (destroy tracking)

**Phase 2: Core GTK Wrappers (2 weeks)**
- TextView wrapper (with buffer and selection)
- ScrolledWindow wrapper
- HeaderBar wrapper
- Entry (text input) wrapper
- Label wrapper

**Phase 3: Nimtalk GTK Classes (1-2 weeks)**
- Write Widget.nt, Window.nt, Button.nt, Box.nt
- Write TextView.nt, ScrolledWindow.nt
- Write signal handling in Nimtalk

**Phase 4: Transcript + Workspace (2-3 weeks)**
- Launcher window with Transcript
- Workspace with Do It / Print It / Inspect It
- Output redirection from interpreter
- Basic error display

**MVP Total: 7-9 weeks**

**MVP Deliverable:** A working IDE where you can write Nimtalk code in a Workspace, evaluate it, and see output in the Transcript.

---

### Milestone 2: Full IDE

After MVP is stable and usable, continue with:

**Phase 5: Inspector Tool (2-3 weeks)**
- Tree view of object slots
- Drill-down (double-click to inspect slot)
- Value display formatting
- Refresh/update mechanism

**Phase 6: Browser Tool (4-6 weeks)**
- Multi-pane layout (category/class/protocol/method)
- Load method source from files
- Edit and save methods
- Compile/install methods
- This is the most complex tool - allow adequate time

**Phase 7: Debugger (4-6 weeks - optional)**
- Add hooks to evaluator for breakpoints
- Stack frame display
- Step over/into/out/continue
- Variable inspection at each frame
- This requires evaluator modifications

**Full IDE Total: 10-15 additional weeks**

---

## Part 10: Benefits of This Architecture

### 1. True Malleability
All IDE tools are Nimtalk code. Modify the browser layout live. Change colors, add buttons, rearrange panes - all from within the running IDE.

### 2. Evolution Path
```
Phase 1 (Now):      Nim GTK wrapper -> Nimtalk GUI tools
Phase 2 (Future):   FFI to GTK -> Pure Nimtalk GTK binding
```

Eventually, even the wrapper can be replaced with FFI calls from Nimtalk.

### 3. Teaching Tool
Students can read and modify the IDE itself to learn Nimtalk.

### 4. Community Contributions
Users can share custom IDE tools as Nimtalk packages.

### 5. Multiple UIs
The same bridge supports:
- GTK-based IDE (default)
- TUI version (terminal UI)
- Web-based IDE (via WebAssembly bridge)

---

## Part 11: Glade/XML UI Definition Support (Optional Enhancement)

**Note:** This is an optional feature for UI prototyping. The primary workflow is code-based construction in Nimtalk, which provides full malleability. Glade can be used to quickly prototype layouts, then import them into Nimtalk for further refinement and dynamic behavior.

For visual UI design, add support for Glade XML files:

**File:** `lib/nimtalk/gui/Gtk4/Builder.nt`

```smalltalk
"GtkBuilder - load UIs from Glade XML"

GtkBuilder := Object derive: #(
    proxy
).

GtkBuilder at: #new put: [
    | instance |
    instance := self basicNew.
    instance proxy: (GtkBridge createBuilder).
    ^instance
].

GtkBuilder at: #addFromFile: put: [ :filepath |
    proxy addFromFile: filepath.
    ^self
].

GtkBuilder at: #getObject: put: [ :name |
    | widgetProxy |
    widgetProxy := proxy getObject: name.
    ^GtkWidget new proxy: widgetProxy
].

GtkBuilder at: #connectSignals: put: [ :signalDict |
    "signalDict maps signal names to blocks"
    signalDict keysAndValuesDo: [ :name :block |
        proxy connectSignal: name to: block
    ].
    ^self
].
```

**Usage example:**
```smalltalk
"Load a Glade-designed UI"
builder := GtkBuilder new.
builder addFromFile: 'lib/nimtalk/gui/glade/Workspace.glade'.

"Get widgets by ID"
window := builder getObject: 'workspaceWindow'.
textView := builder getObject: 'codeTextView'.
doItButton := builder getObject: 'doItButton'.

"Connect signals"
doItButton clicked: [ self doIt ].
```

**Benefits:**
- Design UIs visually in Glade
- Load and hook up in Nimtalk
- Completely malleable

---

## Part 12: Risk Mitigation

| Risk | Mitigation |
|------|------------|
| gintro complexity | Only use ~20 core GTK widgets |
| Signal handler errors | Safe evaluation wrapper, report to Transcript |
| UI freezes on long ops | Chunked evaluation via idle callbacks |
| Widget lifecycle bugs | Track destroyed state, validate before operations |
| Type-unsafe proxy casts | Type-checking `asWidgetProxy` helper |
| Performance | Lazy widget creation, virtual scrolling |
| GTK learning curve | Mirror GTK API closely in Nimtalk |
| Debugging bridge issues | Extensive logging in bridge layer |

---

## Summary

This revised plan uses **gintro** instead of Owlkettle because:

1. **gintro enables malleability** - GTK objects can be exposed to Nimtalk
2. **Owlkettle prevents malleability** - its declarative macros are compile-time only
3. **gintro is more direct** - simpler bridge, less abstraction

The GUI tools (Transcript, Workspace, Inspector, Browser, Debugger) are all written in **Nimtalk itself**, making them fully malleable at runtime. Only a thin bridge layer (~20 core GTK widgets) is static Nim code.

**Timeline:**
- **MVP (Transcript + Workspace): 7-9 weeks**
- **Full IDE (+ Inspector, Browser, Debugger): 17-24 weeks total**

**Critical Success Metric:** A user can open a Workspace, modify the `IdeLauncher` class, and see the changes immediately in the running IDE.

**Why NOT Owlkettle?**
Owlkettle uses its own custom GTK bindings (not gintro). Its value is in compile-time macros (`gui:`, `viewable`) that generate code at compile time. Since we want GUI construction to happen in Nimtalk at runtime, Owlkettle's declarative layer cannot be used. We'd only access its low-level bindings, offering no advantage over gintro.

**Why gintro?**
gintro exposes GTK directly. We can wrap its objects in Nim proxies and pass them to Nimtalk. This enables true malleability - Nimtalk code creates and manages GTK widgets at runtime.
