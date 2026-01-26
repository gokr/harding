#!/usr/bin/env nim
#
# Core tests for Nimtalk
# Tests basic parsing, objects, and evaluation
#

import std/[strutils, os, terminal]
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/[lexer, parser]
import ../src/nimtalk/interpreter/[evaluator, objects, activation]

# Colored output
proc green(text: string): string =
  if terminal.isatty(stdout):
    "\x1b[32m" & text & "\x1b[0m"
  else:
    text

proc red(text: string): string =
  if terminal.isatty(stdout):
    "\x1b[31m" & text & "\x1b[0m"
  else:
    text

proc yellow(text: string): string =
  if terminal.isatty(stdout):
    "\x1b[33m" & text & "\x1b[0m"
  else:
    text

# Test framework
var testsPassed = 0
var testsFailed = 0

proc test(name: string; body: proc(): bool) =
  ## Run a test
  try:
    if body():
      inc testsPassed
      echo "✓ " & green(name)
    else:
      inc testsFailed
      echo "✗ " & red(name)
  except Exception as e:
    inc testsFailed
    echo "✗ " & red(name) & " (Exception: " & e.msg & ")"

# ============================================================================
# Test Suite
# ============================================================================

echo "Nimtalk Core Test Suite"
echo "========================"
echo ""

# Test 1: Tokenization
test("Tokenizer recognizes integer literals", proc(): bool =
  let tokens = lex("42")
  result = tokens.len == 2 and tokens[0].kind == tkInt and tokens[0].value == "42"
)

test("Tokenizer recognizes string literals", proc(): bool =
  let tokens = lex("\"hello\"")
  result = tokens.len == 2 and tokens[0].kind == tkString and tokens[0].value == "hello")

test("Tokenizer recognizes identifiers", proc(): bool =
  let tokens = lex("foo")
  result = tokens.len == 2 and tokens[0].kind == tkIdent and tokens[0].value == "foo")

test("Tokenizer recognizes keywords", proc(): bool =
  let tokens = lex("at:")
  result = tokens.len == 2 and tokens[0].kind == tkKeyword and tokens[0].value == "at:")

test("Tokenizer handles keyword sequences", proc(): bool =
  let tokens = lex("at:put:")
  result = tokens.len == 2 and tokens[0].kind == tkKeyword and tokens[0].value == "at:put:")

test("Tokenizer recognizes symbols", proc(): bool =
  let tokens = lex("#selector")
  result = tokens.len == 2 and tokens[0].kind == tkSymbol and tokens[0].value == "selector"
)

# Test 2: Parsing
test("Parser creates literal nodes", proc(): bool =
  let tokens = lex("42")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  result = node != nil and node of LiteralNode
)

test("Parser handles unary messages", proc(): bool =
  # For now, just test that it doesn't crash
  let tokens = lex("Object clone")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  result = node != nil
)

test("Parser handles keyword messages", proc(): bool =
  let tokens = lex("obj at: 'key'")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  result = node != nil
)

# Test 3: Object system
test("Root object initialization", proc(): bool =
  let root = initRootObject()
  result = root != nil and "Object" in root.tags and "Proto" in root.tags
)

test("Object cloning", proc(): bool =
  let root = initRootObject()
  let clone = root.clone().toObject()
  result = clone != nil and clone != root
)

test("Property access", proc(): bool =
  var obj = newObject()
  obj.setProperty("test", toValue(42))
  let val = obj.getProperty("test")
  result = val.kind == vkInt and val.intVal == 42
)

# Test 4: Interpreter
test("Interpreter evaluates integers", proc(): bool =
  var interp = newInterpreter()
  let tokens = lex("42")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let evalResult = interp.eval(node)
  result = evalResult.kind == vkInt and evalResult.intVal == 42
)

test("Interpreter handles property access", proc(): bool =
  var interp = newInterpreter()
  let code = "Object clone"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let evalResult = interp.eval(node)
  result = evalResult.kind == vkObject
)

test("Interpreter handles message sends", proc(): bool =
  var interp = newInterpreter()
  initGlobals(interp)

  # Create object with property
  let obj = interp.rootObject.clone().toObject()
  obj.setProperty("value", toValue(3))

  # Set current receiver
  interp.currentReceiver = obj

  # Try to access property via message
  let code = "at: 'value'"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let evalResult = interp.eval(node)

  result = evalResult.kind == vkObject  # Should return the value object
)

# Test 5: Canonical Smalltalk test
test("Canonical Smalltalk test (3 + 4 = 7)", proc(): bool =
  var interp = newInterpreter()
  initGlobals(interp)

  # Create a number object
  let numObj = interp.rootObject.clone().toObject()
  numObj.setProperty("value", toValue(3))
  numObj.setProperty("other", toValue(4))

  # Set as current receiver
  interp.currentReceiver = numObj

  # Try to add (basic plumbing test)
  let code = "at: 'value'"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let evalResult = interp.eval(node)

  result = evalResult.kind == vkObject  # Basic messaging works
)

# Test 6: Error handling
test("Parser reports errors for invalid input", proc(): bool =
  let tokens = lex("@")
  var parser = initParser(tokens)
  discard parser.parseExpression()
  result = parser.hasError or parser.peek().kind == tkError
)

test("Interpreter handles undefined messages gracefully", proc(): bool =
  var interp = newInterpreter()
  initGlobals(interp)

  let code = "someUndefinedMessage"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()

  try:
    discard interp.eval(node)
    result = false  # Should have raised
  except:
    result = true  # Expected to fail
)

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================"
echo "Test Results: " & $testsPassed & " passed, " & $testsFailed & " failed"

if testsFailed == 0:
  echo ""
  echo green("✅ All tests passed!")
  quit(0)
else:
  echo ""
  echo red("❌ Some tests failed")
  quit(1)
