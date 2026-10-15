import std/logging
import ./types

proc writeHardingLog*(level: logging.Level, value: NodeValue): NodeValue =
  ## Application logging keeps all levels available in release builds. Existing
  ## host handlers and their filters take precedence over a default stderr sink.
  if logging.getHandlers().len == 0:
    logging.addHandler(logging.newConsoleLogger(levelThreshold = globalLogLevel,
                                                useStderr = true))
  logging.log(level, value.toString())
  return NodeValue(kind: vkNil)

proc logDebug*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  writeHardingLog(logging.lvlDebug, if args.len > 0: args[0] else: nilValue())

proc logInfo*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  writeHardingLog(logging.lvlInfo, if args.len > 0: args[0] else: nilValue())

proc logWarn*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  writeHardingLog(logging.lvlWarn, if args.len > 0: args[0] else: nilValue())

proc logError*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  writeHardingLog(logging.lvlError, if args.len > 0: args[0] else: nilValue())

proc logFatal*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  writeHardingLog(logging.lvlFatal, if args.len > 0: args[0] else: nilValue())
