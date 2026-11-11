# Native Nim reference for benchmark/shapes.hrd (polymorphic dispatch).
#
# This is the "aim" for the Harding version: the same protocol in idiomatic Nim,
# using ref objects and a closed hierarchy so the compiler can devirtualise what it
# can. It is a representation reference, not a semantics oracle -- it is hand
# written, and its existence says nothing about what the Harding source must compile
# to. Compare trends, not exact multipliers.
#
# The Harding program sends `area`, `describe` and `label` to a heterogeneous
# collection, repeating the whole protocol 200 times per pass. This port keeps that
# structure exactly: an array of distinct concrete types dispatched through one
# variable, 200 times per pass.
import std/[os, strutils]

type
  Shape = ref object of RootObj
  Circle = ref object of Shape
    radius: int
  Rect = ref object of Shape
    width, height: int
  Square = ref object of Rect
  Triangle = ref object of Shape
    base, height: int
  Ellipse = ref object of Shape
    major, minor: int

method area(shape: Shape): int {.base.} = 0
method area(shape: Circle): int = shape.radius * shape.radius * 3
method area(shape: Rect): int = shape.width * shape.height
method area(shape: Square): int = shape.width * shape.width
method area(shape: Triangle): int = shape.base * shape.height div 2
method area(shape: Ellipse): int = shape.major * shape.minor * 2

method describe(shape: Shape): int {.base.} = 0
method describe(shape: Circle): int = 1
method describe(shape: Rect): int = 2
method describe(shape: Square): int = 3
method describe(shape: Triangle): int = 4
method describe(shape: Ellipse): int = 5

method labelLen(shape: Shape): int {.base.} = 5
method labelLen(shape: Circle): int = 6
method labelLen(shape: Rect): int = 4
method labelLen(shape: Square): int = 6
method labelLen(shape: Triangle): int = 8
method labelLen(shape: Ellipse): int = 7

proc runShapes(): int =
  let shapes: seq[Shape] = @[
    Circle(radius: 10),
    Rect(width: 20, height: 15),
    Square(width: 12, height: 12),
    Triangle(base: 16, height: 9),
    Ellipse(major: 7, minor: 3)
  ]
  var total = 0
  for _ in 0..<200:
    for each in shapes: total += each.area()
    for each in shapes:
      if each.describe() == 1: inc total
    for each in shapes: total += each.labelLen()
  total

when isMainModule:
  let repetitions = if paramCount() > 0: parseInt(paramStr(1)) else: 1
  doAssert repetitions >= 0
  var total = 0
  for _ in 0..<repetitions:
    total += runShapes()
  doAssert total == 178000 * repetitions, "shapes total differs: " & $total
  echo total
