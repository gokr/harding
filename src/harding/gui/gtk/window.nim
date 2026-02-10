## ============================================================================
## GtkWindowProxy - Window widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

## GtkWindowProxy extends GtkWidgetProxy
type
  GtkWindowProxyObj* = object of GtkWidgetProxyObj
    ## Additional window-specific fields can go here

  GtkWindowProxy* = ref GtkWindowProxyObj

## Create a new window proxy
proc newGtkWindowProxy*(window: GtkWindow, interp: ptr Interpreter): GtkWindowProxy =
  result = GtkWindowProxy(
    widget: window,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](window)] = result

## Factory: create a new window
proc createGtkWindow*(interp: var Interpreter): NodeValue =
  ## Create a new GTK window and return a proxy object
  when not defined(gtk3):
    let window = gtkWindowNew()
  else:
    let window = gtkWindowNew(GTKWINDOWTOPLEVEL)
  discard newGtkWindowProxy(window, addr(interp))

  # Create a Harding instance to wrap the proxy
  # We need to get the GtkWindow class from globals
  var windowClass: Class = nil
  if "GtkWindow" in interp.globals[]:
    let winVal = interp.globals[]["GtkWindow"]
    if winVal.kind == vkClass:
      windowClass = winVal.classVal

  if windowClass == nil:
    # Fallback to Object class
    windowClass = objectClass

  let obj = newInstance(windowClass)
  obj.isNimProxy = true
  storeInstanceWidget(obj, window)
  obj.nimValue = cast[pointer](window)

  return obj.toValue()

## Native method: new (class method for Window)
proc windowNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  createGtkWindow(interp)

## Native method: title:
proc windowSetTitleImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let title = args[0].strVal
      gtkWindowSetTitle(window, title.cstring)

  nilValue()

## Native method: setDefaultSize:height:
proc windowSetDefaultSizeImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 2:
    return nilValue()

  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let width = args[0].intVal
      let height = args[1].intVal
      gtkWindowSetDefaultSize(window, width.cint, height.cint)

  nilValue()

## Native method: setChild: (GTK3/GTK4 compatible)
proc windowSetChildImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()

  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let childInstance = args[0].instVal
      if childInstance.isNimProxy:
        var childWidget = getInstanceWidget(childInstance)
        if childWidget == nil and childInstance.nimValue != nil:
          childWidget = cast[GtkWidget](childInstance.nimValue)
        if childWidget != nil:
          when not defined(gtk3):
            gtkWindowSetChild(window, childWidget)
            gtkWidgetShow(childWidget)
          else:
            gtkContainerAdd(window, childWidget)

  nilValue()

## Native method: present
proc windowPresentImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      gtkWidgetShow(cast[GtkWidget](window))
      gtkWindowPresent(window)

  nilValue()

## Native method: close
proc windowCloseImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      gtkWindowClose(window)

  nilValue()

## Callback for window destroy signal
proc onWindowDestroy(widget: GtkWidget, userData: pointer) {.cdecl.} =
  ## Called when window is destroyed - exit the application
  quit(0)

## Native method: connectDestroy (to auto-exit on close)
proc windowConnectDestroyImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Connect destroy signal to exit the application
  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let gObject = cast[GObject](window)
      discard gSignalConnect(gObject, "destroy",
                             cast[GCallback](onWindowDestroy), nil)

  nilValue()

## Native method: destroyed: (block-based destroy signal)
proc windowDestroyedImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Connect destroy signal to a Harding block
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

  let handler = SignalHandler(
    blockNode: blockVal.blockVal,
    interp: addr(interp)
  )

  if "destroy" notin proxy.signalHandlers:
    proxy.signalHandlers["destroy"] = @[]
  proxy.signalHandlers["destroy"].add(handler)

  let gObject = cast[GObject](widget)
  discard gSignalConnect(gObject, "destroy",
                         cast[GCallback](destroyCallbackProc), nil)

  nilValue()

## Native method: iconName:
proc windowSetIconNameImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set the window icon by name (from icon theme)
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let iconName = args[0].strVal
      gtkWindowSetIconName(window, iconName.cstring)

  nilValue()
## Native method: iconFromFile:
proc windowSetIconFromFileImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set the window icon
  ## GTK3: Supports file path loading
  ## GTK4: Treats argument as icon name (uses icon theme)
  if args.len < 1 or args[0].kind != vkString:
    return toValue(false)

  if self.isNimProxy:
    var window = getInstanceWidget(self)
    if window == nil and self.nimValue != nil:
      window = cast[GtkWindow](self.nimValue)
    if window != nil:
      let iconArg = args[0].strVal

      when defined(gtk3):
        if fileExists(iconArg):
          let result = gtkWindowSetIconFromFile(window, iconArg.cstring)
          if result != 0: return toValue(true)
        else:
          gtkWindowSetIconName(window, iconArg.cstring)
          return toValue(true)
      else:
        gtkWindowSetIconName(window, iconArg.cstring)
        return toValue(true)

  toValue(false)
