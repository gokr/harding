## Numeric string conversion shared by the interpreter and compiled runtime.
import std/strutils
import ./types

proc stringAsInteger*(source: string): NodeValue =
  ## Parse a complete integer string; invalid or out-of-range input answers nil.
  try:
    result = toValue(parseInt(source))
  except ValueError:
    result = nilValue()

proc stringAsFloat*(source: string): NodeValue =
  ## Parse a complete floating-point string; invalid input answers nil.
  try:
    result = toValue(parseFloat(source))
  except ValueError:
    result = nilValue()

proc stringAsNumber*(source: string): NodeValue =
  ## Prefer Integer, falling back to Float when integer parsing fails.
  result = stringAsInteger(source)
  if isNilValue(result):
    result = stringAsFloat(source)
