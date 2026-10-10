import std/[os, strutils, tempfiles]
import ../core/types
import ../parser/lexer
import ../parser/parser

type
  SourceSpan = object
    owner: string
    selector: string
    first: int
    last: int

proc parseSourceSpans(source: string): tuple[spans: seq[SourceSpan], error: string] =
  var lexer = initLexer(source)
  var tokens: seq[Token] = @[]
  var ends: seq[int] = @[]
  while true:
    let token = lexer.nextToken()
    tokens.add(token)
    ends.add(lexer.pos)
    if token.kind == tkError:
      return (@[], token.value)
    if token.kind == tkEOF:
      break

  var starts: seq[int] = @[]
  var lineStarts = @[0]
  for i, ch in source:
    if ch == '\n':
      lineStarts.add(i + 1)
  for token in tokens:
    starts.add(lineStarts[token.line - 1] + token.col - 1)

  var parser = initParser(tokens)
  while parser.peek().kind != tkEOF:
    while parser.peek().kind in {tkSeparator, tkPeriod}:
      inc parser.pos
    if parser.peek().kind == tkEOF:
      break
    let firstToken = parser.pos
    let node = parser.parseStatement()
    if parser.hasError:
      return (@[], parser.errorMsg)
    if node == nil or parser.pos <= firstToken:
      return (@[], "Could not determine source statement boundaries")
    var lastToken = parser.pos - 1
    while lastToken > firstToken and tokens[lastToken].kind in {tkPeriod, tkSeparator}:
      dec lastToken
    var span = SourceSpan(first: starts[firstToken], last: ends[lastToken])
    if node of MessageNode:
      let message = MessageNode(node)
      if message.selector in ["selector:put:", "classSelector:put:"] and
          message.receiver of IdentNode and message.arguments.len == 2 and
          message.arguments[0] of LiteralNode:
        span.owner = IdentNode(message.receiver).name
        if message.selector == "classSelector:put:":
          span.owner.add(" class")
        span.selector = LiteralNode(message.arguments[0]).value.symVal
    elif node of AssignNode:
      let assignment = AssignNode(node)
      if assignment.expression of MessageNode:
        let message = MessageNode(assignment.expression)
        if message.selector.startsWith("derive"):
          span.owner = assignment.variable
          span.selector = "<classDefinition>"
    result.spans.add(span)

proc rewriteSource*(source, owner, selector, replacement: string,
                    deleting = false): tuple[source: string, error: string] =
  ## Replace one definition while preserving every byte outside its token span.
  let parsed = parseSourceSpans(source)
  if parsed.error.len > 0:
    return ("", "Existing source is invalid: " & parsed.error)
  var matches: seq[SourceSpan] = @[]
  for span in parsed.spans:
    if span.owner == owner and span.selector == selector:
      matches.add(span)
  if matches.len > 1:
    return ("", "Ambiguous source definition: " & owner & ">>" & selector)

  var text = replacement.strip()
  if not deleting:
    let proposed = parseSourceSpans(text)
    if proposed.error.len > 0:
      return ("", "Replacement source is invalid: " & proposed.error)
    if proposed.spans.len != 1 or proposed.spans[0].owner != owner or
        proposed.spans[0].selector != selector:
      return ("", "Replacement must define only the selected class or method")
    # Separators and trailing comments belong to the original file.
    let definition = proposed.spans[0]
    text = text[definition.first ..< definition.last]

  if matches.len == 0:
    if deleting or selector == "<classDefinition>":
      return ("", "Source definition not found: " & owner & ">>" & selector)
    let separator = if source.len > 0 and source[^1] != '\n': "\n" else: ""
    result.source = source & separator & text & ".\n"
  else:
    let span = matches[0]
    result.source = source[0 ..< span.first] &
      (if deleting: "" else: text) & source[span.last ..< source.len]
  let validated = parseSourceSpans(result.source)
  if validated.error.len > 0:
    return ("", "Edited source is invalid: " & validated.error)

proc rewriteSourceFile*(path, owner, selector, replacement: string,
                        deleting = false): tuple[source: string, error: string] =
  ## Validate and atomically replace a source file in its own directory.
  var tempPath = ""
  try:
    let original = readFile(path)
    result = rewriteSource(original, owner, selector, replacement, deleting)
    if result.error.len > 0:
      return
    let permissions = getFilePermissions(path)
    var (file, createdPath) = createTempFile(".harding-edit-", ".hrd", parentDir(absolutePath(path)))
    tempPath = createdPath
    try:
      file.write(result.source)
    finally:
      file.close()
    setFilePermissions(tempPath, permissions)
    if readFile(path) != original:
      result.error = "Source file changed during editing; save aborted"
      return
    moveFile(tempPath, path)
    tempPath = ""
  except CatchableError as e:
    result.error = "Could not save source: " & e.msg
  finally:
    if tempPath.len > 0 and fileExists(tempPath):
      removeFile(tempPath)
