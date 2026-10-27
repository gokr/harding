import std/unittest
import ../src/harding/runtime/compiled_support
import ../src/harding/gui/gtk/[native_application, application_backend]

var
  savedLabel: NodeValue
  clickCount = 0

proc clicked(): NodeValue {.cdecl.} =
  inc clickCount
  discard sendMessage(nil, savedLabel, "text:", @[toValue($clickCount)])
  nilValue()

proc failing(): NodeValue {.cdecl.} =
  raiseCompiledError(compiledErrorValue("Error", "native action failure"))

proc activated(): NodeValue {.cdecl.} =
  let window = sendMessage(nil, compiledClassValue("GtkWindow"), "new", @[])
  savedLabel = sendMessage(nil, compiledClassValue("GtkLabel"), "new", @[])
  let button = sendMessage(nil, compiledClassValue("GtkButton"), "new", @[])
  discard sendMessage(nil, button, "connect:do:", @[toValue("clicked"), createBlock0(clicked, 0)])
  discard sendMessage(nil, button, "emitSignal:", @[toValue("clicked")])
  doAssert sendMessage(nil, savedLabel, "text", @[]).strVal == "1"
  let errorButton = sendMessage(nil, compiledClassValue("GtkButton"), "new", @[])
  discard sendMessage(nil, errorButton, "connect:do:", @[toValue("clicked"), createBlock0(failing, 0)])
  discard sendMessage(nil, errorButton, "emitSignal:", @[toValue("clicked")])
  discard sendMessage(nil, button, "emitSignal:", @[toValue("clicked")])
  doAssert sendMessage(nil, savedLabel, "text", @[]).strVal == "2"
  discard sendMessage(nil, window, "close", @[])
  discard sendMessage(nil, compiledClassValue("GtkApplication"), "quit", @[])
  nilValue()

initRuntime()
registerNativeGtk()

suite "GTK native counterpart lifecycle":
  test "native callbacks recover from errors and all sessions release resources":
    for iteration in 0..<3:
      clickCount = 0
      let status = sendMessage(nil, compiledClassValue("GtkApplication"), "run:activate:",
        @[toValue("org.hardinglang.NativeBackendTest"), createBlock0(activated, 0)])
      check status.intVal == 1
      check clickCount == 2
      check gtkResourceCounts() == (0, 0, false)
      check hybridInterpreter == nil
      check hybridScheduler == nil
      expect ValueError:
        discard sendMessage(nil, savedLabel, "text", @[])
