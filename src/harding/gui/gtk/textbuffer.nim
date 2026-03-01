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
proc textBufferNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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
proc textBufferSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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
proc textBufferGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get all text from the buffer
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  # Get start and end iterators
  gtkTextBufferGetStartIter(proxy.buffer, startIter)
  gtkTextBufferGetEndIter(proxy.buffer, endIter)

  # Get text
  let text = gtkTextBufferGetText(proxy.buffer, startIter, endIter, 1)
  if text == nil:
    return "".toValue()

  result = toValue($text)

## Native instance method: insert:at:
proc textBufferInsertAtImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var iterStorage: array[256, byte]
  let iter = cast[GtkTextIter](addr(iterStorage[0]))

  gtkTextBufferGetIterAtOffset(proxy.buffer, iter, args[1].intVal.cint)
  gtkTextBufferInsertAtCursor(proxy.buffer, args[0].strVal.cstring, -1)

  debug("Inserted text at position ", args[1].intVal, " in text buffer")

  nilValue()

## Native instance method: delete:to:
proc textBufferDeleteToImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  gtkTextBufferGetIterAtOffset(proxy.buffer, startIter, args[0].intVal.cint)
  gtkTextBufferGetIterAtOffset(proxy.buffer, endIter, args[1].intVal.cint)
  gtkTextBufferDelete(proxy.buffer, startIter, endIter)

  debug("Deleted text from ", args[0].intVal, " to ", args[1].intVal, " in text buffer")

  nilValue()

proc textBufferChangedCallbackProc(buffer: GtkTextBuffer, userData: pointer) {.cdecl.} =
  ## Called by GTK when a text buffer emits "changed"
  discard buffer
  if userData == nil:
    return

  let proxy = cast[GtkTextBufferProxy](userData)
  if proxy == nil or proxy.interp == nil:
    return

  if "changed" notin proxy.signalHandlers or proxy.signalHandlers["changed"].len == 0:
    return

  let handler = proxy.signalHandlers["changed"][0]
  if handler.blockNode == nil:
    return

  try:
    GC_ref(handler.blockNode)
    let msgNode = MessageNode(
      receiver: LiteralNode(value: NodeValue(kind: vkBlock, blockVal: handler.blockNode)),
      selector: "value",
      arguments: @[],
      isCascade: false
    )
    discard evalWithVMCleanContext(proxy.interp[], msgNode)
    GC_unref(handler.blockNode)
  except Exception as e:
    error("Error in text buffer changed callback: ", e.msg)

## Native instance method: changed:
proc textBufferChangedImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Connect changed signal to a block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  if self.nimValue == nil:
    return nilValue()

  let proxy = cast[GtkTextBufferProxy](self.nimValue)
  if proxy.buffer == nil:
    return nilValue()

  let blockVal = args[0]

  # Create signal handler and store in proxy's GC-managed table
  let handler = SignalHandler(
    blockNode: blockVal.blockVal,
    interp: addr(interp)
  )

  if "changed" notin proxy.signalHandlers:
    proxy.signalHandlers["changed"] = @[]
  proxy.signalHandlers["changed"].add(handler)

  # Connect the signal
  let gObject = cast[GObject](proxy.buffer)
  discard gSignalConnect(gObject, "changed",
                         cast[GCallback](textBufferChangedCallbackProc), cast[pointer](proxy))

  nilValue()
