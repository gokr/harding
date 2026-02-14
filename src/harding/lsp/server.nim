#
# server.nim - Harding Language Server Protocol (LSP) implementation
#
# JSON-RPC over stdio (standard LSP transport)
#

import std/[json, strutils, tables, os, streams, logging]
import ../core/types
import ../parser/lexer
import ../parser/parser

# ============================================================================
# LSP Constants
# ============================================================================

const
  LSP_VERSION* = "1.0"
  LSP_CONTENT_TYPE* = "application/vscode-jsonrpc; charset=utf-8"

# ============================================================================
# LSP Server State
# ============================================================================

type
  LspServer* = ref object
    running*: bool
    capabilities*: JsonNode
    documents*: Table[string, Document]  # uri -> document
    nextRequestId*: int

  Document* = object
    uri*: string
    text*: string
    version*: int
    ast*: seq[Node]
    symbols*: seq[DocumentSymbol]

  DocumentSymbol* = object
    name*: string
    kind*: SymbolKind
    line*: int
    col*: int
    containerName*: string

  SymbolKind* = enum
    skFile = 1, skModule = 2, skNamespace = 3, skPackage = 4,
    skClass = 5, skMethod = 6, skProperty = 7, skField = 8,
    skConstructor = 9, skEnum = 10, skInterface = 11, skFunction = 12,
    skVariable = 13, skConstant = 14, skString = 15, skNumber = 16,
    skBoolean = 17, skArray = 18, skObject = 19, skKey = 20,
    skNull = 21, skEnumMember = 22, skStruct = 23, skEvent = 24,
    skOperator = 25, skTypeParameter = 26

# ============================================================================
# Server Initialization
# ============================================================================

proc newLspServer*(): LspServer =
  ## Create a new LSP server
  new(result)
  result.running = false
  result.documents = initTable[string, Document]()
  result.nextRequestId = 1

  # Server capabilities
  result.capabilities = %*{
    "textDocumentSync": 1,  # Full document sync
    "hoverProvider": true,
    "completionProvider": {
      "triggerCharacters": [":", ">", " ", "'", "\""]
    },
    "definitionProvider": true,
    "documentSymbolProvider": true,
    "workspaceSymbolProvider": true,
    "referencesProvider": false,  # Not yet implemented
    "renameProvider": false       # Not yet implemented
  }

# ============================================================================
# Message I/O
# ============================================================================

proc readMessage*(server: LspServer): JsonNode =
  ## Read a JSON-RPC message from stdin
  ## Format: Content-Length: N\r\n\r\n{json}
  var headerLine = ""
  var contentLength = -1

  # Read headers
  while true:
    let c = stdin.readChar()
    if c == '\r':
      let next = stdin.readChar()
      if next == '\n':
        if headerLine.len == 0:
          # Empty line - end of headers
          break
        # Parse Content-Length header
        if headerLine.startsWith("Content-Length:"):
          let lenStr = headerLine[15..^1].strip()
          contentLength = parseInt(lenStr)
        headerLine = ""
      else:
        headerLine.add(c)
        headerLine.add(next)
    else:
      headerLine.add(c)

  if contentLength < 0:
    raise newException(IOError, "Missing Content-Length header")

  # Read the JSON content
  var content = newString(contentLength)
  if stdin.readChars(content) != contentLength:
    raise newException(IOError, "Could not read full message content")

  return parseJson(content)

proc sendMessage*(server: LspServer, msg: JsonNode) =
  ## Send a JSON-RPC message to stdout
  let content = $msg
  let contentLength = content.len

  stdout.write("Content-Length: ")
  stdout.write($contentLength)
  stdout.write("\r\n\r\n")
  stdout.write(content)
  stdout.flushFile()

proc sendResponse*(server: LspServer, id: JsonNode, result: JsonNode = nil, error: JsonNode = nil) =
  ## Send a JSON-RPC response
  var response = %*{
    "jsonrpc": "2.0",
    "id": id
  }
  if result != nil:
    response["result"] = result
  if error != nil:
    response["error"] = error
  server.sendMessage(response)

proc sendNotification*(server: LspServer, methodName: string, params: JsonNode) =
  ## Send a JSON-RPC notification
  let notification = %*{
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }
  server.sendMessage(notification)

# ============================================================================
# Document Management
# ============================================================================

proc parseDocument*(server: LspServer, uri: string, text: string): Document =
  ## Parse a document and extract symbols
  result = Document(
    uri: uri,
    text: text,
    version: 1,
    ast: @[],
    symbols: @[]
  )

  let tokens = lex(text)
  var parser = initParser(tokens, uri)
  result.ast = parser.parseStatements()

  # Extract symbols from AST
  # TODO: Add more symbol types when parser supports class definition nodes
  for node in result.ast:
    case node.kind:
      of nkAssign:
        # Assignment - could be a variable or class definition
        # For now, just note that something is being assigned
        discard
      else:
        discard

proc updateDocument*(server: LspServer, uri: string, text: string, version: int) =
  ## Update a document's content
  var doc = server.parseDocument(uri, text)
  doc.version = version
  server.documents[uri] = doc

proc getDocument*(server: LspServer, uri: string): Document =
  ## Get a document by URI
  if server.documents.hasKey(uri):
    return server.documents[uri]
  raise newException(KeyError, "Document not found: " & uri)

# ============================================================================
# Request Handlers
# ============================================================================

proc handleInitialize(server: LspServer, params: JsonNode): JsonNode =
  ## Handle initialize request
  result = %*{
    "capabilities": server.capabilities
  }

proc handleShutdown(server: LspServer, params: JsonNode): JsonNode =
  ## Handle shutdown request
  server.running = false
  result = newJNull()

proc handleTextDocumentDidOpen(server: LspServer, params: JsonNode) =
  ## Handle textDocument/didOpen notification
  let textDoc = params["textDocument"]
  let uri = textDoc["uri"].getStr()
  let text = textDoc["text"].getStr()
  let version = textDoc["version"].getInt()
  server.updateDocument(uri, text, version)

proc handleTextDocumentDidChange(server: LspServer, params: JsonNode) =
  ## Handle textDocument/didChange notification
  let textDoc = params["textDocument"]
  let uri = textDoc["uri"].getStr()
  let version = textDoc["version"].getInt()
  let contentChanges = params["contentChanges"]

  if contentChanges.len > 0:
    # For full document sync, just take the first change
    let text = contentChanges[0]["text"].getStr()
    server.updateDocument(uri, text, version)

proc handleTextDocumentDidClose(server: LspServer, params: JsonNode) =
  ## Handle textDocument/didClose notification
  let uri = params["textDocument"]["uri"].getStr()
  if server.documents.hasKey(uri):
    server.documents.del(uri)

proc handleTextDocumentHover(server: LspServer, params: JsonNode): JsonNode =
  ## Handle textDocument/hover request
  let uri = params["textDocument"]["uri"].getStr()
  let position = params["position"]
  let line = position["line"].getInt()
  let character = position["character"].getInt()

  # Simple hover - just show the line text
  try:
    let doc = server.getDocument(uri)
    let lines = doc.text.splitLines()
    if line < lines.len:
      let lineText = lines[line]
      result = %*{
        "contents": {
          "kind": "plaintext",
          "value": lineText
        }
      }
    else:
      result = newJNull()
  except:
    result = newJNull()

proc handleTextDocumentCompletion(server: LspServer, params: JsonNode): JsonNode =
  ## Handle textDocument/completion request
  # Return basic Harding keywords and common selectors
  var items = newJArray()

  # Common Harding selectors
  let selectors = @[
    "new", "clone", "derive:", "deriveWithAccessors:", "extend:", "extendClass:",
    "at:", "at:put:", "do:", "select:", "collect:", "size", "isEmpty", "notEmpty",
    "keys", "values", "includesKey:", "ifTrue:", "ifFalse:", "ifTrue:ifFalse:",
    "whileTrue:", "whileFalse:", "value", "value:", "value:value:", "class",
    "printString", "asString", "yourself"
  ]

  for selector in selectors:
    items.add(%*{
      "label": selector,
      "kind": 3  # Function
    })

  result = %*{ "items": items }

proc handleTextDocumentDefinition(server: LspServer, params: JsonNode): JsonNode =
  ## Handle textDocument/definition request
  # Not fully implemented - just return empty for now
  result = newJNull()

proc handleTextDocumentDocumentSymbol(server: LspServer, params: JsonNode): JsonNode =
  ## Handle textDocument/documentSymbol request
  let uri = params["textDocument"]["uri"].getStr()

  try:
    let doc = server.getDocument(uri)
    var symbols = newJArray()

    for sym in doc.symbols:
      symbols.add(%*{
        "name": sym.name,
        "kind": ord(sym.kind),
        "location": {
          "uri": uri,
          "range": {
            "start": {"line": sym.line, "character": sym.col},
            "end": {"line": sym.line, "character": sym.col + sym.name.len}
          }
        }
      })

    result = symbols
  except:
    result = newJArray()

proc handleWorkspaceSymbol(server: LspServer, params: JsonNode): JsonNode =
  ## Handle workspace/symbol request
  # Search across all documents
  let query = params["query"].getStr().toLowerAscii()
  var results = newJArray()

  for uri, doc in server.documents:
    for sym in doc.symbols:
      if query.len == 0 or sym.name.toLowerAscii().contains(query):
        results.add(%*{
          "name": sym.name,
          "kind": ord(sym.kind),
          "location": {
            "uri": uri,
            "range": {
              "start": {"line": sym.line, "character": sym.col},
              "end": {"line": sym.line, "character": sym.col + sym.name.len}
            }
          }
        })

  result = results

# ============================================================================
# Main Loop
# ============================================================================

proc processRequest*(server: LspServer, msg: JsonNode): JsonNode =
  ## Process a JSON-RPC request
  let methodName = msg["method"].getStr()
  let params = if msg.hasKey("params"): msg["params"] else: newJNull()

  case methodName:
    of "initialize":
      return handleInitialize(server, params)
    of "shutdown":
      return handleShutdown(server, params)
    of "textDocument/hover":
      return handleTextDocumentHover(server, params)
    of "textDocument/completion":
      return handleTextDocumentCompletion(server, params)
    of "textDocument/definition":
      return handleTextDocumentDefinition(server, params)
    of "textDocument/documentSymbol":
      return handleTextDocumentDocumentSymbol(server, params)
    of "workspace/symbol":
      return handleWorkspaceSymbol(server, params)
    else:
      # Notification methods (no response needed)
      if methodName == "initialized":
        return nil
      if methodName == "textDocument/didOpen":
        handleTextDocumentDidOpen(server, params)
        return nil
      if methodName == "textDocument/didChange":
        handleTextDocumentDidChange(server, params)
        return nil
      if methodName == "textDocument/didClose":
        handleTextDocumentDidClose(server, params)
        return nil
      if methodName == "exit":
        server.running = false
        return nil

      # Method not found
      return %*{
        "code": -32601,
        "message": "Method not found: " & methodName
      }

proc runLspServer*() =
  ## Run the LSP server main loop
  var server = newLspServer()
  server.running = true

  # Use a wrapper to catch errors
  try:
    while server.running:
      try:
        let msg = server.readMessage()

        if msg.hasKey("id"):
          # This is a request - send a response
          let id = msg["id"]
          let result = server.processRequest(msg)

          if result != nil:
            if result.hasKey("code") and result.hasKey("message"):
              # Error response
              server.sendResponse(id, nil, result)
            else:
              # Success response
              server.sendResponse(id, result)
        else:
          # This is a notification - process without response
          discard server.processRequest(msg)

      except JsonParsingError as e:
        stderr.writeLine("JSON parse error: ", e.msg)
      except IOError as e:
        stderr.writeLine("IO error: ", e.msg)
        server.running = false
      except Exception as e:
        stderr.writeLine("Error: ", e.msg)

  except Exception as e:
    stderr.writeLine("Fatal error in LSP server: ", e.msg)
    quit(1)
