import std/[unittest, json, os, tables, strutils]
import checksums/sha1
import ../src/harding/core/types
import ../src/harding/core/type_feedback

proc profile(sources: JsonNode, slots: JsonNode, valid = true, schema = 1): string =
  pretty(%*{"schema": schema, "valid": valid, "sources": sources, "slots": slots})

proc loaderError(document: string, input: string): string =
  let dir = "build/type-feedback-tests"
  createDir(dir)
  let path = dir / "candidate.json"
  writeFile(path, document)
  try:
    discard loadTypeFeedback(path, input)
  except JsonParsingError:
    return "Invalid type feedback"
  except ValueError as failure:
    return failure.msg

suite "Type feedback core":
  test "sessions are explicit, non-nested and released on stop":
    startTypeFeedback()
    var rejected = false
    try:
      startTypeFeedback()
    except ValueError:
      rejected = true
    check rejected
    stopTypeFeedback()
    startTypeFeedback()
    stopTypeFeedback()
    var noSession = false
    try:
      writeTypeFeedback("build/type-feedback-tests/never.json")
    except ValueError:
      noSession = true
    check noSession

  test "nil is one language type despite two representations":
    check feedbackValueType(nilValue()) == "Nil"
    if nilInstance != nil:
      check feedbackValueType(NodeValue(kind: vkInstance, instVal: nilInstance)) == "Nil"
    check feedbackValueType(toValue(3)) == "Integer"
    check feedbackValueType(toValue("text")) == "String"
    check feedbackValueType(NodeValue(kind: vkSymbol, symVal: "")) == "Symbol"
    check feedbackValueType(newInstance(newClass(name = "FeedbackObject")).toValue()) ==
      "Object:FeedbackObject"

  test "accepted writes and reads are counted, rejected writes are not":
    let dir = "build/type-feedback-tests"
    createDir(dir)
    let path = dir / "observations.json"
    let cls = newClass(slotNames = @["value"], name = "FeedbackScalar")
    cls.slotContracts["value"] = SlotContract(kind: scInteger)
    startTypeFeedback()
    let instance = newInstance(cls)
    instance.writeInstanceSlot(0, toValue(7))
    discard instance.readInstanceSlot(0)
    expect SlotTypeError:
      instance.writeInstanceSlot(0, toValue("wrong"))
    expect SlotTypeError:
      instance.writeInstanceSlot(0, nilValue())
    writeTypeFeedback(path)
    stopTypeFeedback()
    let slot = parseJson(readFile(path))["slots"]["FeedbackScalar#value"]
    check slot["write:Integer"].getInt == 1
    check slot["read:Integer"].getInt == 1
    check slot.hasKey("initial:Integer")
    check not slot.hasKey("write:String")
    check not slot.hasKey("write:Nil")

  test "source changes during a run invalidate the session":
    let dir = "build/type-feedback-tests"
    createDir(dir)
    let path = dir / "invalidated.json"
    let sourcePath = dir / "changing.hrd"
    writeFile(sourcePath, "1")
    startTypeFeedback()
    recordFeedbackSource(sourcePath, "1")
    recordFeedbackSource(sourcePath, "2")
    writeTypeFeedback(path)
    stopTypeFeedback()
    check parseJson(readFile(path))["valid"].getBool == false

  test "loader rejects malformed, uncovered, unvalidated and stale profiles":
    let dir = "build/type-feedback-tests"
    createDir(dir)
    let input = dir / "input.hrd"
    writeFile(input, "Box := Object derivePublic: #(v).\n")
    let digest = $secureHash("Box := Object derivePublic: #(v).\n")
    let covered = %*{absolutePath(input): digest}
    let oneSlot = %*{"Box#v": {"write:Integer": 1}}

    check "Invalid type feedback" in loaderError("{", input)
    check "Invalid type feedback schema" in loaderError(profile(%*{}, %*{}, schema = 99), input)
    check "Invalid type feedback schema" in loaderError(profile(%*{}, %*{}, valid = false), input)
    check "does not cover input source" in loaderError(profile(%*{}, oneSlot), input)
    check "Invalid type feedback slot" in
      loaderError(profile(covered, %*{"badschema": {"read:Nil": 1}}), input)
    check "Invalid type feedback observation" in
      loaderError(profile(covered, %*{"Box#v": {"assign:Nil": 1}}), input)
    check "Invalid type feedback observation" in
      loaderError(profile(covered, %*{"Box#v": {"read:Nil": 0}}), input)
    check "Stale type feedback source" in
      loaderError(profile(%*{absolutePath(input): "deadbeef"}, oneSlot), input)

    check "Invalid type feedback" notin loaderError(profile(covered, oneSlot), input)

  test "a valid profile loads and a changed source is reported stale":
    let dir = "build/type-feedback-tests"
    createDir(dir)
    let input = dir / "valid.hrd"
    writeFile(input, "Box := Object derivePublic: #(v).\n")
    let path = dir / "valid.json"
    writeFile(path, profile(%*{absolutePath(input): $secureHash("Box := Object derivePublic: #(v).\n")},
      %*{"Box#v": {"read:Nil": 2, "write:Integer": 1}}))
    let loaded = loadTypeFeedback(path, input)
    check loaded["slots"]["Box#v"]["write:Integer"].getInt == 1
    writeFile(input, "Box := Object derivePublic: #(v, extra).\n")
    var message = ""
    try:
      discard loadTypeFeedback(path, input)
    except ValueError as failure:
      message = failure.msg
    check "Stale type feedback source" in message
