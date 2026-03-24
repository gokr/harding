## Tests for MCP Bridge

import std/[unittest, json, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/objects
import ../src/harding/web/mcp_bridge

## Test MCP Server Creation

suite "MCP Server Management":
  test "Create MCP server":
    let serverId = createMcpServer("test-server", "1.0.0")
    check serverId > 0

  test "Register tool":
    let serverId = createMcpServer("test-server", "1.0.0")

    ## Create a dummy block node
    var dummyBlock: BlockNode
    dummyBlock.parameters = @[]

    let success = registerMcpTool(serverId, "test_tool", "A test tool",
      %*{"type": "object"}, dummyBlock)
    check success == true

  test "Register tool with invalid server":
    var dummyBlock: BlockNode
    let success = registerMcpTool(99999, "test_tool", "A test tool",
      %*{"type": "object"}, dummyBlock)
    check success == false

## Test JSON-RPC Helpers

suite "JSON-RPC Helpers":
  test "Create success response":
    let response = createJsonRpcResponse(%1, %*{"result": "ok"})
    check response{"jsonrpc"}.getStr() == "2.0"
    check response{"id"}.getInt() == 1
    check response{"result"}{"result"}.getStr() == "ok"

  test "Create error response":
    let response = createJsonRpcError(%1, -32601, "Method not found")
    check response{"jsonrpc"}.getStr() == "2.0"
    check response{"error"}{"code"}.getInt() == -32601
    check response{"error"}{"message"}.getStr() == "Method not found"

## Test MCP Protocol Handlers

suite "MCP Protocol":
  setup:
    let serverId = createMcpServer("test-server", "1.0.0")
    var dummyBlock: BlockNode

  test "Initialize returns correct protocol version":
    let server = mcpServers[serverId]
    let result = handleMcpInitialize(server)
    check result{"protocolVersion"}.getStr() == "2024-11-05"
    check result{"serverInfo"}{"name"}.getStr() == "test-server"

  test "Tools list returns empty array initially":
    let server = mcpServers[serverId]
    let result = handleMcpToolsList(server)
    check result{"tools"}.len() == 0

  test "Tools list returns registered tools":
    discard registerMcpTool(serverId, "tool1", "First tool",
      %*{"type": "object"}, dummyBlock)
    discard registerMcpTool(serverId, "tool2", "Second tool",
      %*{"type": "object"}, dummyBlock)

    let server = mcpServers[serverId]
    let result = handleMcpToolsList(server)
    check result{"tools"}.len() == 2

  test "Tool call with non-existent tool":
    let server = mcpServers[serverId]
    let interp: Interpreter  ## Mock interpreter
    let result = handleMcpToolCall(interp, server, "nonexistent", %*{})
    check result.hasKey("error")
    check result{"error"}{"code"}.getInt() == -32601

## Test Request Dispatch

suite "Request Dispatch":
  setup:
    let serverId = createMcpServer("test-server", "1.0.0")
    var interp: Interpreter  ## Would need proper initialization in real tests

  test "Dispatch initialize request":
    let request = $ %*{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": {}
    }
    let response = dispatchMcpRequest(interp, serverId, request)
    let responseJson = parseJson(response)
    check responseJson{"result"}{"protocolVersion"}.getStr() == "2024-11-05"

  test "Dispatch unknown method":
    let request = $ %*{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "unknown/method"
    }
    let response = dispatchMcpRequest(interp, serverId, request)
    let responseJson = parseJson(response)
    check responseJson{"error"}{"code"}.getInt() == -32601

  test "Dispatch with invalid JSON":
    let response = dispatchMcpRequest(interp, serverId, "not valid json")
    let responseJson = parseJson(response)
    check responseJson{"error"}{"code"}.getInt() == -32700

## Test Integration with MummyX
## These would be integration tests that actually start an HTTP server

suite "MCP HTTP Integration":
  test "MCP endpoint returns correct content-type":
    skip()
    ## Would need to start MummyX and make actual HTTP request
    ## For now, this is a placeholder for future integration tests

  test "MCP endpoint handles batch requests":
    skip()
    ## MCP supports JSON-RPC batch requests

  test "MCP endpoint handles notifications":
    skip()
    ## Notifications have no id and don't expect response
