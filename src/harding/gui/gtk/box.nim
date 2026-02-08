## ============================================================================
## GtkBoxProxy - Box layout widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

## GtkBoxProxy extends GtkWidgetProxy
type
  GtkBoxProxyObj* = object of GtkWidgetProxyObj
    ## Additional box-specific fields can go here

  GtkBoxProxy* = ref GtkBoxProxyObj

## Create a new box proxy
proc newGtkBoxProxy*(box: GtkBox, interp: ptr Interpreter): GtkBoxProxy =
  result = GtkBoxProxy(
    widget: box,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](box)] = result

## Factory: create a new box
proc createGtkBox*(interp: var Interpreter, orientation: cint, spacing: cint = 0): NodeValue =
  ## Create a new GTK box and return a proxy object
  let box = gtkBoxNew(orientation, spacing)
  discard newGtkBoxProxy(box, addr(interp))

  # Look up the GtkBox class
  var boxClass: Class = nil
  debug("createGtkBox: interp.globals.len=", interp.globals[].len)
  if "GtkBox" in interp.globals[]:
    let boxVal = interp.globals[]["GtkBox"]
    debug("createGtkBox: GtkBox found, kind=", $boxVal.kind)
    if boxVal.kind == vkClass:
      boxClass = boxVal.classVal
      debug("createGtkBox: using GtkBox class")
  else:
    debug("createGtkBox: GtkBox NOT in globals!")

  if boxClass == nil:
    debug("createGtkBox: falling back to objectClass")
    boxClass = objectClass

  let obj = newInstance(boxClass)
  obj.isNimProxy = true
  storeInstanceWidget(obj, box)
  obj.nimValue = cast[pointer](box)

  debug("createGtkBox: created instance ptr=", cast[int](obj), " class=", boxClass.name)
  return obj.toValue()

## Native method: new (class method) - creates vertical box by default
proc boxNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  createGtkBox(interp, 1, 0)  # GTK_ORIENTATION_VERTICAL = 1

## Native method: newOrientation:spacing: (class method)
proc boxNewOrientationSpacingImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 2:
    return nilValue()

  let orientation = args[0].intVal.cint
  let spacing = args[1].intVal.cint
  createGtkBox(interp, orientation, spacing)

## Native method: append:
proc boxAppendImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()

  let childInstance = args[0].instVal

  if self.isNimProxy:
    var boxWidget = getInstanceWidget(self)
    if boxWidget == nil and self.nimValue != nil:
      boxWidget = cast[GtkBox](self.nimValue)
    debug("boxAppend: boxWidget=", repr(boxWidget))

    if childInstance.isNimProxy:
      # Try to get widget from instance->widget table first (more reliable)
      var childWidget = getInstanceWidget(childInstance)
      # Fallback to nimValue if not found
      if childWidget == nil and childInstance.nimValue != nil:
        childWidget = cast[GtkWidget](childInstance.nimValue)
      if childWidget != nil and boxWidget != nil:
        when not defined(gtk3):
          gtkBoxAppend(boxWidget, childWidget)
          gtkWidgetShow(childWidget)
        else:
          gtkBoxPackStart(boxWidget, childWidget, 1, 1, 0)

  nilValue()

## Native method: prepend:
proc boxPrependImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let box = cast[GtkBox](self.nimValue)
    let childInstance = args[0].instVal

    if childInstance.isNimProxy and childInstance.nimValue != nil:
      let childWidget = cast[GtkWidget](childInstance.nimValue)
      when not defined(gtk3):
        gtkBoxPrepend(box, childWidget)
      else:
        gtkBoxPackEnd(box, childWidget, 1, 1, 0)

  nilValue()

## Native method: setSpacing:
proc boxSetSpacingImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1:
    return nilValue()

  if self.isNimProxy:
    var box = getInstanceWidget(self)
    if box == nil and self.nimValue != nil:
      box = cast[GtkBox](self.nimValue)
    if box != nil:
      let spacing = args[0].intVal
      gtkBoxSetSpacing(box, spacing.cint)

  nilValue()
