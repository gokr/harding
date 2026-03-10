## ============================================================================
## GtkEntryProxy - Entry widget wrapper
## ============================================================================

import std/[tables]
import harding/core/types
import ./ffi
import ./widget

type
  GtkEntryProxyObj* = object of GtkWidgetProxyObj

  GtkEntryProxy* = ref GtkEntryProxyObj

proc newGtkEntryProxy*(widget: GtkEntry, interp: ptr Interpreter): GtkEntryProxy =
  result = GtkEntryProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    connectedSignals: initTable[string, bool](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

proc entryNodeValueToString(val: NodeValue): string =
  case val.kind
  of vkString:
    val.strVal
  of vkInstance:
    if val.instVal != nil and val.instVal.kind == ikString:
      val.instVal.strVal
    else:
      ""
  else:
    ""

proc entryNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  let widget = gtkEntryNew()
  discard newGtkEntryProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkEntry" in interp.globals[]:
    let val = interp.globals[]["GtkEntry"]
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
  obj.toValue()

proc entryGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if not self.isNimProxy:
    return "".toValue()

  var widget = cast[GtkEntry](getInstanceWidget(self))
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkEntry](self.nimValue)
  if widget == nil:
    return "".toValue()

  let text = gtkEntryGetText(widget)
  if text == nil:
    return "".toValue()
  toValue($text)

proc entrySetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or not self.isNimProxy:
    return nilValue()

  var widget = cast[GtkEntry](getInstanceWidget(self))
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkEntry](self.nimValue)
  if widget == nil:
    return nilValue()

  gtkEntrySetText(widget, entryNodeValueToString(args[0]).cstring)
  nilValue()

proc entrySetPlaceholderTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or not self.isNimProxy:
    return nilValue()

  var widget = cast[GtkEntry](getInstanceWidget(self))
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkEntry](self.nimValue)
  if widget == nil:
    return nilValue()

  gtkEntrySetPlaceholderText(widget, entryNodeValueToString(args[0]).cstring)
  nilValue()
