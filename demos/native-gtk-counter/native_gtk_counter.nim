## Native GTK4 shell for a Granite-compiled Harding model and event handlers.
## The build script stages this file beside counter_model.nim.
import std/[tables, os]
import ./counter_model
import ../../src/harding/runtime/compiled_support

{.passl: gorge("pkg-config --libs gtk4").}

type
  Widget = pointer
  Application = pointer
  Callback = proc(widget: pointer, data: pointer) {.cdecl.}
  DestroyNotify = proc(data: pointer, closure: pointer) {.cdecl.}

proc gtkApplicationNew(id: cstring, flags: cint): Application {.cdecl, importc: "gtk_application_new".}
proc gApplicationRun(app: Application, argc: cint, argv: pointer): cint {.cdecl, importc: "g_application_run".}
proc gApplicationQuit(app: Application) {.cdecl, importc: "g_application_quit".}
proc gApplicationHold(app: Application) {.cdecl, importc: "g_application_hold".}
proc gApplicationRelease(app: Application) {.cdecl, importc: "g_application_release".}
proc gObjectUnref(obj: pointer) {.cdecl, importc: "g_object_unref".}
proc gObjectRef(obj: pointer): pointer {.cdecl, importc: "g_object_ref".}
proc connectSignal(obj: pointer, name: cstring, callback: Callback, data: pointer,
                   destroy: DestroyNotify, flags: cint): culong {.cdecl, importc: "g_signal_connect_data".}
proc emitSignal(obj: pointer, name: cstring) {.cdecl, varargs, importc: "g_signal_emit_by_name".}
proc applicationWindow(app: Application): Widget {.cdecl, importc: "gtk_application_window_new".}
proc windowTitle(window: Widget, title: cstring) {.cdecl, importc: "gtk_window_set_title".}
proc windowSize(window: Widget, width, height: cint) {.cdecl, importc: "gtk_window_set_default_size".}
proc windowChild(window, child: Widget) {.cdecl, importc: "gtk_window_set_child".}
proc present(window: Widget) {.cdecl, importc: "gtk_window_present".}
proc destroyWindow(window: Widget) {.cdecl, importc: "gtk_window_destroy".}
proc newBox(orientation, spacing: cint): Widget {.cdecl, importc: "gtk_box_new".}
proc append(box, child: Widget) {.cdecl, importc: "gtk_box_append".}
proc newLabel(text: cstring): Widget {.cdecl, importc: "gtk_label_new".}
proc labelText(label: Widget, text: cstring) {.cdecl, importc: "gtk_label_set_text".}
proc labelText(label: Widget): cstring {.cdecl, importc: "gtk_label_get_text".}
proc newButton(text: cstring): Widget {.cdecl, importc: "gtk_button_new_with_label".}
proc timeout(milliseconds: cuint, callback: proc(data: pointer): cint {.cdecl.},
             data: pointer): cuint {.cdecl, importc: "g_timeout_add".}

type
  Connection = object
    callback: NodeValue
    view: Widget

var
  connections = initTable[int, Connection]()
  nextConnection = 0
  callbackFailures = 0
  exitCode = 0
  app: Application
  window, label, incrementButton, resetButton, errorButton: Widget
  model: NodeValue
  selfTest = false
  selfTestStage = 0
  destroyedConnections = 0

proc releaseConnection(data: pointer, closure: pointer) {.cdecl.} =
  try:
    let id = cast[int](data)
    if id in connections:
      let view = connections[id].view
      connections.del(id)
      gObjectUnref(view)
      inc destroyedConnections
  except Exception as failure:
    stderr.writeLine("Connection cleanup failed: " & failure.msg)
    exitCode = 1

proc onClick(widget: pointer, data: pointer) {.cdecl.} =
  ## No Harding transfer may unwind through GLib's C callback frames.
  try:
    let id = cast[int](data)
    if id notin connections: return
    let callback = connections[id].callback
    discard invokeCompiledBlock(callback.blockVal, @[])
  except CatchableError as failure:
    inc callbackFailures
    stderr.writeLine("Callback error: " & failure.msg)
  except Exception as failure:
    exitCode = 1
    stderr.writeLine("Callback defect: " & failure.msg)

proc connectButton(button: Widget, action: NodeValue) =
  if action.kind != vkBlock or action.blockVal == nil or action.blockVal.compiledInvoker == nil:
    raise newException(ValueError, "Expected a compiled Harding action")
  inc nextConnection
  discard gObjectRef(label)
  connections[nextConnection] = Connection(callback: action, view: label)
  discard connectSignal(button, "clicked", onClick, cast[pointer](nextConnection), releaseConnection, 0)

proc checkCount(expected: int) =
  let value = sendMessage(nil, model, "count", @[])
  if value.kind != vkInt or value.intVal != expected:
    raise newException(ValueError, "Unexpected counter value")
  if $labelText(label) != "Count: " & $expected:
    raise newException(ValueError, "Rendered GTK label does not match counter")
  if hybridInterpreter != nil or hybridScheduler != nil:
    raise newException(ValueError, "Demo unexpectedly initialized an interpreter")

proc advanceSelfTest(data: pointer): cint {.cdecl.} =
  try:
    case selfTestStage
    of 0:
      checkCount(0)
      emitSignal(incrementButton, "clicked")
      emitSignal(incrementButton, "clicked")
      checkCount(2)
      emitSignal(errorButton, "clicked")
      if callbackFailures != 1: raise newException(ValueError, "Expected exactly one callback error")
      emitSignal(incrementButton, "clicked")
      checkCount(3)
      emitSignal(resetButton, "clicked")
      checkCount(0)
      emitSignal(incrementButton, "clicked")
      checkCount(1)
      destroyWindow(window)
      window = nil
      label = nil
      inc selfTestStage
      return 1
    else:
      if connections.len != 0 or destroyedConnections != 3:
        raise newException(ValueError, "Signal closure owners were not released")
      if hybridInterpreter != nil: raise newException(ValueError, "Unexpected interpreter")
      echo "native GTK counter passed"
      gApplicationRelease(app)
      gApplicationQuit(app)
      return 0
  except Exception as failure:
    stderr.writeLine("Self-test failed: " & failure.msg)
    exitCode = 1
    gApplicationQuit(app)
    return 0

proc activate(application: pointer, data: pointer) {.cdecl.} =
  try:
    window = applicationWindow(application)
    windowTitle(window, "Harding — Native GTK Counter")
    windowSize(window, 360, 200)
    let box = newBox(1, 12)
    label = newLabel("")
    incrementButton = newButton("Increment")
    resetButton = newButton("Reset")
    errorButton = newButton("Test callback error")
    model = sendMessage(nil, compiledClassValue("CounterModel"), "new", @[])
    let view = NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject,
      class: compiledClassValue("CounterView").classVal, isNimProxy: true, nimValue: label))
    discard sendMessage(nil, model, "startOn:", @[view])
    connectButton(incrementButton, sendMessage(nil, model, "incrementAction", @[]))
    connectButton(resetButton, sendMessage(nil, model, "resetAction", @[]))
    connectButton(errorButton, sendMessage(nil, model, "failingAction", @[]))
    for child in [label, incrementButton, resetButton, errorButton]: append(box, child)
    windowChild(window, box)
    present(window)
    if selfTest:
      gApplicationHold(app)
      discard timeout(50, advanceSelfTest, nil)
  except Exception as failure:
    stderr.writeLine("Activation failed: " & failure.msg)
    exitCode = 1
    gApplicationQuit(application)

proc main(): int =
  selfTest = "--self-test" in commandLineParams()
  initRuntime()
  registerCompiledMethods()
  registerSuperclassHierarchy()
  registerCompiledClass("CounterModel", proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
    counter_model.toValue(newClass_436F756E7465724D6F64656C()))
  registerCompiledClass("CounterView", proc(self: NodeValue, args: seq[NodeValue]): NodeValue = nilValue())
  registerCompiledMethod("CounterView", "text:", proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
    labelText(self.instVal.nimValue, args[0].strVal.cstring)
    self)
  app = gtkApplicationNew("org.hardinglang.NativeCounter", 32) # G_APPLICATION_NON_UNIQUE
  discard connectSignal(app, "activate", activate, nil, nil, 0)
  let status = gApplicationRun(app, 0, nil)
  gObjectUnref(app)
  if exitCode != 0: return exitCode
  status.int

when isMainModule:
  quit(main())
