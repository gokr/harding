## Shared GTK4 protocol backend. Contains no interpreter initialization.
import std/[tables, strutils]
import ../../core/types

{.passl: gorge("pkg-config --libs gtk4").}

type
  Callback = proc(widget, data: pointer) {.cdecl.}
  DestroyNotify = proc(data, closure: pointer) {.cdecl.}
  Dispatch* = proc(receiver: NodeValue, selector: string, args: seq[NodeValue]): NodeValue
  GtkAction = object
    blockValue: NodeValue
    invoke: Dispatch
    widget: pointer
    handler: culong
  GtkOwnerObj = object of RootObj
    widget: pointer
  GtkOwner = ref GtkOwnerObj

proc applicationNew(id: cstring, flags: cint): pointer {.cdecl, importc: "gtk_application_new".}
proc validApplicationId(id: cstring): cint {.cdecl, importc: "g_application_id_is_valid".}
proc applicationRun(app: pointer, argc: cint, argv: pointer): cint {.cdecl, importc: "g_application_run".}
proc applicationQuit(app: pointer) {.cdecl, importc: "g_application_quit".}
proc objectRef(obj: pointer): pointer {.cdecl, importc: "g_object_ref_sink".}
proc objectUnref(obj: pointer) {.cdecl, importc: "g_object_unref".}
proc signalConnect(obj: pointer, name: cstring, callback: Callback, data: pointer,
                   destroy: DestroyNotify, flags: cint): culong {.cdecl, importc: "g_signal_connect_data".}
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
proc boxHomogeneous(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_box_set_homogeneous".}
proc labelNew(text: cstring): pointer {.cdecl, importc: "gtk_label_new".}
proc labelSet(widget: pointer, text: cstring) {.cdecl, importc: "gtk_label_set_text".}
proc labelGet(widget: pointer): cstring {.cdecl, importc: "gtk_label_get_text".}
proc labelWrap(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_label_set_wrap".}
proc buttonNew(): pointer {.cdecl, importc: "gtk_button_new".}
proc buttonSet(widget: pointer, text: cstring) {.cdecl, importc: "gtk_button_set_label".}
proc buttonGet(widget: pointer): cstring {.cdecl, importc: "gtk_button_get_label".}
proc marginTop(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_top".}
proc marginBottom(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_bottom".}
proc marginStart(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_start".}
proc marginEnd(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_margin_end".}
proc expandHorizontal(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_widget_set_hexpand".}
proc expandVertical(widget: pointer, enabled: cint) {.cdecl, importc: "gtk_widget_set_vexpand".}
proc alignHorizontal(widget: pointer, value: cint) {.cdecl, importc: "gtk_widget_set_halign".}
proc cssClass(widget: pointer, name: cstring) {.cdecl, importc: "gtk_widget_add_css_class".}

var
  actions = initTable[int, GtkAction]()
  nextAction = 0
  application: pointer
  activeClasses: Table[string, Class]
  owners: seq[GtkOwner]
  windows: seq[pointer]
  callbackFailed: bool

proc `=destroy`(owner: GtkOwnerObj) =
  if owner.widget != nil: objectUnref(owner.widget)

proc releaseAction(data, closure: pointer) {.cdecl.} =
  try:
    actions.del(cast[int](data))
  except Exception as failure:
    stderr.writeLine("GTK cleanup error: " & failure.msg)

proc invokeAction(widget, data: pointer) {.cdecl.} =
  try:
    let id = cast[int](data)
    if id notin actions: return
    let action = actions[id]
    discard action.invoke(action.blockValue, "value", @[])
  except Exception as failure:
    callbackFailed = true
    stderr.writeLine("GTK callback error: " & failure.msg)
    if widget == application and application != nil:
      applicationQuit(application)

proc connectAction(widget: pointer, name: string, blockValue: NodeValue, dispatch: Dispatch) =
  if blockValue.kind != vkBlock or blockValue.blockVal == nil or blockValue.blockVal.parameters.len != 0:
    raise newException(ValueError, "GTK action must be a zero-argument block")
  if name notin ["clicked", "activate"]:
    raise newException(ValueError, "Unsupported GTK callback signature: " & name)
  if nextAction == high(int):
    raise newException(ValueError, "GTK signal handle space exhausted")
  inc nextAction
  let id = nextAction
  actions[id] = GtkAction(blockValue: blockValue, invoke: dispatch, widget: widget)
  let handler = signalConnect(widget, name.cstring, invokeAction, cast[pointer](id), releaseAction, 0)
  if handler == 0:
    actions.del(id)
    raise newException(ValueError, "GTK signal connection failed")
  actions[id].handler = handler

proc wrapWidget(widget: pointer, name: string): NodeValue =
  if widget == nil: raise newException(ValueError, "GTK allocation failed")
  discard objectRef(widget)
  let owner = GtkOwner(widget: widget)
  owners.add(owner)
  if name == "GtkWindow": windows.add(widget)
  NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject, class: activeClasses[name],
    isNimProxy: true, nimValue: widget, compiledOwner: owner))

proc widgetPointer(value: NodeValue): pointer =
  if value.kind != vkInstance or value.instVal == nil or value.instVal.nimValue == nil or
     not (value.instVal.compiledOwner of GtkOwner):
    raise newException(ValueError, "Expected a GTK widget")
  let owner = GtkOwner(value.instVal.compiledOwner)
  if owner.widget == nil: raise newException(ValueError, "GTK widget belongs to a closed application")
  owner.widget

proc gtkResourceCounts*(): tuple[connections, widgets: int, running: bool] =
  ## Diagnostic snapshot used to validate deterministic host shutdown.
  (actions.len, owners.len, application != nil)

proc validateCall(selector: string, args: seq[NodeValue]) =
  let arity = selector.count(':')
  if args.len != arity:
    raise newException(ValueError, "Wrong number of GTK arguments for " & selector)
  for index, argument in args:
    let expected = case selector
      of "run:activate:", "connect:do:":
        if index == 0: vkString else: vkBlock
      of "title:", "text:", "label:", "addCssClass:", "emitSignal:": vkString
      of "setDefaultSize:height:", "newOrientation:spacing:", "marginTop:", "marginBottom:", "marginStart:", "marginEnd:": vkInt
      of "setHexpand:", "setVexpand:", "homogeneous:", "wrap:": vkBool
      of "setChild:", "append:": vkInstance
      else: argument.kind
    if argument.kind != expected:
      raise newException(ValueError, "Wrong GTK argument type for " & selector)
  if selector == "newOrientation:spacing:":
    if args[0].intVal notin 0..1 or args[1].intVal < 0:
      raise newException(ValueError, "Invalid GTK box orientation or spacing")
  if selector in ["marginTop:", "marginBottom:", "marginStart:", "marginEnd:"] and args[0].intVal < 0:
    raise newException(ValueError, "GTK margins must be nonnegative")

proc gtkCall*(receiver: NodeValue, selector: string, args: seq[NodeValue],
              dispatch: Dispatch, classes: Table[string, Class]): NodeValue =
  ## Common low-level implementation used by native and interpreted registration.
  validateCall(selector, args)
  if receiver.kind == vkClass:
    let name = receiver.classVal.name
    case selector
    of "run:activate:":
      if application != nil: raise newException(ValueError, "GTK application already running")
      if args[1].blockVal == nil or args[1].blockVal.parameters.len != 0:
        raise newException(ValueError, "GTK activation must be a zero-argument block")
      if validApplicationId(args[0].strVal.cstring) == 0 or '\0' in args[0].strVal:
        raise newException(ValueError, "Invalid GTK application ID")
      activeClasses = classes
      callbackFailed = false
      application = applicationNew(args[0].strVal.cstring, 32)
      if application == nil: raise newException(ValueError, "GTK application allocation failed")
      var status: cint
      try:
        connectAction(application, "activate", args[1], dispatch)
        status = applicationRun(application, 0, nil)
      finally:
        var ids: seq[int]
        for id in actions.keys: ids.add(id)
        for id in ids:
          if id in actions:
            signalDisconnect(actions[id].widget, actions[id].handler)
        for window in windows: windowDestroy(window)
        windows.setLen(0)
        for owner in owners:
          objectUnref(owner.widget)
          owner.widget = nil
        owners.setLen(0)
        objectUnref(application)
        application = nil
        activeClasses.clear()
      return toValue(if callbackFailed: 1 else: status.int)
    of "quit":
      if application != nil: applicationQuit(application)
      return receiver
    of "new", "newOrientation:spacing:":
      if application == nil: raise newException(ValueError, "Create GTK widgets in the activation block")
      case name
      of "GtkWindow": return wrapWidget(windowNew(application), name)
      of "GtkLabel": return wrapWidget(labelNew(""), name)
      of "GtkButton": return wrapWidget(buttonNew(), name)
      of "GtkBox":
        return wrapWidget(boxNew(if args.len == 0: 1 else: args[0].intVal.cint,
                                 if args.len == 0: 0 else: args[1].intVal.cint), name)
      else: raise newException(ValueError, "Unknown GTK class: " & name)
    else: raise newException(ValueError, "Unknown GTK class selector: " & selector)
  let widget = widgetPointer(receiver)
  case selector
  of "title:": windowTitle(widget, args[0].strVal.cstring)
  of "setDefaultSize:height:": windowSize(widget, args[0].intVal.cint, args[1].intVal.cint)
  of "setChild:": windowChild(widget, widgetPointer(args[0]))
  of "present": windowPresent(widget)
  of "close": windowClose(widget)
  of "append:": boxAppend(widget, widgetPointer(args[0]))
  of "homogeneous:": boxHomogeneous(widget, cint(args[0].boolVal))
  of "text:": labelSet(widget, args[0].strVal.cstring)
  of "text": return toValue($labelGet(widget))
  of "wrap:": labelWrap(widget, cint(args[0].boolVal))
  of "label:": buttonSet(widget, args[0].strVal.cstring)
  of "label": return toValue($buttonGet(widget))
  of "connect:do:": connectAction(widget, args[0].strVal, args[1], dispatch)
  of "emitSignal:":
    if args[0].strVal != "clicked": raise newException(ValueError, "Only clicked emission is supported")
    signalEmit(widget, "clicked")
  of "marginTop:": marginTop(widget, args[0].intVal.cint)
  of "marginBottom:": marginBottom(widget, args[0].intVal.cint)
  of "marginStart:": marginStart(widget, args[0].intVal.cint)
  of "marginEnd:": marginEnd(widget, args[0].intVal.cint)
  of "setHexpand:": expandHorizontal(widget, cint(args[0].boolVal))
  of "setVexpand:": expandVertical(widget, cint(args[0].boolVal))
  of "center": alignHorizontal(widget, 3)
  of "addCssClass:": cssClass(widget, args[0].strVal.cstring)
  else: raise newException(ValueError, "Unknown GTK selector: " & selector)
  receiver

const gtkClasses* = ["GtkApplication", "GtkWidget", "GtkWindow", "GtkBox", "GtkLabel", "GtkButton"]
const gtkInstanceProtocol* = [
  ("GtkWindow", "title:"), ("GtkWindow", "setDefaultSize:height:"),
  ("GtkWindow", "setChild:"), ("GtkWindow", "present"), ("GtkWindow", "close"),
  ("GtkBox", "append:"), ("GtkBox", "homogeneous:"),
  ("GtkLabel", "text:"), ("GtkLabel", "text"), ("GtkLabel", "wrap:"),
  ("GtkButton", "label:"), ("GtkButton", "label"),
  ("GtkWidget", "connect:do:"), ("GtkWidget", "emitSignal:"),
  ("GtkWidget", "marginTop:"), ("GtkWidget", "marginBottom:"),
  ("GtkWidget", "marginStart:"), ("GtkWidget", "marginEnd:"),
  ("GtkWidget", "setHexpand:"), ("GtkWidget", "setVexpand:"),
  ("GtkWidget", "center"), ("GtkWidget", "addCssClass:")]
const gtkClassProtocol* = [("GtkApplication", "run:activate:"), ("GtkApplication", "quit"),
  ("GtkWindow", "new"), ("GtkLabel", "new"), ("GtkButton", "new"),
  ("GtkBox", "new"), ("GtkBox", "newOrientation:spacing:")]
