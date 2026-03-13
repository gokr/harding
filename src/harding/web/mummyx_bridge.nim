## ============================================================================
## MummyX Bridge for Harding
## Provides HTTP server capabilities via MummyX with channel-based dispatch
## to the main Harding interpreter thread.
##
## Architecture:
##   - MummyX runs on a background Nim thread
##   - Worker threads package requests and send them via Channel
##   - Main thread processes requests by invoking Harding handler blocks
##   - Responses are sent back via per-request response Channels
##   - Compatible with Bona (live development) and standalone use
##
## Build: nim c -d:mummyx --threads:on --mm:orc ...
## ============================================================================

import std/[tables, os, strutils, options, uri, times]
import mummy, mummy/routers
import ../core/types
import ../interpreter/objects

# ============================================================================
# Types
# ============================================================================

type
  HttpRequestLogLevel* = enum
    hrllOff = 0,
    hrllBasic = 1,
    hrllDetailed = 2

  PendingResponse* = object
    statusCode*: int
    headers*: seq[(string, string)]
    body*: string

  PendingRequest* = object
    httpMethod*: string
    uri*: string
    path*: string
    body*: string
    remoteAddress*: string
    headers*: seq[(string, string)]
    queryParams*: seq[(string, string)]
    formParams*: seq[(string, string)]
    pathParams*: seq[(string, string)]
    responseChan*: ptr Channel[PendingResponse]

  HardingRoute* = object
    httpMethod*: string  # "GET", "POST", etc. or "*" for all
    pattern*: string     # e.g., "/", "/users/@id"
    parts*: seq[string]  # split pattern parts for matching
    handlerBlock*: NodeValue  # The Harding block (vkBlock)

  RouterProxy* = ref object
    routes*: seq[HardingRoute]

  ServerProxy* = ref object
    routerProxy*: RouterProxy
    running*: bool
    port*: int
    address*: string
    requestLogLevel*: HttpRequestLogLevel

  RequestProxy* = ref object
    httpMethod*: string
    uri*: string
    path*: string
    body*: string
    remoteAddress*: string
    headers*: seq[(string, string)]
    queryParams*: seq[(string, string)]
    formParams*: seq[(string, string)]
    pathParams*: seq[(string, string)]
    responseChan*: ptr Channel[PendingResponse]
    responded*: bool
    startedAt*: float
    logLevel*: HttpRequestLogLevel

# Keep proxies alive for ARC
var serverProxies*: seq[ServerProxy] = @[]
var routerProxies*: seq[RouterProxy] = @[]
var requestProxies*: seq[RequestProxy] = @[]

# Global class references for MummyX types
var httpServerClass*: Class = nil
var httpRequestClass*: Class = nil
var routerClass*: Class = nil

# Global request channel for the MummyX handler (one server per process)
var globalRequestChan*: Channel[PendingRequest]
var globalRequestChanOpen* = false
var activeRouterProxy*: RouterProxy = nil
var activeRequestLogLevel*: HttpRequestLogLevel = hrllOff

type
  ServerThreadArgs = object
    port: int
    address: string

# ============================================================================
# Route Matching
# ============================================================================

proc matchRoute(route: HardingRoute, httpMethod: string, path: string,
                pathParams: var seq[(string, string)]): bool =
  ## Match a request against a route pattern.
  ## Supports @param named parameters and * / ** wildcards.
  if route.httpMethod != "*" and route.httpMethod != httpMethod:
    return false

  let requestParts = path.strip(chars = {'/'}).split('/')
  let routeParts = route.parts

  if routeParts.len == 0 and requestParts.len == 0:
    return true
  if routeParts.len == 0 and requestParts == @[""]:
    return true

  var ri = 0
  var pi = 0
  pathParams = @[]

  while ri < routeParts.len and pi < requestParts.len:
    let rp = routeParts[ri]
    let pp = requestParts[pi]

    if rp.startsWith("@"):
      # Named parameter
      pathParams.add((rp[1..^1], pp))
      inc ri
      inc pi
    elif rp == "**":
      # Multi-segment wildcard - matches rest
      return true
    elif rp == "*":
      # Single segment wildcard
      inc ri
      inc pi
    else:
      # Exact match
      if rp != pp:
        return false
      inc ri
      inc pi

  return ri == routeParts.len and pi == requestParts.len

proc findRoute(routes: seq[HardingRoute], httpMethod: string, path: string,
               pathParams: var seq[(string, string)]): Option[HardingRoute] =
  for route in routes:
    if matchRoute(route, httpMethod, path, pathParams):
      return some(route)
  return none(HardingRoute)

proc decodeFormComponent(value: string): string =
  decodeUrl(value.replace("+", " "))

proc parseFormBody(body: string): seq[(string, string)] =
  result = @[]
  if body.len == 0:
    return result

  for part in body.split('&'):
    if part.len == 0:
      continue

    let pieces = part.split("=", maxsplit = 1)
    let key = decodeFormComponent(pieces[0])
    let value = if pieces.len > 1: decodeFormComponent(pieces[1]) else: ""
    result.add((key, value))

proc requestLogLevelName(level: HttpRequestLogLevel): string =
  case level
  of hrllBasic:
    "basic"
  of hrllDetailed:
    "detailed"
  else:
    "off"

proc parseRequestLogLevel(value: NodeValue): HttpRequestLogLevel =
  case value.kind
  of vkInt:
    case value.intVal
    of 2:
      hrllDetailed
    of 1:
      hrllBasic
    else:
      hrllOff
  of vkString:
    case value.strVal.toLowerAscii()
    of "detailed", "debug", "verbose", "2":
      hrllDetailed
    of "basic", "info", "1", "on", "true":
      hrllBasic
    else:
      hrllOff
  of vkBool:
    if value.boolVal: hrllBasic else: hrllOff
  else:
    hrllOff

proc truncateForLog(value: string, limit: int = 240): string =
  if value.len <= limit:
    return value
  value[0..<limit] & "..."

proc formatPairSeq(pairs: seq[(string, string)]): string =
  if pairs.len == 0:
    return "[]"

  result = "["
  for i, (key, value) in pairs:
    if i > 0:
      result.add(", ")
    result.add(key)
    result.add("=")
    result.add(value)
  result.add("]")

proc logRequestStart(level: HttpRequestLogLevel, pending: PendingRequest) =
  if level == hrllOff:
    return

  stdout.writeLine("[HTTP] ", pending.httpMethod, " ", pending.path,
                   " remote=", pending.remoteAddress)

  if level == hrllDetailed:
    stdout.writeLine("[HTTP]   uri=", pending.uri)
    stdout.writeLine("[HTTP]   query=", formatPairSeq(pending.queryParams))
    stdout.writeLine("[HTTP]   pathParams=", formatPairSeq(pending.pathParams))
    stdout.writeLine("[HTTP]   form=", formatPairSeq(pending.formParams))
    stdout.writeLine("[HTTP]   headers=", formatPairSeq(pending.headers))
    stdout.writeLine("[HTTP]   body=", truncateForLog(pending.body))

  flushFile(stdout)

proc logRequestResponse(level: HttpRequestLogLevel, httpMethod: string,
                        path: string, response: PendingResponse, elapsedMs: int) =
  if level == hrllOff:
    return

  stdout.writeLine("[HTTP] ", httpMethod, " ", path,
                   " -> ", $response.statusCode,
                   " ", $elapsedMs, "ms",
                   " bytes=", $response.body.len)

  if level == hrllDetailed:
    stdout.writeLine("[HTTP]   responseHeaders=", formatPairSeq(response.headers))
    stdout.writeLine("[HTTP]   responseBody=", truncateForLog(response.body))

  flushFile(stdout)

proc sendResponse(proxy: RequestProxy, response: PendingResponse) =
  proxy.responseChan[].send(response)
  logRequestResponse(proxy.logLevel, proxy.httpMethod, proxy.path, response,
                     int((epochTime() - proxy.startedAt) * 1000.0))

proc syncActiveServerSettings(proxy: ServerProxy) =
  activeRouterProxy = proxy.routerProxy
  activeRequestLogLevel = proxy.requestLogLevel

# ============================================================================
# MummyX Request Handler (runs on worker threads)
# ============================================================================

proc mummyxRequestHandler(request: Request) {.gcsafe.} =
  ## Called by MummyX on worker threads. Packages the request and sends it
  ## to the main Harding interpreter thread via channel.
  if not globalRequestChanOpen:
    request.respond(503, emptyHttpHeaders(), "Server not initialized")
    return

  # Copy request data into a PendingRequest
  var pending = PendingRequest(
    httpMethod: request.httpMethod,
    uri: request.uri,
    path: request.path,
    body: request.body,
    remoteAddress: request.remoteAddress,
  )

  # Copy headers
  for (key, value) in request.headers:
    pending.headers.add((key, value))

  for (key, value) in pending.headers:
    if key.toLowerAscii() == "content-type" and
        value.toLowerAscii().startsWith("application/x-www-form-urlencoded"):
      pending.formParams = parseFormBody(pending.body)
      break

  # Copy query params
  for (key, value) in request.queryParams:
    pending.queryParams.add((key, value))

  # Copy path params
  for (key, value) in request.pathParams:
    pending.pathParams.add((key, value))

  # Create per-request response channel
  var respChan: Channel[PendingResponse]
  respChan.open()
  pending.responseChan = addr respChan

  # Send to main thread
  globalRequestChan.send(pending)

  # Block until Harding handler produces a response
  let response = respChan.recv()
  respChan.close()

  # Send HTTP response via MummyX
  var httpHeaders: HttpHeaders
  for (k, v) in response.headers:
    httpHeaders[k] = v
  request.respond(response.statusCode, httpHeaders, response.body)

# ============================================================================
# Server Thread
# ============================================================================

var activeServer: Server
var serverThread: Thread[ServerThreadArgs]

proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
  ## Background thread that runs the MummyX event loop
  {.gcsafe.}:
    let server = newServer(mummyxRequestHandler)
    activeServer = server
    try:
      server.serve(Port(args.port), args.address)
    except:
      stderr.writeLine("[MUMMYX] server thread failed: " & getCurrentExceptionMsg())

# ============================================================================
# Callbacks - set by vm.nim to break circular dependency
# (bridge can't import scheduler directly since scheduler imports vm imports bridge)
# ============================================================================

# Sets up scheduler on interpreter, creates NimChannel, forks worker processes,
# and returns the SchedulerContext pointer (as raw pointer for the run loop).
var setupSchedulerAndWorkersProc*: proc(interp: var Interpreter,
    pollProc: proc(): Option[NodeValue], workerCount: int): pointer = nil

# Runs one scheduler tick. Returns true if work was done.
var runOneSliceProc*: proc(ctxPtr: pointer): bool = nil

# ============================================================================
# NimChannel poll callback for request dispatch
# ============================================================================
#
# The pollProc reads PendingRequests from globalRequestChan (fed by MummyX
# worker threads), does route matching on the main thread, creates an
# HttpRequest instance, and returns an Array #(request handlerBlock) that
# the worker Process unpacks and invokes.

proc mummyxPollProc(): Option[NodeValue] =
  ## Poll globalRequestChan for incoming requests.
  ## Returns Some(#(request handlerBlock)) or None.
  if not globalRequestChanOpen:
    return none(NodeValue)

  let (hasData, pending) = globalRequestChan.tryRecv()
  if not hasData:
    return none(NodeValue)

  # Route matching
  var pathParams: seq[(string, string)] = @[]
  let routes = if activeRouterProxy == nil: @[] else: activeRouterProxy.routes
  let route = findRoute(routes, pending.httpMethod, pending.path, pathParams)

  if route.isNone:
    # 404 - respond directly, don't bother a worker Process
    pending.responseChan[].send(PendingResponse(
      statusCode: 404,
      headers: @[("Content-Type", "text/plain")],
      body: "Not Found"
    ))
    return none(NodeValue)

  # Create HttpRequest instance on the main thread
  let reqProxy = RequestProxy(
    httpMethod: pending.httpMethod,
    uri: pending.uri,
    path: pending.path,
    body: pending.body,
    remoteAddress: pending.remoteAddress,
    headers: pending.headers,
    queryParams: pending.queryParams,
    formParams: pending.formParams,
    pathParams: pathParams,
    responseChan: pending.responseChan,
    responded: false,
    startedAt: epochTime(),
    logLevel: activeRequestLogLevel
  )
  requestProxies.add(reqProxy)

  logRequestStart(reqProxy.logLevel, pending)

  let reqInst = newInstance(httpRequestClass)
  reqInst.isNimProxy = true
  reqInst.nimValue = cast[pointer](reqProxy)

  # Return #(request handlerBlock) as a Harding Array
  let arr = newArrayInstance(arrayClass, @[reqInst.toValue(), route.get.handlerBlock])
  return some(arr.toValue())

# ============================================================================
# Native Method Implementations - HttpServer
# ============================================================================

proc serverNewImpl(interp: var Interpreter, self: Instance,
                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer class>>new
  let inst = newInstance(httpServerClass)
  inst.isNimProxy = true
  let proxy = ServerProxy(
    routerProxy: nil,
    running: false,
    port: 8080,
    address: "localhost",
    requestLogLevel: hrllOff
  )
  serverProxies.add(proxy)
  inst.nimValue = cast[pointer](proxy)
  return inst.toValue()

proc serverRouterImpl(interp: var Interpreter, self: Instance,
                      args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>router: aRouter
  if self.nimValue == nil:
    return nilValue()
  let serverProxy = cast[ServerProxy](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance:
    let routerInst = args[0].instVal
    if routerInst.nimValue != nil:
      let routerProxy = cast[RouterProxy](routerInst.nimValue)
      serverProxy.routerProxy = routerProxy
      if serverProxy.running:
        syncActiveServerSettings(serverProxy)
  return self.toValue()

proc serverRequestLogLevelImpl(interp: var Interpreter, self: Instance,
                               args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil:
    return NodeValue(kind: vkString, strVal: "off")
  let proxy = cast[ServerProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: requestLogLevelName(proxy.requestLogLevel))

proc serverSetRequestLogLevelImpl(interp: var Interpreter, self: Instance,
                                  args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)
  if args.len > 0:
    proxy.requestLogLevel = parseRequestLogLevel(args[0])
    if proxy.running:
      syncActiveServerSettings(proxy)
  return self.toValue()

const defaultWorkerCount = 10

proc startMummyxServer(proxy: ServerProxy) =
  ## Common startup: open channel, start MummyX background thread.
  syncActiveServerSettings(proxy)
  globalRequestChan.open()
  globalRequestChanOpen = true
  proxy.running = true

  createThread(serverThread, serverThreadProc, ServerThreadArgs(port: proxy.port, address: proxy.address))

proc serverStartImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>start: port
  ## Starts MummyX on a background thread with worker Processes. Non-blocking.
  if self == nil or self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)
  if proxy.running:
    return self.toValue()

  if args.len > 0 and args[0].kind == vkInt:
    proxy.port = args[0].intVal

  startMummyxServer(proxy)
  discard setupSchedulerAndWorkersProc(interp, mummyxPollProc, defaultWorkerCount)

  return self.toValue()

proc serverStartAddressImpl(interp: var Interpreter, self: Instance,
                            args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>start: port address: address
  if self == nil or self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)
  if proxy.running:
    return self.toValue()

  if args.len > 0 and args[0].kind == vkInt:
    proxy.port = args[0].intVal
  if args.len > 1 and args[1].kind == vkString:
    proxy.address = args[1].strVal

  startMummyxServer(proxy)
  discard setupSchedulerAndWorkersProc(interp, mummyxPollProc, defaultWorkerCount)

  return self.toValue()

proc serverProcessRequestsImpl(interp: var Interpreter, self: Instance,
                                args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>processRequests
  ## Run one scheduler tick - processes pending requests via worker Processes.
  if self == nil or self.nimValue == nil:
    return nilValue()
  if interp.schedulerContextPtr == nil:
    return NodeValue(kind: vkInt, intVal: 0)
  var count = 0
  while runOneSliceProc(interp.schedulerContextPtr):
    inc count
    if count >= 100:
      break
  return NodeValue(kind: vkInt, intVal: count)

proc serverServeForeverImpl(interp: var Interpreter, self: Instance,
                            args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>serveForever: port
  ## Starts server with worker Process pool and enters scheduler loop.
  if self == nil or self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)

  if args.len > 0 and args[0].kind == vkInt:
    proxy.port = args[0].intVal

  startMummyxServer(proxy)
  let ctxPtr = setupSchedulerAndWorkersProc(interp, mummyxPollProc, defaultWorkerCount)

  # Run scheduler loop - polls NimChannel and dispatches to workers
  while proxy.running:
    let didWork = runOneSliceProc(ctxPtr)
    if not didWork:
      sleep(1)

  return nilValue()

proc serverIsRunningImpl(interp: var Interpreter, self: Instance,
                         args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>isRunning
  if self.nimValue == nil:
    return NodeValue(kind: vkBool, boolVal: false)
  let proxy = cast[ServerProxy](self.nimValue)
  return NodeValue(kind: vkBool, boolVal: proxy.running)

proc serverStopImpl(interp: var Interpreter, self: Instance,
                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>stop
  if self == nil or self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)
  proxy.running = false
  try:
    activeServer.close()
  except:
    discard
  globalRequestChanOpen = false
  activeRequestLogLevel = hrllOff
  return self.toValue()

proc serverPortImpl(interp: var Interpreter, self: Instance,
                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpServer>>port
  if self.nimValue == nil:
    return nilValue()
  let proxy = cast[ServerProxy](self.nimValue)
  return NodeValue(kind: vkInt, intVal: proxy.port)

# ============================================================================
# Native Method Implementations - Router
# ============================================================================

proc routerNewImpl(interp: var Interpreter, self: Instance,
                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router class>>new
  let inst = newInstance(routerClass)
  inst.isNimProxy = true
  let proxy = RouterProxy(routes: @[])
  routerProxies.add(proxy)
  inst.nimValue = cast[pointer](proxy)
  return inst.toValue()

proc addRouteImpl(interp: var Interpreter, self: Instance,
                  httpMethod: string, args: seq[NodeValue]): NodeValue =
  ## Common route registration logic
  if self == nil or self.nimValue == nil or args.len < 2:
    return nilValue()
  let proxy = cast[RouterProxy](self.nimValue)

  let pattern = if args[0].kind == vkString: args[0].strVal else: ""
  let handler = args[1]

  if pattern.len == 0 or handler.kind != vkBlock:
    return nilValue()

  let parts = pattern.strip(chars = {'/'}).split('/')
  proxy.routes.add(HardingRoute(
    httpMethod: httpMethod,
    pattern: pattern,
    parts: if pattern == "/": @[] else: parts,
    handlerBlock: handler
  ))
  return self.toValue()

proc routerGetDoImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>get: path do: handler
  return addRouteImpl(interp, self, "GET", args)

proc routerPostDoImpl(interp: var Interpreter, self: Instance,
                      args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>post: path do: handler
  return addRouteImpl(interp, self, "POST", args)

proc routerPutDoImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>put: path do: handler
  return addRouteImpl(interp, self, "PUT", args)

proc routerDeleteDoImpl(interp: var Interpreter, self: Instance,
                        args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>delete: path do: handler
  return addRouteImpl(interp, self, "DELETE", args)

proc routerPatchDoImpl(interp: var Interpreter, self: Instance,
                       args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>patch: path do: handler
  return addRouteImpl(interp, self, "PATCH", args)

proc routerAnyDoImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Router>>any: path do: handler (matches any HTTP method)
  return addRouteImpl(interp, self, "*", args)

proc routerClearImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self == nil or self.nimValue == nil:
    return nilValue()
  let proxy = cast[RouterProxy](self.nimValue)
  proxy.routes.setLen(0)
  return self.toValue()

# ============================================================================
# Native Method Implementations - HttpRequest
# ============================================================================

proc requestMethodImpl(interp: var Interpreter, self: Instance,
                       args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: proxy.httpMethod)

proc requestUriImpl(interp: var Interpreter, self: Instance,
                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: proxy.uri)

proc requestPathImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: proxy.path)

proc requestBodyImpl(interp: var Interpreter, self: Instance,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: proxy.body)

proc requestRemoteAddressImpl(interp: var Interpreter, self: Instance,
                              args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  return NodeValue(kind: vkString, strVal: proxy.remoteAddress)

proc requestHeaderImpl(interp: var Interpreter, self: Instance,
                       args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>header: name
  if self.nimValue == nil or args.len < 1: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let name = if args[0].kind == vkString: args[0].strVal else: ""
  for (k, v) in proxy.headers:
    if k.toLowerAscii() == name.toLowerAscii():
      return NodeValue(kind: vkString, strVal: v)
  return nilValue()

proc requestQueryParamImpl(interp: var Interpreter, self: Instance,
                           args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>queryParam: name
  if self.nimValue == nil or args.len < 1: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let name = if args[0].kind == vkString: args[0].strVal else: ""
  for (k, v) in proxy.queryParams:
    if k == name:
      return NodeValue(kind: vkString, strVal: v)
  return nilValue()

proc requestPathParamImpl(interp: var Interpreter, self: Instance,
                          args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>pathParam: name
  if self.nimValue == nil or args.len < 1: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let name = if args[0].kind == vkString: args[0].strVal else: ""
  for (k, v) in proxy.pathParams:
    if k == name:
      return NodeValue(kind: vkString, strVal: v)
  return nilValue()

proc requestHeadersImpl(interp: var Interpreter, self: Instance,
                        args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>headers - returns a Table of headers
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let tbl = newInstance(tableClass)
  for (k, v) in proxy.headers:
    tbl.entries[NodeValue(kind: vkString, strVal: k)] = NodeValue(kind: vkString, strVal: v)
  return tbl.toValue()

proc requestQueryParamsImpl(interp: var Interpreter, self: Instance,
                            args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>queryParams - returns a Table of query params
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let tbl = newInstance(tableClass)
  for (k, v) in proxy.queryParams:
    tbl.entries[NodeValue(kind: vkString, strVal: k)] = NodeValue(kind: vkString, strVal: v)
  return tbl.toValue()

proc requestPathParamsImpl(interp: var Interpreter, self: Instance,
                           args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>pathParams - returns a Table of path params
  if self.nimValue == nil: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let tbl = newInstance(tableClass)
  for (k, v) in proxy.pathParams:
    tbl.entries[NodeValue(kind: vkString, strVal: k)] = NodeValue(kind: vkString, strVal: v)
  return tbl.toValue()

proc requestFormParamImpl(interp: var Interpreter, self: Instance,
                          args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil or args.len < 1:
    return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let name = if args[0].kind == vkString: args[0].strVal else: ""
  for (k, v) in proxy.formParams:
    if k == name:
      return NodeValue(kind: vkString, strVal: v)
  return nilValue()

proc requestFormParamsImpl(interp: var Interpreter, self: Instance,
                           args: seq[NodeValue]): NodeValue {.nimcall.} =
  if self.nimValue == nil:
    return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  let tbl = newInstance(tableClass)
  for (k, v) in proxy.formParams:
    tbl.entries[NodeValue(kind: vkString, strVal: k)] = NodeValue(kind: vkString, strVal: v)
  return tbl.toValue()

# Response methods

proc requestRespondBodyImpl(interp: var Interpreter, self: Instance,
                            args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>respond: statusCode body: body
  if self.nimValue == nil or args.len < 2: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  if proxy.responded:
    return nilValue()

  let statusCode = if args[0].kind == vkInt: args[0].intVal else: 200
  let body = if args[1].kind == vkString: args[1].strVal else: args[1].toString()

  sendResponse(proxy, PendingResponse(
    statusCode: statusCode,
    headers: @[("Content-Type", "text/plain")],
    body: body
  ))
  proxy.responded = true
  return self.toValue()

proc requestRespondHeadersBodyImpl(interp: var Interpreter, self: Instance,
                                    args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>respond: statusCode headers: headers body: body
  if self.nimValue == nil or args.len < 3: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  if proxy.responded:
    return nilValue()

  let statusCode = if args[0].kind == vkInt: args[0].intVal else: 200

  # Convert headers Table to seq
  var headerSeq: seq[(string, string)] = @[]
  if args[1].kind == vkInstance and args[1].instVal.kind == ikTable:
    for k, v in args[1].instVal.entries:
      let key = if k.kind == vkString: k.strVal else: k.toString()
      let val = if v.kind == vkString: v.strVal else: v.toString()
      headerSeq.add((key, val))

  let body = if args[2].kind == vkString: args[2].strVal else: args[2].toString()

  sendResponse(proxy, PendingResponse(
    statusCode: statusCode,
    headers: headerSeq,
    body: body
  ))
  proxy.responded = true
  return self.toValue()

proc requestRespondImpl(interp: var Interpreter, self: Instance,
                        args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>respond: statusCode
  if self.nimValue == nil or args.len < 1: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  if proxy.responded:
    return nilValue()

  let statusCode = if args[0].kind == vkInt: args[0].intVal else: 200

  sendResponse(proxy, PendingResponse(
    statusCode: statusCode,
    headers: @[],
    body: ""
  ))
  proxy.responded = true
  return self.toValue()

proc requestRespondJsonImpl(interp: var Interpreter, self: Instance,
                            args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## HttpRequest>>respondJson: body
  if self.nimValue == nil or args.len < 1: return nilValue()
  let proxy = cast[RequestProxy](self.nimValue)
  if proxy.responded:
    return nilValue()

  let body = if args[0].kind == vkString: args[0].strVal else: args[0].toString()

  sendResponse(proxy, PendingResponse(
    statusCode: 200,
    headers: @[("Content-Type", "application/json")],
    body: body
  ))
  proxy.responded = true
  return self.toValue()

# ============================================================================
# Bridge Initialization
# ============================================================================

proc initMummyxBridge*(interp: var Interpreter) =
  ## Initialize MummyX bridge - creates classes and registers native methods.
  ## Call this before loading lib/mummyx/Bootstrap.hrd.

  # ---- HttpServer class ----
  httpServerClass = newClass(superclasses = @[objectClass], name = "HttpServer")
  httpServerClass.isNimProxy = true
  httpServerClass.hardingType = "HttpServer"

  httpServerClass.registerClassMethod("new", serverNewImpl, needsInterp = true)
  httpServerClass.registerMethod("router:", serverRouterImpl)
  httpServerClass.registerMethod("requestLogLevel", serverRequestLogLevelImpl)
  httpServerClass.registerMethod("requestLogLevel:", serverSetRequestLogLevelImpl)
  httpServerClass.registerMethod("start:", serverStartImpl)
  httpServerClass.registerMethod("start:address:", serverStartAddressImpl)
  httpServerClass.registerMethod("processRequests", serverProcessRequestsImpl)
  httpServerClass.registerMethod("serveForever:", serverServeForeverImpl)
  httpServerClass.registerMethod("isRunning", serverIsRunningImpl)
  httpServerClass.registerMethod("stop", serverStopImpl)
  httpServerClass.registerMethod("port", serverPortImpl)

  interp.globals[]["HttpServer"] = httpServerClass.toValue()

  # ---- Router class ----
  routerClass = newClass(superclasses = @[objectClass], name = "Router")
  routerClass.isNimProxy = true
  routerClass.hardingType = "Router"

  routerClass.registerClassMethod("new", routerNewImpl, needsInterp = true)
  routerClass.registerMethod("get:do:", routerGetDoImpl)
  routerClass.registerMethod("post:do:", routerPostDoImpl)
  routerClass.registerMethod("put:do:", routerPutDoImpl)
  routerClass.registerMethod("delete:do:", routerDeleteDoImpl)
  routerClass.registerMethod("patch:do:", routerPatchDoImpl)
  routerClass.registerMethod("any:do:", routerAnyDoImpl)
  routerClass.registerMethod("clear", routerClearImpl)

  interp.globals[]["Router"] = routerClass.toValue()

  # ---- HttpRequest class ----
  httpRequestClass = newClass(superclasses = @[objectClass], name = "HttpRequest")
  httpRequestClass.isNimProxy = true
  httpRequestClass.hardingType = "HttpRequest"

  httpRequestClass.registerMethod("method", requestMethodImpl)
  httpRequestClass.registerMethod("uri", requestUriImpl)
  httpRequestClass.registerMethod("path", requestPathImpl)
  httpRequestClass.registerMethod("body", requestBodyImpl)
  httpRequestClass.registerMethod("remoteAddress", requestRemoteAddressImpl)
  httpRequestClass.registerMethod("header:", requestHeaderImpl)
  httpRequestClass.registerMethod("queryParam:", requestQueryParamImpl)
  httpRequestClass.registerMethod("pathParam:", requestPathParamImpl)
  httpRequestClass.registerMethod("headers", requestHeadersImpl)
  httpRequestClass.registerMethod("queryParams", requestQueryParamsImpl)
  httpRequestClass.registerMethod("pathParams", requestPathParamsImpl)
  httpRequestClass.registerMethod("formParam:", requestFormParamImpl)
  httpRequestClass.registerMethod("formParams", requestFormParamsImpl)
  httpRequestClass.registerMethod("respond:", requestRespondImpl)
  httpRequestClass.registerMethod("respond:body:", requestRespondBodyImpl)
  httpRequestClass.registerMethod("respond:headers:body:", requestRespondHeadersBodyImpl)
  httpRequestClass.registerMethod("respondJson:", requestRespondJsonImpl)

  interp.globals[]["HttpRequest"] = httpRequestClass.toValue()
