## ============================================================================
## GtkEventController - Keyboard and other event handling for GTK4
## ============================================================================

import std/[tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  KeyHandler* = object
    keyVal*: cuint
    modifiers*: cint
    blockNode*: BlockNode
    interp*: ptr Interpreter

  GtkEventControllerProxyObj* = object of GtkWidgetProxyObj
    keyHandlers*: seq[KeyHandler]

  GtkEventControllerProxy* = ref GtkEventControllerProxyObj

## Global table for event controllers keyed by widget
var controllerTable* {.global.}: Table[GtkWidget, GtkEventControllerProxy] = initTable[GtkWidget, GtkEventControllerProxy]()

## C callback for key press events
proc keyPressedCallback(controller: GtkEventControllerKey, keyval: cuint, keycode: cuint, state: cint, userData: pointer): cint {.cdecl.} =
  ## Called when a key is pressed
  let widget = cast[GtkWidget](userData)

  if widget notin controllerTable:
    return 0  # Not handled, propagate

  let proxy = controllerTable[widget]
  if proxy.interp == nil:
    return 0

  # Check if this key combination has a handler
  # Use bitmask matching for modifiers since GTK state may include extra bits
  # (e.g. lock/group), not just the exact requested modifier mask.
  for handler in proxy.keyHandlers:
    let keyMatches = handler.keyVal == keyval
    let modsMatch = (state and handler.modifiers) == handler.modifiers
    if keyMatches and modsMatch:
      # Found matching handler, invoke the block
      try:
        GC_ref(handler.blockNode)
        invokeGtkCallbackBlock(proxy.interp, handler.blockNode, @[])
        # Stop propagation to prevent GTK from inserting the character
        return 1  # Handled, stop propagation
      except Exception as e:
        error("Error in key handler: ", e.msg)
        dumpVmState(proxy.interp[], "keyPressedCallback error")
        printStackTrace(proxy.interp[])
        return 1  # Stop propagation even on error
      finally:
        GC_unref(handler.blockNode)

  return 0  # Not handled, propagate

## Native method: installKeyController on GtkWidget
proc widgetInstallKeyControllerImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Install a keyboard event controller on this widget
  ## This enables key-pressed signals to be handled
  when not defined(gtk3):
    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let widget = cast[GtkWidget](self.nimValue)

    # Create key controller
    let keyController = gtkEventControllerKeyNew()
    if keyController == nil:
      warn("Failed to create key controller")
      return nilValue()

    # Add controller to widget
    gtkWidgetAddController(widget, cast[GtkEventController](keyController))

    # Create or get proxy for this widget
    var proxy: GtkEventControllerProxy
    if widget in controllerTable:
      proxy = controllerTable[widget]
    else:
      proxy = GtkEventControllerProxy(
        widget: widget,
        interp: addr(interp),
        signalHandlers: initTable[string, seq[SignalHandler]](),
        connectedSignals: initTable[string, bool](),
        destroyed: false,
        keyHandlers: @[]
      )
      controllerTable[widget] = proxy

    # Connect the key-pressed signal
    discard gSignalConnect(cast[GObject](keyController), "key-pressed",
                           cast[GCallback](keyPressedCallback), widget)

    debug("Installed key controller on widget")

  nilValue()

## Native method: onKey:modifiers:do: on GtkWidget
proc widgetOnKeyModifiersDoImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Register a key handler for a specific key and modifier combination
  ## Args: keyval (int), modifiers (int), block
  if args.len < 3:
    return nilValue()

  if args[0].kind != vkInt or args[1].kind != vkInt or args[2].kind != vkBlock:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkWidget](self.nimValue)

  # Get or create controller proxy
  var proxy: GtkEventControllerProxy
  if widget in controllerTable:
    proxy = controllerTable[widget]
  else:
    # First handler - install the controller
    discard widgetInstallKeyControllerImpl(interp, self, @[])
    if widget notin controllerTable:
      warn("Failed to install key controller")
      return nilValue()
    proxy = controllerTable[widget]

  # Add the key handler
  let handler = KeyHandler(
    keyVal: args[0].intVal.cuint,
    modifiers: args[1].intVal.cint,
    blockNode: args[2].blockVal,
    interp: addr(interp)
  )
  proxy.keyHandlers.add(handler)

  debug("Registered key handler for keyval=", $args[0].intVal, " modifiers=", $args[1].intVal)

  nilValue()

## Native class method to get GDK key constants
proc eventControllerGetGdkKeyImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get GDK key value by name
  ## Supported: "d", "p", "Return", "Escape", "Tab", "Control"
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  let keyName = args[0].strVal

  case keyName:
    of "d", "D":
      return NodeValue(kind: vkInt, intVal: GDKKEYD.int)
    of "i", "I":
      return NodeValue(kind: vkInt, intVal: GDKKEYI.int)
    of "n", "N":
      return NodeValue(kind: vkInt, intVal: GDKKEYN.int)
    of "p", "P":
      return NodeValue(kind: vkInt, intVal: GDKKEYP.int)
    of "s", "S":
      return NodeValue(kind: vkInt, intVal: GDKKEYS.int)
    of "Return", "Enter":
      return NodeValue(kind: vkInt, intVal: GDKKEYRETURN.int)
    of "Escape":
      return NodeValue(kind: vkInt, intVal: GDKKEYESCAPE.int)
    of "Tab":
      return NodeValue(kind: vkInt, intVal: GDKKEYTAB.int)
    of "Control":
      return NodeValue(kind: vkInt, intVal: GDKCONTROLDMASK.int)
    else:
      return nilValue()

## Native class method to get GDK modifier mask for Control
proc eventControllerGetControlMaskImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get GDK_CONTROL_MASK value
  return NodeValue(kind: vkInt, intVal: GDKCONTROLDMASK.int)
