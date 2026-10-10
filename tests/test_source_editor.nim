import std/[unittest, os, strutils, tempfiles]
import ../src/harding/interpreter/source_editor

const multiClassSource = """# file comment
EditFoo := Object derive: #().
# Keep this documentation.
EditFoo>>answer [ ^ "brackets ] [ inside text" ]. # inline comment
EditFoo class>>answer [ ^ 10 ].
EditBar := Object derive: #().
EditBar>>answer [ ^ 2 ].
EditSentinel := 42.
"""

suite "Targeted source editing":
  test "method edits preserve unrelated source byte for byte":
    let edited = rewriteSource(multiClassSource, "EditFoo", "answer",
                              "EditFoo>>answer [ ^ 3 ].")
    check(edited.error.len == 0)
    check(edited.source == multiClassSource.replace(
      "EditFoo>>answer [ ^ \"brackets ] [ inside text\" ]", "EditFoo>>answer [ ^ 3 ]"))

  test "class-side and instance-side selectors are distinct":
    let edited = rewriteSource(multiClassSource, "EditFoo class", "answer",
                              "EditFoo class>>answer [ ^ 11 ]")
    check(edited.error.len == 0)
    check(edited.source == multiClassSource.replace(
      "EditFoo class>>answer [ ^ 10 ]", "EditFoo class>>answer [ ^ 11 ]"))

  test "class definition edits preserve comments and methods":
    let edited = rewriteSource(multiClassSource, "EditFoo", "<classDefinition>",
                              "EditFoo := Object derive: #(name).")
    check(edited.error.len == 0)
    check(edited.source == multiClassSource.replace(
      "EditFoo := Object derive: #()", "EditFoo := Object derive: #(name)"))

  test "deletion leaves unrelated definitions and trailing comments":
    let edited = rewriteSource(multiClassSource, "EditFoo", "answer", "", deleting = true)
    check(edited.error.len == 0)
    check(edited.source == multiClassSource.replace(
      "EditFoo>>answer [ ^ \"brackets ] [ inside text\" ]", ""))

  test "new methods can be appended to extension files":
    let source = "# extension\nEditFoo>>existing [ ^ 1 ].\n"
    let edited = rewriteSource(source, "EditFoo", "added", "EditFoo>>added [ ^ 2 ]")
    check(edited.error.len == 0)
    check(edited.source == source & "EditFoo>>added [ ^ 2 ].\n")

  test "nested blocks comments multiline strings and same-line definitions are preserved":
    let source = "EditFoo>>answer [ # ] ignored\n ^ [ \"[ ]\" ] value ]. EditFoo>>next [ ^ 2 ].\n"
    let edited = rewriteSource(source, "EditFoo", "answer", "EditFoo>>answer [ ^ 7 ]")
    check(edited.error.len == 0)
    check(edited.source == "EditFoo>>answer [ ^ 7 ]. EditFoo>>next [ ^ 2 ].\n")

  test "triple quoted strings do not change source boundaries":
    let source = "EditFoo>>answer [ ^ \"\"\"\n] [\n\"\"\" ].\nEditFoo>>next [ ^ 2 ].\n"
    let edited = rewriteSource(source, "EditFoo", "answer", "EditFoo>>answer [ ^ 7 ]")
    check(edited.error.len == 0)
    check(edited.source == "EditFoo>>answer [ ^ 7 ].\nEditFoo>>next [ ^ 2 ].\n")

  test "replacement trailing comments do not swallow following source":
    let source = "EditFoo>>answer [ ^ 1 ]. EditFoo>>next [ ^ 2 ].\n"
    let edited = rewriteSource(source, "EditFoo", "answer", "EditFoo>>answer [ ^ 7 ]. # editor suffix")
    check(edited.error.len == 0)
    check(edited.source == "EditFoo>>answer [ ^ 7 ]. EditFoo>>next [ ^ 2 ].\n")

  test "CRLF and Unicode outside the edit survive":
    let source = "# café\r\nEditFoo>>answer [ ^ 1 ].\r\n# résumé\r\n"
    let edited = rewriteSource(source, "EditFoo", "answer", "EditFoo>>answer [ ^ 2 ]")
    check(edited.error.len == 0)
    check(edited.source == source.replace("^ 1", "^ 2"))

  test "duplicate definitions are rejected":
    let edited = rewriteSource("EditFoo>>answer [ ^ 1 ].\nEditFoo>>answer [ ^ 2 ].",
                              "EditFoo", "answer", "EditFoo>>answer [ ^ 3 ]")
    check(edited.error.contains("Ambiguous"))

  test "replacement must be one matching definition":
    for replacement in ["EditFoo>>answer [", "EditBar>>answer [ ^ 2 ]",
                        "EditFoo>>answer [ ^ 2 ]. EditSentinel := 0."]:
      let edited = rewriteSource(multiClassSource, "EditFoo", "answer", replacement)
      check(edited.error.len > 0)

  test "invalid save leaves original file and permissions unchanged":
    createDir("build")
    let directory = createTempDir("source-editor-", "", "build")
    let path = directory / "source.hrd"
    defer: removeDir(directory)
    writeFile(path, multiClassSource)
    let permissions = getFilePermissions(path)
    let rejected = rewriteSourceFile(path, "EditFoo", "answer", "EditFoo>>answer [")
    check(rejected.error.len > 0)
    check(readFile(path) == multiClassSource)
    let edited = rewriteSourceFile(path, "EditFoo", "answer", "EditFoo>>answer [ ^ 3 ]")
    check(edited.error.len == 0)
    check(readFile(path) == edited.source)
    check(getFilePermissions(path) == permissions)
    var fileCount = 0
    for kind, filePath in walkDir(directory):
      check(kind == pcFile)
      check(filePath == path)
      inc fileCount
    check(fileCount == 1)
