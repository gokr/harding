## ============================================================================
## GtkMenuItemProxy - MenuItem widget wrapper
## ============================================================================

import std/[logging, tables]
import nemo/core/types
import nemo/interpreter/evaluator
import ./ffi
import ./widget

type
  GtkMenuItemProxyObj* {.acyclic.} = object of GtkWidgetProxyObj

  GtkMenuItemProxy* = ref GtkMenuItemProxyObj

## Factory: Create new menu item proxy
proc newGtkMenuItemProxy*(widget: GtkMenuItem, interp: ptr Interpreter): GtkMenuItemProxy =
  result = GtkMenuItemProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Native class method: new
proc menuItemNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create a new menu item
  let widget = gtkMenuItemNew()
  discard newGtkMenuItemProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkMenuItem" in interp.globals[]:
    let val = interp.globals[]["GtkMenuItem"]
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

## Native class method: newLabel:
proc menuItemNewLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create a new menu item with a label
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  let widget = gtkMenuItemNewWithLabel(args[0].strVal.cstring)
  discard newGtkMenuItemProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkMenuItem" in interp.globals[]:
    let val = interp.globals[]["GtkMenuItem"]
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

## Native instance method: activate:
proc menuItemActivateImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set activate handler - alias for connect:do: with "activate" (or "clicked" for GTK4)
  if args.len < 1:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  let blockVal = args[0]
  if blockVal.kind != vkBlock:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkWidget](self.nimValue)
  if widget == nil:
    return nilValue()

  # Get or create proxy for signal handling
  let proxy = getGtkWidgetProxy(widget)
  if proxy == nil:
    return nilValue()

  # Create signal handler data
  var callbackData = cast[ptr SignalCallbackData](alloc0(sizeof(SignalCallbackData)))
  callbackData.handler = SignalHandler(
    blockNode: blockVal.blockVal,
    interp: addr(interp)
  )

  # GTK4 uses clicked signal for button-based menu items
  let signalName = when defined(gtk4): "clicked" else: "activate"
  callbackData.signalName = signalName

  # Store in proxy's signal handlers table
  if signalName notin proxy.signalHandlers:
    proxy.signalHandlers[signalName] = @[]
  proxy.signalHandlers[signalName].add(callbackData.handler)

  # Connect the signal
  let gObject = cast[GObject](widget)
  discard gSignalConnect(gObject, signalName.cstring,
                         cast[GCallback](signalCallbackProc), cast[pointer](callbackData))

  debug("Connected ", signalName, " signal on menu item")

  nilValue()
