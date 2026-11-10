#
# test_smalltalk_alignment.nim - Regressions for the findings in docs/FIXES.md.
#
# Each test names the FIXES.md item it protects.
#
# Fixed defects have unconditional assertions: regressions must fail, not skip.
#
# Tests marked "guard" protect behaviour that is currently correct and easy to
# regress, including several things that were mis-reported as broken during the
# review (super in class methods, mixin adoption, Set>>clone).
#

import std/unittest
import std/[strutils, tables]
import std/os
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var sharedInterp = newSharedStdlibInterpreter()

proc answer(source: string): string =
  ## Evaluate and answer the last expression as text, without the quotes
  ## `toString` puts around a String result. Raises when the source fails, so a
  ## test cannot silently pass on a broken script.
  ##
  ## `doit` reports a caught Harding error in the returned string but lets an
  ## uncaught one reach the caller as a Nim exception (that is how the CLI
  ## prints it), so both shapes count as failure here.
  var value: NodeValue
  var err: string
  try:
    (value, err) = sharedInterp.doit(source)
  except CatchableError as e:
    raise newException(AssertionDefect, "uncaught for <" & source & ">: " & e.msg)
  doAssert err.len == 0, "unexpected error for <" & source & ">: " & err
  result = value.toString()
  if result.len >= 2 and result[0] == '"' and result[^1] == '"':
    result = result[1 .. ^2]

proc fails(source: string): bool =
  ## True when the source fails to parse or raises while evaluating, whether
  ## the failure is reported or raised.
  try:
    let (value, err) = sharedInterp.doit(source)
    discard value
    result = err.len > 0
  except CatchableError:
    result = true

proc symbolLiteral(name: string): string =
  ## The string-symbol form, which is the escape hatch for an operator that
  ## cannot be written bare: `#"<="` is the symbol `#<=`.
  "#\"" & name & "\""

const repoRoot = currentSourcePath().parentDir().parentDir()

const stdlibSourceFiles = [
  "lib/core/Array.hrd", "lib/core/Bag.hrd", "lib/core/Block.hrd",
  "lib/core/Boolean.hrd", "lib/core/Comparable.hrd", "lib/core/Equatable.hrd",
  "lib/core/Exception.hrd", "lib/core/False.hrd", "lib/core/Float.hrd",
  "lib/core/Integer.hrd", "lib/core/Iterable.hrd", "lib/core/Number.hrd",
  "lib/core/Object.hrd", "lib/core/Printable.hrd", "lib/core/Set.hrd",
  "lib/core/String.hrd", "lib/core/Symbol.hrd", "lib/core/System.hrd",
  "lib/core/Table.hrd", "lib/core/True.hrd", "lib/core/UndefinedObject.hrd",
  "lib/standard/Interval.hrd", "lib/standard/Json.hrd",
  "lib/standard/SortedCollection.hrd"
]

proc methodHeadline(line: string): string =
  ## The `Class>>selector` key of a method definition headline, or "".
  ##
  ## Deliberately line-based: a duplicate is two headlines with the same
  ## selector, which needs no parse. The headline form is
  ## `Class>>keyword: arg keyword: arg [` with parameter names between the
  ## keyword parts, so the selector is the whitespace-separated tokens that end
  ## in `:`. A unary or binary method has one token and no keyword parts.
  if line.len == 0 or not line[0].isAlphaAscii or not line[0].isUpperAscii:
    return ""
  let marker = line.find(">>")
  if marker <= 0:
    return ""
  let bodyStart = line.find('[', marker)
  if bodyStart < 0:
    return ""
  let classPart = line[0 ..< marker].strip()
  let head = line[marker + 2 ..< bodyStart].strip()
  if classPart.len == 0 or head.len == 0:
    return ""
  var keywordParts: seq[string]
  for token in head.splitWhitespace():
    if token.endsWith(":"):
      keywordParts.add(token)
  let selector = if keywordParts.len > 0: keywordParts.join("")
                 else: head.splitWhitespace()[0]
  result = classPart & ">>" & selector

suite "FIXES.md controlled defects":

  test "D1: a user-defined & wins over the quick primitive":
    # Granite answers 11. The interpreter answers "<instance of K>1" because a
    # quick primitive runs ahead of method lookup.
    check answer("""
      K := Object derive: #().
      K>>& other [ ^ 11 ].
      K new & 1
    """) == "11"

  test "D2a: Comparable defines > and no bogus unary anObject":
    # The file lost the `>` selector, so the body is installed as a unary method
    # named `anObject` and `>` is missing from the mixin entirely.
    check answer("""
      ((Comparable definedMethods includes: #>) printString & "/" &
       (Comparable definedMethods includes: #anObject) printString)
    """) == "true/false"

  test "D2b: <= and >= work on String through Comparable":
    check answer("""("a" <= "b") printString""") == "true"
    check answer("""("b" >= "a") printString""") == "true"
    check answer("""("a" compareTo: "a")""") == "0"
    check answer("""("a" compareTo: "b")""") == "-1"

  test "D3: class-side method reflection has its own selectors":
    # `K class == K`, so a class receiver cannot select a side; each table needs
    # its own selector. `methods`/`definedMethods` stay instance-side and
    # `classMethods`/`definedClassMethods` answer the class side.
    check answer("""
      K := Object derive: #().
      K>>im [ ^ 1 ].
      K class>>cm [ ^ 2 ].
      K class definedMethods printString
    """) == "#(#im)"
    check answer("""
      K2 := Object derive: #().
      K2>>im2 [ ^ 1 ].
      K2 class>>cm2 [ ^ 2 ].
      K2 class definedClassMethods printString
    """) == "#(#cm2)"
    check answer("""
      K3 := Object derive: #().
      K3 class>>cm3 [ ^ 2 ].
      K3 class classMethods includes: #cm3
    """) == "true"

  test "D4: Interval>>asArray has no nil hole and keeps the count":
    check answer("""
      arr := (1 to: 3) asArray.
      arr size printString & "/" & (arr at: 0) printString
    """) == "3/1"

  test "D4b: Interval>>withIndexDo: is 0-based like Array>>withIndexDo:":
    check answer("""
      first := -1.
      (1 to: 3) withIndexDo: [:each :index | first = -1 ifTrue: [ first := index ] ].
      first
    """) == "0"

  test "D4c: Interval>>asArray keeps the last element":
    check answer("""
      arr := (1 to: 3) asArray.
      arr last printString
    """) == "3"

  test "D5: an out-of-range at:put: signals instead of dropping the write":
    check answer("""
      arr := Array new: 3.
      [ arr at: 9 put: 9 ] on: SubscriptOutOfBounds do: [:e | "signalled" ]
    """) == "signalled"
    # The read side already signals, so the write must match it.
    check answer("""
      arr2 := Array new: 3.
      [ arr2 at: 9 ] on: SubscriptOutOfBounds do: [:e | "read-signals" ]
    """) == "read-signals"

  test "D6: bare multi-character operator symbols":
    # Under the current lexer, '#' followed by any of = - * / . | & @ ! starts a
    # comment, so those cannot be written bare, and #<= / #>= truncate after one
    # character. The fix reduces the rule to '# + whitespace'; until then the
    # bare forms fail and this stays skipped.
    const bare = ["<=", ">=", "~=", "-", "|", "&"]
    var failures: seq[string]
    for selector in bare:
      let (value, err) = sharedInterp.doit("#" & selector)
      if err.len > 0 or value.toString() != selector:
        failures.add(selector)
    check failures.len == 0

  test "D6b: whitespace alone decides between comment and symbol":
    # The rule is one condition: `#` at end of line, before whitespace, or before
    # another `#` starts a comment; anything else starts a symbol or literal.
    check answer("""
      # a comment
      total := 0
      # ===== separator in the new spelling
      total := total + 1
      total
    """) == "1"
    check answer("#size printString") == "#size"
    # A `#` + space line is a comment, so it cannot be an expression.
    check fails("# size asSymbol isNil")
    # `#name` with no space is a symbol, so a bare `#comment` line is an error,
    # not silently swallowed as a comment.
    check fails("#no-space-comment here")

  test "D6c: '##' is reserved for documentation comments":
    # Nim semantics: ## precedes a declaration and is collected by tooling.
    # Today '##text' lexes as '#'+symbol then a stray identifier.
    const source = """
      ## Documented method below.
      K := Object derive: #().
      K>>m [ ^ 1 ].
      K new m
    """
    check answer(source) == "1"

  test "D7: a symbol answers its class":
    # classOfValue returns nil for vkSymbol; Granite answers <class Symbol>.
    check answer("#foo class printString") == "<class Symbol>"
    check answer("#foo isKindOf: Symbol") == "true"

  test "D9: Printable writes to a write: sink without Streams or Transcript":
    check answer("""
      AlignmentSink := Object derive: #(text).
      AlignmentSink>>initialize [ text := "". ^self ].
      AlignmentSink>>write: value [ text := text & value. ^self ].
      AlignmentSink>>contents [ ^text ].
      AlignmentPrintable := Object derive: #().
      AlignmentPrintable addSuperclass: Printable.
      sink := AlignmentSink new.
      AlignmentPrintable new printOn: sink.
      sink contents
    """) == "<AlignmentPrintable>"
    check answer("""
      sink := AlignmentSink new.
      AlignmentPrintable new displayOn: sink.
      sink contents
    """) == "<AlignmentPrintable>"

  test "D11: indexOf: answers nil on a miss for every collection":
    check answer("#(10, 20) indexOf: 99") == "nil"
    # String answers -1; every other collection and NotFound.hrd say nil.
    check answer("""("abc" indexOf: "z") printString""") == "nil"

  test "D13: a super send to a missing method is a catchable error":
    # The interpreter raises a Nim ValueError here, which escapes both the
    # returned error string and an enclosing on:do:, so the script dies.
    const source = """
      P := Object derive: #().
      C := P derive: #().
      C>>m [ ^ super nope ].
      [ C new m ] on: Error do: [:e | "caught" ]
    """
    check answer(source) == "caught"

  test "D8: no stdlib file defines the same method twice":
    # Interval.hrd defined anySatisfy:, allSatisfy: and sum twice; the later
    # definition silently won, and the first read as if it were live code.
    # A duplicate is invisible in the loaded method table, so scan the source.
    var duplicates: seq[string]
    for relative in stdlibSourceFiles:
      let path = repoRoot / relative
      var seen = initTable[string, int]()
      var lineNumber = 0
      for line in lines(path):
        inc lineNumber
        let key = methodHeadline(line)
        if key.len == 0:
          continue
        if seen.hasKey(key):
          duplicates.add(relative & ":" & $lineNumber & " repeats " & key)
        else:
          seen[key] = lineNumber
    if duplicates.len > 0:
      for entry in duplicates:
        echo "  duplicate definition: ", entry
    check duplicates.len == 0

suite "FIXES.md guards: behaviour to keep":

  test "guard: super works in class methods":
    check answer("""
      B := Object derive: #().
      B class>>greet [ ^ "B" ].
      D := B derive: #().
      D class>>greet [ ^ "D+" & super greet ].
      D greet
    """) == "D+B"

  test "guard: qualified super selects a named parent":
    check answer("""
      P1 := Object derive: #().
      P1>>who [ ^ "p1" ].
      P2 := Object derive: #().
      P2>>who [ ^ "p2" ].
      C := Object derive: #().
      C addSuperclass: P1.
      C addSuperclass: P2.
      C>>who [ ^ super<P1> who & "/" & super<P2> who ].
      C new who
    """) == "p1/p2"

  test "guard: super works in instance methods":
    check answer("""
      B := Object derive: #().
      B>>inst [ ^ "bi" ].
      D := B derive: #().
      D>>inst [ ^ "di+" & super inst ].
      D new inst
    """) == "di+bi"

  test "guard: class-side methods are inherited":
    check answer("""
      B := Object derive: #().
      B class>>greet [ ^ "B" ].
      D := B derive: #().
      D greet
    """) == "B"

  test "guard: a mixin supplies methods and the adopter's own definition wins":
    check answer("""
      M := Mixin derive.
      M>>describe [ ^ "mixin" ].
      K := Object derive: #().
      K addSuperclass: M.
      K new describe
    """) == "mixin"
    check answer("""
      M2 := Mixin derive.
      M2>>describe2 [ ^ "mixin" ].
      K2 := Object derive: #().
      K2 addSuperclass: M2.
      K2>>describe2 [ ^ "own" ].
      K2 new describe2
    """) == "own"

  test "guard: multiple inheritance reports conflicting methods":
    check answer("""
      P1 := Object derive: #().
      P1>>clash [ ^ 1 ].
      P2 := Object derive: #().
      P2>>clash [ ^ 2 ].
      C := Object derive: #().
      C addSuperclass: P1.
      C addSuperclass: P2.
      C new conflictSelectors includes: "clash"
    """) == "true"

  test "guard: & concatenates string representations of any receiver":
    check answer("(1 & 2) printString") == "12"
    check answer("""("ab" & "cd")""") == "abcd"
    check answer("#(1, 2) & #(3)") == "#(1 2)#(3)"

  test "guard: & and | on Boolean are conjunction and disjunction":
    # True>>&/False>>& and True>>|/False>>| are Smalltalk's non-short-circuit
    # Boolean operators. A quick primitive used to answer them with string
    # concatenation, which shadowed the shipped library definitions.
    check answer("(true & false) printString") == "false"
    check answer("(true & true) printString") == "true"
    check answer("(true | false) printString") == "true"
    check answer("(false | false) printString") == "false"
    check answer("(true & false) isKindOf: Boolean") == "true"

  test "guard: a class can override & like any other method":
    check answer("""
      K := Object derive: #().
      K>>& other [ ^ "overridden" ].
      K new & 1
    """) == "overridden"

  test "guard: the string-symbol escape hatch names any operator":
    for selector in ["<=", ">=", "~=", "==", "-", "|", "&", "//"]:
      check answer("(" & selector.symbolLiteral & ") printString") == "#" & selector

  test "guard: single-character symbols that are not comment starters":
    for selector in ["#<", "#>", "#+", "#%", "#~"]:
      check answer("(" & selector & ") printString") == selector

  test "guard: message precedence is Smalltalk's table":
    # unary > binary (left-to-right, no arithmetic precedence) > keyword.
    # This is the Smalltalk-80 table, so these results are not Harding quirks:
    # `2 * 3 max: 4` answering 6 is Smalltalk behaviour, not a divergence.
    check answer("2 + 3 * 4") == "20"          # left-to-right, no precedence
    check answer("10 - 2 - 3") == "5"
    check answer("5 - 2 negated") == "7"       # unary binds tighter than binary
    check answer("2 * 3 negated") == "-6"
    check answer("2 * 3 max: 4") == "6"        # binary binds tighter than keyword
    check answer("2 * (3 max: 4)") == "8"
    # Binary binds tighter than a keyword argument.
    check answer("#(10, 20, 30, 40, 50) at: 1 + 2") == "40"

  test "guard: numbers and strings compare as documented":
    check answer("(1 = 1.0) printString") == "false"
    check answer("(1 + 1.0) printString") == "2.0"
    check answer("(4 / 2) printString") == "2.0"
    check answer("(-7 // 2) printString") == "-3"
    check answer("(-7 % 2) printString") == "-1"

  test "guard: structural equality is per class":
    check answer("(Table new at: #a put: 1) = (Table new at: #a put: 1)") == "true"
    check answer("(Set new add: 1) = (Set new add: 1)") == "true"
    check answer("(1 to: 2) = (1 to: 2)") == "true"
    # Array equality is identity by design; changing it is a language decision.
    check answer("#(1, 2) = #(1, 2)") == "false"

  test "guard: clone is a shallow copy for instances and builtin collections":
    check answer("""
      a := Array new.
      a add: 1.
      b := a clone.
      b add: 2.
      a size
    """) == "1"
    check answer("""
      s := Set new.
      s add: 1.
      (s clone) size
    """) == "1"
    check answer("(Object new clone) class name") == "Object"

  test "guard: overflow is a catchable Overflow":
    check answer("""
      [ 9223372036854775807 + 1 ] on: Overflow do: [:e | "caught" ]
    """) == "caught"
    check answer("Overflow superclassNames at: 0") == "ArithmeticError"

  test "guard: doesNotUnderstand: is reachable for unary, binary and keyword":
    check answer("""
      K := Object derive: #().
      K>>doesNotUnderstand: selector [ ^ "dnu:" & selector asString ].
      K new bogus
    """) == "dnu:bogus"
    check answer("""
      K2 := Object derive: #().
      K2>>doesNotUnderstand: selector [ ^ "dnu:" & selector asString ].
      K2 new at: 1 put: 2
    """) == "dnu:at:put:"

  test "guard: reflection vocabulary stays method-based":
    check answer("Object methods includes: #printString") == "true"
    check answer("Object new respondsTo: #perform:with:") == "true"
    # A method name is a Symbol, and perform: accepts it.
    check answer("""
      m := Object methods.
      (m at: 0) isKindOf: Symbol
    """) == "true"

  test "guard: nil is an object and answers ifNil:":
    check answer("nil isNil") == "true"
    check answer("nil class name") == "UndefinedObject"
    check answer("nil ifNil: [ 1 ]") == "1"
