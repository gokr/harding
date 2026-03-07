## ============================================================================
## GtkAlertDialog - Async dialog support for GTK4
## ============================================================================
## Provides native GTK4 AlertDialog with async callback support
## Uses a registry to map async operations to Harding blocks

import std/tables
import harding/core/types
import ./ffi
import ./widget

## Async callback registry - maps operation ID to (block, interpreter)
type
  AsyncDialogCallback* = object
    blockNode*: BlockNode
    interp*: Interpreter
    yesBlock*: BlockNode  # For yes/no dialogs
    noBlock*: BlockNode

var asyncDialogRegistry*: Table[int, AsyncDialogCallback] = initTable[int, AsyncDialogCallback]()
var asyncDialogIdCounter*: int = 0

## C callback for async dialog completion
proc alertDialogCallback*(sourceObject: pointer, result: pointer, userData: pointer) {.cdecl.} =
  ## GTK callback when dialog button is clicked
  let dialogId = cast[int](userData)

  if dialogId notin asyncDialogRegistry:
    warn("AlertDialog callback for unknown dialog ID: ", dialogId)
    return

  let callback = asyncDialogRegistry[dialogId]
  asyncDialogRegistry.del(dialogId)

  # Get the selected button index
  let dialog = cast[GtkAlertDialog](sourceObject)
  let buttonIndex = gtkAlertDialogChooseFinish(dialog, result)
  
  debug("AlertDialog callback: buttonIndex=", buttonIndex, " dialogId=", dialogId)

  # Schedule the appropriate block based on button clicked
  # For yes/no dialogs: 0 = yes, 1 = no, -1 = cancelled
  var blockToRun: BlockNode = nil

  if buttonIndex == 0 and callback.yesBlock != nil:
    debug("AlertDialog: running yesBlock")
    blockToRun = callback.yesBlock
  elif buttonIndex == 1 and callback.noBlock != nil:
    debug("AlertDialog: running noBlock")
    blockToRun = callback.noBlock
  elif callback.blockNode != nil:
    debug("AlertDialog: running response block")
    blockToRun = callback.blockNode
  else:
    debug("AlertDialog: no block to run (buttonIndex=", buttonIndex, ")")

  if blockToRun != nil and callback.interp != nil:
    debug("AlertDialog: executing block")
    try:
      GC_ref(blockToRun)
      invokeGtkCallbackBlock(addr(callback.interp), blockToRun, @[])
    except Exception as e:
      error("Error in AlertDialog callback: ", e.msg)
    finally:
      GC_unref(blockToRun)
  else:
    debug("AlertDialog: no block or interpreter (blockToRun=", cast[int](blockToRun), ", interp=", cast[int](callback.interp), ")")

## Native method: showAlertDialog:message:onResponse:
proc alertDialogShowImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Show an alert dialog with async callback
  ## Args: parent (GtkWindow or nil), message (String), onResponse (Block)
  if args.len < 3:
    return nilValue()

  if args[1].kind != vkString or args[2].kind != vkBlock:
    return nilValue()

  # Get parent window
  var parent: GtkWindow = nil
  if args[0].kind == vkInstance and args[0].instVal.isNimProxy and args[0].instVal.nimValue != nil:
    parent = cast[GtkWindow](args[0].instVal.nimValue)

  let message = args[1].strVal
  let responseBlock = args[2].blockVal

  # Create dialog
  let dialog = gtkAlertDialogNew(message.cstring)
  gtkAlertDialogSetModal(dialog, 1)

  # Register callback
  asyncDialogIdCounter += 1
  let dialogId = asyncDialogIdCounter
  asyncDialogRegistry[dialogId] = AsyncDialogCallback(
    blockNode: responseBlock,
    interp: interp
  )

  # Show dialog
  gtkAlertDialogChoose(dialog, parent, nil,
                       cast[pointer](alertDialogCallback),
                       cast[pointer](dialogId))

  nilValue()

## Native method: showConfirmDialog:message:onYes:onNo:
proc alertDialogConfirmImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Show a confirmation dialog with Yes/No buttons
  ## Args: parent (GtkWindow or nil), message (String), onYes (Block), onNo (Block)
  if args.len < 4:
    return nilValue()

  if args[1].kind != vkString or args[2].kind != vkBlock or args[3].kind != vkBlock:
    return nilValue()

  # Get parent window
  var parent: GtkWindow = nil
  if args[0].kind == vkInstance and args[0].instVal.isNimProxy and args[0].instVal.nimValue != nil:
    parent = cast[GtkWindow](args[0].instVal.nimValue)

  let message = args[1].strVal
  let yesBlock = args[2].blockVal
  let noBlock = args[3].blockVal

  # Create dialog with Yes/No buttons
  let dialog = gtkAlertDialogNew(message.cstring)
  gtkAlertDialogSetModal(dialog, 1)

  # Set up buttons (NULL-terminated array required by GTK)
  var labels: array[3, cstring] = [cstring"Yes", cstring"No", nil]
  gtkAlertDialogSetButtons(dialog, cast[cstringArray](addr(labels[0])), 2.csize_t)
  gtkAlertDialogSetCancelButton(dialog, 1)  # No is cancel
  gtkAlertDialogSetDefaultButton(dialog, 0)  # Yes is default

  # Register callback
  asyncDialogIdCounter += 1
  let dialogId = asyncDialogIdCounter
  asyncDialogRegistry[dialogId] = AsyncDialogCallback(
    yesBlock: yesBlock,
    noBlock: noBlock,
    interp: interp
  )

  # Show dialog
  gtkAlertDialogChoose(dialog, parent, nil,
                       cast[pointer](alertDialogCallback),
                       cast[pointer](dialogId))

  nilValue()
