## Interpreter adapter for the same GTK protocol used by Granite --gtk.
import std/[tables, os, macros]
import ../../core/types
import ../../interpreter/[vm, objects]
import ./application_backend

proc interpretedCall(interp: var Interpreter, receiver: NodeValue,
                     selector: string, args: seq[NodeValue]): NodeValue =
  var classes = initTable[string, Class]()
  for name in gtkClasses:
    classes[name] = interp.globals[][name].classVal
  let host = interp
  proc dispatch(value: NodeValue, message: string, arguments: seq[NodeValue]): NodeValue =
    var argNodes: seq[Node]
    for argument in arguments: argNodes.add(LiteralNode(value: argument))
    var callbackHost = host
    evalCallbackNonFatal(callbackHost, MessageNode(receiver: LiteralNode(value: value),
      selector: message, arguments: argNodes))
  gtkCall(receiver, selector, args, dispatch, classes)

macro gtkAdapters(): untyped =
  result = newStmtList()
  let host = ident("interp")
  var installs = newStmtList()
  var index = 0
  for classSide in [false, true]:
    let protocol = if classSide: @gtkClassProtocol else: @gtkInstanceProtocol
    for (owner, selector) in protocol:
      let adapter = ident("gtkAdapter" & $index)
      inc index
      let ownerName = newLit(owner)
      let selectorName = newLit(selector)
      let side = newLit(classSide)
      result.add quote do:
        proc `adapter`(interp: var Interpreter, self: NodeValue,
                       args: seq[NodeValue]): NodeValue {.nimcall.} =
          interpretedCall(interp, self, `selectorName`, args)
      installs.add quote do:
        block:
          let cls = `host`.globals[][`ownerName`].classVal
          let meth = createCoreMethod(`selectorName`)
          meth.setNativeValueImpl(`adapter`)
          meth.hasInterpreterParam = true
          addMethodToClass(cls, `selectorName`, meth, isClassMethod = `side`)
  result.add quote do:
    proc installGtkPrimitives(`host`: var Interpreter) =
      `installs`

gtkAdapters()

proc registerGtkApplication*(interp: var Interpreter) =
  ## No display initialization occurs until GtkApplication run:activate:.
  let source = readFile(interp.hardingHome / "lib/gui/Gtk.hrd")
  let (_, error) = interp.evalStatements(source)
  if error.len > 0: raise newException(ValueError, error)
  installGtkPrimitives(interp)
