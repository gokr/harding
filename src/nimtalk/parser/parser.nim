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

# Helper to parse primitive tag content as keyword message syntax
# Input: "primitiveAt: key put: value" or "primitiveClone"
# Returns: (selector, arguments)
proc parsePrimitiveTagContent(tagContent: string): (string, seq[Node], string) =
  ## Parse primitive tag content using keyword message syntax
  ## Returns (selector, arguments, errorMsg)
  ## errorMsg is empty on success

  # Strip "primitive " prefix
  var content = tagContent
  if content.startsWith("primitive "):
    content = content[10..^1].strip()
  elif content.startsWith("primitive\t"):
    content = content[10..^1].strip()
  else:
    return ("", @[], "Expected 'primitive ' prefix in tag content")

  # Skip optional leading # for backward compatibility
  if content.startsWith("#"):
    content = content[1..^1]

  if content.len == 0:
    return ("", @[], "Expected primitive selector after 'primitive'")

  # Lex the content as Nimtalk tokens
  let tokens = lex(content)
  if tokens.len == 0:
    return ("", @[], "Failed to lex primitive content")

  var pos = 0
  var selector = ""
  var arguments: seq[Node] = @[]

  # Check first token to determine message type
  if tokens[pos].kind == tkIdent:
    # Could be unary selector or start of an argument
    # Check if next token is a keyword - if so, this ident is an arg
    if pos + 1 < tokens.len and tokens[pos + 1].kind == tkKeyword:
      # First token is an argument, we need a keyword selector
      return ("", @[], "Expected keyword selector, got identifier: " & tokens[pos].value)
    else:
      # Unary selector (no arguments)
      selector = tokens[pos].value
      inc pos
  elif tokens[pos].kind == tkKeyword:
    # Keyword message - parse keyword:arg pairs
    while pos < tokens.len and tokens[pos].kind == tkKeyword:
      let keyword = tokens[pos].value
      selector.add(keyword)
      inc pos

      # Parse the argument for this keyword part
      if pos >= tokens.len:
        return ("", @[], "Expected argument after keyword: " & keyword)

      let argToken = tokens[pos]
      case argToken.kind
      of tkIdent:
        arguments.add(IdentNode(name: argToken.value))
        inc pos
      of tkInt:
        arguments.add(LiteralNode(value: NodeValue(kind: vkInt, intVal: parseInt(argToken.value))))
        inc pos
      of tkFloat:
        arguments.add(LiteralNode(value: NodeValue(kind: vkFloat, floatVal: parseFloat(argToken.value))))
        inc pos
      of tkString:
        arguments.add(LiteralNode(value: NodeValue(kind: vkString, strVal: argToken.value)))
        inc pos
      of tkSymbol:
        arguments.add(LiteralNode(value: getSymbol(argToken.value)))
        inc pos
      else:
        return ("", @[], "Expected argument after keyword, got: " & $argToken.kind)
  else:
    return ("", @[], "Expected selector (identifier or keyword), got: " & $tokens[pos].kind)

  # Check for extra tokens (should be at EOF or only have EOF left)
  while pos < tokens.len:
    if tokens[pos].kind == tkEOF:
      break
    else:
      return ("", @[], "Unexpected token after primitive arguments: " & tokens[pos].value)

  return (selector, arguments, "")

# Forward declarations for recursive parsing functions
proc parseExpression*(parser: var Parser; parseMessages = true): Node
proc parsePrimaryUnaryOnly(parser: var Parser): Node
proc parseBlock*(parser: var Parser): BlockNode
proc parseArrayLiteral(parser: var Parser): ArrayNode
proc parseTableLiteral(parser: var Parser): TableNode
proc parseObjectLiteral(parser: var Parser): ObjectLiteralNode
proc parseStatement(parser: var Parser; parseMessages = true): Node
proc parseMethod(parser: var Parser): BlockNode
proc parsePrimitive(parser: var Parser): Node
proc checkForCascade(parser: var Parser, primary: Node, firstMsg: MessageNode): Node
proc parseMethodDefinition(parser: var Parser, receiver: Node): Node
proc parseDeclarativePrimitive(parser: var Parser, selector: string, params: seq[string]): PrimitiveCallNode

# Reserved pseudo-variables that cannot be used as slot names or regular identifiers
const PseudoVariables* = ["self", "nil", "true", "false", "super"]

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
    # Check for pseudo-variables (self, nil, true, false, super)
    debug("parsePrimary: tkIdent value='", token.value, "'")
    if token.value in PseudoVariables:
      debug("parsePrimary: found pseudo-variable '", token.value, "'")
      # Special handling for super which can have qualified syntax
      if token.value == "super":
        # Check if this is a super send (followed by message selector)
        let nextTok = parser.peek()
        if nextTok.kind in {tkIdent, tkKeyword, tkPlus, tkMinus, tkStar, tkSlash, tkLt, tkGt, tkEq, tkPercent,
                           tkIntDiv, tkMod, tkLtEq, tkGtEq, tkNotEq, tkLt, tkTag}:
          # This is a super send, parse it
          var explicitParent: string = ""

          # Check for explicit parent syntax: super<Parent>
          if nextTok.kind == tkLt:
            discard parser.next()
            if parser.peek().kind == tkIdent:
              explicitParent = parser.next().value
            else:
              parser.parseError("Expected parent class name after super<")
              return nil
            if parser.peek().kind == tkGt:
              discard parser.next()
            else:
              parser.parseError("Expected > after parent class name")
              return nil
          elif nextTok.kind == tkTag:
            explicitParent = nextTok.value
            discard parser.next()

          # Parse the message selector
          let next = parser.peek()
          var selector: string = ""
          var arguments: seq[Node] = @[]

          case next.kind
          of tkIdent:
            selector = parser.next().value
          of tkSpecial, tkPlus, tkMinus, tkStar, tkSlash, tkLt, tkGt, tkEq, tkPercent,
             tkIntDiv, tkMod, tkLtEq, tkGtEq, tkNotEq, tkAmpersand, tkPipe:
            selector = parser.next().value
            let arg = parser.parseExpression(parseMessages = false)
            if arg == nil:
              parser.parseError("Expected argument after binary operator in super send")
              return nil
            arguments.add(arg)
          of tkKeyword:
            while parser.peek().kind == tkKeyword:
              let kw = parser.next().value
              selector.add(kw)
              let arg = parser.parseExpression(parseMessages = false)
              if arg == nil:
                parser.parseError("Expected argument after keyword in super send")
                return nil
              arguments.add(arg)
          else:
            parser.parseError("Expected message selector after super")
            return nil

          return SuperSendNode(
            selector: selector,
            arguments: arguments,
            explicitParent: explicitParent
          )
        # else: fall through to create PseudoVarNode for bare "super"

      # Return PseudoVarNode for all pseudo-variables
      return PseudoVarNode(name: token.value)

    # Regular identifier - needs variable lookup at runtime
    return IdentNode(name: token.value)

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

  of tkTag:
    # Handle inline primitive calls: <primitive selector: arg1 other: arg2>
    discard parser.next()
    let tagValue = token.value

    # Check if this is an inline primitive call (starts with "primitive" but not "primitive:")
    if tagValue.startsWith("primitive ") or tagValue.startsWith("primitive\t"):
      # Parse inline primitive using keyword message syntax
      let (selector, arguments, errorMsg) = parsePrimitiveTagContent(tagValue)
      if errorMsg.len > 0:
        parser.parseError(errorMsg)
        return nil

      return PrimitiveCallNode(
        selector: selector,
        arguments: arguments,
        line: token.line,
        col: token.col
      )

    # Not an inline primitive - error
    parser.parseError("Unknown tag: " & tagValue)
    return nil

  else:
    debug("parsePrimary: unexpected token ", token.value)
    parser.parseError("Unexpected token: " & token.value)
    return nil

# Parse primary expression with optional unary messages only
# Used for keyword arguments where we want to allow "obj msg" but not "obj + obj" or "obj msg: obj"
proc parsePrimaryUnaryOnly(parser: var Parser): Node =
  let primary = parser.parsePrimary()
  if primary == nil:
    return nil

  # Parse unary message chain only (no binary or keyword messages)
  while parser.peek().kind == tkIdent and parser.peek().value[0].isLowerAscii():
    let token = parser.next()
    result = MessageNode(
      receiver: if result == nil: primary else: result,
      selector: token.value,
      arguments: @[],
      isCascade: false
    )

  if result == nil:
    return primary
  return result

# Parse keyword message
proc parseKeywordMessage(parser: var Parser, receiver: Node): MessageNode =
  debug("parseKeywordMessage: entering, receiver type=", receiver.kind, " current token=", parser.peek().kind)
  var selector = ""
  var arguments = newSeq[Node]()

  # Collect keyword segments and arguments
  while true:
    # Skip separators before checking for next keyword (allows multiline keyword messages)
    while parser.peek().kind == tkSeparator:
      discard parser.next()
    if parser.peek().kind != tkKeyword:
      break
    let token = parser.next()
    selector.add(token.value)  # Includes colon

    let arg = parser.parsePrimaryUnaryOnly()
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

  # After unary messages, check for keyword message (e.g., self foo bar x: value)
  if parser.peek().kind == tkKeyword:
    return parser.parseKeywordMessage(msg)

  return msg

# Binary operator tokens for parsing
const BinaryOpTokens* = {tkPlus, tkMinus, tkStar, tkSlash, tkLt, tkGt, tkEq, tkEqEq, tkPercent, tkComma,
                         tkIntDiv, tkMod, tkLtEq, tkGtEq, tkNotEq, tkAmpersand, tkPipe}

# Parse binary operators with left-to-right associativity
proc parseBinaryOperators(parser: var Parser, left: Node): Node =
  ## Parse binary operators after unary messages
  var expr = left
  while parser.peek().kind in BinaryOpTokens:
    let opToken = parser.next()
    # Parse the right operand (primary + unary messages only, not more binary operators yet)
    var right = parser.parsePrimary()
    if right == nil:
      parser.parseError("Expected expression after binary operator")
      return expr

    # Handle unary messages on right side
    while parser.peek().kind == tkIdent and parser.peek().value[0].isLowerAscii():
      let unaryToken = parser.next()
      right = MessageNode(
        receiver: right,
        selector: unaryToken.value,
        arguments: @[],
        isCascade: false
      )

    # Note: Do NOT parse keyword messages here - they have lower precedence
    # than binary operators and should be parsed in parseExpression after
    # all binary operators are processed. This ensures correct parsing of
    # expressions like "self < 0 ifTrue: [...]" as "(self < 0) ifTrue: [...]"
    # rather than "self < (0 ifTrue: [...])".

    expr = MessageNode(
      receiver: expr,
      selector: opToken.value,
      arguments: @[right],
      isCascade: false
    )
  return expr

# Parse expressions with precedence (no cascade detection)
proc parseExpression*(parser: var Parser; parseMessages = true): Node =
  # Start with primary
  let primary = parser.parsePrimary()
  if primary == nil:
    return nil

  # Check for messages
  if parseMessages:
    var current: Node = primary

    # First check what's immediately next (on same line)
    var next = parser.peek()

    # If we hit a separator, peek at what follows
    # Keyword messages can span lines, but identifiers/assignments cannot
    if next.kind == tkSeparator:
      # Save position for potential backtrack
      let savePos = parser.pos

      # Skip separators to see what's next
      while parser.peek().kind == tkSeparator:
        discard parser.next()

      next = parser.peek()

      # Only continue across newlines for keyword messages
      if next.kind != tkKeyword:
        # Not a keyword - restore position and return
        parser.pos = savePos
        return primary

    case next.kind
    of tkKeyword:
      # Keyword message (lowest precedence, parsed last)
      current = parser.parseKeywordMessage(primary)
      # After keyword messages, check for binary operators (comma concatenation, etc.)
      if parser.peek().kind in BinaryOpTokens:
        current = parser.parseBinaryOperators(current)
      return current
    of tkIdent:
      if next.value[0].isLowerAscii():
        # Unary message chain first
        current = parser.parseBinaryMessage(primary)
        # After unary messages, check for binary operators
        if parser.peek().kind in BinaryOpTokens:
          current = parser.parseBinaryOperators(current)
        # Check for keyword messages (may be on next line)
        if parser.peek().kind == tkKeyword:
          return parser.parseKeywordMessage(current)
        # Also check for keyword after separator (multi-line support)
        if parser.peek().kind == tkSeparator:
          let savePos = parser.pos
          while parser.peek().kind == tkSeparator:
            discard parser.next()
          if parser.peek().kind == tkKeyword:
            return parser.parseKeywordMessage(current)
          # Not a keyword continuation - restore position
          parser.pos = savePos
        return current
      else:
        return primary
    of tkPlus, tkMinus, tkStar, tkSlash, tkLt, tkGt, tkEq, tkEqEq, tkPercent, tkComma,
       tkIntDiv, tkMod, tkLtEq, tkGtEq, tkNotEq, tkAmpersand, tkPipe:
      # Binary operator directly after primary
      current = parser.parseBinaryOperators(primary)
      # Check for keyword messages (may be on next line)
      if parser.peek().kind == tkKeyword:
        return parser.parseKeywordMessage(current)
      # Also check for keyword after separator (multi-line support)
      if parser.peek().kind == tkSeparator:
        let savePos = parser.pos
        while parser.peek().kind == tkSeparator:
          discard parser.next()
        if parser.peek().kind == tkKeyword:
          return parser.parseKeywordMessage(current)
        # Not a keyword continuation - restore position
        parser.pos = savePos
      return current
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
    of tkPlus, tkMinus, tkStar, tkSlash, tkLt, tkGt, tkEq, tkPercent, tkComma,
       tkIntDiv, tkMod, tkLtEq, tkGtEq, tkNotEq:
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
  debug("parseBlock: starting")
  if not parser.expect(tkLBracket):
    parser.parseError("Expected '[' for block start")
    return nil
  debug("parseBlock: consumed [")

  let blk = BlockNode()
  blk.parameters = @[]
  blk.temporaries = @[]
  blk.body = @[]
  blk.isMethod = false

  # Check for parameters [:x :y | ...]
  debug("parseBlock: checking for params, current=", parser.peek().kind, " value=", parser.peek().value)
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
    if not (parser.peek().kind == tkPipe):
      parser.parseError("Expected | after block parameters")
      return nil
    discard parser.next()

  # Skip separators before checking for temporaries (important for newlines after [)
  while parser.peek().kind == tkSeparator:
    discard parser.next()

  # Check for temporaries: | temp1 temp2 | (Smalltalk-style)
  # OR just consume the | separator and parse body (Nimtalk-style)
  # In the test syntax, [| ...] means block with no params, just consume | and parse body
  debug("parseBlock: checking for temporaries, current=", parser.peek().kind, " value=", parser.peek().value)
  if parser.peek().kind == tkPipe:
    # Could be |param| (end of params) or |temp1 temp2| (temporaries)
    discard parser.next()  # Consume |
    # Skip whitespace after |
    while parser.peek().kind == tkSeparator:
      discard parser.next()
    # Check if the next token is an identifier (temporary variable declaration)
    if parser.peek().kind == tkIdent:
      # Parse temporary variables until we hit another |
      while parser.peek().kind == tkIdent:
        let tempName = parser.next().value
        blk.temporaries.add(tempName)
        debug("parseBlock: added temporary: ", tempName)
        # Skip whitespace
        while parser.peek().kind == tkSeparator:
          discard parser.next()
      # Expect closing |
      if parser.peek().kind == tkPipe:
        discard parser.next()
      else:
        parser.parseError("Expected | to close temporary variable declaration")

  # Parse statements until closing bracket
  var loopCount = 0
  while true:
    loopCount += 1
    if loopCount > 100:
      parser.parseError("Block parsing exceeded 100 iterations - possible infinite loop")
      return nil

    let currentTok = parser.peek()
    debug("parseBlock: loop ", loopCount, " pos=", parser.pos, " current=", currentTok.kind, " value='", currentTok.value, "'")

    # Check for closing bracket first
    if parser.expect(tkRBracket):
      debug("parseBlock: found and consumed closing ] at pos=", parser.pos)
      break
    debug("parseBlock: no closing bracket found (pos still ", parser.pos, ")")

    # Check for EOF
    if parser.peek().kind == tkEOF:
      parser.parseError("Unclosed block - expected ']'")
      return nil

    let stmt = parser.parseStatement(parseMessages = true)
    if stmt != nil:
      blk.body.add(stmt)
      debug("parseBlock: added statement, body now has ", blk.body.len, " statements")
    else:
      debug("parseBlock: parseStatement returned nil at pos=", parser.pos, " tok=", parser.peek().kind, " value='", parser.peek().value, "'")
      # Check if it's the closing bracket - if so, consume it and break properly
      if parser.peek().kind == tkRBracket:
        debug("parseBlock: detected closing bracket after nil statement, consuming it")
        discard parser.expect(tkRBracket)
      break

  debug("parseBlock: returning with ", blk.body.len, " statements")
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
    let value = parser.parseExpression(parseMessages = false)
    if value == nil:
      parser.parseError("Expected table value after '->'")
      return nil

    table.entries.add((key, value))

    # Skip optional comma separator
    discard parser.expect(tkComma)

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
  while not (parser.peek().kind == tkPipe):
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
    let value = parser.parseExpression(parseMessages = false)
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
  if parser.peek().kind == tkReturn:
    discard parser.next()  # consume ^
    # For return statements, we need to parse the expression including any assignment
    # because ^value := expr should be parsed as return (assignment), not (return value) := expr
    let expr = parser.parseExpression(parseMessages = parseMessages)
    # Check if the expression is followed by := (assignment to the expression's result)
    # This handles cases like ^value := value + 1
    if parser.peek().kind == tkAssign and expr of IdentNode:
      discard parser.next()  # consume :=
      let varName = expr.IdentNode.name
      let valueExpr = parser.parseExpression()
      let assignNode = AssignNode(variable: varName, expression: valueExpr)
      return ReturnNode(expression: assignNode)
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
  debug("parseStatement: checking for assignment, pos=", parser.pos, " peek.kind=", parser.peek().kind, " value=", parser.peek().value)
  if parser.peek().kind == tkAssign:
    debug("parseStatement: found assignment token, consuming it")
    discard parser.next()
    debug("parseStatement: after consuming :=, pos=", parser.pos, " peek.kind=", parser.peek().kind, " value=", parser.peek().value)

    # Left side must be an identifier
    if expr of IdentNode:
      let varName = expr.IdentNode.name
      let valueExpr = parser.parseExpression()
      debug("parseStatement: after parsing value expression, pos=", parser.pos, " peek.kind=", parser.peek().kind, " value=", parser.peek().value)
      if valueExpr == nil:
        parser.parseError("Expected expression after :=")
        return nil

      # Check if the right side is a message that could be cascaded
      var finalExpr = valueExpr
      if valueExpr of MessageNode:
        let msg = valueExpr.MessageNode
        let cascadeReceiver = msg.receiver
        let msgWithNilReceiver = MessageNode(
          receiver: nil,
          selector: msg.selector,
          arguments: msg.arguments,
          isCascade: false
        )
        let cascaded = parser.checkForCascade(cascadeReceiver, msgWithNilReceiver)
        if cascaded != nil:
          finalExpr = cascaded

      return AssignNode(variable: varName, expression: finalExpr)
    else:
      parser.parseError("Can only assign to variable name")
      return nil
  else:
    # Consume optional trailing period (statement separator)
    discard parser.expect(tkPeriod)
    return expr

# Parse block literal (defined above at line 209)

# Parse method definition (block with isMethod flag)
proc parseMethod(parser: var Parser): BlockNode =
  let blk = parser.parseBlock()
  if blk != nil:
    blk.isMethod = true
  return blk

# Parse method definition syntax: Receiver>>selector [ body ] or Receiver class>>selector [ body ]
# Transforms to: Receiver selector: 'sel' put: [body] (instance method)
# Or: Receiver classSelector: 'sel' put: [body] (class method)
proc parseMethodDefinition(parser: var Parser, receiver: Node): Node =
  ## Parse >> method definition and generate appropriate message
  ## Handles both instance methods (>>) and class methods (class>>)

  var actualReceiver = receiver
  var isClassMethod = false

  # Check if receiver is a message "class" sent to an object (class method pattern)
  # Pattern: Person class>>selector means class method on Person
  if receiver of MessageNode:
    let msg = cast[MessageNode](receiver)
    if msg.selector == "class" and msg.arguments.len == 0:
      # This is a class method definition - extract the actual receiver
      actualReceiver = msg.receiver
      isClassMethod = true

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
      # Each keyword part has a parameter (ident or block literal)
      if parser.peek().kind == tkIdent:
        params.add(parser.next().value)
      elif parser.peek().kind == tkLBracket:
        # Block literal as last parameter - name it generically
        params.add("block")
        break  # Stop parsing params at this point, parseBlock will handle the block
      else:
        parser.parseError("Expected parameter name after keyword part: " & keywordPart)
        return nil
  elif tok.kind in BinaryOpTokens:
    # Binary operator like '+', '-', etc.
    selector = parser.next().value
    # Binary operators have one parameter
    if parser.peek().kind == tkIdent:
      params.add(parser.next().value)
    else:
      parser.parseError("Expected parameter name for binary operator: " & selector)
      return nil
  elif tok.kind == tkSpecial:
    # Special character like '~', '!', '=' etc.
    # Consume all repeated special chars for operators like '~~', '==', '~=' etc.
    let firstChar = parser.next().value
    selector = firstChar
    while parser.peek().kind == tkSpecial and parser.peek().value == firstChar:
      selector.add(parser.next().value)
    # Binary operators have one parameter
    if parser.peek().kind == tkIdent:
      params.add(parser.next().value)
    else:
      parser.parseError("Expected parameter name for binary operator: " & selector)
      return nil
  else:
    parser.parseError("Expected method selector after >>")
    return nil

  # Parse method body - check for declarative primitive syntax: <primitive: #primitiveSelector>
  var blk: BlockNode
  if parser.peek().kind == tkTag and parser.peek().value.startsWith("primitive:"):
    # Declarative primitive - parse directly from tag value
    let tagValue = parser.next().value  # Consume <primitive: #selector> tag

    # Extract the selector from the tag value (after "primitive: ")
    var tagParts = tagValue.split({' ', '\t'}, maxSplit = 1)
    if tagParts.len < 2:
      parser.parseError("Expected primitive selector after <primitive:, got: " & tagValue)
      return nil

    let primSelectorRaw = tagParts[1]
    # Strip the # prefix from the selector symbol (e.g., "#primitiveClone" -> "primitiveClone")
    let primSelector = if primSelectorRaw.startsWith("#"):
                        primSelectorRaw[1..^1]
                      else:
                        primSelectorRaw

    # Validate arity (colon count in selector must match param count)
    let primitiveColonCount = primSelector.count(':')
    if primitiveColonCount != params.len:
      parser.parseError("Method takes " & $params.len & " arguments but #" &
                       primSelector & " expects " & $primitiveColonCount)
      return nil

    # Create a block with primitive call as return
    let primCall = parseDeclarativePrimitive(parser, primSelector, params)

    blk = BlockNode(
      parameters: params,
      temporaries: @[],
      body: @[cast[Node](ReturnNode(expression: primCall))],
      isMethod: true,
      nativeImpl: nil
    )
  else:
    # Parse method body as a block (parseBlock expects the [ itself)
    blk = parser.parseBlock()
    if blk == nil:
      return nil

    # Mark as method
    blk.isMethod = true

    # Set parameters if we have keyword/binary selector params
    if params.len > 0:
      blk.parameters = params

  # Generate appropriate message based on method type
  let arg1: Node = LiteralNode(value: NodeValue(kind: vkSymbol, symVal: selector))
  let arg2: Node = LiteralNode(value: NodeValue(kind: vkBlock, blockVal: blk))

  if isClassMethod:
    # Class method: Receiver classSelector: 'sel' put: [body]
    return MessageNode(
      receiver: actualReceiver,
      selector: "classSelector:put:",
      arguments: @[arg1, arg2],
      isCascade: false
    )
  else:
    # Instance method: Receiver selector: 'sel' put: [body]
    return MessageNode(
      receiver: actualReceiver,
      selector: "selector:put:",
      arguments: @[arg1, arg2],
      isCascade: false
    )

# Parse primitive declaration: <primitive> ... </primitive> followed by Smalltalk fallback
# OR parse inline primitive call: <primitive #selector args>
proc parsePrimitive(parser: var Parser): Node =
  let startLine = parser.lastLine
  let startCol = parser.lastCol

  # Expect opening <primitive> tag
  let openingTag = parser.next()
  if openingTag.kind != tkTag or not openingTag.value.startsWith("primitive"):
    parser.parseError("Expected <primitive> tag")
    return nil

  # Check for inline primitive: <primitive selector: arg1 other: arg2>
  # The tag value will be like "primitive primitiveAt: key put: value"
  if openingTag.value.startsWith("primitive ") or openingTag.value.startsWith("primitive\t"):
    # Inline primitive syntax - parse using keyword message format
    let (selector, arguments, errorMsg) = parsePrimitiveTagContent(openingTag.value)
    if errorMsg.len > 0:
      parser.parseError(errorMsg)
      return nil

    let node = PrimitiveCallNode(
      selector: selector,
      arguments: arguments,
      line: startLine,
      col: startCol
    )
    return node

  # Check for declarative primitive in wrong context (should be in method definition)
  if openingTag.value.startsWith("primitive:"):
    parser.parseError("Declarative primitive syntax <primitive: #selector> is only valid in method definitions")
    return nil

  # Old XML-style primitive: <primitive> ... </primitive>
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

# Parse declarative primitive call in method definition: <primitive: #selector>
proc parseDeclarativePrimitive(parser: var Parser, selector: string, params: seq[string]): PrimitiveCallNode =
  let startLine = parser.lastLine
  let startCol = parser.lastCol

  let primSelector = selector

  # Create primitive call with parameter references as arguments
  var arguments: seq[Node] = @[]
  for param in params:
    arguments.add(IdentNode(name: param))

  let node = PrimitiveCallNode(
    selector: primSelector,
    arguments: arguments,
    line: startLine,
    col: startCol
  )
  return node


# Parse sequence of statements (method body or REPL input)
proc parseStatements*(parser: var Parser): seq[Node] =
  result = @[]
  var loopCount = 0

  while not parser.peek().isEOF:
    inc loopCount
    if loopCount > 1000:
      debug("PARSE LOOP DETECTED: parseStatements exceeded 1000 iterations")
      raise newException(ValueError, "Parse loop detected - infinite loop in parseStatements")

    debug("parseStatements: loop ", loopCount, ", pos=", parser.pos, ", token=", parser.peek().kind, " value='", parser.peek().value, "'")
    let stmt = parser.parseStatement(parseMessages = true)
    if stmt != nil:
      debug("parseStatements: got statement, adding to results")
      result.add(stmt)
    else:
      debug("parseStatements: parseStatement returned nil")

    # Skip separators and periods
    var skipped = 0
    while parser.expect(tkSeparator) or parser.expect(tkPeriod):
      inc skipped
      if skipped > 100:
        debug("PARSE LOOP: separator skipping exceeded 100 iterations")
        raise newException(ValueError, "Parse loop in separator skipping")

    if parser.hasError:
      debug("parseStatements: parser has error, breaking")
      break

  debug("parseStatements: done, parsed ", result.len, " statements in ", loopCount, " loops")

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

  of nkPrimitiveCall:
    let primCall = node.PrimitiveCallNode
    var res = spaces & "PrimitiveCall(" & primCall.selector & ")\n"
    for arg in primCall.arguments:
      res.add(spaces & "  arg:\n")
      res.add(printAST(arg, indent + 2))
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

  of nkPseudoVar:
    return spaces & "PseudoVar(" & node.PseudoVarNode.name & ")\n"

  of nkSuperSend:
    let superNode = node.SuperSendNode
    var res = spaces & "SuperSend(" & superNode.selector & ")"
    if superNode.explicitParent.len > 0:
      res.add(" <" & superNode.explicitParent & ">")
    res.add("\n")
    for arg in superNode.arguments:
      res.add(spaces & "  arg:\n")
      res.add(printAST(arg, indent + 2))
    return res

  of nkSlotAccess:
    let slotNode = node.SlotAccessNode
    var res = spaces & "SlotAccess(" & slotNode.slotName & "[" & $slotNode.slotIndex & "]"
    if slotNode.isAssignment:
      res.add(" :=")
    res.add(")\n")
    return res

  else:
    return spaces & "Unknown(" & $node.kind & ")\n"
