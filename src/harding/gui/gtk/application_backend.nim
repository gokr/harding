## Shared GTK4 protocol backend. Contains no interpreter initialization.
import std/[tables, strutils]
import ../../core/types

{.passl: gorge("pkg-config --libs gtk4").}

type
  Callback = proc(widget, data: pointer) {.cdecl.}
  DestroyNotify = proc(data, closure: pointer) {.cdecl.}
  Dispatch* = proc(receiver: NodeValue, selector: string, args: seq[NodeValue]): NodeValue
  CallbackKind* = enum
    cbVoid, cbRowSelected, cbCloseRequest
  GtkAction = object
    blockValue: NodeValue
    invoke: Dispatch
    widget: pointer
    handler: culong
    kind: CallbackKind
  GtkOwnerObj = object of RootObj
    widget: pointer
  GtkOwner = ref GtkOwnerObj

proc applicationNew(id: cstring, flags: cint): pointer {.cdecl, importc: "gtk_application_new".}
proc validApplicationId(id: cstring): cint {.cdecl, importc: "g_application_id_is_valid".}
proc applicationRun(app: pointer, argc: cint, argv: pointer): cint {.cdecl, importc: "g_application_run".}
proc applicationQuit(app: pointer) {.cdecl, importc: "g_application_quit".}
proc objectRef(obj: pointer): pointer {.cdecl, importc: "g_object_ref_sink".}
proc objectUnref(obj: pointer) {.cdecl, importc: "g_object_unref".}
proc signalConnectRaw(obj: pointer, name: cstring, callback: pointer, data: pointer,
                      destroy: pointer, flags: cint): culong {.cdecl, importc: "g_signal_connect_data".}
proc signalEmit(obj: pointer, name: cstring) {.cdecl, varargs, importc: "g_signal_emit_by_name".}
proc signalDisconnect(obj: pointer, handler: culong) {.cdecl, importc: "g_signal_handler_disconnect".}
proc windowDestroy(obj: pointer) {.cdecl, importc: "gtk_window_destroy".}
proc windowNew(app: pointer): pointer {.cdecl, importc: "gtk_application_window_new".}
proc windowTitle(widget: pointer, text: cstring) {.cdecl, importc: "gtk_window_set_title".}
proc windowSize(widget: pointer, width, height: cint) {.cdecl, importc: "gtk_window_set_default_size".}
proc windowChild(widget, child: pointer) {.cdecl, importc: "gtk_window_set_child".}
proc windowPresent(widget: pointer) {.cdecl, importc: "gtk_window_present".}
proc windowClose(widget: pointer) {.cdecl, importc: "gtk_window_close".}
proc boxNew(orientation, spacing: cint): pointer {.cdecl, importc: "gtk_box_new".}
proc boxAppend(widget, child: pointer) {.cdecl, importc: "gtk_box_append".}
proc boxPrepend(widget, child: pointer) {.cdecl, importc: "gtk_box_prepend".}
proc boxRemove(widget, child: pointer) {.cdecl, importc: "gtk_box_remove".}
proc boxHomogeneous(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_box_set_homogeneous".}
proc boxSpacing(widget: pointer, spacing: cint) {.cdecl, importc: "gtk_box_set_spacing".}
proc labelNew(text: cstring): pointer {.cdecl, importc: "gtk_label_new".}
proc labelSet(widget: pointer, text: cstring) {.cdecl, importc: "gtk_label_set_text".}
proc labelGet(widget: pointer): cstring {.cdecl, importc: "gtk_label_get_text".}
proc labelWrap(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_label_set_wrap".}
proc labelSelectable(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_label_set_selectable".}
proc buttonNew(): pointer {.cdecl, importc: "gtk_button_new".}
proc buttonNewWithLabel(label: cstring): pointer {.cdecl, importc: "gtk_button_new_with_label".}
proc buttonNewFromIcon(icon: cstring): pointer {.cdecl, importc: "gtk_button_new_from_icon_name".}
proc buttonSetChild(button, child: pointer) {.cdecl, importc: "gtk_button_set_child".}
proc toggleButtonNew(): pointer {.cdecl, importc: "gtk_toggle_button_new".}
proc toggleButtonSetActive(widget: pointer, active: cint) {.cdecl, importc: "gtk_toggle_button_set_active".}
proc toggleButtonGetActive(widget: pointer): cint {.cdecl, importc: "gtk_toggle_button_get_active".}
proc imageNewFromIcon(icon: cstring): pointer {.cdecl, importc: "gtk_image_new_from_icon_name".}
proc imageSetPixelSize(image: pointer, size: cint) {.cdecl, importc: "gtk_image_set_pixel_size".}
proc widgetValign(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_valign".}
proc buttonSet(widget: pointer, text: cstring) {.cdecl, importc: "gtk_button_set_label".}
proc buttonGet(widget: pointer): cstring {.cdecl, importc: "gtk_button_get_label".}
proc entryNew(): pointer {.cdecl, importc: "gtk_entry_new".}
proc entrySet(widget: pointer, text: cstring) {.cdecl, importc: "gtk_editable_set_text".}
proc entryGet(widget: pointer): cstring {.cdecl, importc: "gtk_editable_get_text".}
proc entryPlaceholder(widget: pointer, text: cstring) {.cdecl, importc: "gtk_entry_set_placeholder_text".}
proc entryActivatesDefault(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_entry_set_activates_default".}
proc textViewNew(): pointer {.cdecl, importc: "gtk_text_view_new".}
proc textViewBuffer(view: pointer): pointer {.cdecl, importc: "gtk_text_view_get_buffer".}
proc textViewEditable(view: pointer, enabled: cint) {.cdecl, importc: "gtk_text_view_set_editable".}
proc textViewWrapMode(view: pointer, mode: cint) {.cdecl, importc: "gtk_text_view_set_wrap_mode".}
proc textBufferSet(buffer: pointer, text: cstring, length: cint) {.cdecl, importc: "gtk_text_buffer_set_text".}
proc textBufferGet(buffer: pointer, start, finish: pointer, includeHidden: cint): cstring {.cdecl, importc: "gtk_text_buffer_get_text".}
proc textBufferStart(buffer: pointer, iter: pointer) {.cdecl, importc: "gtk_text_buffer_get_start_iter".}
proc textBufferEnd(buffer: pointer, iter: pointer) {.cdecl, importc: "gtk_text_buffer_get_end_iter".}
proc textBufferCharCount(buffer: pointer): cint {.cdecl, importc: "gtk_text_buffer_get_char_count".}
proc scrolledNew(): pointer {.cdecl, importc: "gtk_scrolled_window_new".}
proc scrolledChild(widget, child: pointer) {.cdecl, importc: "gtk_scrolled_window_set_child".}
proc panedNew(orientation: cint): pointer {.cdecl, importc: "gtk_paned_new".}
proc panedStartChild(widget, child: pointer) {.cdecl, importc: "gtk_paned_set_start_child".}
proc panedEndChild(widget, child: pointer) {.cdecl, importc: "gtk_paned_set_end_child".}
proc panedPosition(widget: pointer, position: cint) {.cdecl, importc: "gtk_paned_set_position".}
proc panedResizeStart(widget: pointer, resize: cint) {.cdecl, importc: "gtk_paned_set_resize_start_child".}
proc panedResizeEnd(widget: pointer, resize: cint) {.cdecl, importc: "gtk_paned_set_resize_end_child".}
proc listBoxNew(): pointer {.cdecl, importc: "gtk_list_box_new".}
proc listBoxAppend(widget, child: pointer) {.cdecl, importc: "gtk_list_box_append".}
proc listBoxRowNew(): pointer {.cdecl, importc: "gtk_list_box_row_new".}
proc listBoxRowSetChild(row, child: pointer) {.cdecl, importc: "gtk_list_box_row_set_child".}
proc listBoxRemove(widget, child: pointer) {.cdecl, importc: "gtk_list_box_remove".}
proc listBoxSelectRow(widget: pointer, row: pointer) {.cdecl, importc: "gtk_list_box_select_row".}
proc listBoxSelectedRow(widget: pointer): pointer {.cdecl, importc: "gtk_list_box_get_selected_row".}
proc listBoxSelectionMode(widget: pointer, mode: cint) {.cdecl, importc: "gtk_list_box_set_selection_mode".}
proc listBoxRowAtIndex(widget: pointer, index: cint): pointer {.cdecl, importc: "gtk_list_box_get_row_at_index".}
proc widgetFirstChild(widget: pointer): pointer {.cdecl, importc: "gtk_widget_get_first_child".}
proc widgetNextSibling(widget: pointer): pointer {.cdecl, importc: "gtk_widget_get_next_sibling".}
proc widgetVisible(widget: pointer, visible: cint) {.cdecl, importc: "gtk_widget_set_visible".}
proc widgetSensitive(widget: pointer, sensitive: cint) {.cdecl, importc: "gtk_widget_set_sensitive".}
proc widgetFocus(widget: pointer) {.cdecl, importc: "gtk_widget_grab_focus".}
proc widgetTooltip(widget: pointer, text: cstring) {.cdecl, importc: "gtk_widget_set_tooltip_text".}
proc marginTop(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_top".}
proc marginBottom(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_bottom".}
proc marginStart(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_start".}
proc marginEnd(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_end".}
proc expandHorizontal(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_widget_set_hexpand".}
proc expandVertical(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_widget_set_vexpand".}
proc alignHorizontal(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_halign".}
proc cssAddClass(widget: pointer, name: cstring) {.cdecl, importc: "gtk_widget_add_css_class".}
proc cssRemoveClass(widget: pointer, name: cstring) {.cdecl, importc: "gtk_widget_remove_css_class".}

var
  actions = initTable[int, GtkAction]()
  nextAction = 0
  application: pointer
  activeClasses: Table[string, Class]
  owners: Table[pointer, GtkOwner]
  windows: seq[pointer]
  callbackFailed: bool

proc `=destroy`(owner: GtkOwnerObj) =
  if owner.widget != nil: objectUnref(owner.widget)

proc releaseAction(data, closure: pointer) {.cdecl.} =
  try:
    actions.del(cast[int](data))
  except Exception as failure:
    stderr.writeLine("GTK cleanup error: " & failure.msg)

proc releaseActionsFor(widget: pointer) =
  ## Disconnect and forget every handler bound to a widget that is going away.
  var ids: seq[int]
  for id, action in actions.pairs:
    if action.widget == widget: ids.add(id)
  for id in ids:
    if id notin actions: continue
    signalDisconnect(widget, actions[id].handler)
    actions.del(id)

proc releaseWidget(widget: pointer) =
  ## Drop the session's reference to a widget removed from its parent.
  releaseActionsFor(widget)
  if widget in owners:
    let owner = owners[widget]
    owners.del(widget)
    owner.widget = nil

proc runAction(widget: pointer, data: pointer, args: seq[NodeValue],
               holdOnFailure = true): bool =
  ## Returns the block's truthiness; failures never unwind into C frames.
  let id = cast[int](data)
  if id notin actions: return false
  let action = actions[id]
  try:
    let value = action.invoke(action.blockValue, "value", args)
    return value.kind == vkBool and value.boolVal
  except Exception as failure:
    callbackFailed = true
    stderr.writeLine("GTK callback error: " & failure.msg)
    if holdOnFailure and widget == application and application != nil:
      applicationQuit(application)
    return false

proc invokeAction(widget, data: pointer) {.cdecl.} =
  discard runAction(widget, data, @[])

proc invokeRowSelected(list: pointer, row: pointer, data: pointer) {.cdecl.} =
  var index = -1
  if row != nil:
    var child = widgetFirstChild(list)
    var offset = 0
    while child != nil:
      if child == row:
        index = offset
        break
      inc offset
      child = widgetNextSibling(child)
  discard runAction(list, data, @[toValue(index)])

proc invokeCloseRequest(window: pointer, data: pointer): cint {.cdecl.} =
  ## A handler answers true to allow the close; anything else vetoes it.
  if runAction(window, data, @[], holdOnFailure = false): return 0
  return 1

proc invokeBufferChanged(buffer: pointer, data: pointer) {.cdecl.} =
  discard runAction(buffer, data, @[])

proc connectAction(widget: pointer, name: string, blockValue: NodeValue, dispatch: Dispatch) =
  if blockValue.kind != vkBlock or blockValue.blockVal == nil:
    raise newException(ValueError, "GTK action must be a block")
  var kind: CallbackKind
  var expectedParameters = 0
  case name
  of "clicked", "activate", "changed", "toggled":
    kind = cbVoid
  of "row-selected":
    kind = cbRowSelected
    expectedParameters = 1
  of "close-request":
    kind = cbCloseRequest
  else:
    raise newException(ValueError, "Unsupported GTK callback signature: " & name)
  if blockValue.blockVal.parameters.len != expectedParameters:
    let shape = if expectedParameters == 0: "a zero-argument block" else: "a one-argument block"
    raise newException(ValueError, "GTK action for " & name & " must be " & shape)
  if nextAction == high(int):
    raise newException(ValueError, "GTK signal handle space exhausted")
  inc nextAction
  let id = nextAction
  actions[id] = GtkAction(blockValue: blockValue, invoke: dispatch, widget: widget, kind: kind)
  var handler: culong
  case kind
  of cbVoid:
    handler = signalConnectRaw(widget, name.cstring, cast[pointer](invokeAction), cast[pointer](id), cast[pointer](releaseAction), 0)
  of cbRowSelected:
    handler = signalConnectRaw(widget, name.cstring, cast[pointer](invokeRowSelected), cast[pointer](id), cast[pointer](releaseAction), 0)
  of cbCloseRequest:
    handler = signalConnectRaw(widget, name.cstring, cast[pointer](invokeCloseRequest), cast[pointer](id), cast[pointer](releaseAction), 0)
  if handler == 0:
    actions.del(id)
    raise newException(ValueError, "GTK signal connection failed")
  actions[id].handler = handler

proc trackWidget(widget: pointer, name: string): NodeValue =
  let owner = GtkOwner(widget: widget)
  owners[widget] = owner
  if name == "GtkWindow": windows.add(widget)
  NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject, class: activeClasses[name],
    isNimProxy: true, nimValue: widget, compiledOwner: owner))

proc wrapWidget(widget: pointer, name: string): NodeValue =
  if widget == nil: raise newException(ValueError, "GTK allocation failed")
  discard objectRef(widget)
  trackWidget(widget, name)

proc widgetPointer(value: NodeValue): pointer =
  if value.kind != vkInstance or value.instVal == nil or value.instVal.nimValue == nil or
     not (value.instVal.compiledOwner of GtkOwner):
    raise newException(ValueError, "Expected a GTK widget")
  let owner = GtkOwner(value.instVal.compiledOwner)
  if owner.widget == nil: raise newException(ValueError, "GTK widget belongs to a closed application")
  owner.widget

proc childWidget(value: NodeValue): pointer =
  widgetPointer(value)

proc requireConnected() =
  if application == nil:
    raise newException(ValueError, "Create GTK widgets in the activation block")

proc gtkResourceCounts*(): tuple[connections, widgets: int, running: bool] =
  ## Diagnostic snapshot used to validate deterministic host shutdown.
  (actions.len, owners.len, application != nil)

proc gtkLiveWidgets*(): int =
  ## Retained widget references (must be zero outside an application session).
  owners.len

proc validateCall(selector: string, args: seq[NodeValue]) =
  let arity = selector.count(':')
  if args.len != arity:
    raise newException(ValueError, "Wrong number of GTK arguments for " & selector)
  for index, argument in args:
    var expected = argument.kind
    case selector
    of "run:activate:":
      expected = if index == 0: vkString else: vkBlock
    of "connect:do:":
      expected = if index == 0: vkString else: vkBlock
    of "onRowSelected:", "onCloseRequest:", "onBufferChanged:", "toggled:":
      expected = vkBlock
    of "active:":
      expected = vkBool
    of "title:", "text:", "label:", "addCssClass:", "removeCssClass:", "emitSignal:",
       "placeholderText:", "setTooltipText:", "iconName:":
      expected = vkString
    of "setDefaultSize:height:", "newOrientation:spacing:", "newOrientation:",
       "marginTop:", "marginBottom:", "marginStart:", "marginEnd:",
       "setSpacing:", "setPosition:", "setSelectionMode:", "selectRowAtIndex:",
       "wrapMode:":
      expected = vkInt
    of "valign:":
      expected = vkInt
    of "setHexpand:", "setVexpand:", "homogeneous:", "wrap:", "selectable:",
       "activatesDefault:", "editable:", "setVisible:", "setSensitive:",
       "resizeStartChild:", "resizeEndChild:":
      expected = vkBool
    of "setChild:", "append:", "prepend:", "setStartChild:", "setEndChild:":
      expected = vkInstance
    else: discard
    if argument.kind != expected:
      raise newException(ValueError, "Wrong GTK argument type for " & selector)
  if selector in ["newOrientation:spacing:", "newOrientation:"]:
    if args[0].intVal notin 0..1:
      raise newException(ValueError, "Invalid GTK box orientation or spacing")
  if selector == "newOrientation:spacing:" and args[1].intVal < 0:
    raise newException(ValueError, "Invalid GTK box orientation or spacing")
  if selector in ["marginTop:", "marginBottom:", "marginStart:", "marginEnd:"] and args[0].intVal < 0:
    raise newException(ValueError, "GTK margins must be nonnegative")
  if selector == "setSelectionMode:" and args[0].intVal notin 0..3:
    raise newException(ValueError, "Invalid GTK selection mode")

proc removeChildren(widget: pointer, container: string) =
  ## Detach every child and drop the session's references to it, so repeated
  ## list rebuilds do not accumulate widget and callback owners.
  var children: seq[pointer]
  var child = widgetFirstChild(widget)
  while child != nil:
    children.add(child)
    child = widgetNextSibling(child)
  for item in children:
    if container == "list": listBoxRemove(widget, item)
    else: boxRemove(widget, item)
    releaseWidget(item)

proc textOf(buffer: pointer): string =
  # GtkTextIter is an opaque struct; 256 bytes matches textview.nim's storage.
  var startStorage: array[256, byte]
  var endStorage: array[256, byte]
  let start = cast[pointer](addr(startStorage[0]))
  let finish = cast[pointer](addr(endStorage[0]))
  textBufferStart(buffer, start)
  textBufferEnd(buffer, finish)
  let text = textBufferGet(buffer, start, finish, 0)
  if text == nil: return ""
  $text

proc setBufferText(buffer: pointer, text: cstring) =
  textBufferSet(buffer, text, -1)

proc newWidget(selector: string, args: seq[NodeValue], name: string): NodeValue =
  case name
  of "GtkWindow": wrapWidget(windowNew(application), name)
  of "GtkLabel": wrapWidget(labelNew(""), name)
  of "GtkButton": wrapWidget(buttonNew(), name)
  of "GtkToggleButton": wrapWidget(toggleButtonNew(), name)
  of "GtkEntry": wrapWidget(entryNew(), name)
  of "GtkTextView": wrapWidget(textViewNew(), name)
  of "GtkScrolledWindow": wrapWidget(scrolledNew(), name)
  of "GtkListBox": wrapWidget(listBoxNew(), name)
  of "GtkPaned":
    if selector == "new":
      raise newException(ValueError, "GtkPaned needs newOrientation:")
    wrapWidget(panedNew(args[0].intVal.cint), name)
  of "GtkBox":
    if selector == "newOrientation:":
      raise newException(ValueError, "GtkBox needs newOrientation:spacing:")
    wrapWidget(boxNew(if args.len == 0: 1 else: args[0].intVal.cint,
                      if args.len == 0: 0 else: args[1].intVal.cint), name)
  else: raise newException(ValueError, "Unknown GTK class: " & name)

proc runApplication(id, activation: NodeValue, dispatch: Dispatch,
                    classes: Table[string, Class]): NodeValue =
  if application != nil: raise newException(ValueError, "GTK application already running")
  if activation.blockVal == nil or activation.blockVal.parameters.len != 0:
    raise newException(ValueError, "GTK activation must be a zero-argument block")
  if validApplicationId(id.strVal.cstring) == 0 or '\0' in id.strVal:
    raise newException(ValueError, "Invalid GTK application ID")
  activeClasses = classes
  callbackFailed = false
  application = applicationNew(id.strVal.cstring, 32)
  if application == nil: raise newException(ValueError, "GTK application allocation failed")
  var status: cint
  try:
    connectAction(application, "activate", activation, dispatch)
    status = applicationRun(application, 0, nil)
  finally:
    var ids: seq[int]
    for id in actions.keys: ids.add(id)
    for id in ids:
      if id in actions:
        signalDisconnect(actions[id].widget, actions[id].handler)
    actions.clear()
    for window in windows: windowDestroy(window)
    windows.setLen(0)
    for owner in owners.values:
      if owner.widget != nil:
        objectUnref(owner.widget)
        owner.widget = nil
    owners.clear()
    objectUnref(application)
    application = nil
    activeClasses.clear()
  toValue(if callbackFailed: 1 else: status.int)

proc classCall(name, selector: string, args: seq[NodeValue], dispatch: Dispatch,
               classes: Table[string, Class]): NodeValue =
  case selector
  of "run:activate:":
    return runApplication(args[0], args[1], dispatch, classes)
  of "quit":
    if application != nil: applicationQuit(application)
    return nilValue()
  of "new", "newOrientation:spacing:", "newOrientation:":
    requireConnected()
    return newWidget(selector, args, name)
  else:
    raise newException(ValueError, "Unknown GTK class selector: " & selector)

proc instanceCall(receiver: NodeValue, widget: pointer, selector: string,
                  args: seq[NodeValue], dispatch: Dispatch): NodeValue =
  let className = receiver.instVal.class.name
  case selector
  of "title:": windowTitle(widget, args[0].strVal.cstring)
  of "setDefaultSize:height:": windowSize(widget, args[0].intVal.cint, args[1].intVal.cint)
  of "setChild:":
    if className == "GtkScrolledWindow": scrolledChild(widget, childWidget(args[0]))
    else: windowChild(widget, childWidget(args[0]))
  of "present": windowPresent(widget)
  of "close": windowClose(widget)
  of "onCloseRequest:": connectAction(widget, "close-request", args[0], dispatch)
  of "append:":
    if className == "GtkListBox":
      # gtk_list_box_append needs a GtkListBoxRow: a plain child renders at zero
      # size and is invisible to accessibility tooling.
      let row = listBoxRowNew()
      listBoxRowSetChild(row, childWidget(args[0]))
      listBoxAppend(widget, row)
    else: boxAppend(widget, childWidget(args[0]))
  of "prepend:": boxPrepend(widget, childWidget(args[0]))
  of "removeAll":
    removeChildren(widget, if className == "GtkListBox": "list" else: "box")
  of "homogeneous:": boxHomogeneous(widget, cint(args[0].boolVal))
  of "setSpacing:": boxSpacing(widget, args[0].intVal.cint)
  of "text:":
    case className
    of "GtkEntry": entrySet(widget, args[0].strVal.cstring)
    of "GtkTextView": setBufferText(textViewBuffer(widget), args[0].strVal.cstring)
    else: labelSet(widget, args[0].strVal.cstring)
  of "text":
    case className
    of "GtkEntry": return toValue($entryGet(widget))
    of "GtkTextView": return toValue(textOf(textViewBuffer(widget)))
    else: return toValue($labelGet(widget))
  of "wrap:": labelWrap(widget, cint(args[0].boolVal))
  of "selectable:": labelSelectable(widget, cint(args[0].boolVal))
  of "label:": buttonSet(widget, args[0].strVal.cstring)
  of "label": return toValue($buttonGet(widget))
  of "placeholderText:": entryPlaceholder(widget, args[0].strVal.cstring)
  of "activatesDefault:": entryActivatesDefault(widget, cint(args[0].boolVal))
  of "editable:": textViewEditable(widget, cint(args[0].boolVal))
  of "wrapMode:": textViewWrapMode(widget, args[0].intVal.cint)
  of "setStartChild:": panedStartChild(widget, childWidget(args[0]))
  of "setEndChild:": panedEndChild(widget, childWidget(args[0]))
  of "setPosition:": panedPosition(widget, args[0].intVal.cint)
  of "resizeStartChild:": panedResizeStart(widget, cint(args[0].boolVal))
  of "resizeEndChild:": panedResizeEnd(widget, cint(args[0].boolVal))
  of "selectedRowIndex":
    let row = listBoxSelectedRow(widget)
    if row == nil: return toValue(-1)
    var index = 0
    var child = widgetFirstChild(widget)
    while child != nil and child != row:
      inc index
      child = widgetNextSibling(child)
    return toValue(if child == nil: -1 else: index)
  of "selectRowAtIndex:":
    let row = listBoxRowAtIndex(widget, args[0].intVal.cint)
    if row != nil: listBoxSelectRow(widget, row)
  of "setSelectionMode:": listBoxSelectionMode(widget, args[0].intVal.cint)
  of "onRowSelected:": connectAction(widget, "row-selected", args[0], dispatch)
  of "onBufferChanged:": connectAction(textViewBuffer(widget), "changed", args[0], dispatch)
  of "connect:do:": connectAction(widget, args[0].strVal, args[1], dispatch)
  of "emitSignal:":
    if args[0].strVal notin ["clicked", "activate", "changed", "toggled"]:
      raise newException(ValueError, "Only clicked and changed emission is supported")
    signalEmit(widget, args[0].strVal.cstring)
  of "marginTop:": marginTop(widget, args[0].intVal.cint)
  of "marginBottom:": marginBottom(widget, args[0].intVal.cint)
  of "marginStart:": marginStart(widget, args[0].intVal.cint)
  of "marginEnd:": marginEnd(widget, args[0].intVal.cint)
  of "setHexpand:": expandHorizontal(widget, cint(args[0].boolVal))
  of "setVexpand:": expandVertical(widget, cint(args[0].boolVal))
  of "center": alignHorizontal(widget, 3)
  of "addCssClass:": cssAddClass(widget, args[0].strVal.cstring)
  of "removeCssClass:": cssRemoveClass(widget, args[0].strVal.cstring)
  of "setVisible:": widgetVisible(widget, cint(args[0].boolVal))
  of "setSensitive:": widgetSensitive(widget, cint(args[0].boolVal))
  of "grabFocus": widgetFocus(widget)
  of "setTooltipText:": widgetTooltip(widget, args[0].strVal.cstring)
  of "valign:": widgetValign(widget, args[0].intVal.cint)
  of "toggled:":
    connectAction(widget, "toggled", args[0], dispatch)
  of "active:":
    toggleButtonSetActive(widget, cint(args[0].boolVal))
  of "active":
    return toValue(toggleButtonGetActive(widget) != 0)
  of "iconName:":
    # Compose icon + existing caption so the button keeps its text.
    let content = boxNew(0, 6)
    widgetValign(content, 3)
    let icon = imageNewFromIcon(args[0].strVal.cstring)
    imageSetPixelSize(icon, 16)
    boxAppend(content, icon)
    let caption = buttonGet(widget)
    if caption != nil and ($caption).len > 0:
      boxAppend(content, labelNew(caption))
    buttonSetChild(widget, content)
  else: raise newException(ValueError, "Unknown GTK selector: " & selector)
  receiver

proc gtkCall*(receiver: NodeValue, selector: string, args: seq[NodeValue],
              dispatch: Dispatch, classes: Table[string, Class]): NodeValue =
  ## Common low-level implementation used by native and interpreted registration.
  validateCall(selector, args)
  if receiver.kind == vkClass:
    return classCall(receiver.classVal.name, selector, args, dispatch, classes)
  let widget = widgetPointer(receiver)
  instanceCall(receiver, widget, selector, args, dispatch)

const gtkClasses* = ["GtkApplication", "GtkWidget", "GtkWindow", "GtkBox", "GtkLabel",
  "GtkButton", "GtkToggleButton", "GtkEntry", "GtkTextView",
  "GtkScrolledWindow", "GtkPaned", "GtkListBox"]

const gtkInstanceProtocol* = [
  ("GtkWindow", "title:"), ("GtkWindow", "setDefaultSize:height:"),
  ("GtkWindow", "setChild:"), ("GtkWindow", "present"), ("GtkWindow", "close"),
  ("GtkWindow", "onCloseRequest:"),
  ("GtkBox", "append:"), ("GtkBox", "prepend:"), ("GtkBox", "removeAll"),
  ("GtkBox", "homogeneous:"), ("GtkBox", "setSpacing:"),
  ("GtkListBox", "append:"), ("GtkListBox", "removeAll"),
  ("GtkListBox", "selectedRowIndex"), ("GtkListBox", "selectRowAtIndex:"),
  ("GtkListBox", "setSelectionMode:"), ("GtkListBox", "onRowSelected:"),
  ("GtkLabel", "text:"), ("GtkLabel", "text"), ("GtkLabel", "wrap:"),
  ("GtkLabel", "selectable:"),
  ("GtkButton", "label:"), ("GtkButton", "label"), ("GtkButton", "iconName:"),
  ("GtkToggleButton", "label:"), ("GtkToggleButton", "label"),
  ("GtkToggleButton", "iconName:"), ("GtkToggleButton", "active"),
  ("GtkToggleButton", "active:"), ("GtkToggleButton", "toggled:"),
  ("GtkEntry", "text:"), ("GtkEntry", "text"), ("GtkEntry", "placeholderText:"),
  ("GtkEntry", "activatesDefault:"), ("GtkEntry", "connect:do:"),
  ("GtkTextView", "text:"), ("GtkTextView", "text"), ("GtkTextView", "editable:"),
  ("GtkTextView", "wrapMode:"), ("GtkTextView", "onBufferChanged:"),
  ("GtkScrolledWindow", "setChild:"),
  ("GtkPaned", "setStartChild:"), ("GtkPaned", "setEndChild:"),
  ("GtkPaned", "setPosition:"), ("GtkPaned", "resizeStartChild:"),
  ("GtkPaned", "resizeEndChild:"),
  ("GtkWidget", "connect:do:"), ("GtkWidget", "emitSignal:"),
  ("GtkWidget", "marginTop:"), ("GtkWidget", "marginBottom:"),
  ("GtkWidget", "marginStart:"), ("GtkWidget", "marginEnd:"),
  ("GtkWidget", "setHexpand:"), ("GtkWidget", "setVexpand:"), ("GtkWidget", "valign:"),
  ("GtkWidget", "center"), ("GtkWidget", "addCssClass:"),
  ("GtkWidget", "removeCssClass:"), ("GtkWidget", "setVisible:"),
  ("GtkWidget", "setSensitive:"), ("GtkWidget", "grabFocus"),
  ("GtkWidget", "setTooltipText:")]

const gtkClassProtocol* = [("GtkApplication", "run:activate:"), ("GtkApplication", "quit"),
  ("GtkWindow", "new"), ("GtkLabel", "new"), ("GtkButton", "new"),
  ("GtkToggleButton", "new"), ("GtkEntry", "new"),
  ("GtkTextView", "new"), ("GtkScrolledWindow", "new"), ("GtkListBox", "new"),
  ("GtkPaned", "newOrientation:"),
  ("GtkBox", "new"), ("GtkBox", "newOrientation:spacing:")]
