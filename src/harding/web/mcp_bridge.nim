## MCP Bridge for Harding/MummyX
## 
## Provides MCP (Model Context Protocol) server capabilities via MummyX.
## This module integrates with the existing MummyX infrastructure to handle
## MCP JSON-RPC requests on the Harding main thread.
##
## Usage:
##   server := BonaMCP startDefault.  "Starts MCP on http://localhost:8765/mcp

import std/[json, tables, options, strutils, locks]
import ../core/types
import ../interpreter/objects
import ../interpreter/activation
import ../parser/parser
import mummyx_bridge

## MCP Server State

type
  McpToolDef* = object
    name*: string
    description*: string
    schema*: JsonNode
    handlerBlock*: BlockNode

  McpServerState* = ref object
    name*: string
    version*: string
    tools*: Table[string, McpToolDef]
    initialized*: bool
    lock*: Lock

var
  mcpServers*: Table[int, McpServerState] = initTable[int, McpServerState]()
  nextMcpServerId*: int = 0
  mcpLock*: Lock

initLock(mcpLock)

## MCP Server Management

proc createMcpServer*(name: string, version: string): int =
  ## Create a new MCP server and return its ID
  withLock mcpLock:
    inc nextMcpServerId
    let serverId = nextMcpServerId

    let server = McpServerState(
      name: name,
      version: version,
      tools: initTable[string, McpToolDef](),
      initialized: false
    )
    initLock(server.lock)
    mcpServers[serverId] = server
    return serverId

proc registerMcpTool*(serverId: int, name: string, description: string,
                      schema: JsonNode, handlerBlock: BlockNode): bool =
  ## Register a tool with an MCP server
  withLock mcpLock:
    if serverId notin mcpServers:
      return false

    let server = mcpServers[serverId]
    withLock server.lock:
      server.tools[name] = McpToolDef(
        name: name,
        description: description,
        schema: schema,
        handlerBlock: handlerBlock
      )
    return true

## JSON-RPC Helpers

proc createJsonRpcResponse*(id: JsonNode, res: JsonNode): JsonNode =
  %*{ "jsonrpc": "2.0", "id": id, "result": res }

proc createJsonRpcError*(id: JsonNode, code: int, message: string): JsonNode =
  %*{ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }

## Forward declarations
proc jsonToHarding(node: JsonNode): NodeValue
proc evalBlock(interp: var Interpreter, blockNode: BlockNode, arg: NodeValue): NodeValue

## Helper to convert JSON to Harding values
proc jsonToHarding(node: JsonNode): NodeValue =
  case node.kind
  of JObject:
    var entries = initTable[NodeValue, NodeValue]()
    for key, val in node.pairs:
      entries[NodeValue(kind: vkString, strVal: key)] = jsonToHarding(val)
    if tableClass != nil:
      let tbl = newInstance(tableClass)
      tbl.entries = entries
      return tbl.toValue()
    NodeValue(kind: vkTable, tableVal: entries)
  of JArray:
    var elements: seq[NodeValue] = @[]
    for elem in node.items:
      elements.add(jsonToHarding(elem))
    if arrayClass != nil:
      return newArrayInstance(arrayClass, elements).toValue()
    NodeValue(kind: vkArray, arrayVal: elements)
  of JString:
    NodeValue(kind: vkString, strVal: node.getStr())
  of JInt:
    NodeValue(kind: vkInt, intVal: node.getInt())
  of JFloat:
    NodeValue(kind: vkFloat, floatVal: node.getFloat())
  of JBool:
    NodeValue(kind: vkBool, boolVal: node.getBool())
  of JNull:
    nilValue()

## MCP Protocol Handlers

proc handleMcpInitialize*(server: McpServerState): JsonNode =
  ## Handle initialize request
  server.initialized = true
  %*{
    "protocolVersion": "2024-11-05",
    "serverInfo": { "name": server.name, "version": server.version },
    "capabilities": { "tools": { "listChanged": false } }
  }

proc handleMcpToolsList*(server: McpServerState): JsonNode =
  ## Handle tools/list request
  var tools: seq[JsonNode] = @[]
  withLock server.lock:
    for name, tool in server.tools:
      tools.add(%*{
        "name": name,
        "description": tool.description,
        "inputSchema": tool.schema
      })
  %*{ "tools": tools }

proc handleMcpToolCall*(interp: var Interpreter, server: McpServerState,
                        toolName: string, args: JsonNode): JsonNode =
  ## Handle tools/call request - executes the tool block on the main thread
  var toolDef: McpToolDef
  var found = false

  withLock server.lock:
    if toolName in server.tools:
      toolDef = server.tools[toolName]
      found = true

  if not found:
    return createJsonRpcError(%0, -32601, "Tool not found: " & toolName)

  ## Convert JSON args to Harding Table
  let argsTable = jsonToHarding(args)

  ## Create the job array for the worker: #(replyProxy handlerBlock args)
  ## For now, we execute directly since we're on the main thread
  ## TODO: Dispatch through the scheduler for proper async handling

  try:
    ## Execute the tool block directly
    let result = evalBlock(interp, toolDef.handlerBlock, argsTable)
    let resultStr = result.toString()

    ## Try to parse result as JSON, otherwise wrap as text
    var content: seq[JsonNode] = @[]
    try:
      let resultJson = parseJson(resultStr)
      content.add(%*{
        "type": "text",
        "text": resultStr
      })
    except CatchableError:
      content.add(%*{
        "type": "text",
        "text": resultStr
      })

    return createJsonRpcResponse(%0, %*{ "content": content })

  except CatchableError as e:
    return createJsonRpcError(%0, -32603, "Tool execution error: " & e.msg)

## Main MCP Request Handler

proc dispatchMcpRequest*(interp: var Interpreter, serverId: int, requestBody: string): string =
  ## Dispatch an MCP JSON-RPC request and return the response
  try:
    let req = parseJson(requestBody)
    let id = req{"id"}
    let methodName = req{"method"}.getStr()

    withLock mcpLock:
      if serverId notin mcpServers:
        return $createJsonRpcError(id, -32603, "Server not found")

      let server = mcpServers[serverId]

      case methodName:
        of "initialize":
          return $createJsonRpcResponse(id, handleMcpInitialize(server))

        of "tools/list":
          return $createJsonRpcResponse(id, handleMcpToolsList(server))

        of "tools/call":
          let params = req{"params"}
          let toolName = params{"name"}.getStr()
          let args = params{"arguments"}
          return $handleMcpToolCall(interp, server, toolName, args)

        else:
          return $createJsonRpcError(id, -32601, "Method not found: " & methodName)

  except CatchableError as e:
    return $createJsonRpcError(%0, -32700, "Parse error: " & e.msg)

## Harding Primitive Implementations

proc mcpServerNewImpl(interp: var Interpreter, self: Instance,
                       args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## MCPServer class>>named:version:
  discard self

  let name = if args.len > 0: args[0].toString() else: "mcp"
  let version = if args.len > 1: args[1].toString() else: "0.1.0"

  let serverId = createMcpServer(name, version)

  ## Return server object
  let obj = newInstance(interp.globals[]["MCPServer"].classVal)
  obj.isNimProxy = true
  obj.slots[0] = NodeValue(kind: vkInt, intVal: serverId)  ## serverId slot
  obj.toValue()

proc mcpServerRegisterToolImpl(interp: var Interpreter, self: Instance,
                                args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## MCPServer>>toolNamed:description:schema:do:
  if self.slots.len < 1 or self.slots[0].kind != vkInt:
    return nilValue()

  let serverId = self.slots[0].intVal

  if args.len < 4:
    return nilValue()

  let toolName = args[0].toString()
  let description = args[1].toString()
  let schemaStr = args[2].toString()

  if args[3].kind != vkBlock:
    return nilValue()

  var schema = %*{"type": "object", "properties": %*{}}
  if schemaStr.len > 0:
    try:
      schema = parseJson(schemaStr)
    except CatchableError:
      discard

  if registerMcpTool(serverId, toolName, description, schema, args[3].blockVal):
    return self.toValue()
  else:
    return nilValue()

proc mcpServerStartImpl(interp: var Interpreter, self: Instance,
                         args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## MCPServer>>startOn: port  
  ## This is handled on the Harding side - see MCP.hrd
  ## The Harding code creates HttpServer, sets router, and starts it
  ## We just store the port for reference
  if self.slots.len < 1 or self.slots[0].kind != vkInt:
    return nilValue()

  let port = if args.len > 0: args[0].intVal else: 8765
  
  ## Store port in a slot for reference
  if self.slots.len < 2:
    self.slots.add(NodeValue(kind: vkInt, intVal: port))
  else:
    self.slots[1] = NodeValue(kind: vkInt, intVal: port)

  return self.toValue()

## Initialization

proc registerMcpPrimitives*(interp: var Interpreter) =
  ## Register MCP classes and primitives with Harding

  ## Create MCPServer class
  let mcpServerClass = newClass(superclasses = @[objectClass], name: "MCPServer")
  mcpServerClass.isNimProxy = true

  ## Register methods
  let newMethod = createCoreMethod("named:version:")
  newMethod.nativeImpl = cast[pointer](mcpServerNewImpl)
  newMethod.hasInterpreterParam = true
  addMethodToClass(mcpServerClass, "named:version:", newMethod, isClassMethod = true)

  let registerMethod = createCoreMethod("toolNamed:description:schema:do:")
  registerMethod.nativeImpl = cast[pointer](mcpServerRegisterToolImpl)
  registerMethod.hasInterpreterParam = true
  addMethodToClass(mcpServerClass, "toolNamed:description:schema:do:", registerMethod)

  let startMethod = createCoreMethod("startOn:")
  startMethod.nativeImpl = cast[pointer](mcpServerStartImpl)
  startMethod.hasInterpreterParam = true
  addMethodToClass(mcpServerClass, "startOn:", startMethod)

  interp.globals[]["MCPServer"] = mcpServerClass.toValue()

## Helper to evaluate a block
proc evalBlock(interp: var Interpreter, blockNode: BlockNode, arg: NodeValue): NodeValue =
  ## Evaluate a block with an argument
  ## This is a simplified version - in reality we'd use the full VM
  ## For now, return a placeholder
  NodeValue(kind: vkString, strVal: "Tool executed (placeholder)")
