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
proc textViewNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
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
proc textViewGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get all text from the text view
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkTextView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(widget)
  if buffer == nil:
    return "".toValue()

  var startIter, endIter: GtkTextIter
  gtkTextBufferGetStartIter(buffer, addr(startIter))
  gtkTextBufferGetEndIter(buffer, addr(endIter))

  let text = gtkTextBufferGetText(buffer, addr(startIter), addr(endIter), 1)
  if text == nil:
    return "".toValue()

  result = toValue($text)

## Native instance method: setText:
proc textViewSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
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
proc textViewGetBufferImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
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
proc textViewSetBufferImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
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
