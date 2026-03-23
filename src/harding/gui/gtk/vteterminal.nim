## ============================================================================
## VteTerminalProxy - Native terminal widget wrapper
## ============================================================================

import std/[os, tables]
import harding/core/types
import ./ffi
import ./widget

proc nodeValueToStringArg(val: NodeValue): string =
  case val.kind
  of vkString:
    val.strVal
  of vkInstance:
    if val.instVal != nil and val.instVal.kind == ikString:
      val.instVal.strVal
    else:
      ""
  else:
    ""

type
  VteTerminalProxyObj* = object of GtkWidgetProxyObj

  VteTerminalProxy* = ref VteTerminalProxyObj

proc newVteTerminalProxy*(widget: VteTerminal,
                          interp: ptr Interpreter): VteTerminalProxy =
  result = VteTerminalProxy(
    widget: cast[GtkWidget](widget),
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    connectedSignals: initTable[string, bool](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

proc terminalWidget(self: Instance): VteTerminal =
  if not (self.isNimProxy and self.nimValue != nil):
    return nil
  cast[VteTerminal](self.nimValue)

proc spawnTerminalProcess(widget: VteTerminal, workingDirectory: string,
                          argv: var seq[cstring]) =
  vteTerminalSpawnAsync(
    widget,
    VTEPTYDEFAULT,
    workingDirectory.cstring,
    cast[ptr cstring](addr(argv[0])),
    nil,
    GSPAWNDEFAULT,
    nil,
    nil,
    nil,
    -1,
    nil,
    nil,
    nil
  )

proc vteTerminalNewImpl*(interp: var Interpreter, self: Instance,
                         args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard self
  discard args

  let widget = vteTerminalNew()
  discard newVteTerminalProxy(widget, addr(interp))

  var cls: Class = nil
  if "VteTerminal" in interp.globals[]:
    let val = interp.globals[]["VteTerminal"]
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
  storeInstanceWidget(obj, cast[GtkWidget](widget))
  obj.nimValue = cast[pointer](widget)
  obj.toValue()

proc vteTerminalSpawnShellInImpl*(interp: var Interpreter, self: Instance,
                                  args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp

  let widget = terminalWidget(self)
  if widget == nil:
    return nilValue()

  var workingDirectory = getCurrentDir()
  if args.len > 0:
    let requestedDirectory = nodeValueToStringArg(args[0])
    if requestedDirectory.len > 0 and dirExists(requestedDirectory):
      workingDirectory = requestedDirectory

  let shellPath = getEnv("SHELL", "/bin/sh")
  var argv = @[shellPath.cstring, nil]

  spawnTerminalProcess(widget, workingDirectory, argv)

  nilValue()

proc vteTerminalSpawnCommandInImpl*(interp: var Interpreter, self: Instance,
                                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp

  let widget = terminalWidget(self)
  if widget == nil or args.len < 2:
    return nilValue()

  let commandString = nodeValueToStringArg(args[0])
  if commandString.len == 0:
    return nilValue()

  var workingDirectory = getCurrentDir()
  let requestedDirectory = nodeValueToStringArg(args[1])
  if requestedDirectory.len > 0 and dirExists(requestedDirectory):
    workingDirectory = requestedDirectory

  let shellPath = "/bin/sh"
  let execCommand = "exec " & commandString
  var argv = @[shellPath.cstring, "-lc".cstring, execCommand.cstring, nil]

  spawnTerminalProcess(widget, workingDirectory, argv)

  nilValue()

proc vteTerminalFeedImpl*(interp: var Interpreter, self: Instance,
                          args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp

  let widget = terminalWidget(self)
  if widget == nil or args.len < 1:
    return nilValue()

  let text = nodeValueToStringArg(args[0])
  if text.len == 0:
    return nilValue()

  vteTerminalFeedChild(widget, text.cstring, -1)

  nilValue()

proc vteTerminalFeedLineImpl*(interp: var Interpreter, self: Instance,
                              args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp

  let widget = terminalWidget(self)
  if widget == nil or args.len < 1:
    return nilValue()

  let text = nodeValueToStringArg(args[0])
  vteTerminalFeedChild(widget, (text & "\n").cstring, -1)

  nilValue()

proc vteTerminalCopyClipboardImpl*(interp: var Interpreter, self: Instance,
                                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp
  discard args

  let widget = terminalWidget(self)
  if widget == nil:
    return nilValue()

  vteTerminalCopyClipboard(widget)

  nilValue()

proc vteTerminalPasteClipboardImpl*(interp: var Interpreter, self: Instance,
                                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp
  discard args

  let widget = terminalWidget(self)
  if widget == nil:
    return nilValue()

  vteTerminalPasteClipboard(widget)

  nilValue()

proc vteTerminalSelectAllImpl*(interp: var Interpreter, self: Instance,
                               args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp
  discard args

  let widget = terminalWidget(self)
  if widget == nil:
    return nilValue()

  vteTerminalSelectAll(widget)

  nilValue()

proc vteTerminalResetImpl*(interp: var Interpreter, self: Instance,
                           args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard interp
  discard args

  let widget = terminalWidget(self)
  if widget == nil:
    return nilValue()

  vteTerminalReset(widget, 1, 1)

  nilValue()
