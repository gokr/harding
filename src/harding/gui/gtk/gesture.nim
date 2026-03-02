## ============================================================================
## GtkGestureClick - Right-click and gesture handling for GTK4
## ============================================================================

import std/[tables]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  GestureClickHandler* = object
    button*: cuint  # 1 = left, 2 = middle, 3 = right
    blockNode*: BlockNode
    interp*: ptr Interpreter

  GtkGestureClickProxyObj* = object of GtkWidgetProxyObj
    gestureHandlers*: seq[GestureClickHandler]

  GtkGestureClickProxy* = ref GtkGestureClickProxyObj

## Global table for gesture click controllers keyed by widget
var gestureClickTable* {.global.}: Table[GtkWidget, GtkGestureClickProxy] = initTable[GtkWidget, GtkGestureClickProxy]()

## C callback for gesture pressed events
proc gesturePressedCallback(gesture: GtkGestureClick, nPress: cint, x: cdouble, y: cdouble, userData: pointer) {.cdecl.} =
  ## Called when a gesture is pressed (button down)
  let widget = cast[GtkWidget](userData)

  if widget notin gestureClickTable:
    return

  let proxy = gestureClickTable[widget]
  if proxy.interp == nil:
    return

  # Get the button that triggered this
  # Note: GTK4 doesn't provide a direct getter, but we can infer from the gesture setup
  # For simplicity, we'll invoke all handlers and let them filter

  # Invoke handlers for this button
  for handler in proxy.gestureHandlers:
    try:
      GC_ref(handler.blockNode)

      # Create a Point-like array with x, y coordinates
      let pointArray = NodeValue(
        kind: vkArray,
        arrayVal: @[
          NodeValue(kind: vkFloat, floatVal: x),
          NodeValue(kind: vkFloat, floatVal: y)
        ]
      )

      let pointLiteral: Node = LiteralNode(value: pointArray)
      let msgNode = MessageNode(
        receiver: LiteralNode(value: NodeValue(kind: vkBlock, blockVal: handler.blockNode)),
        selector: "value:",
        arguments: @[pointLiteral],
        isCascade: false
      )
      discard evalWithVMCleanContext(proxy.interp[], msgNode)
      GC_unref(handler.blockNode)
    except Exception as e:
      error("Error in gesture click handler: ", e.msg)

## Native method: onRightClick: on GtkWidget
proc widgetOnRightClickImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Install a right-click handler on this widget
  ## The block receives an array with [x, y] coordinates
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkBlock:
      return nilValue()

    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let widget = cast[GtkWidget](self.nimValue)

    # Create gesture click controller
    let gestureClick = gtkGestureClickNew()
    if gestureClick == nil:
      warn("Failed to create gesture click controller")
      return nilValue()

    # Set to only trigger on right button (button 3)
    gtkGestureSingleSetButton(gestureClick, 3.cuint)

    # Add controller to widget
    gtkWidgetAddController(widget, cast[GtkEventController](gestureClick))

    # Create or get proxy for this widget
    var proxy: GtkGestureClickProxy
    if widget in gestureClickTable:
      proxy = gestureClickTable[widget]
    else:
      proxy = GtkGestureClickProxy(
        widget: widget,
        interp: addr(interp),
        signalHandlers: initTable[string, seq[SignalHandler]](),
        destroyed: false,
        gestureHandlers: @[]
      )
      gestureClickTable[widget] = proxy

    # Add the gesture handler
    let handler = GestureClickHandler(
      button: 3.cuint,  # Right button
      blockNode: args[0].blockVal,
      interp: addr(interp)
    )
    proxy.gestureHandlers.add(handler)

    # Connect the pressed signal
    discard gSignalConnect(cast[GObject](gestureClick), "pressed",
                           cast[GCallback](gesturePressedCallback), widget)

    debug("Installed right-click handler on widget")

  nilValue()
