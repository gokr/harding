## ============================================================================
## GtkTextViewProxy - TextView widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget
import ./textbuffer

type
  GtkTextViewProxyObj* = object of GtkWidgetProxyObj

  GtkTextViewProxy* = ref GtkTextViewProxyObj

## Factory: Create new text view proxy
proc newGtkTextViewProxy*(widget: GtkTextView, interp: ptr Interpreter): GtkTextViewProxy =
  result = GtkTextViewProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Native class method: new
proc textViewNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Create a new text view
  let widget = gtkTextViewNew()
  let proxy = newGtkTextViewProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkTextView" in interp.globals[]:
    let val = interp.globals[]["GtkTextView"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil and "GtkWidget" in interp.globals[]:
    let val = interp.globals[]["GtkWidget"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil:
    cls = objectClass

  let obj = newInstance(cls)
  obj.isNimProxy = true
  storeInstanceWidget(obj, cast[GtkWidget](widget))
  obj.nimValue = cast[pointer](widget)
  return obj.toValue()

## Native instance method: getText:
proc textViewGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get all text from the text view
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return "".toValue()

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  gtkTextBufferGetStartIter(buffer, startIter)
  gtkTextBufferGetEndIter(buffer, endIter)

  let text = gtkTextBufferGetText(buffer, startIter, endIter, 1)
  if text == nil:
    return "".toValue()

  result = toValue($text)

## Native instance method: setText:
proc textViewSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set text in the text view
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  gtkTextBufferSetText(buffer, args[0].strVal.cstring, -1)

  debug("Set text in text view")

  nilValue()

## Native instance method: getBuffer:
proc textViewGetBufferImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get the text buffer associated with the text view
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    let newBuffer = gtkTextBufferNew()
    gtkTextViewSetBuffer(widget, newBuffer)

    var cls: Class = nil
    if "GtkTextBuffer" in interp.globals[]:
      let val = interp.globals[]["GtkTextBuffer"]
      if val.kind == vkClass:
        cls = val.classVal
    if cls == nil:
      cls = objectClass

    let wrapper = newGtkTextBufferProxy(newBuffer, addr(interp))
    let obj = newInstance(cls)
    obj.isNimProxy = true
    obj.nimValue = cast[pointer](wrapper)
    GC_ref(cast[ref RootObj](wrapper))
    return obj.toValue()

  nilValue()

## Native instance method: setBuffer:
proc textViewSetBufferImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set the text buffer for the text view
  if args.len < 1:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)

  let bufferVal = args[0]
  if not (bufferVal.kind == vkInstance and bufferVal.instVal.isNimProxy):
    return nilValue()

  let bufferProxy = cast[GtkWidgetProxy](bufferVal.instVal.nimValue)
  if bufferProxy.widget == nil:
    return nilValue()

  gtkTextViewSetBuffer(widget, cast[GtkTextBuffer](bufferProxy.widget))

  debug("Set text buffer on text view")

  nilValue()

## Native instance method: insertText:at:
proc textViewInsertTextAtImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Insert text at a specific position in the text view
  if args.len < 2 or args[0].kind != vkString or args[1].kind != vkInt:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var iterStorage: array[256, byte]
  let iter = cast[GtkTextIter](addr(iterStorage[0]))

  gtkTextBufferGetIterAtOffset(buffer, iter, args[1].intVal.cint)

  gtkTextBufferInsert(buffer, iter, args[0].strVal.cstring, -1)

  nilValue()

## Native instance method: insertTextAtEnd:
proc textViewInsertTextAtEndImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Insert text at the end of the text buffer
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    debug("insertTextAtEnd: Not a NimProxy or nimValue is nil")
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    debug("insertTextAtEnd: buffer is nil")
    return nilValue()

  var endIterStorage: array[256, byte]
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  gtkTextBufferGetEndIter(buffer, endIter)
  gtkTextBufferInsert(buffer, endIter, args[0].strVal.cstring, -1)

  # Get some buffer content to identify which widget this is
  var startIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  gtkTextBufferGetStartIter(buffer, startIter)
  let firstChars = gtkTextBufferGetText(buffer, startIter, endIter, 1)
  var contentPreview = ""
  if firstChars != nil:
    contentPreview = $firstChars
    if contentPreview.len > 30:
      contentPreview = contentPreview[0..<30] & "..."

  debug("insertTextAtEnd: Inserted '", args[0].strVal, "' into widget ", repr(cast[int](widget)), " buffer now: '", contentPreview, "'")

  nilValue()

## Native instance method: selectRangeFrom:to:
proc textViewSelectRangeFromToImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Select a range of text in the text view
  if args.len < 2 or args[0].kind != vkInt or args[1].kind != vkInt:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  # Get end position iterator
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  gtkTextBufferGetIterAtOffset(buffer, startIter, args[0].intVal.cint)
  gtkTextBufferGetIterAtOffset(buffer, endIter, args[1].intVal.cint)

  gtkTextBufferSelectRange(buffer, startIter, endIter)

  nilValue()

## Native instance method: insertTextAtSelectedEnd:
proc textViewInsertTextAtSelectedEndImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Insert text after the end of the current selection
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  var endIterStorage: array[256, byte]
  var startIterStorage: array[256, byte]
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))

  # Get selection bounds
  let hasSelection = gtkTextBufferGetSelectionBounds(buffer, startIter, endIter)

  let insertPos = if hasSelection != 0:
    gtkTextIterGetOffset(endIter)
  else:
    # No selection, use cursor position
    let insertMark = gtkTextBufferGetInsert(buffer)
    gtkTextBufferGetIterAtMark(buffer, endIter, insertMark)
    gtkTextIterGetOffset(endIter)

  # Insert the text
  gtkTextBufferGetIterAtOffset(buffer, endIter, insertPos)
  gtkTextBufferInsert(buffer, endIter, args[0].strVal.cstring, -1)

  # Return the position where text was inserted
  NodeValue(kind: vkInt, intVal: insertPos)

## Native instance method: getSelectionEnd:
proc textViewGetSelectionEndImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get the end position of the current selection (or cursor position if no selection)
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  var endIterStorage: array[256, byte]
  var startIterStorage: array[256, byte]
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))

  let hasSelection = gtkTextBufferGetSelectionBounds(buffer, startIter, endIter)

  # Use the cursor position (insert mark) as reference
  let insertMark = gtkTextBufferGetInsert(buffer)
  gtkTextBufferGetIterAtMark(buffer, endIter, insertMark)

  result = NodeValue(kind: vkInt, intVal: gtkTextIterGetOffset(endIter))

## Native instance method: scrollToEnd
proc textViewScrollToEndImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Scroll the text view to the end (cursor position)
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return nilValue()

  # Get the insert mark (cursor position) and scroll to it
  let insertMark = gtkTextBufferGetInsert(buffer)
  gtkTextViewScrollToMark(widget, insertMark, 0.0'f64, 0, 0.0'f64, 1.0'f64)

  debug("Scrolled text view to end")

  nilValue()

## Native instance method: setEditable:
proc textViewSetEditableImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set whether the text view is editable
  if args.len < 1 or args[0].kind != vkBool:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)
  gtkTextViewSetEditable(widget, if args[0].boolVal: 1 else: 0)

  nilValue()
