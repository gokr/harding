## ============================================================================
## GtkMenuProxy - Menu widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  GtkMenuProxyObj* = object of GtkWidgetProxyObj

  GtkMenuProxy* = ref GtkMenuProxyObj

## Factory: Create new menu proxy
proc newGtkMenuProxy*(widget: GtkMenu, interp: ptr Interpreter): GtkMenuProxy =
  result = GtkMenuProxy()

## Native method: append:
proc menuAppendImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Append an item to the menu
  if args.len < 1:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let menuItemVal = args[0]
  if menuItemVal.kind != vkInstance or not menuItemVal.instVal.isNimProxy:
    return nilValue()

  let menuProxy = cast[GtkMenuProxy](self.nimValue)
  if menuProxy.widget == nil:
    return nilValue()

  let menuItemProxy = cast[GtkWidgetProxy](menuItemVal.instVal.nimValue)
  if menuItemProxy.widget == nil:
    return nilValue()

  when not defined(gtk3):
    # GTK4: use gtkBoxAppend since Menu is a Box
    gtkBoxAppend(cast[GtkBox](menuProxy.widget), menuItemProxy.widget)
  else:
    # GTK3: use gtkMenuShellAppend
    gtkMenuShellAppend(menuProxy.widget, menuItemProxy.widget)

  debug("Appended item to menu")

  nilValue()

## Native method: popup
proc menuPopupAtPointerImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Show the menu at the current pointer position
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let menuProxy = cast[GtkMenuProxy](self.nimValue)
  if menuProxy.widget == nil:
    return nilValue()

  gtkMenuPopupAtPointer(menuProxy.widget, nil)

  debug("Popped up menu at pointer")

  nilValue()
