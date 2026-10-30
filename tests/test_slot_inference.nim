import std/[unittest, tables, strutils]
import ../src/harding/parser/parser
import ../src/harding/compiler/analyzer
import ../src/harding/compiler/slot_inference
import ../src/harding/compiler/types

proc infer(source: string): InferenceResult =
  let (nodes, syntax) = parse(source)
  require not syntax.hasError
  let analysis = buildClassGraph(nodes)
  inferSlots(nodes, analysis.classes)

suite "Static slot-kind inference":
  test "literal writes classify primitives":
    let result = infer("""
      Point := Object derivePublic: #(x, y, tag, label).
      Point>>setup [
        x := 1. y := 2.5. tag := true. label := "north". ^ self
      ]
    """)
    check result.slots["Point#x"].kind == skInt
    check result.slots["Point#y"].kind == skFloat
    check result.slots["Point#tag"].kind == skBool
    check result.slots["Point#label"].kind == skString

  test "nil writes leave a slot dynamic":
    let result = infer("""
      Node := Object derivePublic: #(next).
      Node>>setup [ next := nil. ^ self ]
    """)
    check result.slots["Node#next"].kind == skDynamic
    check result.slots["Node#next"].nilSeen

  test "conflicting primitive kinds fall back to dynamic":
    let result = infer("""
      Acc := Object derivePublic: #(balance).
      Acc>>a [ balance := 1. ^ self ]
      Acc>>b [ balance := 2.5. ^ self ]
    """)
    check result.slots["Acc#balance"].kind == skDynamic
    check result.slots["Acc#balance"].reason == "conflicting kinds"

  test "a non-literal write prevents typing":
    let result = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: v [ value := v. ^ self ]
    """)
    check result.slots["Box#value"].kind == skDynamic

  test "object evidence comes from Class new":
    let result = infer("""
      Link := Object derivePublic: #().
      Holder := Object derivePublic: #(first).
      Holder>>setup [ first := Link new. ^ self ]
    """)
    check result.slots["Holder#first"].kind == skObject
    check result.slots["Holder#first"].className == "Link"

  test "different object classes fall back to dynamic":
    let result = infer("""
      A := Object derivePublic: #().
      B := Object derivePublic: #().
      H := Object derivePublic: #(held).
      H>>one [ held := A new. ^ self ]
      H>>two [ held := B new. ^ self ]
    """)
    check result.slots["H#held"].kind == skDynamic
    check result.slots["H#held"].reason == "conflicting classes"

  test "declared temporaries are never mistaken for slot writes":
    let result = infer("""
      C := Object derivePublic: #(total).
      C>>run [
        | scratch |
        scratch := 1.
        total := scratch.
        ^ self
      ]
    """)
    check result.slots["C#total"].kind == skDynamic
    check "C#scratch" notin result.slots

  test "unwritten slots are reported unresolved rather than assumed":
    let result = infer("""
      C := Object derivePublic: #(used, unused).
      C>>set [ used := 1. ^ self ]
    """)
    check result.slots["C#used"].kind == skInt
    check result.slots["C#unused"].writes == 0
    check "C#unused" in result.unresolved

  test "writes inside nested blocks and conditionals are seen":
    let result = infer("""
      C := Object derivePublic: #(count).
      C>>run: flag [
        flag ifTrue: [ count := 7 ] ifFalse: [ count := 8 ].
        ^ self
      ]
    """)
    check result.slots["C#count"].kind == skInt

  test "summary is auditable":
    let result = infer("""
      C := Object derivePublic: #(a, b).
      C>>set [ a := 1. b := nil. ^ self ]
    """)
    let text = summarise(result)
    check text.contains("int=1")
    check text.contains("dynamic=1")

  test "inference changes no generated behaviour":
    # The result is advisory only: nothing here mutates the analysis it came from.
    let (nodes, syntax) = parse("""
      C := Object derivePublic: #(x).
      C>>set [ x := 1. ^ self ]
    """)
    require not syntax.hasError
    let before = buildClassGraph(nodes)
    let slotCount = before.classes["C"].slots.len
    discard inferSlots(nodes, before.classes)
    check before.classes["C"].slots.len == slotCount
    check before.classes["C"].slots[0].constraint == tcNone

suite "Outside and class-side writes":
  test "outside named access prevents typing the slot":
    let result = infer("""
      C := Object derivePublic: #(items).
      C>>setup [ items := 1. ^ self ]
      Factory := Object derive: #().
      Factory class>>build [ | t | t := C basicNew. t::items := 2. ^ t ]
    """)
    check result.slots["C#items"].kind == skDynamic

  test "class-side write through a variable receiver stays dynamic":
    # The receiver is a local (`t`), so the analyzer cannot prove it is a `C`.
    # Conservative and correct: this is the shape of every factory in lib/.
    let result = infer("""
      C := Object derivePublic: #(items).
      C class>>build [ | t | t := self basicNew. t::items := 5. ^ t ]
    """)
    check result.slots["C#items"].kind == skDynamic
    check result.slots["C#items"].reason == "written from outside the class"

  test "class-side method writes are not attributed to instance slots":
    let result = infer("""
      C := Object derivePublic: #(x).
      C class>>make [ ^ 1 ]
    """)
    check result.slots["C#x"].writes == 0
    check "C#x" in result.unresolved
