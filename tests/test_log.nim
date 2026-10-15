import std/[unittest, logging, strutils]
import ../src/harding/core/types
import ../src/harding/core/log_support
import ../src/harding/interpreter/vm
import ../src/harding/runtime/runtime

type CaptureLogger = ref object of logging.Logger
  messages: seq[string]

method log(logger: CaptureLogger, level: logging.Level, args: varargs[string, `$`]) =
  let message = args.join("")
  if message in ["application-message", "compiled-message", "42", "hidden", "visible"]:
    logger.messages.add($level & ":" & message)

proc overriddenLog(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkInt, intVal: 77)

var interp = newInterpreter()
initGlobals(interp)
loadStdlib(interp)

suite "Application logging":
  var capture: CaptureLogger
  var previousFilter: logging.Level
  setup:
    previousFilter = logging.getLogFilter()
    logging.setLogFilter(logging.lvlAll)
    capture = CaptureLogger(levelThreshold: logging.lvlAll)
    logging.addHandler(capture)
  teardown:
    logging.removeHandler(capture)
    logging.setLogFilter(previousFilter)

  test "interpreter dispatches all levels and fatal does not terminate":
    for selector in ["debug", "info", "warn", "error", "fatal"]:
      let (values, error) = interp.evalStatements("Log " & selector & ": \"application-message\"")
      check error.len == 0
      check values.len > 0
      check isNilValue(values[^1])
    check capture.messages.len == 5
    for message in capture.messages:
      check message.endsWith(":application-message")

  test "compiled runtime shares host handlers and aliases":
    let rt = newRuntime()
    let receiver = compiledLogClassValue()
    for selector in ["debug:", "info:", "warn:", "error:", "fatal:"]:
      check sendMessage(rt, receiver, selector,
                        @[NodeValue(kind: vkString, strVal: "compiled-message")]).kind == vkNil
    let alias = receiver
    discard sendMessage(rt, alias, "info:", @[NodeValue(kind: vkInt, intVal: 42)])
    check capture.messages.len == 6
    check capture.messages[^1].endsWith(":42")

  test "level filter does not install an extra handler":
    logging.setLogFilter(logging.lvlError)
    let count = logging.getHandlers().len
    discard writeHardingLog(logging.lvlInfo, NodeValue(kind: vkString, strVal: "hidden"))
    discard writeHardingLog(logging.lvlError, NodeValue(kind: vkString, strVal: "visible"))
    check capture.messages == @["lvlError:visible"]
    check logging.getHandlers().len == count

  test "lazy default sink uses Harding's configured threshold":
    let savedHandlers = logging.getHandlers()
    let savedLevel = globalLogLevel
    for handler in savedHandlers:
      logging.removeHandler(handler)
    try:
      for level in [logging.lvlError, logging.lvlWarn]:
        globalLogLevel = level
        discard writeHardingLog(logging.lvlDebug, toValue("hidden"))
        let handlers = logging.getHandlers()
        check handlers.len == 1
        check handlers[0].levelThreshold == level
        check logging.getLogFilter() == logging.lvlAll
        logging.removeHandler(handlers[0])
    finally:
      for handler in logging.getHandlers():
        logging.removeHandler(handler)
      for handler in savedHandlers:
        logging.addHandler(handler)
      globalLogLevel = savedLevel

  test "existing host threshold is not replaced by Harding's default":
    let previousLevel = globalLogLevel
    globalLogLevel = logging.lvlFatal
    try:
      discard writeHardingLog(logging.lvlInfo, toValue("application-message"))
      check capture.levelThreshold == logging.lvlAll
      check capture.messages == @["lvlInfo:application-message"]
    finally:
      globalLogLevel = previousLevel

  test "stream aliases return their receiver":
    let (values, error) = interp.evalStatements("(Stdout print: \"\") == Stdout")
    check error.len == 0
    check values[^1].boolVal

  test "compiled logging respects registered class-side overrides":
    registerCompiledClassMethod("Log", "info:", overriddenLog)
    let answer = sendMessage(newRuntime(), compiledLogClassValue(), "info:",
                             @[NodeValue(kind: vkString, strVal: "unused")])
    check answer.kind == vkInt
    check answer.intVal == 77
    check capture.messages.len == 0
