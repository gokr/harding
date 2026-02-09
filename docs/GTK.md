# GTK Bridge and GUI Development

## Overview

The GTK bridge provides a way to create and manipulate GTK widgets from Harding code. It enables building GUI applications and development tools (like an IDE) directly in Harding.

### Key Design Principles

1. **Malleability** - GUI tools are written in Harding and can be modified at runtime
2. **Thin Bridge** - Only a thin Nim wrapper exposes GTK to Harding
3. **Signal Integration** - GTK signals connect to Harding blocks
4. **Safety** - Error handling prevents GTK crashes from Harding exceptions

### Architecture

```
+--------------------------------------------------------+
|                   Harding Layer                            |
|           (All written in .harding files)                  |
|  +------------+  +------------+  +-------------------+ |
|  |  Widgets   |  |   IDE      |  |   Application     | |
|  | (GTK4/...) |  |  Tools     |  |     Logic         | |
|  +------------+  +------------+  +-------------------+ |
+-----------------------|--------------------------------+
                        | GTK Bridge Calls (Nim)
+-----------------------v--------------------------------+
|                GTK4 Bridge Layer (Nim)                   |
|   - Widget wrappers                                    |
|   - Signal handling                                    |
|   - Creation factories                                 |
+-----------------------|--------------------------------+
                        |
+-----------------------v--------------------------------+
|                      GTK4 Library                        |
+--------------------------------------------------------+
```

## Bridge Architecture

### GTK4 Bridge Layer (Nim)

The bridge consists of several components in `src/harding/gui/gtk/`:

1. **ffi.nim** - Raw GTK4 C function bindings
2. **widget.nim** - Base widget proxy and two-table system
3. **window.nim**, **button.nim**, **box.nim**, etc. - Widget-specific wrappers
4. **bridge.nim** - Class registration with Harding interpreter

### Two-Table System

The bridge uses two complementary tables to solve the GC issue:

1. **`proxyTable: Table[GtkWidget, GtkWidgetProxy]`**
   - Maps widget pointers to their proxy objects
   - Used for signal handling and proxy lookup

2. **`instanceWidgetTable: Table[int, GtkWidget]`**
   - Maps Instance addresses (as integers) to widget pointers
   - Ensures correct widget lookup even if Instance is copied by GC

### Widget Creation Flow

```
Harding code (e.g., GtkButton newLabel: "X")
    ↓
Nim native method (buttonNewLabelImpl)
    ↓
GTK function (gtk_button_new_with_label)
    ↓
Create proxy and store in both tables
    ↓
Return Instance to Harding with isNimProxy = true
```

## Creating Widgets from Harding

### Basic Window and Layout

```harding
# Create window
window := GtkWindow new.
window title: "My App".
window setDefaultSize: 800 height: 600.

# Create layout box
box := GtkBox vertical.
box setSpacing: 10.

# Create button
button := GtkButton newLabel: "Click Me".
button clicked: [
    Transcript showCr: "Button was clicked!"
].

# Layout children
box append: button.

# Attach box to window
window setChild: box.

# Show window
window present
```

### Signal Handling

Connect GTK signals to Harding blocks:

```harding
# Simple signal (no arguments)
button clicked: [
    Transcript showCr: "Clicked!"
].

# Motion signal (passes x, y coordinates)
canvas connectMotion: [ :x :y |
    Transcript showCr: "Position: ", x asString, " ", y asString
].

# Key press signal
entry connectKeyPressed: [ :keyval :keycode :mods |
    (keyval = 65293) "Enter key"
        ifTrue: [ self submit ]
        ifFalse: [ false ]  "Don't consume other keys"
].
```

### Common Widgets

| Widget | Creation | Key Methods |
|--------|----------|-------------|
| Window | `GtkWindow new` | `title:`, `setDefaultSize:height:`, `setChild:`, `present` |
| Button | `GtkButton newLabel:` | `label:`, `clicked:` |
| Box | `GtkBox vertical` / `horizontal` | `append:`, `prepend:`, `remove:`, `setSpacing:` |
| Label | `GtkLabel newLabel:` | `label:`, `markup:` |
| Entry | `GtkEntry new` | `text:`, `text`, `connectTextChanged:` |
| TextView | `GtkTextView new` | `text:`, `text`, `editable:`, `monospace:`, `insertText:at:`, `selectRangeFrom:to:`, `insertTextAtSelectedEnd:` |
| SourceView | `GtkSourceView new` | Inherits TextView methods, `showLineNumbers:`, `setTabWidth:`, `selectedText` |
| ScrolledWindow | `GtkScrolledWindow new` | `setChild:` |

### TextView and SourceView Text Manipulation

TextView and SourceView provide methods for text manipulation:

```harding
# Get all text
sourceView text

# Set all text
sourceView text: "Hello, World!"

# Insert text at a specific position
sourceView insertText: "injected" at: 5

# Select a range of text (positions are character offsets)
sourceView selectRangeFrom: 0 to: 10

# Get selected text or current line
sourceView selectedText

# Insert text after the selection (for Print It)
resultPos := sourceView insertTextAtSelectedEnd: resultString

# Get selection end position (or cursor position if no selection)
endPos := sourceView getSelectionEnd
```

#### SourceView-Specific Features

```harding
sourceView := GtkSourceView new.

# Configure the editor
sourceView showLineNumbers: true.
sourceView setTabWidth: 2.

# Get selected text (or current line if nothing selected)
code := sourceView selectedText.
```

## IDE Tools

### Workspace - Code Editor and Evaluation

The Workspace (`lib/harding/gui/Ide/Workspace.hrd`) provides a source code editor with interactive evaluation:

```harding
# Create a workspace
Workspace open
```

#### Do It (Ctrl+D)

Evaluate the selected code or current line and print result to Transcript:

```harding
self doItSelection
```

**Behavior:**
- Evaluates selected text, or current line if no selection
- Prints result to Transcript
- No changes to editor content

#### Print It (Ctrl+P)

Evaluate and insert result in the editor:

```harding
self printItSelection
```

**Behavior:**
- Evaluates selected text, or current line if no selection
- **Inserts result after the selection** (Smalltalk-style)
- **Automatically selects the inserted text** so you can press Delete to remove it
- Also prints to Transcript for reference

**Example:**
1. Select: `3 + 4`
2. Press Ctrl+P or click "Print It"
3. Result: `7` appears after the selection and is selected
4. Press Delete to remove the result

## Memory Management and Lifecycle

### Widget Lifecycle

GTK widgets are reference-counted via GObject. The bridge tracks destruction state:

```nim
type
  GtkWidgetProxy* = ref object
    widget*: gtk4.Widget
    interp*: ptr Interpreter
    signalHandlers*: Table[string, seq[SignalHandler]]
    destroyed*: bool
```

When a GTK widget is destroyed:
1. `destroyed` flag is set to true
2. Signal handlers are cleared
3. Methods check `destroyed` flag before operating

### Rules

1. **GTK owns widget lifetime** via GObject refcount
2. **Harding proxy tracks destroyed state**
3. **Methods validate** before operating
4. **Explicit destroy available** for manual cleanup
5. **Closing window** destroys child widgets automatically

## Error Handling

Signal handlers use safe evaluation via the stackless VM. Widget callbacks construct a `MessageNode` and invoke it through `evalWithVM`, with exception handling to prevent Harding errors from crashing the GTK event loop.

```nim
# Signal handlers evaluate blocks through the stackless VM
try:
  let result = evalWithVM(interp[], msgNode)
except Exception as e:
  stderr.writeLine("Error in signal handler: ", e.msg)
```

**Implication**: Harding exceptions in signal handlers will not crash the GTK event loop.

## Current Status

### Implemented (Core)

- Basic widget wrappers (Window, Button, Box, Label, Entry)
- TextView with buffer
- ScrolledWindow
- Base signal handling with safe evaluation
- Two-table system for GC safety
- Basic layout containers

### In Progress

- IDE tools (Workspace, Transcript, Launcher via `bona` command)
- TreeView for hierarchical data
- HeaderBar
- Menu system

### Planned

- Inspector tool (object introspection)
- System Browser (class/method browsing)
- Debugger (stack frame inspection)

## Future Extensions

### Typed Signal Handlers

Provide typed helpers for common signal patterns:

```harding
# Motion - passes x, y
connectMotion: [:x :y | ...]

# Key press - passes keyval, keycode, modifiers
connectKeyPressed: [:keyval :keycode :mods | ...]

# TreeView row activated
connectRowActivated: [:path | ...]
```

### Glade/XML UI Support (Optional)

Load UI definitions from Glade XML files:

```harding
builder := GtkBuilder new.
builder addFromFile: 'ui/app.glade'.
window := builder getObject: 'mainWindow'.
```

This is optional - primary workflow remains code-based construction for maximum malleability.

## Debugging Tips

1. **Check proxy table** - Add debug prints to see if widgets are being stored/looked up
2. **Instance addresses** - Compare Instance addresses between creation and use
3. **Signal connection** - Verify `gSignalConnect` returns non-zero handler ID
4. **GTK warnings** - Watch for `Gtk-CRITICAL` warnings about invalid widgets
5. **Safe evaluation** - Check stderr for signal handler errors

## Common Issues

### "proxy is nil"
- Proxy not stored in `proxyTable` during creation
- Widget pointer type mismatch (need `cast[GtkWidget]`)

### Widget not visible
- Missing `gtkWidgetShow()` call
- Widget not added to parent container

### Signal not firing
- Block not captured correctly
- Signal name mismatch (GTK4 signal names)

### Window doesn't exit on close
- Need to connect "destroy" signal or use `connectDestroy`

## For More Information

- [MANUAL.md](MANUAL.md) - Core language manual
- [FUTURE.md](FUTURE.md) - GUI IDE plans
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - VM internals
- [VSCODE.md](VSCODE.md) - VSCode extension
