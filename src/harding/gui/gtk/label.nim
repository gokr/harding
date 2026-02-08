## ============================================================================
## GtkLabelProxy - Label widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  GtkLabelProxyObj* = object of GtkWidgetProxyObj

  GtkLabelProxy* = ref GtkLabelProxyObj

## Factory: Create new label proxy
proc newGtkLabelProxy*(widget: GtkLabel, interp: ptr Interpreter): GtkLabelProxy =
  result = GtkLabelProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Native class method: new
proc labelNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Create a new empty label
  let widget = gtkLabelNew(nil)
  discard newGtkLabelProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkLabel" in interp.globals[]:
    let val = interp.globals[]["GtkLabel"]
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
  storeInstanceWidget(obj, widget)
  obj.nimValue = cast[pointer](widget)
  return obj.toValue()

## Native instance method: text:
proc labelSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set label text
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkLabel](self.nimValue)
  if widget == nil:
    return nilValue()

  gtkLabelSetText(widget, args[0].strVal.cstring)

  debug("Set label text to '", args[0].strVal, "'")

  nilValue()

## Native instance method: text (getter)
proc labelGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get label text
  if not self.isNimProxy:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkLabel](self.nimValue)
  if widget == nil:
    return "".toValue()

  let text = gtkLabelGetText(widget)
  if text == nil:
    return "".toValue()

  result = toValue($text)
