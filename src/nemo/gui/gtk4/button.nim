## ============================================================================
## GtkButtonProxy - Button widget wrapper
## ============================================================================

import std/[logging, tables]
import nemo/core/types
import nemo/interpreter/evaluator
import ./ffi
import ./widget

## GtkButtonProxy extends GtkWidgetProxy
type
  GtkButtonProxyObj* {.acyclic.} = object of GtkWidgetProxyObj
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

## Factory: create a new button
proc createGtkButton*(interp: var Interpreter, label: string = ""): NodeValue =
  ## Create a new GTK button and return a proxy object
  let button = if label.len > 0:
    gtkButtonNewWithLabel(label.cstring)
  else:
    gtkButtonNew()

  let proxy = newGtkButtonProxy(button, addr(interp))

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
  obj.nimValue = cast[pointer](proxy)

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
    let proxy = cast[GtkButtonProxy](self.nimValue)
    let label = args[0].strVal
    if proxy.widget != nil:
      gtkButtonSetLabel(cast[GtkButton](proxy.widget), label.cstring)

  nilValue()

## Native method: label
proc buttonGetLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if self.isNimProxy and self.nimValue != nil:
    let proxy = cast[GtkButtonProxy](self.nimValue)
    if proxy.widget != nil:
      let label = gtkButtonGetLabel(cast[GtkButton](proxy.widget))
      return NodeValue(kind: vkString, strVal: $label)

  nilValue()

## Native method: clicked:
proc buttonClickedImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Stub for clicked: handler - stores the block for later use
  nilValue()
