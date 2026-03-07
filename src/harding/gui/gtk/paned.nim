## ============================================================================
## GtkPanedProxy - Split pane container wrapper
## ============================================================================

import std/[tables]
import harding/core/types
import ./ffi
import ./widget

type
  GtkPanedProxyObj* = object of GtkWidgetProxyObj

  GtkPanedProxy* = ref GtkPanedProxyObj

proc newGtkPanedProxy*(widget: GtkPaned, interp: ptr Interpreter): GtkPanedProxy =
  result = GtkPanedProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    connectedSignals: initTable[string, bool](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

proc panedNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Class method new: — takes orientation int (0=horizontal, 1=vertical)
  var orientation = GTKORIENTATIONHORIZONTAL
  if args.len >= 1 and args[0].kind == vkInt:
    orientation = args[0].intVal.cint

  let widget = gtkPanedNew(orientation)
  discard newGtkPanedProxy(widget, addr(interp))

  var cls: Class = nil
  if "GtkPaned" in interp.globals[]:
    let val = interp.globals[]["GtkPaned"]
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

proc panedSetStartChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let paned = cast[GtkPaned](self.nimValue)
  let childInstance = args[0].instVal

  if childInstance.isNimProxy:
    var childWidget = getInstanceWidget(childInstance)
    if childWidget == nil and childInstance.nimValue != nil:
      childWidget = cast[GtkWidget](childInstance.nimValue)
    if childWidget != nil:
      when not defined(gtk3):
        gtkPanedSetStartChild(paned, childWidget)
      else:
        gtkPanedPack1(paned, childWidget, 1, 0)
      debug("Set start child on paned")

  nilValue()

proc panedSetEndChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let paned = cast[GtkPaned](self.nimValue)
  let childInstance = args[0].instVal

  if childInstance.isNimProxy:
    var childWidget = getInstanceWidget(childInstance)
    if childWidget == nil and childInstance.nimValue != nil:
      childWidget = cast[GtkWidget](childInstance.nimValue)
    if childWidget != nil:
      when not defined(gtk3):
        gtkPanedSetEndChild(paned, childWidget)
      else:
        gtkPanedPack2(paned, childWidget, 1, 0)
      debug("Set end child on paned")

  nilValue()

proc panedSetPositionImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let paned = cast[GtkPaned](self.nimValue)
  gtkPanedSetPosition(paned, args[0].intVal.cint)
  debug("Set paned position to ", args[0].intVal)
  nilValue()

proc panedSetShrinkStartChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let paned = cast[GtkPaned](self.nimValue)
  let shrink = if args[0].kind == vkBool: (if args[0].boolVal: 1.cint else: 0.cint) else: 0.cint
  when not defined(gtk3):
    gtkPanedSetShrinkStartChild(paned, shrink)
  nilValue()

proc panedSetShrinkEndChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let paned = cast[GtkPaned](self.nimValue)
  let shrink = if args[0].kind == vkBool: (if args[0].boolVal: 1.cint else: 0.cint) else: 0.cint
  when not defined(gtk3):
    gtkPanedSetShrinkEndChild(paned, shrink)
  nilValue()
