import std/[unittest, tables, strutils, json]
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

  test "an implicit last expression return carries its kind":
    # `n + 1` is the answer; the body has no explicit ^, so the collector must
    # treat the trailing expression as the return value. The evidence originates
    # at a real call site with an Integer argument.
    let result = infer("""
      Helper := Object derivePublic: #(tag).
      Helper>>plain: n [ n + 1 ]
      Acc := Object derivePublic: #(total).
      Acc>>bump: n [ total := Helper plain: n. ^ self ]
      Entry := Object derivePublic: #(tag).
      Entry>>run [ | a | a := Acc new. a bump: 3. ^ a ]
    """)
    check result.slots["Acc#total"].kind == skInt

  test "a return inside a block carries its kind":
    let result = infer("""
      Picker := Object derivePublic: #(tag).
      Picker>>choose: n [ ^(n > 0 ifTrue: [1] ifFalse: [2]) ]
      Acc := Object derivePublic: #(chosen).
      Acc>>set: n [ chosen := Picker choose: n. ^ self ]
      Entry := Object derivePublic: #(tag).
      Entry>>run [ | a | a := Acc new. a set: 5. ^ a ]
    """)
    check result.slots["Acc#chosen"].kind == skInt

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
    check result.slots["C#total"].kind == skInt
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

suite "Static propagation candidates":
  test "call arguments propagate through temporaries into slots":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [ | saved | saved := argument. value := saved ].
      box := Box new.
      box set: 3.
    """)
    check evidence.slots["Box#value"].kind == skInt

  test "conflicting call sites keep a dynamic candidate":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [ value := argument ].
      box := Box new. box set: 3. box set: 2.5.
    """)
    check evidence.slots["Box#value"].kind == skDynamic

  test "self and super method returns propagate to slot assignments":
    let evidence = infer("""
      Parent := Object derivePublic: #().
      Parent>>answer [^4].
      Child := Parent derivePublic: #(total).
      Child>>answer [^super answer].
      Child>>setup [total := self answer + 1].
    """)
    check evidence.slots["Child#total"].kind == skInt

  test "nested block locals cannot create phantom slots":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [ [| scratch | scratch := 3. value := scratch] value ].
    """)
    check "Box#scratch" notin evidence.slots
    check evidence.slots["Box#value"].kind == skInt

  test "Symbol literals are distinct candidates":
    let evidence = infer("""
      Box := Object derivePublic: #(state).
      Box>>set [state := #""].
    """)
    check evidence.slots["Box#state"].kind == skSymbol

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

suite "Observations reconcile with static candidates":
  proc report(inferred: InferenceResult, observed: JsonNode): JsonNode =
    inferenceReport(inferred, observed)

  test "observations can reject a wrong static candidate":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [value := argument].
      box := Box new. box set: 3.
    """)
    check evidence.slots["Box#value"].kind == skInt
    let observed = %*{"slots": {"Box#value": {"write:Integer": 5, "write:String": 1}}}
    let slot = report(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["effectiveReason"].getStr == "contradicted by observations"

  test "observed nil rejects a static candidate":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 1].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 2, "write:Nil": 1}}}
    let slot = report(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["effectiveReason"].getStr == "nil observed at runtime"

  test "agreement is recorded as confirmed but still guarded and unnarrowed":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 1].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 4}}}
    let slot = report(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skInt"
    check slot["evidence"].getStr == "static+observations"
    check slot["requiresGuard"].getBool
    check not slot["storageNarrowed"].getBool

  test "a dynamic static slot is never narrowed by observations alone":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [value := argument].
    """)
    check evidence.slots["Box#value"].kind == skDynamic
    let observed = %*{"slots": {"Box#value": {"write:Integer": 9}}}
    let slot = report(evidence, observed)["slots"]["Box#value"]
    check slot["evidence"].getStr == "observed-proposal"
    check slot["effectiveCandidate"].getStr == "skInt"
    check slot["requiresGuard"].getBool
    check not slot["storageNarrowed"].getBool

  test "multiple observed kinds leave a dynamic slot dynamic":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [value := argument].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 1, "write:String": 1}}}
    let slot = report(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["evidence"].getStr == "static"

  test "report carries no storage-narrowing claim":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 1].
    """)
    let document = report(evidence, nil)
    check document["semantics"].getStr == "advisory-no-storage-narrowing"
    for _, slot in document["slots"]:
      check slot["requiresGuard"].getBool
      check not slot["storageNarrowed"].getBool

suite "Integer and Float together require a decision":
  proc widen(inferred: InferenceResult, observed: JsonNode): JsonNode =
    inferenceReport(inferred, observed)

  test "Integer and Float together are reported as a conflict, not auto-widened":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 0].
    """)
    check evidence.slots["Box#value"].kind == skInt
    let observed = %*{"slots": {"Box#value": {"write:Integer": 12932, "write:Float": 33}}}
    let slot = widen(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["evidence"].getStr == "numeric-conflict"
    check slot["effectiveReason"].getStr.contains("declare Float or Integer")
    check not slot["storageNarrowed"].getBool

  test "a dynamic slot seeing both numerics stays dynamic":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set: argument [value := argument].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 2, "write:Float": 1}}}
    let slot = widen(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["evidence"].getStr == "numeric-conflict"

  test "nil still wins over numeric widening":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 0].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 3, "write:Float": 1, "write:Nil": 1}}}
    check widen(evidence, observed)["slots"]["Box#value"]["effectiveCandidate"].getStr == "skDynamic"

  test "widening does not apply to non-numeric mixtures":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 0].
    """)
    let observed = %*{"slots": {"Box#value": {"write:Integer": 1, "write:String": 1}}}
    let slot = widen(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["effectiveReason"].getStr == "contradicted by observations"

  test "a declared Float that also sees Integers is flagged for a decision":
    let evidence = infer("""
      Box := Object derivePublic: #(value).
      Box>>set [value := 1.5].
    """)
    check evidence.slots["Box#value"].kind == skFloat
    let observed = %*{"slots": {"Box#value": {"write:Integer": 1, "write:Float": 4}}}
    let slot = widen(evidence, observed)["slots"]["Box#value"]
    check slot["effectiveCandidate"].getStr == "skDynamic"
    check slot["evidence"].getStr == "numeric-conflict"
