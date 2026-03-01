## ============================================================================
## GtkButtonProxy - Button widget wrapper
## ============================================================================

import std/tables
import harding/core/types
import ./ffi
import ./widget

when not defined(gtk3):
  # GTK4 only: set child widget for button
  proc gtkButtonSetChild*(button: GtkButton, child: GtkWidget) {.cdecl, importc: "gtk_button_set_child".}

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
proc buttonNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  createGtkButton(interp, "")

## Native method: label:
proc buttonSetLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let label = args[0].strVal
    gtkButtonSetLabel(button, label.cstring)

  nilValue()

## Native method: label
proc buttonGetLabelImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let label = gtkButtonGetLabel(button)
    return NodeValue(kind: vkString, strVal: $label)

  nilValue()

## Native method: clicked:
proc buttonClickedImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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

## Native method: iconName:
proc buttonSetIconNameImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set icon name for the button (replaces label with icon)
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let iconName = args[0].strVal
    gtkButtonSetIconName(button, iconName.cstring)

  nilValue()

## Native method: label:iconName:
proc buttonSetLabelAndIconImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set both label and icon for the button
  ## Args: label (String), iconName (String)
  if args.len < 2 or args[0].kind != vkString or args[1].kind != vkString:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let button = cast[GtkButton](self.nimValue)
    let label = args[0].strVal
    let iconName = args[1].strVal
    
    when not defined(gtk3):
      # GTK4: Create box with image and label as child
      let box = gtkBoxNew(0.cint, 6.cint)  # Horizontal, 6px spacing
      let image = gtkImageNewFromIconName(iconName.cstring)
      
      # Create label
      let labelWidget = gtkLabelNew(label.cstring)
      
      # Add to box
      gtkBoxAppend(box, cast[GtkWidget](image))
      gtkBoxAppend(box, cast[GtkWidget](labelWidget))
      
      # Set box as button child
      gtkButtonSetChild(button, box)
    else:
      # GTK3 fallback: just set the label, icon not supported this way
      gtkButtonSetLabel(button, label.cstring)

  nilValue()
