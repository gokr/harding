#
# bridge.nim - Debugger integration with VM execution loop
#
# Provides hooks into the VM work frame processing for breakpoint handling.
#

import std/[tables, locks, json, strutils]
import ../core/types
import ../interpreter/activation
import ./protocol
import ./breakpoints

# ============================================================================
# Debugger Bridge State
# ============================================================================

type
  DebuggerBridge* = ref object
    manager*: BreakpointManager
    enabled*: bool
    lock*: Lock
    currentInterp*: ptr Interpreter  # Weak reference to current interpreter
    lastHitBreakpoint*: (string, int)  # File, line of last breakpoint hit
    isPaused*: bool

var globalDebuggerBridge*: DebuggerBridge = nil

# ============================================================================
# Bridge Initialization
# ============================================================================

proc newDebuggerBridge*(): DebuggerBridge =
  ## Create a new debugger bridge
  new(result)
  result.manager = newBreakpointManager()
  result.enabled = false
  result.lock = Lock()
  result.currentInterp = nil
  result.lastHitBreakpoint = ("", 0)
  result.isPaused = false
  initLock(result.lock)

proc setGlobalDebuggerBridge*(bridge: DebuggerBridge) =
  ## Set the global debugger bridge instance
  globalDebuggerBridge = bridge

proc getGlobalDebuggerBridge*(): DebuggerBridge =
  ## Get the global debugger bridge instance
  return globalDebuggerBridge

proc enableDebugger*(bridge: DebuggerBridge) =
  ## Enable the debugger
  withLock(bridge.lock):
    bridge.enabled = true
    bridge.manager.state.enabled = true

proc disableDebugger*(bridge: DebuggerBridge) =
  ## Disable the debugger
  withLock(bridge.lock):
    bridge.enabled = false
    bridge.manager.state.enabled = false

proc isDebuggerEnabled*(bridge: DebuggerBridge): bool =
  ## Check if debugger is enabled
  return bridge.enabled and bridge.manager.state.enabled

# ============================================================================
# VM Integration Hooks
# ============================================================================

proc setCurrentInterpreter*(bridge: DebuggerBridge, interp: var Interpreter) =
  ## Set the current interpreter for context
  bridge.currentInterp = addr(interp)

proc clearCurrentInterpreter*(bridge: DebuggerBridge) =
  ## Clear the current interpreter reference
  bridge.currentInterp = nil

proc checkDebuggerHook*(interp: var Interpreter, frame: WorkFrame) =
  ## Check if debugger should pause at this work frame
  ## Called from VM execution loop

  if globalDebuggerBridge == nil:
    return

  if not globalDebuggerBridge.enabled:
    return

  # Only check at specific frame types that correspond to source locations
  if frame.kind notin {wfSendMessage, wfEvalNode}:
    return

  let bridge = globalDebuggerBridge

  withLock(bridge.lock):
    # Check for pause request
    if bridge.manager.shouldPause():
      bridge.manager.clearPauseRequest()
      bridge.isPaused = true
      # TODO: Signal paused state to debug server
      return

    # Get source location from frame (line only - nodes don't store filename)
    var line = 0

    if frame.kind == wfSendMessage and frame.msgNode != nil:
      line = frame.msgNode.line
    elif frame.kind == wfEvalNode and frame.node != nil:
      line = frame.node.line

    if line == 0:
      return

    # Check for breakpoint (using empty filename for now since nodes don't track it)
    # TODO: Add filename tracking to nodes
    if bridge.manager.shouldBreakAt("", line):
      bridge.lastHitBreakpoint = ("", line)
      bridge.isPaused = true
      # TODO: Signal breakpoint hit to debug server

# ============================================================================
# Stack Frame Inspection
# ============================================================================

proc buildStackFrame*(interp: Interpreter, depth: int): StackFrame =
  ## Build a stack frame from interpreter state
  ## depth: 0 = current activation, 1 = caller, etc.

  if depth >= interp.activationStack.len:
    raise newException(ValueError, "Stack depth out of range: " & $depth)

  let activation = interp.activationStack[interp.activationStack.len - 1 - depth]
  let currentMethod = activation.currentMethod

  var line = 0
  var col = 0

  if currentMethod != nil:
    line = currentMethod.line
    col = currentMethod.col

  var className = ""
  if activation.definingObject != nil:
    className = activation.definingObject.name

  var receiverClass = ""
  if activation.receiver != nil and activation.receiver.class != nil:
    receiverClass = activation.receiver.class.name

  result = StackFrame(
    id: depth,
    name: if currentMethod != nil: currentMethod.selector else: "<unknown>",
    file: "",  # Nodes don't store filename currently
    line: line,
    column: col,
    className: className,
    receiverClass: receiverClass
  )

proc getStackFrames*(interp: Interpreter, startFrame: int = 0, levels: int = 0): seq[StackFrame] =
  ## Get stack frames for display
  ## startFrame: index of first frame to return
  ## levels: maximum number of frames (0 = all)

  result = @[]

  let totalFrames = interp.activationStack.len
  if totalFrames == 0:
    return

  let endFrame = if levels > 0: min(startFrame + levels, totalFrames) else: totalFrames

  for i in startFrame..<endFrame:
    let frame = buildStackFrame(interp, i)
    result.add(frame)

# ============================================================================
# Variable Inspection
# ============================================================================

proc valueToString*(val: NodeValue): string =
  ## Convert a NodeValue to string for display
  case val.kind:
    of vkNil: return "nil"
    of vkInt: return $val.intVal
    of vkFloat: return $val.floatVal
    of vkString: return "\"" & val.strVal & "\""
    of vkSymbol: return "'" & val.symVal
    of vkBool: return $val.boolVal
    of vkInstance:
      if val.instVal == nil:
        return "nil"
      let inst = val.instVal
      case inst.kind:
        of ikObject: return "a " & inst.class.name
        of ikArray: return "Array(" & $inst.elements.len & " items)"
        of ikTable: return "Table(" & $inst.entries.len & " items)"
        of ikInt: return $inst.intVal
        of ikFloat: return $inst.floatVal
        of ikString: return "\"" & inst.strVal & "\""
    of vkBlock: return "[:" & val.blockVal.parameters.join(":") & " | ...]"
    of vkClass: return val.classVal.name
    of vkArray: return "Array(" & $val.arrayVal.len & " items)"
    of vkTable: return "Table(" & $val.tableVal.len & " items)"

proc getVariables*(interp: Interpreter, frameId: int): seq[Variable] =
  ## Get variables visible at a stack frame
  result = @[]

  if frameId >= interp.activationStack.len:
    return

  let activation = interp.activationStack[interp.activationStack.len - 1 - frameId]

  # Add parameters (from current method)
  if activation.currentMethod != nil:
    for i, param in activation.currentMethod.parameters:
      # Parameters are stored in locals with their names
      if activation.locals.hasKey(param):
        let val = activation.locals[param]
        result.add(Variable(
          name: param,
          value: valueToString(val),
          varType: vtArgument,
          varClass: if val.kind == vkInstance and val.instVal != nil and val.instVal.class != nil:
                      val.instVal.class.name else: "Object",
          variablesReference: 0
        ))

  # Add locals (temporaries)
  for name, val in activation.locals:
    result.add(Variable(
      name: name,
      value: valueToString(val),
      varType: vtTemporary,
      varClass: if val.kind == vkInstance and val.instVal != nil and val.instVal.class != nil:
                  val.instVal.class.name else: "Object",
      variablesReference: 0
    ))

  # Add self (receiver)
  if activation.receiver != nil:
    let selfVal = activation.receiver.toValue()
    result.add(Variable(
      name: "self",
      value: valueToString(selfVal),
      varType: vtLocal,
      varClass: activation.receiver.class.name,
      variablesReference: if activation.receiver.kind == ikObject: 1 else: 0
    ))

# ============================================================================
# Expression Evaluation
# ============================================================================

proc evaluateExpression*(interp: var Interpreter, frameId: int, expr: string): (string, bool) =
  ## Evaluate an expression in the context of a stack frame
  ## Returns (result string, success flag)
  ## TODO: Implement expression parsing and evaluation
  ## For now, return placeholder
  result = ("<expression evaluation not yet implemented>", false)

# ============================================================================
# Stepping Control
# ============================================================================

proc stepOver*(bridge: DebuggerBridge) =
  ## Step over next method call
  bridge.manager.setSteppingMode(smStepOver, bridge.manager.state.stepTargetFrame)
  bridge.isPaused = false

proc stepInto*(bridge: DebuggerBridge) =
  ## Step into method call
  bridge.manager.setSteppingMode(smStepInto, bridge.manager.state.stepTargetFrame)
  bridge.isPaused = false

proc stepOut*(bridge: DebuggerBridge, currentFrame: int) =
  ## Step out of current method
  bridge.manager.setSteppingMode(smStepOut, currentFrame)
  bridge.isPaused = false

proc continueExecution*(bridge: DebuggerBridge) =
  ## Continue execution
  bridge.manager.clearStepping()
  bridge.isPaused = false

proc pauseExecution*(bridge: DebuggerBridge) =
  ## Request pause at next opportunity
  bridge.manager.requestPause()

# ============================================================================
# Breakpoint Management (Passthrough)
# ============================================================================

proc setBreakpoint*(bridge: DebuggerBridge, file: string, line: int,
                    condition: string = "", column: int = 0): Breakpoint =
  ## Set a breakpoint
  return bridge.manager.addBreakpoint(file, line, condition, column)

proc removeBreakpoint*(bridge: DebuggerBridge, id: int): bool =
  ## Remove a breakpoint by ID
  return bridge.manager.removeBreakpoint(id)

proc removeBreakpoint*(bridge: DebuggerBridge, file: string, line: int): bool =
  ## Remove a breakpoint by location
  return bridge.manager.removeBreakpoint(file, line)

proc clearBreakpointsInFile*(bridge: DebuggerBridge, file: string) =
  ## Clear all breakpoints in a file
  bridge.manager.clearBreakpointsInFile(file)

proc getBreakpoints*(bridge: DebuggerBridge): seq[Breakpoint] =
  ## Get all breakpoints
  return bridge.manager.getAllBreakpoints()
