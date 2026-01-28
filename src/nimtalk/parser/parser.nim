import std/[strutils, logging]
import ../parser/lexer
import ../core/types

# ============================================================================
# Parser for Nimtalk
# Parses Smalltalk-style syntax into AST nodes
# ============================================================================

type
  Parser* = ref object
    tokens*: seq[Token]
    pos*: int
    pendingCascade*: bool
    hasError*: bool
    errorMsg*: string
    lastLine*, lastCol*: int

# Forward declarations for recursive parsing functions
proc parseExpression*(parser: var Parser; parseMessages = true): Node
proc parseBlock*(parser: var Parser): BlockNode
proc parseArrayLiteral(parser: var Parser): ArrayNode
proc parseTableLiteral(parser: var Parser): TableNode
proc parseObjectLiteral(parser: var Parser): ObjectLiteralNode
proc parseStatement(parser: var Parser; parseMessages = true): Node
proc parseMethod(parser: var Parser): BlockNode
proc parsePrimitive(parser: var Parser): PrimitiveNode
proc checkForCascade(parser: var Parser, primary: Node, firstMsg: MessageNode): Node
proc parseMethodDefinition(parser: var Parser, receiver: Node): Node

# Parser errors
proc parseError*(parser: var Parser, msg: string) =
  parser.hasError = true
  if parser.pos < parser.tokens.len:
    let token = parser.tokens[parser.pos]
    parser.errorMsg = "Parse error at line " & $token.line & ", col " & $token.col & ": " & msg
    parser.lastLine = token.line
    parser.lastCol = token.col
  else:
    parser.errorMsg = "Parse error: " & msg
    parser.lastLine = parser.lastLine
    parser.lastCol = parser.lastCol

# Initialize parser
proc initParser*(tokens: seq[Token], filename: string = ""): Parser =
  result = Parser(
    tokens: tokens,
    pos: 0,
    pendingCascade: false,
    hasError: false,
    errorMsg: "",
    lastLine: 1,
    lastCol: 1
  )

# Peek at current token without advancing
proc peek*(parser: var Parser): Token =
  if parser.pos < parser.tokens.len:
    return parser.tokens[parser.pos]
  else:
    return Token(kind: tkEOF, value: "")

# Get current token and advance
proc next(parser: var Parser): Token =
  if parser.pos < parser.tokens.len:
    let token = parser.tokens[parser.pos]
    inc parser.pos
    parser.lastLine = token.line
    parser.lastCol = token.col
    return token
  else:
    return Token(kind: tkEOF, value: "")

# Check if next token matches expected kind
proc expect(parser: var Parser, kind: TokenKind): bool =
  if parser.peek().kind == kind:
    discard parser.next()
    return true
  else:
    return false


# Parse primary expressions
proc parsePrimary(parser: var Parser): Node =
  let token = parser.peek()

  case token.kind
  of tkInt:
    discard parser.next()
    return LiteralNode(value: NodeValue(kind: vkInt, intVal: parseInt(token.value)))

  of tkFloat:
    discard parser.next()
    return LiteralNode(value: NodeValue(kind: vkFloat, floatVal: parseFloat(token.value)))

  of tkString:
    discard parser.next()
    return LiteralNode(value: NodeValue(kind: vkString, strVal: token.value))

  of tkSymbol:
    discard parser.next()
    return LiteralNode(value: getSymbol(token.value))

  of tkIdent:
    discard parser.next()
    # Identifiers can be variables or message receivers
    return LiteralNode(value: getSymbol(token.value))

  of tkLParen:
    # Parenthesized expression
    discard parser.next()  # Skip (
    let expr = parser.parseExpression()
    if not parser.expect(tkRParen):
      parser.parseError("Expected ')'")
    return expr

  of tkLBracket:
    # Block literal
    debug("parsePrimary: found block [")
    return parser.parseBlock()

  of tkArrayStart:
    # Array literal #(...)
    return parser.parseArrayLiteral()

  of tkTableStart:
    # Table literal #{...}
    return parser.parseTableLiteral()

  of tkObjectStart:
    # Object literal {| ... |}
    return parser.parseObjectLiteral()

  of tkRBracket:
    # Closing bracket - can appear when parsing blocks
    # Return nil to indicate end of block
    return nil

  else:
    debug("parsePrimary: unexpected token ", token.value)
    parser.parseError("Unexpected token: " & token.value)
    return nil

# Parse keyword message
proc parseKeywordMessage(parser: var Parser, receiver: Node): MessageNode =
  debug("parseKeywordMessage: entering, receiver type=", receiver.kind, " current token=", parser.peek().kind)
  var selector = ""
  var arguments = newSeq[Node]()

  # Collect keyword segments and arguments
  while parser.peek().kind == tkKeyword:
    let token = parser.next()
    selector.add(token.value)  # Includes colon

    let arg = parser.parseExpression(parseMessages = false)
    if arg == nil:
      parser.parseError("Expected argument after keyword")
      return nil
    arguments.add(arg)

  return MessageNode(
    receiver: receiver,
    selector: selector,
    arguments: arguments,
    isCascade: false
  )

# Parse binary/unary messages
proc parseBinaryMessage(parser: var Parser, receiver: Node): MessageNode =
  # If there are no unary messages, return the receiver wrapped as a message
  # This should not happen in practice as we only call this when we detect messages
  if not (parser.peek().kind == tkIdent and parser.peek().value[0].isLowerAscii()):
    # Should not get here - but create a dummy message to satisfy return type
    return MessageNode(receiver: receiver, selector: "", arguments: @[], isCascade: false)

  # Parse the first unary message
  var msg: MessageNode
  if parser.peek().kind == tkIdent and parser.peek().value[0].isLowerAscii():
    let token = parser.next()
    msg = MessageNode(
      receiver: receiver,
      selector: token.value,
      arguments: @[],
      isCascade: false
    )

    # Continue parsing additional unary messages
    while parser.peek().kind == tkIdent and parser.peek().value[0].isLowerAscii():
      let token = parser.next()
      msg = MessageNode(
        receiver: msg,
        selector: token.value,
        arguments: @[],
        isCascade: false
      )

  # Binary messages (operators - not yet implemented)
  # For now, treat binary operators as keywords

  return msg

# Parse expressions with precedence (no cascade detection)
proc parseExpression*(parser: var Parser; parseMessages = true): Node =
  # Start with primary
  let primary = parser.parsePrimary()
  if primary == nil:
    return nil

  # Check for messages
  if parseMessages:
    let next = parser.peek()
    case next.kind
    of tkKeyword:
      # Keyword message
      return parser.parseKeywordMessage(primary)
    of tkIdent:
      if next.value[0].isLowerAscii():
        # Unary message
        return parser.parseBinaryMessage(primary)
      else:
        return primary
    of tkPlus, tkMinus, tkComma:
      # Binary operator - handle very simple left-to-right for now
      discard parser.next()  # Skip operator
      let right = parser.parseExpression(parseMessages)
      if right == nil:
        return nil

      # Create a message node for the operator
      return MessageNode(
        receiver: primary,
        selector: next.value,  # Use the actual operator (+, -, or ,)
        arguments: @[right],
        isCascade: false
      )
    else:
      return primary
  else:
    # Don't parse any messages, just return the primary
    return primary

# Parse cascade messages
proc checkForCascade(parser: var Parser, primary: Node, firstMsg: MessageNode): Node =
  ## Check for cascade and collect all messages separated by ;
  var messages = @[firstMsg]

  # Determine the receiver for the cascade
  let cascadeReceiver = if primary != nil:
                          primary
                        else:
                          firstMsg.receiver

  # Check if we have a cascade
  var safetyCounter = 0
  const MAX_CASCADE_MESSAGES = 100  # Safety limit

  while parser.peek().kind == tkSpecial and parser.peek().value == ";":
    inc safetyCounter
    if safetyCounter > MAX_CASCADE_MESSAGES:
      parser.parseError("Too many cascade messages (infinite loop?)")
      return nil

    discard parser.next()  # Skip ;

    # Parse next message (could be unary, binary, or keyword)
    let next = parser.peek()
    var nextMsg: MessageNode

    case next.kind
    of tkKeyword:
      # Keyword message - need to parse it to get arguments
      nextMsg = parser.parseKeywordMessage(cascadeReceiver)
    of tkIdent:
      if next.value[0].isLowerAscii():
        # Unary message
        nextMsg = parser.parseBinaryMessage(cascadeReceiver)
      else:
        parser.parseError("Expected message after ;")
        return nil
    of tkPlus, tkMinus:
      # Binary operator
      discard parser.next()  # Skip operator
      let right = parser.parseExpression(parseMessages = false)
      if right == nil:
        parser.parseError("Expected expression after binary operator")
        return nil

      nextMsg = MessageNode(
        receiver: cascadeReceiver,
        selector: next.value,
        arguments: @[right],
        isCascade: false
      )
    else:
      parser.parseError("Expected message after ;")
      return nil

    messages.add(nextMsg)

  # If we have multiple messages, return a CascadeNode
  if messages.len > 1:
    return CascadeNode(receiver: cascadeReceiver, messages: messages)
  else:
    # Single message (no cascade), return nil to use original expression
    return nil

# Parse block literal
proc parseBlock*(parser: var Parser): BlockNode =
  if not parser.expect(tkLBracket):
    parser.parseError("Expected '[' for block start")
    return nil

  let blk = BlockNode()
  blk.parameters = @[]
  blk.temporaries = @[]
  blk.body = @[]
  blk.isMethod = false

  # Check for parameters [:x :y | ...]
  if parser.peek().kind == tkColon:
    # Consume initial colon
    discard parser.next()

    # Parse parameters: identifier (colon identifier)*
    while parser.peek().kind == tkIdent:
      if parser.expect(tkIdent):
        let paramToken = parser.tokens[parser.pos - 1]
        blk.parameters.add(paramToken.value)
      else:
        break

      # Optional colon before next parameter
      if parser.peek().kind == tkColon:
        discard parser.next()

    # Expect | after parameters
    if not (parser.peek().kind == tkSpecial and parser.peek().value == "|"):
      parser.parseError("Expected | after block parameters")
      return nil
    discard parser.next()

  # Parse statements until closing bracket
  while true:
    # Check for closing bracket first
    if parser.expect(tkRBracket):
      break

    # Check for EOF
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed block - expected ']'")
      return nil

    let stmt = parser.parseStatement(parseMessages = true)
    if stmt != nil:
      blk.body.add(stmt)
    else:
      break

  # After loop, make sure we found the closing bracket
  if parser.peek().kind == tkRBracket:
    discard parser.next()

  return blk

# Parse array literal #(...)
proc parseArrayLiteral(parser: var Parser): ArrayNode =
  if not parser.expect(tkArrayStart):
    parser.parseError("Expected '#(' for array literal start")
    return nil

  let array = ArrayNode()
  array.elements = @[]

  # Parse elements until closing )
  while not parser.expect(tkRParen):
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed array literal - expected ')'")
      return nil

    # Parse expression (element) - don't parse messages inside arrays
    let element = parser.parseExpression(parseMessages = false)
    if element == nil:
      parser.parseError("Expected array element")
      return nil
    array.elements.add(element)

    # Skip optional whitespace (already handled by lexer)

  return array

# Parse table literal #{...}
proc parseTableLiteral(parser: var Parser): TableNode =
  if not parser.expect(tkTableStart):
    parser.parseError("Expected '#{' for table literal start")
    return nil

  let table = TableNode()
  table.entries = @[]

  # Parse entries until closing }
  while not (parser.peek().kind == tkSpecial and parser.peek().value == "}"):
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed table literal - expected '}'")
      return nil

    # Parse key
    let key = parser.parseExpression()
    if key == nil:
      parser.parseError("Expected table key")
      return nil

    # Expect arrow ->
    if not (parser.expect(tkArrow)):
      parser.parseError("Expected '->' after table key")
      return nil

    # Parse value
    let value = parser.parseExpression(parseMessages = true)
    if value == nil:
      parser.parseError("Expected table value after '->'")
      return nil

    table.entries.add((key, value))

    # Skip optional whitespace

  # Consume closing }
  discard parser.next()  # Skip }

  return table

# Parse object literal {| ... |}
proc parseObjectLiteral(parser: var Parser): ObjectLiteralNode =
  if not parser.expect(tkObjectStart):
    parser.parseError("Expected '{|' for object literal start")
    return nil

  let obj = ObjectLiteralNode()
  obj.properties = @[]

  # Parse properties until closing |}
  while not (parser.peek().kind == tkSpecial and parser.peek().value == "|"):
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed object literal - expected '|'")
      return nil

    # Property name (identifier)
    if not parser.expect(tkIdent):
      parser.parseError("Expected property name in object literal")
      return nil
    let propName = parser.tokens[parser.pos - 1].value

    # Expect colon :
    if not parser.expect(tkColon):
      parser.parseError("Expected ':' after property name")
      return nil

    # Parse value
    let value = parser.parseExpression(parseMessages = true)
    if value == nil:
      parser.parseError("Expected property value after ':'")
      return nil

    obj.properties.add((propName, value))

    # Skip optional whitespace

  # Consume closing |
  discard parser.next()

  # Expect closing }
  if not (parser.peek().kind == tkSpecial and parser.peek().value == "}"):
    parser.parseError("Expected '}' after '|' in object literal")
    return nil
  discard parser.next()

  return obj

# Parse statement (expression or assignment)
proc parseStatement(parser: var Parser; parseMessages = true): Node =
  # Skip separators and periods at the start
  while parser.expect(tkSeparator) or parser.expect(tkPeriod):
    discard

  # Check for EOF
  if parser.peek().isEOF:
    return nil

  # Check for primitive declaration
  if parser.peek().kind == tkTag and parser.peek().value.startsWith("primitive"):
    return parser.parsePrimitive()

  # Check for return statement
  if parser.expect(tkReturn):
    let expr = parser.parseExpression(parseMessages = parseMessages)
    return ReturnNode(expression: expr)

  # Parse expression
  let expr = parser.parseExpression(parseMessages = parseMessages)
  if expr == nil:
    return nil

  # Check for cascade - extract receiver if it's a message
  if expr of MessageNode:
    let msg = expr.MessageNode
    let cascadeReceiver = msg.receiver
    # Create a new message with nil receiver for cascade detection
    let msgWithNilReceiver = MessageNode(
      receiver: nil,
      selector: msg.selector,
      arguments: msg.arguments,
      isCascade: false
    )
    let cascaded = parser.checkForCascade(cascadeReceiver, msgWithNilReceiver)
    if cascaded != nil:
      return cascaded

  # Check for method definition syntax: Receiver>>selector [ body ]
  if parser.peek().kind == tkMethodDef:
    return parser.parseMethodDefinition(expr)

  # Check for assignment :=
  if parser.peek().kind == tkAssign:
    discard parser.next()

    # Left side must be a symbol
    if expr of LiteralNode and expr.LiteralNode.value.kind == vkSymbol:
      let varName = expr.LiteralNode.value.symVal
      let valueExpr = parser.parseExpression()
      if valueExpr == nil:
        parser.parseError("Expected expression after :=")
        return nil
      return AssignNode(variable: varName, expression: valueExpr)
    else:
      parser.parseError("Can only assign to variable name")
      return nil
  else:
    return expr

# Parse block literal (defined above at line 209)

# Parse method definition (block with isMethod flag)
proc parseMethod(parser: var Parser): BlockNode =
  let blk = parser.parseBlock()
  if blk != nil:
    blk.isMethod = true
  return blk

# Parse method definition syntax: Receiver>>selector [ body ]
# Transforms to: Receiver at: "selector" put: [ body ]
proc parseMethodDefinition(parser: var Parser, receiver: Node): Node =
  ## Parse >> method definition and generate at:put: message

  # Consume >> token
  discard parser.next()

  # Parse method selector
  var selector: string
  var params: seq[string] = @[]

  # Check what kind of selector we have
  let tok = parser.peek()

  if tok.kind == tkIdent:
    # Unary: just an identifier like 'greet'
    selector = parser.next().value
  elif tok.kind == tkKeyword:
    # Keyword: one or more keyword parts like 'at:put:' or 'name:'
    while parser.peek().kind == tkKeyword:
      let keywordPart = parser.next().value
      selector.add(keywordPart)
      # Each keyword part has a parameter
      if parser.peek().kind == tkIdent:
        params.add(parser.next().value)
      else:
        parser.parseError("Expected parameter name after keyword part: " & keywordPart)
        return nil
  elif tok.kind == tkSpecial or tok.kind == tkPlus or tok.kind == tkMinus or tok.kind == tkComma:
    # Binary operator like '+', '-', etc.
    selector = parser.next().value
    # Binary operators have one parameter
    if parser.peek().kind == tkIdent:
      params.add(parser.next().value)
    else:
      parser.parseError("Expected parameter name for binary operator: " & selector)
      return nil
  else:
    parser.parseError("Expected method selector after >>")
    return nil

  # Expect [ for method body
  if not parser.expect(tkLBracket):
    parser.parseError("Expected '[' for method body after selector: " & selector)
    return nil

  # Parse method body as a block
  let blk = parser.parseBlock()
  if blk == nil:
    return nil

  # Mark as method
  blk.isMethod = true

  # Set parameters if we have keyword/binary selector params
  if params.len > 0:
    blk.parameters = params

  # Generate at:put: message
  # Receiver at: "selector" put: [ body ]
  let arg1: Node = LiteralNode(value: NodeValue(kind: vkSymbol, symVal: selector))
  let arg2: Node = LiteralNode(value: NodeValue(kind: vkBlock, blockVal: blk))
  return MessageNode(
    receiver: receiver,
    selector: "at:put:",
    arguments: @[arg1, arg2],
    isCascade: false
  )

# Parse primitive declaration: <primitive> ... </primitive> followed by Smalltalk fallback
proc parsePrimitive(parser: var Parser): PrimitiveNode =
  let startLine = parser.lastLine
  let startCol = parser.lastCol

  # Expect opening <primitive> tag
  let openingTag = parser.next()
  if openingTag.kind != tkTag or not openingTag.value.startsWith("primitive"):
    parser.parseError("Expected <primitive> tag")
    return nil

  # Collect Nim code tokens until closing </primitive>
  var nimCode = ""
  while parser.pos < parser.tokens.len:
    let token = parser.peek()
    if token.kind == tkTag and token.value.startsWith("/primitive"):
      # Closing tag - consume it and break
      discard parser.next()
      break
    elif token.kind == tkNimCode:
      nimCode.add(token.value)
      discard parser.next()
    else:
      # Unexpected token in Nim code (should not happen)
      parser.parseError("Expected Nim code or closing tag")
      return nil

  # Parse remaining statements as fallback
  var fallback: seq[Node] = @[]
  while parser.pos < parser.tokens.len:
    # Skip separators and periods before checking for end
    while parser.expect(tkSeparator) or parser.expect(tkPeriod):
      discard
    # Check if we've reached the end of the block/method
    if parser.peek().kind in {tkRBracket, tkPeriod, tkEOF}:
      break
    let stmt = parser.parseStatement(parseMessages = true)
    if stmt != nil:
      fallback.add(stmt)
    # Skip separators and periods after statement
    while parser.expect(tkSeparator) or parser.expect(tkPeriod):
      discard
    if parser.hasError:
      break

  let prim = PrimitiveNode()
  prim.line = startLine
  prim.col = startCol
  prim.tag = openingTag.value
  prim.nimCode = nimCode
  prim.fallback = fallback
  return prim

# Parse sequence of statements (method body or REPL input)
proc parseStatements*(parser: var Parser): seq[Node] =
  result = @[]

  while not parser.peek().isEOF:
    let stmt = parser.parseStatement(parseMessages = true)
    if stmt != nil:
      result.add(stmt)

    # Skip separators and periods
    while parser.expect(tkSeparator) or parser.expect(tkPeriod):
      discard

    if parser.hasError:
      break

# Convenience function to parse full input
proc parse*(input: string): (seq[Node], Parser) =
  ## Parse entire input string and return AST
  let tokens = lex(input)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()
  return (nodes, parser)

# Convenience function for REPL - parse single expression
proc parseExpression*(input: string): (Node, Parser) =
  ## Parse a single expression for REPL
  let tokens = lex(input)
  var parser = initParser(tokens)
  let node = parser.parseExpression(parseMessages = true)
  return (node, parser)

# Convenience function to parse a method
proc parseMethod*(input: string): (BlockNode, Parser) =
  ## Parse a method definition
  let tokens = lex(input)
  var parser = initParser(tokens)
  let meth = parser.parseMethod()
  return (meth, parser)

# AST printing for debugging
proc printAST*(node: Node, indent: int = 0): string =
  ## Pretty print AST for debugging
  let spaces = repeat(' ', indent * 2)

  if node == nil:
    return spaces & "nil\n"

  case node.kind
  of nkLiteral:
    return spaces & "Literal(" & node.LiteralNode.value.toString() & ")\n"

  of nkMessage:
    let msg = node.MessageNode
    var res = spaces & "Message(" & msg.selector & ")\n"
    res.add(spaces & "  receiver:\n")
    if msg.receiver != nil:
      res.add(printAST(msg.receiver, indent + 2))
    else:
      res.add(spaces & "    (implicit self)\n")
    for arg in msg.arguments:
      res.add(spaces & "  arg:\n")
      res.add(printAST(arg, indent + 2))
    return res

  of nkBlock:
    let blk = node.BlockNode
    var res = spaces & "Block"
    if blk.isMethod:
      res.add(" (method)")
    res.add("\n")
    if blk.parameters.len > 0:
      res.add(spaces & "  params: " & $blk.parameters & "\n")
    if blk.temporaries.len > 0:
      res.add(spaces & "  temps: " & $blk.temporaries & "\n")
    res.add(spaces & "  body:\n")
    for stmt in blk.body:
      res.add(printAST(stmt, indent + 2))
    return res

  of nkAssign:
    let assign = node.AssignNode
    var res = spaces & "Assign(" & assign.variable & ")\n"
    res.add(spaces & "  value:\n")
    res.add(printAST(assign.expression, indent + 2))
    return res

  of nkReturn:
    let ret = node.ReturnNode
    var res = spaces & "Return\n"
    if ret.expression != nil:
      res.add(spaces & "  value:\n")
      res.add(printAST(ret.expression, indent + 2))
    else:
      res.add(spaces & "  (self)\n")
    return res

  of nkPrimitive:
    let prim = node.PrimitiveNode
    var res = spaces & "Primitive(" & prim.tag & ")\n"
    res.add(spaces & "  nimCode: " & $prim.nimCode.len & " chars\n")
    if prim.fallback.len > 0:
      res.add(spaces & "  fallback:\n")
      for stmt in prim.fallback:
        res.add(printAST(stmt, indent + 2))
    return res

  of nkCascade:
    let cascade = node.CascadeNode
    var res = spaces & "Cascade\n"
    res.add(spaces & "  receiver:\n")
    res.add(printAST(cascade.receiver, indent + 2))
    res.add(spaces & "  messages:\n")
    for msg in cascade.messages:
      res.add(spaces & "  - ")
      res.add(printAST(msg, indent + 2))
    return res
  else:
    return spaces & "Unknown(" & $node.kind & ")\n"
