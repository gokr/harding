import std/[unittest, tables, strutils]
import ../src/harding/parser/parser
import ../src/harding/compiler/analyzer
import ../src/harding/compiler/slot_diagnostics

proc diagnose(source: string): seq[SlotDiagnostic] =
  let (nodes, syntax) = parse(source)
  require not syntax.hasError
  diagnoseSlotStores(nodes, buildClassGraph(nodes).classes, "test.hrd")

suite "Numeric slot store diagnostics":
  test "warns when an Integer is provably stored into a Float slot":
    let found = diagnose("""
      P := Object derivePublic: #{#ratio -> Float}.
      P>>set [ratio := 3].
    """)
    check found.len == 1
    check found[0].rule == "int-to-float"
    check found[0].severity == dsWarning
    check found[0].slotName == "ratio"
    check found[0].message.contains("2^53")

  test "errors when a Float is provably stored into an Integer slot":
    let found = diagnose("""
      P := Object derivePublic: #{#count -> Integer}.
      P>>set [count := 1.5].
    """)
    check found.len == 1
    check found[0].rule == "float-to-int"
    check found[0].severity == dsError

  test "a matching kind produces no diagnostic":
    check diagnose("""
      P := Object derivePublic: #{#count -> Integer, #ratio -> Float}.
      P>>set [count := 7. ratio := 2.5].
    """).len == 0

  test "untyped and dynamic slots are never diagnosed":
    check diagnose("""
      P := Object derivePublic: #(free, other).
      Q := Object derivePublic: #{#anything -> nil}.
      P>>set [free := 1. other := 2.5].
      Q>>set [anything := 1. anything := 2.5].
    """).len == 0

  test "non-literal values stay silent rather than guessing":
    check diagnose("""
      P := Object derivePublic: #{#ratio -> Float, #count -> Integer}.
      P>>set: n [ratio := n. count := n].
      P>>fromCall [ratio := self compute. count := self compute].
      P>>compute [^1].
    """).len == 0

  test "temporaries are not mistaken for slots":
    check diagnose("""
      P := Object derivePublic: #{#ratio -> Float}.
      P>>set [| ratio | ratio := 3. ^self].
    """).len == 0

  test "integer arithmetic is still Integer":
    let found = diagnose("""
      P := Object derivePublic: #{#ratio -> Float}.
      P>>set [ratio := 2 + 3].
    """)
    check found.len == 1
    check found[0].rule == "int-to-float"

  test "float arithmetic is Float":
    let found = diagnose("""
      P := Object derivePublic: #{#count -> Integer}.
      P>>set [count := 1.5 + 2].
    """)
    check found.len == 1
    check found[0].rule == "float-to-int"

  test "inherited declared slots are diagnosed":
    let found = diagnose("""
      Base := Object derivePublic: #{#ratio -> Float}.
      Child := Base derivePublic: #(extra).
      Child>>set [ratio := 4].
    """)
    check found.len == 1
    check found[0].rule == "int-to-float"

  test "both problems are reported, not just the first":
    let found = diagnose("""
      P := Object derivePublic: #{#count -> Integer, #ratio -> Float}.
      P>>set [count := 1.5. ratio := 3].
    """)
    check found.len == 2

  test "format names the rule":
    let found = diagnose("""
      P := Object derivePublic: #{#ratio -> Float}.
      P>>set [ratio := 3].
    """)
    let text = format(found[0])
    check text.contains("warning")
    check text.contains("[int-to-float]")
