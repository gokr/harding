## ============================================================================
## GtkTextBufferProxy - TextBuffer widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

## GtkTextBufferProxy type extending proxy object
type
  GtkTextBufferProxyObj* = object of RootObj
    buffer*: GtkTextBuffer
    interp*: ptr Interpreter
    signalHandlers*: Table[string, seq[SignalHandler]]
    destroyed*: bool

  GtkTextBufferProxy* = ref GtkTextBufferProxyObj

## Factory: Create new text buffer proxy
proc newGtkTextBufferProxy*(buffer: GtkTextBuffer, interp: ptr Interpreter): GtkTextBufferProxy =
  result = GtkTextBufferProxy(buffer: buffer, interp: interp,
                             signalHandlers: initTable[string, seq[SignalHandler]](),
                             destroyed: false)

## Native class method: new
proc textBufferNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create a new text buffer
  let buffer = gtkTextBufferNew()
  let proxy = newGtkTextBufferProxy(buffer, addr(interp))

  var cls: Class = nil
  if "GtkTextBuffer" in interp.globals[]:
    let val = interp.globals[]["GtkTextBuffer"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil:
    cls = objectClass

  let obj = newInstance(cls)
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  GC_ref(cast[ref RootObj](proxy))
  return obj.toValue()

## Native instance method: setText:
proc textBufferSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set text in the buffer
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  gtkTextBufferSetText(proxy.buffer, args[0].strVal.cstring, -1)

  debug("Set text in text buffer")

  nilValue()

## Native instance method: getText:
proc textBufferGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get all text from the buffer
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  # Get start and end iterators
  var startIter, endIter: GtkTextIter
  gtkTextBufferGetStartIter(proxy.buffer, addr(startIter))
  gtkTextBufferGetEndIter(proxy.buffer, addr(endIter))

  # Get text
  let text = gtkTextBufferGetText(proxy.buffer, addr(startIter), addr(endIter), 1)
  if text == nil:
    return "".toValue()

  result = toValue($text)

## Native instance method: insert:at:
proc textBufferInsertAtImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Insert text at position
  if args.len < 2:
    return nilValue()

  if args[0].kind != vkString or args[1].kind != vkInt:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  var iter: GtkTextIter
  gtkTextBufferGetIterAtOffset(proxy.buffer, addr(iter), args[1].intVal.cint)
  gtkTextBufferInsertAtCursor(proxy.buffer, args[0].strVal.cstring, -1)

  debug("Inserted text at position ", args[1].intVal, " in text buffer")

  nilValue()

## Native instance method: delete:to:
proc textBufferDeleteToImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Delete text from start to end position
  if args.len < 2:
    return nilValue()

  if args[0].kind != vkInt or args[1].kind != vkInt:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  var startIter, endIter: GtkTextIter
  gtkTextBufferGetIterAtOffset(proxy.buffer, addr(startIter), args[0].intVal.cint)
  gtkTextBufferGetIterAtOffset(proxy.buffer, addr(endIter), args[1].intVal.cint)
  gtkTextBufferDelete(proxy.buffer, addr(startIter), addr(endIter))

  debug("Deleted text from ", args[0].intVal, " to ", args[1].intVal, " in text buffer")

  nilValue()
