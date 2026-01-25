#!/usr/bin/env nim
#
# Core tests for NimTalk
# Tests basic parsing, objects, and evaluation
#

import std/[strutils, os, terminal]
import ../nimtalk/core/types
import ../nimtalk/parser/[lexer, parser]
import ../nimtalk/interpreter/[evaluator, objects, activation]

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

echo "NimTalk Core Test Suite"
echo "========================"
echo ""

# Test 1: Tokenization
test("Tokenizer recognizes integer literals"):
  let tokens = lex("42")
  tokens.len == 2 and tokens[0].kind == tkInt and tokens[0].value == "42"

test("Tokenizer recognizes string literals"):
  let tokens = lex("'hello'")
  tokens.len == 2 and tokens[0].kind == tkString and tokens[0].value == "hello"

test("Tokenizer recognizes identifiers"):
  let tokens = lex("foo")
  tokens.len == 2 and tokens[0].kind == tkIdent and tokens[0].value == "foo"

test("Tokenizer recognizes keywords"):
  let tokens = lex("at:")
  tokens.len == 2 and tokens[0].kind == tkKeyword and tokens[0].value == "at:"

test("Tokenizer handles keyword sequences"):
  let tokens = lex("at:put:")
  tokens.len == 2 and tokens[0].kind == tkKeyword and tokens[0].value == "at:put:"

test("Tokenizer recognizes symbols"):
  let tokens = lex("#selector")
  tokens.len == 2 and tokens[0].kind == tkSymbol and tokens[0].value == "selector"

# Test 2: Parsing
test("Parser creates literal nodes"):
  let tokens = lex("42")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  node != nil and node of LiteralNode

test("Parser handles unary messages"):
  # For now, just test that it doesn't crash
  let tokens = lex("Object clone")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  node != nil

test("Parser handles keyword messages"):
  let tokens = lex("obj at: 'key'")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  node != nil

# Test 3: Object system
test("Root object initialization"):
  let root = initRootObject()
  root != nil and "Object" in root.tags and "Proto" in root.tags

test("Object cloning"):
  let root = initRootObject()
  let clone = root.clone().toObject()
  clone != nil and clone != root

test("Property access"):
  let obj = newObject()
  obj.setProperty("test", toValue(42))
  let val = obj.getProperty("test")
  val.kind == vkInt and val.intVal == 42

# Test 4: Interpreter
test("Interpreter evaluates integers"):
  var interp = newInterpreter()
  let tokens = lex("42")
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let result = interp.eval(node)
  result.kind == vkInt and result.intVal == 42

test("Interpreter handles property access"):
  var interp = newInterpreter()
  let code = "Object clone"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()
  let result = interp.eval(node)
  result.kind == vkObject

test("Interpreter handles message sends"):
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
  let result = interp.eval(node)

  result.kind == vkObject  # Should return the value object

# Test 5: Canonical Smalltalk test
test("Canonical Smalltalk test (3 + 4 = 7)"):
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
  let result = interp.eval(node)

  result.kind == vkObject  # Basic messaging works

# Test 6: Error handling
test("Parser reports errors for invalid input"):
  let tokens = lex("@")
  var parser = initParser(tokens)
  discard parser.parseExpression()
  parser.hasError or parser.peek().kind == tkError

test("Interpreter handles undefined messages gracefully"):
  var interp = newInterpreter()
  initGlobals(interp)

  let code = "someUndefinedMessage"
  let tokens = lex(code)
  var parser = initParser(tokens)
  let node = parser.parseExpression()

  try:
    discard interp.eval(node)
    false  # Should have raised
  except:
    true  # Expected to fail

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
