import std/[unittest, os, json, tables, strutils]
import checksums/sha1
import ../src/harding/compiler/frozen_manifest

let scratch = "build/frozen-manifest-tests"
createDir(scratch)

proc fixture(): JsonNode =
  writeFile(scratch / "Parent.hrd", "Parent := Object derive: #().\n")
  writeFile(scratch / "Child.hrd", "# @frozen\nChild := Parent derive: #(). Child>>answer [ ^ 42 ].\n")
  result = %*{"version": 1, "roots": ["Child"], "classes": [
    {"name": "Parent", "source": "Parent.hrd", "sha1": $secureHash(readFile(scratch / "Parent.hrd")),
     "tier": "counterpart", "dependencies": newJArray(), "cases": ["class_factory"]},
    {"name": "Child", "source": "Child.hrd", "sha1": $secureHash(readFile(scratch / "Child.hrd")),
     "tier": "generic", "dependencies": ["Parent"], "cases": ["class_factory"]}]}

proc load(document: JsonNode): FrozenPlan =
  writeFile(scratch / "manifest.json", $document)
  loadFrozenPlan(scratch / "manifest.json", scratch)

suite "Frozen manifest":
  teardown:
    for name in ["Parent.hrd", "Child.hrd", "manifest.json"]:
      if fileExists(scratch / name): removeFile(scratch / name)

  test "dependency closure is ordered and only generic source is composed":
    let plan = load(fixture())
    check plan.order == @["Parent", "Child"]
    check plan.entries.len == 2
    check frozenSources(plan, scratch).contains("Child>>answer")
    check not frozenSources(plan, scratch).contains("Parent :=")

  test "malformed schema fails with a catchable error":
    for document in [%*{"version": "one"}, %*{"version": 1, "roots": ["X"], "classes": [1]}]:
      expect ValueError: discard load(document)

  test "source drift is refused":
    let document = fixture()
    writeFile(scratch / "Child.hrd", "# @frozen\nChild := Parent derive: #(changed).")
    expect ValueError: discard load(document)

  test "generic source requires a header annotation":
    var document = fixture()
    let source = "Child := Parent derive: #()."
    writeFile(scratch / "Child.hrd", source)
    document["classes"][1]["sha1"] = %($secureHash(source))
    expect ValueError: discard load(document)

  test "undeclared references and absent dependency entries are refused":
    var document = fixture()
    document["classes"][1]["dependencies"] = newJArray()
    expect ValueError: discard load(document)
    document = fixture()
    document["classes"][1]["dependencies"] = %*["Missing"]
    expect ValueError: discard load(document)

  test "stale and duplicate entries are refused":
    var document = fixture()
    document["roots"] = %*["Parent"]
    expect ValueError: discard load(document)
    document = fixture()
    document["classes"].add(document["classes"][0])
    expect ValueError: discard load(document)

  test "counterparts require conformance and paths stay relative":
    var document = fixture()
    document["classes"][0]["cases"] = newJArray()
    expect ValueError: discard load(document)
    document = fixture()
    document["classes"][0]["source"] = %"../escape.hrd"
    expect ValueError: discard load(document)

  test "capture parameters and temporaries shadow global names":
    check frozenReferences("Probe := Object derive: #(). Probe>>run: Global [ ^ [Global] ].") == @["Object", "Probe"]

  test "unlisted annotated stdlib source is refused":
    let document = fixture()
    createDir(scratch / "lib")
    writeFile(scratch / "lib/Unlisted.hrd", "# @frozen\nUnlisted := Parent derive: #().")
    defer:
      removeFile(scratch / "lib/Unlisted.hrd")
      removeDir(scratch / "lib")
    expect ValueError: discard load(document)

  test "mutually recursive method references form a closure":
    var document = fixture()
    document["classes"][0]["dependencies"] = %*["Child"]
    check load(document).order == @["Parent", "Child"]
