import std/[unittest, strutils, math]
import ../src/harding/core/[types, string_conversion]

suite "Shared numeric string conversion":
  test "complete integers and native range boundaries":
    for source in ["0", "42", "+42", "-42", $high(int), $low(int)]:
      let parsed = stringAsInteger(source)
      check parsed.kind == vkInt
      check parsed.intVal == parseInt(source)
      check stringAsNumber(source).kind == vkInt
    for source in ["", "bad", "12tail", "3.5", "1e2", " 1", "1 ", "999999999999999999999999999999"]:
      check isNilValue(stringAsInteger(source))

  test "floats and integer-first number selection":
    for source in ["3.5", "-0.25", "1e2", "+2.5", ".5"]:
      check stringAsFloat(source).kind == vkFloat
      check stringAsFloat(source).floatVal == parseFloat(source)
      check stringAsNumber(source).kind == vkFloat
    check stringAsFloat("42").floatVal == 42.0
    check stringAsNumber("42").kind == vkInt
    check stringAsNumber("999999999999999999999999999999").kind == vkFloat
    check stringAsFloat("NaN").floatVal.classify == fcNan
    check stringAsFloat("Inf").floatVal.classify == fcInf

  test "invalid input answers nil rather than zero":
    for source in ["", "bad", "12tail", "1.2tail", " 1", "1 ", "1e", "--3"]:
      check isNilValue(stringAsFloat(source))
      check isNilValue(stringAsNumber(source))
