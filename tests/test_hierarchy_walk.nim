## Traversal guarantees of the allocation-free hierarchy walk used by dispatch.
import ../src/harding/runtime/runtime

var collected: seq[string]

proc seenNames(start: string): seq[string] =
  collected.setLen(0)
  discard walkCompiledHierarchy(start, proc(name: string): bool =
    collected.add(name)
    false)
  collected

registerSuperclass("D", "B")
registerSuperclass("D", "C")
registerSuperclass("B", "A")
registerSuperclass("C", "A")
doAssert seenNames("D") == @["D", "B", "A", "C"], $seenNames("D")
# stop at the first match, in declaration order
doAssert walkCompiledHierarchy("D", proc(n: string): bool = n == "C") == "C"
doAssert walkCompiledHierarchy("D", proc(n: string): bool = n == "A") == "A"
doAssert walkCompiledHierarchy("D", proc(n: string): bool = n == "Z") == ""
# a malformed cycle must still terminate
registerSuperclass("X", "Y")
registerSuperclass("Y", "X")
doAssert walkCompiledHierarchy("X", proc(n: string): bool = n == "Y") == "Y"
doAssert walkCompiledHierarchy("X", proc(n: string): bool = false) == ""
doAssert walkCompiledHierarchy("", proc(n: string): bool = true) == ""
# the single-name registration path still reaches the parent
registerSuperclass("Sole", "OnlyParent")
doAssert seenNames("Sole") == @["Sole", "OnlyParent"], $seenNames("Sole")
echo "ok"
