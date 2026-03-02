## ============================================================================
## GtkListBoxProxy - List widget wrapper for GTK4
## ============================================================================

import std/[tables]
import harding/core/types
import ./ffi
import ./widget

type
  GtkListBoxProxyObj* = object of GtkWidgetProxyObj

  GtkListBoxProxy* = ref GtkListBoxProxyObj

proc newGtkListBoxProxy*(listBox: GtkListBox, interp: ptr Interpreter): GtkListBoxProxy =
  result = GtkListBoxProxy(
    widget: listBox,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](listBox)] = result

proc listBoxNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Class method: Create a new list box
  let listBox = gtkListBoxNew()
  discard newGtkListBoxProxy(listBox, addr(interp))

  var cls: Class = nil
  if "GtkListBox" in interp.globals[]:
    let val = interp.globals[]["GtkListBox"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil and "GtkWidget" in interp.globals[]:
    let val = interp.globals[]["GtkWidget"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil:
    cls = objectClass

  let obj = newInstance(cls)
  obj.isNimProxy = true
  storeInstanceWidget(obj, cast[GtkWidget](listBox))
  obj.nimValue = cast[pointer](listBox)
  return obj.toValue()

proc listBoxAppendImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Append a widget to the list
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let listBox = cast[GtkListBox](self.nimValue)
  let childInstance = args[0].instVal

  if childInstance.isNimProxy:
    var childWidget = getInstanceWidget(childInstance)
    if childWidget == nil and childInstance.nimValue != nil:
      childWidget = cast[GtkWidget](childInstance.nimValue)
    if childWidget != nil:
      gtkListBoxAppend(listBox, childWidget)
      debug("Appended widget to list box")

  nilValue()

proc listBoxPrependImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Prepend a widget to the list
  if args.len < 1 or args[0].kind != vkInstance:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let listBox = cast[GtkListBox](self.nimValue)
  let childInstance = args[0].instVal

  if childInstance.isNimProxy:
    var childWidget = getInstanceWidget(childInstance)
    if childWidget == nil and childInstance.nimValue != nil:
      childWidget = cast[GtkWidget](childInstance.nimValue)
    if childWidget != nil:
      gtkListBoxPrepend(listBox, childWidget)

  nilValue()

proc listBoxRemoveAllImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Remove all children from the list
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let listBox = cast[GtkListBox](self.nimValue)
  when not defined(gtk3):
    gtkListBoxRemoveAll(listBox)
  else:
    # GTK3 doesn't have remove_all, iterate and remove
    var row = gtkListBoxGetRowAtIndex(listBox, 0)
    while row != nil:
      gtkListBoxRemove(listBox, cast[GtkWidget](row))
      row = gtkListBoxGetRowAtIndex(listBox, 0)

  debug("Removed all items from list box")
  nilValue()

proc listBoxSetSelectionModeImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Set selection mode (0=none, 1=single, 2=multiple, 3=browse)
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let listBox = cast[GtkListBox](self.nimValue)
  let mode = args[0].intVal.cint
  gtkListBoxSetSelectionMode(listBox, mode)
  debug("Set list box selection mode to ", args[0].intVal)
  nilValue()

proc listBoxGetSelectedRowIndexImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Get index of selected row (-1 if none)
  if not (self.isNimProxy and self.nimValue != nil):
    return NodeValue(kind: vkInt, intVal: -1)

  let listBox = cast[GtkListBox](self.nimValue)
  let row = gtkListBoxGetSelectedRow(listBox)
  if row == nil:
    return NodeValue(kind: vkInt, intVal: -1)

  let idx = gtkListBoxRowGetIndex(row)
  return NodeValue(kind: vkInt, intVal: idx.int)

proc listBoxSelectRowAtIndexImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Instance method: Select row at given index
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let listBox = cast[GtkListBox](self.nimValue)
  let index = args[0].intVal.cint
  let row = gtkListBoxGetRowAtIndex(listBox, index)
  if row != nil:
    gtkListBoxSelectRow(listBox, row)
    debug("Selected row at index ", args[0].intVal)
  nilValue()
