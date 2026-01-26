import std/[sequtils, strutils, tables, options]
import ../parser/lexer
import ../core/types

# ============================================================================
# Parser for NimTalk
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
proc parseExpression(parser: var Parser): Node
proc parseBlock(parser: var Parser): BlockNode
proc parseArrayLiteral(parser: var Parser): ArrayNode
proc parseTableLiteral(parser: var Parser): TableNode
proc parseObjectLiteral(parser: var Parser): ObjectLiteralNode

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
proc peek(parser: Parser): Token =
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

# Require a token or produce error
proc require(parser: var Parser, kind: TokenKind, msg: string): bool =
  if parser.peek().kind == kind:
    discard parser.next()
    return true
  else:
    parser.parseError(msg)
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
    return LiteralNode(value: NodeValue(kind: vkSymbol, symVal: token.value))

  of tkIdent:
    discard parser.next()
    # Identifiers can be variables or message receivers
    return LiteralNode(value: NodeValue(kind: vkSymbol, symVal: token.value))

  of tkLParen:
    # Parenthesized expression
    discard parser.next()  # Skip (
    let expr = parser.parseExpression()
    if not parser.expect(tkRParen):
      parser.parseError("Expected ')'")
    return expr

  of tkLBracket:
    # Block literal
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

  else:
    parser.parseError("Unexpected token: " & token.value)
    return nil

# Parse keyword message
proc parseKeywordMessage(parser: var Parser, receiver: Node): MessageNode =
  var selector = ""
  var arguments = newSeq[Node]()

  # Collect keyword segments and arguments
  while parser.peek().kind == tkKeyword:
    let token = parser.next()
    selector.add(token.value)  # Includes colon

    let arg = parser.parseExpression()
    if arg == nil:
      parser.parseError("Expected argument after keyword")
      return nil
    arguments.add(arg)

  # Check for cascade
  parser.pendingCascade = parser.expect(tkSpecial) and parser.peek().value == ";"

  return MessageNode(
    receiver: receiver,
    selector: selector,
    arguments: arguments,
    isCascade: false
  )

# Parse binary/unary messages
proc parseBinaryMessage(parser: var Parser, receiver: Node): Node =
  var msg = receiver

  # Unary messages (single token identifiers)
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

# Parse expressions with precedence
proc parseExpression(parser: var Parser): Node =
  # Start with primary
  let primary = parser.parsePrimary()
  if primary == nil:
    return nil

  # Check for messages
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
  else:
    return primary

# Parse block literal
proc parseBlock(parser: var Parser): BlockNode =
  if not parser.expect(tkLBracket):
    parser.parseError("Expected '[' for block start")
    return nil

  let blk = BlockNode()
  blk.parameters = @[]
  blk.temporaries = @[]
  blk.body = @[]
  blk.isMethod = false

  # Check for parameters [:x :y | ...]
  if parser.expect(tkSpecial) and parser.peek().value == ":":
    # Parse parameters
    while parser.expect(tkSpecial) and parser.peek().value == ":":
      discard parser.next()  # Skip :
      if parser.expect(tkIdent):
        let paramToken = parser.tokens[parser.pos - 1]
        blk.parameters.add(paramToken.value)
      else:
        parser.parseError("Expected parameter name after :")
        return nil

    # Expect | after parameters
    if not (parser.expect(tkSpecial) and parser.peek().value == "|"):
      parser.parseError("Expected | after block parameters")
      return nil
    discard parser.next()

  # Parse statements until closing bracket
  while not parser.expect(tkRBracket):
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed block - expected ']'")
      return nil

    let stmt = parser.parseStatement()
    if stmt != nil:
      blk.body.add(stmt)

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

    # Parse expression (element)
    let element = parser.parseExpression()
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
    let value = parser.parseExpression()
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
    let value = parser.parseExpression()
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
proc parseStatement(parser: var Parser): Node =
  # Check for return statement
  if parser.expect(tkReturn):
    let expr = parser.parseExpression()
    return ReturnNode(expression: expr)

  # Parse expression
  let expr = parser.parseExpression()
  if expr == nil:
    return nil

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

# Parse method definition (block with isMethod flag)
proc parseMethod(parser: var Parser): BlockNode =
  let blk = parser.parseBlock()
  if blk != nil:
    blk.isMethod = true
  return blk

# Parse sequence of statements (method body or REPL input)
proc parseStatements(parser: var Parser): seq[Node] =
  result = @[]

  while not parser.peek().isEOF:
    let stmt = parser.parseStatement()
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
  let node = parser.parseExpression()
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
    var result = spaces & "Message(" & msg.selector & ")\n"
    result.add(spaces & "  receiver:\n")
    if msg.receiver != nil:
      result.add(printAST(msg.receiver, indent + 2))
    else:
      result.add(spaces & "    (implicit self)\n")
    for arg in msg.arguments:
      result.add(spaces & "  arg:\n")
      result.add(printAST(arg, indent + 2))
    return result

  of nkBlock:
    let blk = node.BlockNode
    var result = spaces & "Block"
    if blk.isMethod:
      result.add(" (method)")
    result.add("\n")
    if blk.parameters.len > 0:
      result.add(spaces & "  params: " & $blk.parameters & "\n")
    if blk.temporaries.len > 0:
      result.add(spaces & "  temps: " & $blk.temporaries & "\n")
    result.add(spaces & "  body:\n")
    for stmt in blk.body:
      result.add(printAST(stmt, indent + 2))
    return result

  of nkAssign:
    let assign = node.AssignNode
    var result = spaces & "Assign(" & assign.variable & ")\n"
    result.add(spaces & "  value:\n")
    result.add(printAST(assign.expression, indent + 2))
    return result

  of nkReturn:
    let ret = node.ReturnNode
    var result = spaces & "Return\n"
    if ret.expression != nil:
      result.add(spaces & "  value:\n")
      result.add(printAST(ret.expression, indent + 2))
    else:
      result.add(spaces & "  (self)\n")
    return result

  else:
    return spaces & "Unknown(" & $node.kind & ")\n"
