## ============================================================================
## GtkScrolledWindowProxy - Scrolled window container wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  GtkScrolledWindowProxyObj* = object of GtkWidgetProxyObj

  GtkScrolledWindowProxy* = ref GtkScrolledWindowProxyObj

## Factory: Create new scrolled window proxy
proc newGtkScrolledWindowProxy*(widget: GtkScrolledWindow, interp: ptr Interpreter): GtkScrolledWindowProxy =
  result = GtkScrolledWindowProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Native class method: new
proc scrolledWindowNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Create a new scrolled window
  when not defined(gtk3):
    let widget = gtkScrolledWindowNew()
  else:
    let widget = gtkScrolledWindowNew(nil, nil)

  let proxy = newGtkScrolledWindowProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkScrolledWindow" in interp.globals[]:
    let val = interp.globals[]["GtkScrolledWindow"]
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

## Native instance method: setChild:
proc scrolledWindowSetChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set the child widget of the scrolled window
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let scrolledWindow = cast[GtkScrolledWindow](self.nimValue)
  let childInstance = args[0].instVal

  if childInstance.isNimProxy:
    var childWidget = getInstanceWidget(childInstance)
    if childWidget == nil and childInstance.nimValue != nil:
      childWidget = cast[GtkWidget](childInstance.nimValue)
    if childWidget != nil:
      when not defined(gtk3):
        gtkScrolledWindowSetChild(scrolledWindow, childWidget)
      else:
        gtkContainerAdd(scrolledWindow, childWidget)
      debug("Set child on scrolled window")

  nilValue()
