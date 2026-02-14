#
# protocol.nim - Harding Debug Protocol (HDP) message definitions
#
# JSON-based protocol similar to BitBarrel's WebSocket protocol.
# Communicates between the VSCode debugger and the Harding VM.
#

import std/[json, tables, sequtils]

# ============================================================================
# Protocol Constants
# ============================================================================

const
  HDP_DEFAULT_PORT* = 9877
  HDP_PROTOCOL_VERSION* = "1.0"

# ============================================================================
# Request Types
# ============================================================================

type
  HDPRequestType* = enum
    hrConnect
    hrDisconnect
    hrSetBreakpoint
    hrRemoveBreakpoint
    hrClearBreakpoints
    hrStepOver
    hrStepInto
    hrStepOut
    hrContinue
    hrPause
    hrGetStackFrames
    hrGetVariables
    hrEvaluateExpression
    hrGetSource
    hrSetExceptionBreakpoints

  HDPRequest* = object
    seq*: int                    # Request sequence number
    requestType*: HDPRequestType
    arguments*: JsonNode         # Request-specific arguments

# ============================================================================
# Response Types
# ============================================================================

type
  HDPResponseType* = enum
    hprSuccess
    hprError

  HDPResponse* = object
    requestSeq*: int             # Sequence number of request this responds to
    responseType*: HDPResponseType
    success*: bool
    message*: string             # Error message if success=false
    body*: JsonNode              # Response body

# ============================================================================
# Event Types (async notifications from VM to debugger)
# ============================================================================

type
  HDPEventType* = enum
    heBreakpointHit
    hePaused
    heContinued
    heException
    heThreadStarted
    heThreadExited
    heOutput

  HDPEvent* = object
    eventType*: HDPEventType
    body*: JsonNode

# ============================================================================
# Breakpoint Types
# ============================================================================

type
  Breakpoint* = object
    id*: int
    file*: string
    line*: int
    column*: int
    condition*: string          # Optional condition expression
    enabled*: bool
    verified*: bool            # Whether VM has resolved this breakpoint

  BreakpointTable* = Table[(string, int), Breakpoint]

# ============================================================================
# Stack Frame Types
# ============================================================================

type
  StackFrame* = object
    id*: int
    name*: string               # Method selector
    file*: string
    line*: int
    column*: int
    className*: string          # Class where method defined
    receiverClass*: string      # Class of receiver

# ============================================================================
# Variable Types
# ============================================================================

type
  VariableType* = enum
    vtLocal
    vtArgument
    vtSlot
    vtGlobal
    vtTemporary

  Variable* = object
    name*: string
    value*: string              # String representation
    varType*: VariableType
    varClass*: string           # Class of the value
    variablesReference*: int    # For objects with expandable children

# ============================================================================
# Stepping Mode
# ============================================================================

type
  SteppingMode* = enum
    smNone
    smStepOver
    smStepInto
    smStepOut

# ============================================================================
# Debugger State
# ============================================================================

type
  DebuggerState* = object
    enabled*: bool
    connected*: bool
    breakpoints*: BreakpointTable
    nextBreakpointId*: int
    nextFrameId*: int
    nextVarRef*: int
    steppingMode*: SteppingMode
    stepTargetFrame*: int       # For step-out: target frame depth
    pauseRequested*: bool

# ============================================================================
# JSON Serialization
# ============================================================================

proc toJson*(bp: Breakpoint): JsonNode =
  ## Serialize breakpoint to JSON
  result = %*{
    "id": bp.id,
    "file": bp.file,
    "line": bp.line,
    "column": bp.column,
    "condition": bp.condition,
    "enabled": bp.enabled,
    "verified": bp.verified
  }

proc toJson*(frame: StackFrame): JsonNode =
  ## Serialize stack frame to JSON
  result = %*{
    "id": frame.id,
    "name": frame.name,
    "source": {
      "path": frame.file
    },
    "line": frame.line,
    "column": frame.column,
    "className": frame.className,
    "receiverClass": frame.receiverClass
  }

proc toJson*(variable: Variable): JsonNode =
  ## Serialize variable to JSON
  result = %*{
    "name": variable.name,
    "value": variable.value,
    "type": variable.varClass,
    "variablesReference": variable.variablesReference
  }

proc toJson*(evt: HDPEvent): JsonNode =
  ## Serialize event to JSON
  result = %*{
    "type": "event",
    "event": $evt.eventType,
    "body": evt.body
  }

proc parseBreakpointRequest*(args: JsonNode): (string, int, string) =
  ## Parse setBreakpoint request arguments
  ## Returns (file, line, condition)
  let file = args["source"]["path"].getStr()
  let line = args["line"].getInt()
  var condition = ""
  if args.hasKey("condition"):
    condition = args["condition"].getStr()
  result = (file, line, condition)

proc createBreakpointHitEvent*(file: string, line: int, frames: seq[StackFrame]): HDPEvent =
  ## Create a breakpoint hit event
  result = HDPEvent(
    eventType: heBreakpointHit,
    body: %*{
      "reason": "breakpoint",
      "file": file,
      "line": line,
      "stackFrames": frames.mapIt(it.toJson())
    }
  )

proc createPausedEvent*(reason: string, description: string = ""): HDPEvent =
  ## Create a paused event
  var body = %*{"reason": reason}
  if description.len > 0:
    body["description"] = %description
  result = HDPEvent(eventType: hePaused, body: body)

proc createExceptionEvent*(message: string, stackTrace: string): HDPEvent =
  ## Create an exception event
  result = HDPEvent(
    eventType: heException,
    body: %*{
      "message": message,
      "stackTrace": stackTrace
    }
  )

proc createOutputEvent*(category: string, output: string): HDPEvent =
  ## Create an output event
  result = HDPEvent(
    eventType: heOutput,
    body: %*{
      "category": category,
      "output": output
    }
  )

# ============================================================================
# Response Helpers
# ============================================================================

proc createSuccessResponse*(requestSeq: int, body: JsonNode = nil): HDPResponse =
  ## Create a successful response
  result = HDPResponse(
    requestSeq: requestSeq,
    responseType: hprSuccess,
    success: true,
    body: body
  )

proc createErrorResponse*(requestSeq: int, message: string): HDPResponse =
  ## Create an error response
  result = HDPResponse(
    requestSeq: requestSeq,
    responseType: hprError,
    success: false,
    message: message
  )

# ============================================================================
# Protocol Line Parsing (JSON-RPC style)
# ============================================================================

proc parseRequest*(jsonStr: string): HDPRequest =
  ## Parse a JSON request from the debugger client
  let json = parseJson(jsonStr)
  let seqNum = json["seq"].getInt()
  let cmd = json["command"].getStr()

  var reqType: HDPRequestType
  case cmd:
    of "connect": reqType = hrConnect
    of "disconnect": reqType = hrDisconnect
    of "setBreakpoint": reqType = hrSetBreakpoint
    of "removeBreakpoint": reqType = hrRemoveBreakpoint
    of "clearBreakpoints": reqType = hrClearBreakpoints
    of "stepOver": reqType = hrStepOver
    of "stepInto": reqType = hrStepInto
    of "stepOut": reqType = hrStepOut
    of "continue": reqType = hrContinue
    of "pause": reqType = hrPause
    of "getStackFrames": reqType = hrGetStackFrames
    of "getVariables": reqType = hrGetVariables
    of "evaluate": reqType = hrEvaluateExpression
    of "getSource": reqType = hrGetSource
    of "setExceptionBreakpoints": reqType = hrSetExceptionBreakpoints
    else: raise newException(ValueError, "Unknown command: " & cmd)

  var args: JsonNode = nil
  if json.hasKey("arguments"):
    args = json["arguments"]

  result = HDPRequest(seq: seqNum, requestType: reqType, arguments: args)

proc formatResponse*(resp: HDPResponse): string =
  ## Format a response as JSON string
  var json = %*{
    "type": "response",
    "request_seq": resp.requestSeq,
    "success": resp.success
  }
  if not resp.success:
    json["message"] = %resp.message
  if resp.body != nil:
    json["body"] = resp.body
  result = $json

proc formatEvent*(evt: HDPEvent): string =
  ## Format an event as JSON string
  result = $evt.toJson()
