## ============================================================================
## GtkWidgetProxy - Base widget wrapper
## ============================================================================

import std/[tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi

## Forward declarations
type
  SignalHandler* = object
    blockNode*: BlockNode
    interp*: ptr Interpreter

  GtkWidgetProxyObj* = object of RootObj
    widget*: GtkWidget
    interp*: ptr Interpreter
    signalHandlers*: Table[string, seq[SignalHandler]]
    destroyed*: bool

  GtkWidgetProxy* = ref GtkWidgetProxyObj

## Global proxy table - maps widget pointers to their proxies
## This avoids storing ref objects as raw pointers (which GC can move)
var proxyTable* {.global.}: Table[GtkWidget, GtkWidgetProxy] = initTable[GtkWidget, GtkWidgetProxy]()

type
  PendingGtkCallback* = object
    interp*: ptr Interpreter
    blockNode*: BlockNode
    args*: seq[NodeValue]

var pendingGtkCallbacks* {.global.}: seq[PendingGtkCallback] = @[]

proc enqueueGtkCallback*(interp: ptr Interpreter, blockNode: BlockNode, args: seq[NodeValue]) =
  if interp == nil or blockNode == nil:
    return
  GC_ref(blockNode)
  pendingGtkCallbacks.add(PendingGtkCallback(interp: interp, blockNode: blockNode, args: args))

proc drainPendingGtkCallbacks*(targetInterp: ptr Interpreter = nil) =
  var idx = 0
  while idx < pendingGtkCallbacks.len:
    let callback = pendingGtkCallbacks[idx]
    if targetInterp != nil and callback.interp != targetInterp:
      idx += 1
      continue

    pendingGtkCallbacks.delete(idx)

    try:
      discard invokeBlock(callback.interp[], callback.blockNode, callback.args)
    except Exception as e:
      error("Error in deferred GTK callback: ", e.msg)
      dumpVmState(callback.interp[], "deferred GTK callback error")
      printStackTrace(callback.interp[])
    finally:
      GC_unref(callback.blockNode)

## C callback for GTK signals - receives widget and user data
proc signalCallbackProc*(widget: GtkWidget, userData: pointer) {.cdecl.} =
  ## Called by GTK when a signal is emitted
  ## We look up the handler by widget from the proxy table
  # Look up the proxy for this widget
  if widget notin proxyTable:
    return

  let proxy = proxyTable[widget]
  if proxy.interp == nil:
    return

  let interp = proxy.interp

  # Debug: check if globals are accessible
  if interp.globals == nil:
    debug("signalCallback: interp.globals is nil!")
    return
  if "GtkBox" in interp.globals[]:
    let boxVal = interp.globals[]["GtkBox"]
    debug("signalCallback: GtkBox in globals kind=", $boxVal.kind)
  else:
    debug("signalCallback: GtkBox NOT in globals!")

  # For clicked signals, use the "clicked" handler
  # We check both "clicked" and "activate" since GTK3/GTK4 use different names
  var handler: SignalHandler
  var found = false

  if "clicked" in proxy.signalHandlers and proxy.signalHandlers["clicked"].len > 0:
    handler = proxy.signalHandlers["clicked"][0]
    found = true
  elif "activate" in proxy.signalHandlers and proxy.signalHandlers["activate"].len > 0:
    handler = proxy.signalHandlers["activate"][0]
    found = true

  if not found or handler.blockNode == nil:
    return

  let savedDepth = interp[].activationStack.len
  try:
    GC_ref(handler.blockNode)
    discard invokeBlock(interp[], handler.blockNode, @[])
  except Exception as e:
    restoreActivationStackTo(interp[], savedDepth)
    error("Error in signal callback: ", e.msg)
    dumpVmState(interp[], "signalCallback error")
    printStackTrace(interp[])
  finally:
    GC_unref(handler.blockNode)

## C callback for GTK destroy signals
proc destroyCallbackProc*(widget: GtkWidget, userData: pointer) {.cdecl.} =
  ## Called by GTK when a destroy signal is emitted
  if widget notin proxyTable:
    return

  let proxy = proxyTable[widget]
  if proxy.interp == nil:
    return

  if "destroy" in proxy.signalHandlers and proxy.signalHandlers["destroy"].len > 0:
    let handler = proxy.signalHandlers["destroy"][0]
    if handler.blockNode != nil:
      let savedDepth = proxy.interp[].activationStack.len
      try:
        GC_ref(handler.blockNode)
        discard invokeBlock(proxy.interp[], handler.blockNode, @[])
      except Exception as e:
        restoreActivationStackTo(proxy.interp[], savedDepth)
        error("Error in destroy callback: ", e.msg)
        dumpVmState(proxy.interp[], "destroyCallback error")
        printStackTrace(proxy.interp[])
      finally:
        GC_unref(handler.blockNode)

  # Always mark and remove proxy to avoid stale signal handlers
  proxy.destroyed = true
  if widget in proxyTable:
    proxyTable.del(widget)

## Create a new widget proxy - stores in global table instead of raw pointer
proc newGtkWidgetProxy*(widget: GtkWidget, interp: ptr Interpreter): GtkWidgetProxy =
  result = GtkWidgetProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  # Store in global table keyed by widget pointer
  proxyTable[widget] = result

## Get a proxy for a widget from the global table
proc getGtkWidgetProxy*(widget: GtkWidget): GtkWidgetProxy =
  if widget in proxyTable:
    return proxyTable[widget]
  return nil

## Remove a proxy from the global table
proc removeGtkWidgetProxy*(widget: GtkWidget) =
  if widget in proxyTable:
    proxyTable.del(widget)

## Alternative: Store widget pointer keyed by Instance address
## This is more reliable since Instance (ref) identity is preserved
var instanceWidgetTable* {.global.}: Table[int, GtkWidget] = initTable[int, GtkWidget]()

## Store widget for an instance
proc storeInstanceWidget*(inst: Instance, widget: GtkWidget) =
  let key = cast[int](inst)
  instanceWidgetTable[key] = widget

## Retrieve widget for an instance
proc getInstanceWidget*(inst: Instance): GtkWidget =
  let key = cast[int](inst)
  if key in instanceWidgetTable:
    return instanceWidgetTable[key]
  return nil

## Native method: show
proc widgetShowImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetShow(widget)
  nilValue()

## Native method: hide
proc widgetHideImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetHide(widget)
  nilValue()

## Native method: setSizeRequest:
proc widgetSetSizeRequestImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 2:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    let width = args[0].intVal
    let height = args[1].intVal
    gtkWidgetSetSizeRequest(widget, width.cint, height.cint)

  nilValue()

## Native method: addCssClass:
proc widgetAddCssClassImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkString:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      let cssClass = args[0].strVal
      gtkWidgetAddCssClass(widget, cssClass.cstring)

  nilValue()

## Native method: removeCssClass:
proc widgetRemoveCssClassImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkString:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      let cssClass = args[0].strVal
      gtkWidgetRemoveCssClass(widget, cssClass.cstring)

  nilValue()

## Native method: connect:do:
proc widgetConnectDoImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Connect a signal to a block
  ## Takes two arguments: signal name (string) and block to execute
  if args.len < 2:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let signalName = args[0]
  let blockVal = args[1]

  if signalName.kind != vkString or blockVal.kind != vkBlock:
    return nilValue()

  let widget = cast[GtkWidget](self.nimValue)

  # Look up the proxy from the global table
  let proxy = getGtkWidgetProxy(widget)
  if proxy == nil:
    return nilValue()

  let signalStr = signalName.strVal

  # Create signal handler and store in proxy's GC-managed table
  # This ensures the BlockNode and its captured environment are rooted
  let handler = SignalHandler(
    blockNode: blockVal.blockVal,
    interp: addr(interp)
  )

  if signalStr notin proxy.signalHandlers:
    proxy.signalHandlers[signalStr] = @[]
  proxy.signalHandlers[signalStr].add(handler)

  # Connect the signal - no userData needed, we look up by widget
  let gObject = cast[GObject](widget)
  discard gSignalConnect(gObject, signalStr.cstring,
                         cast[GCallback](signalCallbackProc), nil)

  debug("Connected signal '", signalStr, "' on widget")

  nilValue()

## Native method: emitSignal:
proc widgetEmitSignalImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Programmatically emit a GTK signal by name (useful for tests)
  discard interp
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkWidget](self.nimValue)
  if widget == nil:
    return nilValue()

  gSignalEmitByName(cast[GObject](widget), args[0].strVal.cstring)
  return nilValue()

## Native class method: pumpEvents / pumpEvents:
proc widgetPumpEventsImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Process pending GTK events to drive callbacks in tests.
  discard interp
  discard self

  var iterations = 1
  if args.len > 0 and args[0].kind == vkInt and args[0].intVal > 0:
    iterations = args[0].intVal

  for _ in 0..<iterations:
    when defined(gtk3):
      discard gtkMainIterationDo(0)
    else:
      discard gMainContextIteration(nil, 0)
    drainPendingGtkCallbacks()

  return nilValue()

## Native method: setVexpand:
proc widgetSetVexpandImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set vertical expand property (GTK4 only)
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkBool:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      gtkWidgetSetVexpand(widget, if args[0].boolVal: 1 else: 0)
      gtkWidgetSetVexpandSet(widget, 1)  # Always set to 1 to make the setting take effect
      debug("Set vexpand on widget")

  nilValue()

## Native method: setHexpand:
proc widgetSetHexpandImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set horizontal expand property (GTK4 only)
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkBool:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      gtkWidgetSetHexpand(widget, if args[0].boolVal: 1 else: 0)
      gtkWidgetSetHexpandSet(widget, 1)  # Always set to 1 to make the setting take effect
      debug("Set hexpand on widget")

  nilValue()

## Native method: setHalignStart
proc widgetSetHalignStartImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Align widget to the start (left in LTR layouts)
  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetSetHalign(widget, GTKALIGNSTART)

  nilValue()

## Native method: marginStart:
proc widgetMarginStartImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set margin on the start side of the widget
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetSetMarginStart(widget, args[0].intVal.cint)

  nilValue()

## Native method: marginEnd:
proc widgetMarginEndImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set margin on the end side of the widget
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetSetMarginEnd(widget, args[0].intVal.cint)

  nilValue()

## Native method: marginTop:
proc widgetMarginTopImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set margin on the top side of the widget
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetSetMarginTop(widget, args[0].intVal.cint)

  nilValue()

## Native method: marginBottom:
proc widgetMarginBottomImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set margin on the bottom side of the widget
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetSetMarginBottom(widget, args[0].intVal.cint)

  nilValue()

## Native method: setTooltipText:
proc widgetSetTooltipTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set widget tooltip text
  discard interp
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not self.isNimProxy:
    return nilValue()

  var widget = getInstanceWidget(self)
  if widget == nil and self.nimValue != nil:
    widget = cast[GtkWidget](self.nimValue)
  if widget == nil:
    return nilValue()

  gtkWidgetSetTooltipText(widget, args[0].strVal.cstring)
  return nilValue()
