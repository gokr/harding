## ============================================================================
## GtkButtonProxy - Button widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

## GtkButtonProxy extends GtkWidgetProxy
type
  GtkButtonProxyObj* = object of GtkWidgetProxyObj
    ## Additional button-specific fields can go here

  GtkButtonProxy* = ref GtkButtonProxyObj

## Create a new button proxy
proc newGtkButtonProxy*(button: GtkButton, interp: ptr Interpreter): GtkButtonProxy =
  result = GtkButtonProxy(
    widget: button,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  # Store in global table keyed by widget pointer (cast to base type)
  proxyTable[cast[GtkWidget](button)] = result

## Factory: create a new button
proc createGtkButton*(interp: var Interpreter, label: string = ""): NodeValue =
  ## Create a new GTK button and return a proxy object
  let button = if label.len > 0:
    gtkButtonNewWithLabel(label.cstring)
  else:
    gtkButtonNew()

  # Create proxy and store in global table (keyed by widget pointer)
  discard newGtkButtonProxy(button, addr(interp))

  # Look up the GtkButton class
  var buttonClass: Class = nil
  if "GtkButton" in interp.globals[]:
    let btnVal = interp.globals[]["GtkButton"]
    if btnVal.kind == vkClass:
      buttonClass = btnVal.classVal

  if buttonClass == nil:
    buttonClass = objectClass

  let obj = newInstance(buttonClass)
  obj.isNimProxy = true
  # Store widget in instance->widget table for reliable lookup
  storeInstanceWidget(obj, button)
  # Also store in nimValue for backwards compatibility
  obj.nimValue = cast[pointer](button)

  return obj.toValue()

## Native method: new (class method)
proc buttonNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  createGtkButton(interp, "")

## Native method: newLabel: (class method)
proc buttonNewLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if args.len < 1 or args[0].kind != vkString:
    return createGtkButton(interp, "")

  createGtkButton(interp, args[0].strVal)

## Native method: label:
proc buttonSetLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let label = args[0].strVal
    gtkButtonSetLabel(button, label.cstring)

  nilValue()

## Native method: label
proc buttonGetLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let label = gtkButtonGetLabel(button)
    return NodeValue(kind: vkString, strVal: $label)

  nilValue()

## Native method: clicked:
proc buttonClickedImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Connect clicked signal to a block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkWidget](self.nimValue)
  if widget == nil:
    return nilValue()

  let proxy = getGtkWidgetProxy(widget)
  if proxy == nil:
    return nilValue()

  let blockVal = args[0]

  # Create signal handler and store in proxy's GC-managed table
  # This ensures the BlockNode and its captured environment are rooted
  let handler = SignalHandler(
    blockNode: blockVal.blockVal,
    interp: addr(interp)
  )

  if "clicked" notin proxy.signalHandlers:
    proxy.signalHandlers["clicked"] = @[]
  proxy.signalHandlers["clicked"].add(handler)

  # Connect the signal - no userData needed, we look up by widget
  let gObject = cast[GObject](widget)
  discard gSignalConnect(gObject, "clicked",
                         cast[GCallback](signalCallbackProc), nil)

  nilValue()
