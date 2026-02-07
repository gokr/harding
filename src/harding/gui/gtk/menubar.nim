## ============================================================================
## GtkMenuBarProxy - MenuBar widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  GtkMenuBarProxyObj* = object of GtkWidgetProxyObj

  GtkMenuBarProxy* = ref GtkMenuBarProxyObj

## Factory: Create new menu bar proxy
proc newGtkMenuBarProxy*(widget: GtkMenuBar, interp: ptr Interpreter): GtkMenuBarProxy =
  result = GtkMenuBarProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Factory: create a new menu bar
proc createGtkMenuBar*(interp: var Interpreter): NodeValue =
  ## Create a new GTK menu bar and return a proxy object
  let widget = gtkMenuBarNew()
  discard newGtkMenuBarProxy(widget, addr(interp))

  # Look up the GtkMenuBar class
  var menuBarClass: Class = nil
  if "GtkMenuBar" in interp.globals[]:
    let val = interp.globals[]["GtkMenuBar"]
    if val.kind == vkClass:
      menuBarClass = val.classVal
  if menuBarClass == nil and "GtkWidget" in interp.globals[]:
    let val = interp.globals[]["GtkWidget"]
    if val.kind == vkClass:
      menuBarClass = val.classVal
  if menuBarClass == nil:
    menuBarClass = objectClass

  let obj = newInstance(menuBarClass)
  obj.isNimProxy = true
  storeInstanceWidget(obj, widget)
  obj.nimValue = cast[pointer](widget)

  return obj.toValue()

## Native method: new (class method)
proc menuBarNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  createGtkMenuBar(interp)

## Native method: append:
proc menuBarAppendImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Append a menu item to the menu bar
  if args.len < 1:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  let menuItemVal = args[0]
  if menuItemVal.kind != vkInstance or not menuItemVal.instVal.isNimProxy:
    return nilValue()

  var menuBarWidget = getInstanceWidget(self)
  if menuBarWidget == nil and self.nimValue != nil:
    menuBarWidget = cast[GtkMenuBar](self.nimValue)
  if menuBarWidget == nil:
    return nilValue()

  var menuItemWidget = getInstanceWidget(menuItemVal.instVal)
  if menuItemWidget == nil and menuItemVal.instVal.nimValue != nil:
    menuItemWidget = cast[GtkWidget](menuItemVal.instVal.nimValue)
  if menuItemWidget == nil:
    return nilValue()

  when not defined(gtk3):
    # GTK4: use gtkBoxAppend since GtkMenuBar is a GtkBox
    gtkBoxAppend(cast[GtkBox](menuBarWidget), menuItemWidget)
    gtkWidgetShow(menuItemWidget)
  else:
    # GTK3: use gtkMenuShellAppend
    gtkMenuShellAppend(menuBarWidget, menuItemWidget)

  nilValue()
