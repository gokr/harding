import std/[strutils, tables]
import ../core/types

# ============================================================================
# Lexer for NimTalk - Tokenizes Smalltalk-style syntax
# ============================================================================

type
  TokenKind* = enum
    tkIdent, tkKeyword, tkString, tkInt, tkFloat
    tkSymbol, tkComment, tkEOF, tkError
    tkLParen, tkRParen, tkLBracket, tkRBracket
    tkAssign, tkReturn, tkPeriod, tkSeparator
    tkSpecial  # ; & | etc

  Token* = object
    kind*: TokenKind
    value*: string
    line*, col*: int

  LexState* = enum
    lsNormal, lsComment, lsString, lsSymbol, lsChar

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

# Parse string
proc parseString(lexer: var Lexer): Token =
  let startLine = lexer.line
  let startCol = lexer.col
  var value = ""

  # Skip opening quote
  if lexer.peek() == '\'':
    discard lexer.next()
  else:
    return Token(kind: tkError, value: "Expected opening quote", line: startLine, col: startCol)

  # Parse string content
  while lexer.pos < lexer.input.len:
    let c = lexer.peek()
    if c == '\'':
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

# Skip comment
proc skipComment(lexer: var Lexer) =
  # Smalltalk style: "comment"
  if lexer.peek() == '"':
    discard lexer.next()
    while lexer.pos < lexer.input.len:
      if lexer.peek() == '"':
        discard lexer.next()
        if lexer.peek() != '"':  # Not escaped quote
          break
        else:
          discard lexer.next()  # Skip escaped quote
      else:
        discard lexer.next()

# Main tokenization function
proc nextToken*(lexer: var Lexer): Token =
  ## Get the next token from the input

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
  of ';':
    discard lexer.next()
    return Token(kind: tkSpecial, value: ";", line: startLine, col: startCol)
  of '|':
    discard lexer.next()
    return Token(kind: tkSpecial, value: "|", line: startLine, col: startCol)
  of ':':
    # Assignment operator :=
    discard lexer.next()
    if lexer.peek() == '=':
      discard lexer.next()
      return Token(kind: tkAssign, value: ":=", line: startLine, col: startCol)
    else:
      return Token(kind: tkError, value: "Expected = after :", line: startLine, col: startCol)
  of '"':
    # Comment
    lexer.skipComment()
    return nextToken(lexer)  # Continue with next token
  of '#':
    # Symbol
    return parseSymbol(lexer)
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
  "Token(" & $token.kind & ", \"" & token.value.escape.escape & "\")" &
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
