## ============================================================================
## GtkPopover - Custom popup menus for GTK4
## Uses GtkPopover with button content instead of GMenu actions
## ============================================================================

import std/[logging, tables, strformat]
import harding/core/types
import harding/interpreter/vm
import ./ffi
import ./widget

type
  PopoverMenuItem* = object
    label*: string
    blockNode*: BlockNode
    interp*: ptr Interpreter

  GtkPopoverProxyObj* = object of GtkWidgetProxyObj
    menuItems*: seq[PopoverMenuItem]
    parentWidget*: GtkWidget
    contentBox*: GtkBox

  GtkPopoverProxy* = ref GtkPopoverProxyObj

## Global table for popover proxies keyed by parent widget
## This enables caching of popover instances
var popoverTable* {.global.}: Table[GtkWidget, GtkPopoverProxy] = initTable[GtkWidget, GtkPopoverProxy]()

## C callback for menu item clicks
proc menuItemCallback(widget: GtkWidget, userData: pointer) {.cdecl.} =
  ## Called when a menu item button is clicked
  let itemIndex = cast[int](userData)

  # Find the popover that owns this menu item
  for parentWidget, proxy in popoverTable:
    if itemIndex >= 0 and itemIndex < proxy.menuItems.len:
      let item = proxy.menuItems[itemIndex]
      if item.blockNode != nil and item.interp != nil:
        try:
          GC_ref(item.blockNode)
          let msgNode = MessageNode(
            receiver: LiteralNode(value: NodeValue(kind: vkBlock, blockVal: item.blockNode)),
            selector: "value",
            arguments: @[],
            isCascade: false
          )
          discard evalWithVMCleanContext(item.interp[], msgNode)
          GC_unref(item.blockNode)
        except Exception as e:
          error("Error in menu item callback: ", e.msg)

        # Hide the popover after selection
        let popover = cast[GtkPopover](proxy.widget)
        gtkPopoverPopdown(popover)
        return

## Native method: popoverNew - Create a new popover menu for a parent widget
proc popoverNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Create a new popover menu attached to a parent widget
  ## Args: parent widget (GtkWidget)
  ## Returns: popover proxy instance
  when not defined(gtk3):
    if args.len < 1 or args[0].kind != vkInstance or not args[0].instVal.isNimProxy or args[0].instVal.nimValue == nil:
      return nilValue()

    let parentWidget = cast[GtkWidget](args[0].instVal.nimValue)

    # Check if we already have a cached popover for this parent
    if parentWidget in popoverTable:
      # Return existing popover
      let proxy = popoverTable[parentWidget]
      let popoverClass = self.class
      let obj = newInstance(popoverClass)
      obj.isNimProxy = true
      storeInstanceWidget(obj, proxy.widget)
      obj.nimValue = cast[pointer](proxy.widget)
      return obj.toValue()

    # Create new popover
    let popover = gtkPopoverNew()
    if popover == nil:
      warn("Failed to create popover")
      return nilValue()

    # Set parent widget using generic widget method
    gtkWidgetSetParent(cast[GtkWidget](popover), parentWidget)

    # Create content box (vertical)
    let contentBox = gtkBoxNew(1.cint, 4.cint)  # Vertical, 4px spacing

    # Set content box as child
    gtkPopoverSetChild(popover, cast[GtkWidget](contentBox))

    # Create proxy and store in global table
    let proxy = GtkPopoverProxy(
      widget: cast[GtkWidget](popover),
      interp: addr(interp),
      signalHandlers: initTable[string, seq[SignalHandler]](),
      destroyed: false,
      menuItems: @[],
      parentWidget: parentWidget,
      contentBox: contentBox
    )
    popoverTable[parentWidget] = proxy

    # Create instance
    let popoverClass = self.class
    let obj = newInstance(popoverClass)
    obj.isNimProxy = true
    storeInstanceWidget(obj, cast[GtkWidget](popover))
    obj.nimValue = cast[pointer](popover)

    debug("Created new popover menu for widget")
    return obj.toValue()

  else:
    return nilValue()

## Native method: addItem:do: - Add a menu item with callback
proc popoverAddItemDoImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Add a menu item to the popover
  ## Args: label (String), callback block
  when not defined(gtk3):
    if args.len < 2 or args[0].kind != vkString or args[1].kind != vkBlock:
      return nilValue()

    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let popover = cast[GtkPopover](self.nimValue)

    # Find the proxy for this popover
    var proxy: GtkPopoverProxy = nil
    for parentWidget, p in popoverTable:
      if p.widget == cast[GtkWidget](popover):
        proxy = p
        break

    if proxy == nil:
      warn("Popover proxy not found")
      return nilValue()

    # Create menu item button
    let label = args[0].strVal
    let button = gtkButtonNewWithLabel(label.cstring)

    # Add CSS class for menu item styling
    gtkWidgetAddCssClass(cast[GtkWidget](button), "flat".cstring)

    # Add to content box
    gtkBoxAppend(proxy.contentBox, cast[GtkWidget](button))

    # Store menu item with callback
    let itemIndex = proxy.menuItems.len
    let item = PopoverMenuItem(
      label: label,
      blockNode: args[1].blockVal,
      interp: addr(interp)
    )
    proxy.menuItems.add(item)

    # Connect clicked signal
    let gObject = cast[GObject](button)
    discard gSignalConnect(gObject, "clicked",
                           cast[GCallback](menuItemCallback), cast[pointer](itemIndex))

    debug(fmt("Added menu item: {label}"))

  nilValue()

## Native method: popupAtX:Y: - Show popover at specific coordinates
proc popoverPopupAtXYImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Show the popover at specific coordinates relative to parent
  ## Args: x (Number), y (Number)
  when not defined(gtk3):
    if args.len < 2 or (args[0].kind != vkInt and args[0].kind != vkFloat) or
       (args[1].kind != vkInt and args[1].kind != vkFloat):
      return nilValue()

    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let popover = cast[GtkPopover](self.nimValue)

    # Get coordinates
    var x, y: cint
    if args[0].kind == vkInt:
      x = args[0].intVal.cint
    else:
      x = args[0].floatVal.cint

    if args[1].kind == vkInt:
      y = args[1].intVal.cint
    else:
      y = args[1].floatVal.cint

    # Create rectangle for positioning
    var rect = GdkRectangle(
      x: x,
      y: y,
      width: 1,
      height: 1
    )

    # Set positioning
    gtkPopoverSetPointingTo(popover, addr(rect))
    gtkPopoverSetHasArrow(popover, 0)  # No arrow for context menu
    gtkPopoverSetAutohide(popover, 1)  # Auto-hide when clicking outside

    # Show popover
    gtkPopoverPopup(popover)

    debug(fmt("Shown popover at {x},{y}"))

  nilValue()

## Native method: popup - Show popover for parent widget
proc popoverPopupImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Show the popover positioned relative to its parent
  when not defined(gtk3):
    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let popover = cast[GtkPopover](self.nimValue)

    # Use default positioning (centered on parent)
    gtkPopoverSetHasArrow(popover, 1)  # Show arrow
    gtkPopoverSetAutohide(popover, 1)    # Auto-hide when clicking outside

    # Show popover
    gtkPopoverPopup(popover)

    debug("Shown popover with default positioning")

  nilValue()

## Native method: clear - Remove all menu items
proc popoverClearImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Remove all menu items from the popover
  when not defined(gtk3):
    if not (self.isNimProxy and self.nimValue != nil):
      return nilValue()

    let popover = cast[GtkPopover](self.nimValue)

    # Find the proxy for this popover
    var proxy: GtkPopoverProxy = nil
    for parentWidget, p in popoverTable:
      if p.widget == cast[GtkWidget](popover):
        proxy = p
        break

    if proxy == nil:
      return nilValue()

    # Clear menu items
    proxy.menuItems = @[]

    # Remove all children from content box by recreating it
    let newContentBox = gtkBoxNew(1.cint, 4.cint)
    gtkPopoverSetChild(popover, cast[GtkWidget](newContentBox))
    proxy.contentBox = newContentBox

    debug("Cleared all menu items from popover")

  nilValue()
