## Native registry adapter for the shared GTK application protocol.
import std/tables
import ../../runtime/compiled_support
import ./application_backend

var gtkTypes: Table[string, Class]

proc nativeDispatch(receiver: NodeValue, selector: string, args: seq[NodeValue]): NodeValue =
  sendMessage(currentRuntime[], receiver, selector, args)

proc implementation(selector: string): proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
  result = proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
    gtkCall(self, selector, args, nativeDispatch, gtkTypes)

proc registerNativeGtk*() =
  ## Call after generated method and hierarchy registration, before application code.
  for name in gtkClasses:
    registerCompiledClass(name, proc(self: NodeValue, args: seq[NodeValue]): NodeValue = nilValue())
    gtkTypes[name] = compiledClassValue(name).classVal
  registerSuperclass("GtkWidget", "Object")
  for name in ["GtkWindow", "GtkBox", "GtkLabel", "GtkButton"]:
    registerSuperclass(name, "GtkWidget")
  for (owner, selector) in gtkInstanceProtocol:
    registerCompiledMethod(owner, selector, implementation(selector))
  for (owner, selector) in gtkClassProtocol:
    registerCompiledClassMethod(owner, selector, implementation(selector))
