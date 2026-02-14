#
# server.nim - Harding Debug Protocol (HDP) TCP server
#
# Accepts connections from VSCode debugger client and dispatches requests.
# Uses synchronous sockets with threading for concurrent connections.
#

import std/[net, json, strutils, tables, locks, os, streams, threadpool, sequtils]
import ../core/types
import ./protocol
import ./breakpoints
import ./bridge

# ============================================================================
# Server Configuration
# ============================================================================

type
  DebugServerConfig* = object
    port*: int
    host*: string
    logMessages*: bool

proc defaultDebugServerConfig*(): DebugServerConfig =
  ## Return default server configuration
  result.port = HDP_DEFAULT_PORT
  result.host = "127.0.0.1"
  result.logMessages = false

# ============================================================================
# Server State
# ============================================================================

type
  DebugServer* = ref object
    socket*: Socket
    config*: DebugServerConfig
    running*: bool
    bridge*: DebuggerBridge
    clientConnected*: bool
    nextRequestSeq*: int

var globalDebugServer*: DebugServer = nil

# ============================================================================
# Request Handlers
# ============================================================================

proc handleConnect(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle connect request
  result = %*{
    "protocolVersion": HDP_PROTOCOL_VERSION,
    "success": true
  }

proc handleDisconnect(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle disconnect request
  server.clientConnected = false
  server.running = false
  result = %*{}

proc handleSetBreakpoint(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle setBreakpoint request
  let (file, line, condition) = parseBreakpointRequest(args)
  let bp = server.bridge.setBreakpoint(file, line, condition)
  result = %*{
    "id": bp.id,
    "verified": bp.verified,
    "line": bp.line
  }

proc handleRemoveBreakpoint(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle removeBreakpoint request
  let id = args["id"].getInt()
  let success = server.bridge.removeBreakpoint(id)
  result = %*{
    "success": success
  }

proc handleClearBreakpoints(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle clearBreakpoints request
  if args.hasKey("source"):
    let file = args["source"]["path"].getStr()
    server.bridge.clearBreakpointsInFile(file)
  else:
    # Clear all breakpoints (not implemented in bridge yet)
    discard
  result = %*{"success": true}

proc handleContinue(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle continue request
  server.bridge.continueExecution()
  result = %*{"allThreadsContinued": true}

proc handlePause(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle pause request
  server.bridge.pauseExecution()
  result = %*{"success": true}

proc handleStepOver(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle stepOver request
  server.bridge.stepOver()
  result = %*{"success": true}

proc handleStepInto(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle stepInto request
  server.bridge.stepInto()
  result = %*{"success": true}

proc handleStepOut(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle stepOut request
  let frameId = if args.hasKey("frameId"): args["frameId"].getInt() else: 0
  server.bridge.stepOut(frameId)
  result = %*{"success": true}

proc handleGetStackFrames(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle getStackFrames request
  ## TODO: Get actual interpreter from bridge
  var frames: seq[StackFrame] = @[]
  result = %*{
    "stackFrames": frames.mapIt(it.toJson())
  }

proc handleGetVariables(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle getVariables request
  ## TODO: Get actual interpreter from bridge
  let frameId = args["frameId"].getInt()
  var vars: seq[Variable] = @[]
  result = %*{
    "variables": vars.mapIt(it.toJson())
  }

proc handleEvaluate(server: DebugServer, args: JsonNode): JsonNode =
  ## Handle evaluate request
  let expr = args["expression"].getStr()
  let frameId = if args.hasKey("frameId"): args["frameId"].getInt() else: 0
  result = %*{
    "result": "<not implemented>",
    "type": "Object"
  }

proc dispatchRequest(server: DebugServer, req: HDPRequest): HDPResponse =
  ## Dispatch a request to the appropriate handler
  var body: JsonNode = nil
  var success = true
  var message = ""

  try:
    case req.requestType:
      of hrConnect:
        body = handleConnect(server, req.arguments)
      of hrDisconnect:
        body = handleDisconnect(server, req.arguments)
      of hrSetBreakpoint:
        body = handleSetBreakpoint(server, req.arguments)
      of hrRemoveBreakpoint:
        body = handleRemoveBreakpoint(server, req.arguments)
      of hrClearBreakpoints:
        body = handleClearBreakpoints(server, req.arguments)
      of hrContinue:
        body = handleContinue(server, req.arguments)
      of hrPause:
        body = handlePause(server, req.arguments)
      of hrStepOver:
        body = handleStepOver(server, req.arguments)
      of hrStepInto:
        body = handleStepInto(server, req.arguments)
      of hrStepOut:
        body = handleStepOut(server, req.arguments)
      of hrGetStackFrames:
        body = handleGetStackFrames(server, req.arguments)
      of hrGetVariables:
        body = handleGetVariables(server, req.arguments)
      of hrEvaluateExpression:
        body = handleEvaluate(server, req.arguments)
      else:
        success = false
        message = "Request type not implemented: " & $req.requestType
  except Exception as e:
    success = false
    message = e.msg

  if success:
    result = createSuccessResponse(req.seq, body)
  else:
    result = createErrorResponse(req.seq, message)

# ============================================================================
# Client Connection Handling
# ============================================================================

proc processClientMessage(server: DebugServer, msg: string): string =
  ## Process a message from the client
  try:
    let req = parseRequest(msg)
    let resp = dispatchRequest(server, req)
    result = formatResponse(resp)
  except Exception as e:
    result = formatResponse(createErrorResponse(0, "Parse error: " & e.msg))

proc handleClient*(server: DebugServer, client: Socket) =
  ## Handle a connected client
  server.clientConnected = true
  echo "HDP client connected"

  var lineBuf = ""
  var recvBuf = ""

  try:
    while server.running and server.clientConnected:
      recvBuf = client.recv(1)
      if recvBuf.len == 0:
        break

      let c = recvBuf[0]
      if c == '\n':
        let response = processClientMessage(server, lineBuf)
        client.send(response & "\n")
        lineBuf = ""
      else:
        lineBuf.add(c)

  except Exception as e:
    echo "Client error: ", e.msg
  finally:
    server.clientConnected = false
    client.close()
    echo "HDP client disconnected"

# ============================================================================
# Server Lifecycle
# ============================================================================

proc newDebugServer*(config: DebugServerConfig): DebugServer =
  ## Create a new debug server
  new(result)
  result.config = config
  result.running = false
  result.clientConnected = false
  result.nextRequestSeq = 1

proc startServer*(server: DebugServer) =
  ## Start the debug server and accept connections (blocking)
  server.socket = newSocket()
  server.socket.setSockOpt(OptReuseAddr, true)
  server.socket.bindAddr(Port(server.config.port), server.config.host)
  server.socket.listen()

  echo "HDP Server listening on ", server.config.host, ":", server.config.port

  # Create bridge if not exists
  if server.bridge == nil:
    if globalDebuggerBridge == nil:
      globalDebuggerBridge = newDebuggerBridge()
      enableDebugger(globalDebuggerBridge)
    server.bridge = globalDebuggerBridge

  server.running = true

  while server.running:
    var client: Socket
    new(client)
    server.socket.accept(client)
    spawn handleClient(server, client)

proc stopServer*(server: DebugServer) =
  ## Stop the debug server
  server.running = false
  server.clientConnected = false
  if server.socket != nil:
    server.socket.close()

proc runServerBlocking*(config: DebugServerConfig = defaultDebugServerConfig()) =
  ## Run the debug server in a blocking manner (for use in thread)
  let server = newDebugServer(config)
  globalDebugServer = server
  startServer(server)

# ============================================================================
# Thread Entry Point
# ============================================================================

proc runServerThreaded*(config: DebugServerConfig) {.gcsafe, thread.} =
  ## Run the debug server in a thread
  {.gcsafe.}:
    runServerBlocking(config)

proc startDebuggerServerInThread*(config: DebugServerConfig = defaultDebugServerConfig()) =
  ## Start the debug server in a background thread
  var thread: Thread[DebugServerConfig]
  createThread(thread, runServerThreaded, config)
