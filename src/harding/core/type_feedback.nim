import std/[tables, json, os, algorithm, strutils]
import checksums/sha1
import ./types

const feedbackSchema* = 1

type
  FeedbackSession = ref object
    sources: Table[string, string]
    observations: Table[string, Table[string, int]]
    invalid: bool

var session {.threadvar.}: FeedbackSession

proc feedbackValueType*(value: NodeValue): string =
  ## Record language nil, not just its vkNil representation. No values retained.
  if isNilValue(value): return "Nil"
  case value.kind
  of vkInt: "Integer"
  of vkFloat: "Float"
  of vkBool: "Boolean"
  of vkString: "String"
  of vkSymbol: "Symbol"
  of vkClass: "Class"
  of vkBlock: "Block"
  of vkArray: "Array"
  of vkTable: "Table"
  of vkInstance:
    if value.instVal != nil and value.instVal.class != nil:
      "Object:" & value.instVal.class.name
    else: "Unknown"
  else: "Unknown"

proc observe(cls: Class, index: int, value: NodeValue, event: string) {.nimcall.} =
  if session == nil or cls == nil or index < 0 or index >= cls.allSlotNames.len:
    return
  let key = cls.name & "#" & cls.allSlotNames[index]
  let tag = event & ":" & feedbackValueType(value)
  session.observations.mgetOrPut(key, initTable[string, int]()).mgetOrPut(tag, 0) += 1

proc startTypeFeedback*() =
  ## Explicit per-thread session for CLI or embedded interpreted unit-test hosts.
  if session != nil:
    raise newException(ValueError, "Type feedback session already active")
  session = FeedbackSession()
  slotObservationHook = observe

proc stopTypeFeedback*() =
  slotObservationHook = nil
  session = nil

proc recordFeedbackSource*(path, source: string) =
  ## Fingerprint exact evaluated source; changed input during a run poisons it.
  if session == nil: return
  let canonical = absolutePath(path).normalizedPath()
  let digest = $secureHash(source)
  if canonical in session.sources and session.sources[canonical] != digest:
    session.invalid = true
  session.sources[canonical] = digest

proc writeTypeFeedback*(path: string) =
  ## Atomically publish only an explicit session, never merge unrelated runs.
  if session == nil:
    raise newException(ValueError, "No active type feedback session")
  var document = %*{"schema": feedbackSchema, "evidence": "observations-not-proof",
                    "valid": not session.invalid, "sources": {}, "slots": {}}
  var sources: seq[string]
  for name in session.sources.keys: sources.add(name)
  sources.sort()
  for name in sources: document["sources"][name] = %session.sources[name]
  var slots: seq[string]
  for name in session.observations.keys: slots.add(name)
  slots.sort()
  for name in slots:
    document["slots"][name] = newJObject()
    var tags: seq[string]
    for tag in session.observations[name].keys: tags.add(tag)
    tags.sort()
    for tag in tags: document["slots"][name][tag] = %session.observations[name][tag]
  let target = absolutePath(path)
  createDir(target.parentDir)
  let staging = target & ".pending"
  try:
    writeFile(staging, pretty(document) & "\n")
    moveFile(staging, target)
  finally:
    if fileExists(staging): removeFile(staging)

proc loadTypeFeedback*(path, inputFile: string): JsonNode =
  ## Validate all recorded inputs, not just the benchmark file. Stale profiles
  ## are rejected; they never authorize changing dynamic language semantics.
  result = parseJson(readFile(path))
  if result.kind != JObject or result{"schema"} == nil or
     result["schema"].kind != JInt or result["schema"].getInt != feedbackSchema or
     result{"valid"} == nil or result["valid"].kind != JBool or not result["valid"].getBool or
     result{"sources"} == nil or result["sources"].kind != JObject or
     result{"slots"} == nil or result["slots"].kind != JObject:
    raise newException(ValueError, "Invalid type feedback schema or session")
  if absolutePath(inputFile).normalizedPath() notin result["sources"]:
    raise newException(ValueError, "Type feedback does not cover input source")
  for name, digest in result["sources"]:
    if digest.kind != JString or not fileExists(name) or
       $secureHash(readFile(name)) != digest.getStr:
      raise newException(ValueError, "Stale type feedback source: " & name)
  for name, counts in result["slots"]:
    if '#' notin name or counts.kind != JObject:
      raise newException(ValueError, "Invalid type feedback slot")
    for tag, count in counts:
      if not (tag.startsWith("read:") or tag.startsWith("write:") or tag.startsWith("initial:")) or
         count.kind != JInt or count.getBiggestInt < 1:
        raise newException(ValueError, "Invalid type feedback observation")
