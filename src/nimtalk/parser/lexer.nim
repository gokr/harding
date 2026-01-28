# ============================================================================
# Lexer for Nimtalk - Tokenizes Smalltalk-style syntax
# ============================================================================

import std/strutils
type
  TokenKind* = enum
    tkIdent, tkKeyword, tkString, tkInt, tkFloat
    tkSymbol, tkComment, tkEOF, tkError
    tkLParen, tkRParen, tkLBracket, tkRBracket
    tkAssign, tkReturn, tkPeriod, tkSeparator
    tkSpecial  # ; & | etc
    tkArrayStart, tkTableStart, tkObjectStart, tkArrow, tkColon
    tkTag, tkNimCode
    tkPlus, tkMinus, tkComma  # Arithmetic and concatenation operators
    tkMethodDef  # >> for method definitions
  Token* = object
    kind*: TokenKind
    value*: string
    line*, col*: int
  LexState* = enum
    lsNormal, lsComment, lsString, lsSymbol, lsChar, lsNimCode
  Lexer* = ref object
    input*: string
    pos*: int
    line*, col*: int
    state*: LexState
    startCol*: int
    escapeNext*: bool
# Character classification
proc isAlpha(c: char): bool = c in {'a'..'z', 'A'..'Z'}
proc isDigit(c: char): bool = c in {'0'..'9'}
proc isAlphaNum(c: char): bool = c.isAlpha or c.isDigit
proc isSpace(c: char): bool = c in {' ', '\t', '\n', '\r'}
# Lexer initialization
proc initLexer*(input: string, filename: string = ""): Lexer =
  ## Create a new lexer for tokenizing input
  result = Lexer(
    input: input,
    pos: 0,
    line: 1,
    col: 1,
    state: lsNormal,
    startCol: 1
  )
# Peek at next character without advancing
proc peek(lexer: Lexer): char =
  if lexer.pos < lexer.input.len:
    return lexer.input[lexer.pos]
  else:
    return '\0'
# Get current character and advance
proc next(lexer: var Lexer): char =
  if lexer.pos < lexer.input.len:
    let c = lexer.input[lexer.pos]
    inc lexer.pos
    if c == '\n':
      inc lexer.line
      lexer.col = 1
    else:
      inc lexer.col
    return c
  else:
    return '\0'
# Skip whitespace
proc skipWhitespace(lexer: var Lexer) =
  while lexer.peek().isSpace and lexer.peek() != '\n':
    discard lexer.next()
# Parse identifier or keyword
proc parseIdent(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""
  # First char must be alphabetical
  if lexer.peek().isAlpha:
    value.add(lexer.next())
  else:
    return Token(kind: tkError, value: "Expected identifier", line: startLine, col: startCol)
  # Rest can be alphanumeric
  while lexer.peek().isAlphaNum:
    value.add(lexer.next())
  # Check if it's followed by colon (keyword)
  if lexer.peek() == ':':
    value.add(lexer.next())
    # Continue collecting keyword segments (Smalltalk keywords like 'at:put:')
    while lexer.peek().isAlpha:
      while lexer.peek().isAlphaNum:
        value.add(lexer.next())
      if lexer.peek() == ':':
        value.add(lexer.next())
      else:
        break
    return Token(kind: tkKeyword, value: value, line: startLine, col: startCol)
  else:
    return Token(kind: tkIdent, value: value, line: startLine, col: startCol)
# Parse number (integer or float)
proc parseNumber(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""
  var hasDot = false
  while true:
    let c = lexer.peek()
    if c.isDigit:
      value.add(lexer.next())
    elif c == '.' and not hasDot:
      # Check if it's a float or just a dot operator
      let nextChar = if lexer.pos + 1 < lexer.input.len:
                      lexer.input[lexer.pos + 1]
                    else:
                      '\0'
      if nextChar.isDigit:
        value.add(lexer.next())
        hasDot = true
      else:
        break
    elif c in {'e', 'E'}:
      # Exponent notation
      value.add(lexer.next())
      let c2 = lexer.peek()
      if c2 in {'+', '-'}:
        value.add(lexer.next())
    else:
      break
  if hasDot or 'e' in value or 'E' in value:
    return Token(kind: tkFloat, value: value, line: startLine, col: startCol)
  else:
    return Token(kind: tkInt, value: value, line: startLine, col: startCol)
# Parse string (single or double quotes)
proc parseString(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""
  # Check which quote type
  let quoteChar = lexer.peek()
  if quoteChar != '"' and quoteChar != '\'':
    return Token(kind: tkError, value: "Expected opening quote", line: startLine, col: startCol)
  discard lexer.next()
  # Parse string content
  while lexer.pos < lexer.input.len:
    let c = lexer.peek()
    if c == quoteChar:
      discard lexer.next()
      break
    elif c == '\\':
      # Escape sequence
      discard lexer.next()
      let esc = lexer.next()
      case esc
      of 'n': value.add('\n')
      of 't': value.add('\t')
      of 'r': value.add('\r')
      of '\\': value.add('\\')
      of '\'': value.add('\'')
      of '"': value.add('"')
      else:
        value.add('\\')
        value.add(esc)
    else:
      value.add(lexer.next())
  return Token(kind: tkString, value: value, line: startLine, col: startCol)
# Parse symbol (starts with #)
proc parseSymbol(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""
  # Skip #
  if lexer.peek() == '#':
    discard lexer.next()
  else:
    return Token(kind: tkError, value: "Expected # for symbol", line: startLine, col: startCol)
  # Symbol can be identifier, string, or keyword-like
  let c = lexer.peek()
  if c == '\'':
    # String symbol
    let strToken = parseString(lexer)
    if strToken.kind == tkString:
      return Token(kind: tkSymbol, value: strToken.value, line: startLine, col: startCol)
  elif c.isAlpha:
    # Identifier or keyword symbol
    while lexer.peek().isAlphaNum or lexer.peek() == ':':
      value.add(lexer.next())
    return Token(kind: tkSymbol, value: value, line: startLine, col: startCol)
  else:
    # Single char symbol
    value.add(lexer.next())
    return Token(kind: tkSymbol, value: value, line: startLine, col: startCol)
# Parse XML-style tag <primitive> or </primitive>
proc parseTag(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""

  # Skip opening <
  if lexer.peek() == '<':
    discard lexer.next()
  else:
    return Token(kind: tkError, value: "Expected < for tag", line: startLine, col: startCol)

  # Check if it's a closing tag </>
  var isClosing = false
  if lexer.peek() == '/':
    isClosing = true
    discard lexer.next()
    value.add('/')

  # Parse tag content until >
  while lexer.pos < lexer.input.len:
    let c = lexer.peek()
    if c == '>':
      discard lexer.next()
      break
    else:
      value.add(lexer.next())

  # If it's a primitive tag, set appropriate lexer state
  if value.startsWith("primitive") or value.startsWith("/primitive"):
    if isClosing:
      # Closing </primitive> - return to normal state
      lexer.state = lsNormal
    else:
      # Opening <primitive> - enter Nim code mode
      lexer.state = lsNimCode

  return Token(kind: tkTag, value: value, line: startLine, col: startCol)

# Parse Nim code between <primitive> and </primitive>
proc parseNimCode(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""

  # Collect characters until we see </primitive>
  while lexer.pos < lexer.input.len:
    let c = lexer.peek()
    if c == '<':
      # Check if this is </primitive>
      if lexer.pos + 1 < lexer.input.len and lexer.input[lexer.pos + 1] == '/':
        # Peek ahead to see if it's </primitive>
        var i = lexer.pos
        var possibleTag = ""
        while i < lexer.input.len and lexer.input[i] != '>':
          possibleTag.add(lexer.input[i])
          inc i
        if i < lexer.input.len:
          possibleTag.add(lexer.input[i])  # Include '>'

        if possibleTag.startsWith("</primitive"):
          # Found closing tag - stop here, return to normal state
          lexer.state = lsNormal
          break

      # Regular '<' in Nim code, include it
      value.add(lexer.next())
    else:
      value.add(lexer.next())

  # If we collected nothing and reached EOF, return EOF
  if value.len == 0 and lexer.pos >= lexer.input.len:
    return Token(kind: tkEOF, value: "", line: startLine, col: startCol)

  return Token(kind: tkNimCode, value: value, line: startLine, col: startCol)

# Main tokenization function
proc nextToken*(lexer: var Lexer): Token =
  ## Get the next token from the input

  # Handle Nim code mode
  if lexer.state == lsNimCode:
    return parseNimCode(lexer)

  # Skip whitespace (but keep newlines)
  lexer.skipWhitespace()
  # Handle newlines as separators
  if lexer.peek() == '\n':
    let line = lexer.line
    let col = lexer.col
    discard lexer.next()
    return Token(kind: tkSeparator, value: "\n", line: line, col: col)
  let c = lexer.peek()
  let startLine = lexer.line
  let startCol = lexer.col
  # End of input
  if c == '\0':
    return Token(kind: tkEOF, value: "", line: startLine, col: startCol)
  # Punctuation
  case c
  of '(':
    discard lexer.next()
    return Token(kind: tkLParen, value: "(", line: startLine, col: startCol)
  of ')':
    discard lexer.next()
    return Token(kind: tkRParen, value: ")", line: startLine, col: startCol)
  of '[':
    discard lexer.next()
    return Token(kind: tkLBracket, value: "[", line: startLine, col: startCol)
  of ']':
    discard lexer.next()
    return Token(kind: tkRBracket, value: "]", line: startLine, col: startCol)
  of '.':
    discard lexer.next()
    return Token(kind: tkPeriod, value: ".", line: startLine, col: startCol)
  of '^':
    discard lexer.next()
    return Token(kind: tkReturn, value: "^", line: startLine, col: startCol)
  of '+':
    discard lexer.next()
    return Token(kind: tkPlus, value: "+", line: startLine, col: startCol)
  of '-':
    discard lexer.next()
    # Check for arrow operator ->
    if lexer.peek() == '>':
      discard lexer.next()
      return Token(kind: tkArrow, value: "->", line: startLine, col: startCol)
    else:
      return Token(kind: tkMinus, value: "-", line: startLine, col: startCol)
  of ',':
    discard lexer.next()
    return Token(kind: tkComma, value: ",", line: startLine, col: startCol)
  of '>':
    discard lexer.next()
    # Check for method definition operator >>
    if lexer.peek() == '>':
      discard lexer.next()
      return Token(kind: tkMethodDef, value: ">>", line: startLine, col: startCol)
    else:
      # Single > is not a valid token in Smalltalk, treat as special
      return Token(kind: tkSpecial, value: ">", line: startLine, col: startCol)
  of ';':
    discard lexer.next()
    return Token(kind: tkSpecial, value: ";", line: startLine, col: startCol)
  of '|':
    discard lexer.next()
    return Token(kind: tkSpecial, value: "|", line: startLine, col: startCol)
  of ':':
    # Assignment operator := or colon for object literals
    discard lexer.next()
    if lexer.peek() == '=':
      discard lexer.next()
      return Token(kind: tkAssign, value: ":=", line: startLine, col: startCol)
    else:
      return Token(kind: tkColon, value: ":", line: startLine, col: startCol)
  of '"':
    # String literal
    return parseString(lexer)
  of '\'':
    # String literal with single quotes
    return parseString(lexer)
  of '#':
    # Context-sensitive: # followed by whitespace = comment
    # Otherwise: check for #( array, #{ table, or symbol start
    discard lexer.next()
    let nextChar = lexer.peek()

    # Special case: shebang line at start of file (e.g., #!/usr/bin/env ntalk)
    if lexer.line == 1 and lexer.col == 2 and nextChar == '!':
      # Skip shebang line
      while lexer.pos < lexer.input.len and lexer.peek() != '\n':
        discard lexer.next()
      # Return next token (skip the shebang line)
      return nextToken(lexer)

    # If followed by whitespace, it's a comment - skip to end of line
    if nextChar.isSpace:
      # Skip to end of line
      while lexer.pos < lexer.input.len and lexer.peek() != '\n':
        discard lexer.next()
      # Return next token recursively (skip the comment)
      return nextToken(lexer)
    # Check for array literal #(
    elif nextChar == '(':
      discard lexer.next()
      return Token(kind: tkArrayStart, value: "#(", line: startLine, col: startCol)
    # Check for table literal #{
    elif nextChar == '{':
      discard lexer.next()
      return Token(kind: tkTableStart, value: "#{", line: startLine, col: startCol)
    else:
      # Regular symbol - put back the # and let parseSymbol handle it
      lexer.pos = lexer.pos - 1  # Put back the #
      lexer.col = lexer.col - 1   # Adjust column
      return parseSymbol(lexer)
  of '{':
    discard lexer.next()
    # Check for object literal start {|
    if lexer.peek() == '|':
      discard lexer.next()
      return Token(kind: tkObjectStart, value: "{|", line: startLine, col: startCol)
    else:
      return Token(kind: tkError, value: "Expected | after { for object literal", line: startLine, col: startCol)
  of '}':
    discard lexer.next()
    return Token(kind: tkSpecial, value: "}", line: startLine, col: startCol)
  of '<':
    # XML-style tag
    return parseTag(lexer)
  else:
    # Number, identifier, or error
    if c.isDigit:
      return parseNumber(lexer)
    elif c.isAlpha:
      return parseIdent(lexer)
    else:
      discard lexer.next()
      return Token(kind: tkError, value: "Unexpected character: " & c, line: startLine, col: startCol)
# Tokenization helpers
proc lex*(input: string): seq[Token] =
  ## Tokenize entire input string
  var lexer = initLexer(input)
  result = @[]
  while true:
    let token = nextToken(lexer)
    result.add(token)
    if token.kind in {tkEOF, tkError}:
      break
# Token display for debugging
proc `$`*(token: Token): string =
  ## String representation of token
  "Token(" & $token.kind & ", \"" & token.value & "\")" &
  " [" & $token.line & ":" & $token.col & "]"
# Token classification helpers
proc isKeyword*(token: Token): bool =
  token.kind == tkKeyword
proc isIdentifier*(token: Token): bool =
  token.kind in {tkIdent, tkSymbol}
proc isLiteral*(token: Token): bool =
  token.kind in {tkInt, tkFloat, tkString, tkSymbol}
proc isSeparator*(token: Token): bool =
  token.kind == tkSeparator or token.kind == tkPeriod
proc isError*(token: Token): bool =
  token.kind == tkError
proc isEOF*(token: Token): bool =
  token.kind == tkEOF
