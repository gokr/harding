## ============================================================================
## GtkWidgetProxy - Base widget wrapper
## ============================================================================

import std/[logging, tables]
import nemo/core/types
import nemo/interpreter/evaluator
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

  # Invoke the Nemo block with empty args (typical for signal callbacks)
  # The block captures the widget/variables it needs via closure
  try:
    # Keep the handler alive during invocation to prevent GC collection
    # of captured variables
    GC_ref(handler.blockNode)
    let result = invokeBlock(interp[], handler.blockNode, @[])
    GC_unref(handler.blockNode)
    discard result  # Signal callbacks generally ignore return values
  except Exception as e:
    # Log error but don't crash the GUI
    error("Error in signal callback: ", e.msg)

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
proc widgetShowImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetShow(widget)
  nilValue()

## Native method: hide
proc widgetHideImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    gtkWidgetHide(widget)
  nilValue()

## Native method: setSizeRequest:
proc widgetSetSizeRequestImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  if args.len < 2:
    return nilValue()

  if self.isNimProxy and self.nimValue != nil:
    let widget = cast[GtkWidget](self.nimValue)
    let width = args[0].intVal
    let height = args[1].intVal
    gtkWidgetSetSizeRequest(widget, width.cint, height.cint)

  nilValue()

## Native method: addCssClass:
proc widgetAddCssClassImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  when defined(gtk4):
    if args.len < 1 or args[0].kind != vkString:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      let cssClass = args[0].strVal
      gtkWidgetAddCssClass(widget, cssClass.cstring)

  nilValue()

## Native method: removeCssClass:
proc widgetRemoveCssClassImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  when defined(gtk4):
    if args.len < 1 or args[0].kind != vkString:
      return nilValue()

    if self.isNimProxy and self.nimValue != nil:
      let widget = cast[GtkWidget](self.nimValue)
      let cssClass = args[0].strVal
      gtkWidgetRemoveCssClass(widget, cssClass.cstring)

  nilValue()

## Native method: connect:do:
proc widgetConnectDoImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
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
