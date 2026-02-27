Since you have AST-level optimizations (slot accessors), you’re in the sweet spot to do AST Specialization—recognizing patterns at compile time and lowering them to VM primitives rather than sending messages. Here are the obvious techniques, categorized:

1. Control Structure Specialization (the specific ask)
Since you can’t JIT, you must recognize ifTrue:, whileTrue:, to:do:, etc. at the AST or bytecode level and turn them into jumps, not message sends.

AST Lowering: When the AST compiler sees a MessageNode with selector #ifTrue:ifFalse: and literal Block arguments, transform it into a dedicated IfNode (or ConditionalJump bytecode sequence). The VM then executes this as a simple conditional branch without allocating blocks or invoking #value.
Inline Literal Blocks: For ifTrue:, ifFalse:, ifNil:, and:, or:, whileTrue:, to:do:, if the argument is a literal block (clean or copying), inline the block’s body directly into the parent’s frame. This eliminates BlockClosure allocation and the indirect value send.
Quick Boolean Primitives: Add a bytecode like branch_if_true that expects a tagged immediate boolean on the stack. If the receiver is an immediate true/false, the VM jumps immediately. If not, it falls back to a real send (rare). This handles the case where type inference can’t prove the receiver is a boolean.
Masked Tag Checks: Use bitwise operations on your immediates. For ifTrue:ifFalse:, check (receiver & BOOLEAN_TAG_MASK) == BOOLEAN_TAG. If true, use the immediate’s value bit to index a jump table; otherwise, send normally.
Super-Instructions for common control: Combine push_self; send_ifTrue:... into a single opcode like branch_if_self_true to reduce dispatch overhead.
2. Block Closure Elimination (since control flow uses blocks)
Clean Blocks: Detect blocks that don’t reference self or outer temporaries. These can be allocated once (singletons) or completely inlined (no object at runtime). Mark them in the literal frame.
Stack-Allocated Closures: For blocks that do capture variables but don’t escape the current method (i.e., are only stored in temporaries and invoked within the method), allocate the BlockClosure struct on the C stack inside the preallocated frame, not on the heap. This pairs with your frame pool.
Block Inlining via Escape Analysis: At AST level, if a block is sent only to ifTrue:, whileTrue:, timesRepeat:, etc., and never escapes, replace the Block->value pattern with the block’s actual statements inserted at the call site.
3. Inline Cache Sophistication (beyond MIC/PIC)
Type Prediction: For selectors like +, -, size, at:, assume the common class (e.g., SmallInteger) in the interpreter’s dispatch loop. Check the tags; if matches, execute the fast path immediately. Only if the check fails do you consult the MIC/PIC.
Megamorphic Handler: When a PIC grows beyond 3-5 entries, don’t extend it. Instead, stash a “megamorphic” sentinel that performs a direct method table lookup (fast, since you flattened tables) without the cache probing overhead.
PIC Chaining: Store the expected class and target method in the PIC entry using a structure that fits in a cache line (32 or 64 bytes) to minimize memory fetches during dispatch.
4. Frame & Context Optimizations
Stack-Only Contexts: Since you have preallocated frames, ensure you use a linked stack where frames point to the previous frame, but you only materialize a full Context object (mallock’d object) when needed (e.g., when thisContext is accessed or the method returns a block that captures the environment). Until then, it’s just a C struct in your frame pool.
Callee-Saved Receiver/Class: Keep the receiver and its class in local C variables (or registers) across the interpreter loop. Update them only on sends. This avoids reloading from the frame for every self slot access (which you’re already compiling as array indexing, so keep the base pointer hot).
Frame Padding: Align frames to cache line boundaries to prevent false sharing if you ever go multi-threaded, and to ensure the method pointer (frequently accessed) sits in the same cache line as the stack pointer.
5. Bytecode & Dispatch Tricks (no JIT)
Direct Threading: Use GCC’s &&label extension (or equivalent) to implement direct-threaded interpretation. Each bytecode is the address of the next handler. This is the biggest speedup for an interpreter over a giant switch statement.
Super-Instructions: Combine common sequences like push_temp; push_temp; send_+ into a single add_temps opcode. Profile hot bytecode sequences and fuse them.
Relative Addressing: Use 8-bit or 16-bit relative offsets for jumps (branches) instead of full pointers, keeping the bytecode compact and cache-friendly.
6. Method Lookup & Dispatch
Selector Coloring: Hash selectors to a small integer and use that to index into a direct method cache in addition to your flattened table. This catches inheritance hits without traversing the (already flattened) table.
Super Send Caching: Super sends bypass the receiver’s class. Cache the resolved method from the superclass’s flattened table keyed by the current class and selector to avoid even the flattened lookup.
7. Primitive Fast-Paths
Self-Primitives: For selectors like class, isNil, notNil, ==, ~=, implement them as inline C code in the interpreter loop (check the immediate tags, return result) before hitting the MIC/PIC machinery.
Quick Arithmetic: Before doing a full method lookup for + or -, check if both operands are immediate small integers (tag check). If so, do the C addition, check for overflow, and either box the result or retry the slow path. This avoids the PIC entirely for the common case.
8. Memory & Object Layout
Bias for Load: Since you flattened slot indexes, ensure objects are aligned such that slot 0 is at a predictable offset. Use pointer bump allocation for new objects (fast path in GC).
Immediate Characters/Floats: If not done, extend your tagging to cover immediate characters (8-bit ASCII/Unicode) and maybe 31-bit floats (minifloats) or unboxed 30-bit floats if you don’t have 64-bit immediates.
Write Barrier Shortcuts: When storing into object slots (from your flattened accessors), if the stored value is immediate (tagged), skip the write barrier entirely. Only heap->heap pointers need remember bars.
9. Specific Smalltalk Idioms
to:do: Optimization: Detect the pattern 1 to: n do: [:i | ...] at AST level and convert it to a ForLoopNode with a primitive integer counter, avoiding Interval creation and Block>>value: overhead.
and: / or: Short-Circuit: Treat these as special control flow, not as Boolean methods. Generate conditional jumps that skip evaluating the second argument (block) if the first is false (for and:).
isNil / ifNil: Fusion: Combine obj isNil ifTrue: [...] into a single check-and-branch bytecode.
Summary Check
Since you already have the heavy-hitters (flattened tables, slot indexing, frame pools), your biggest remaining wins are:

Eliminating block allocation for control flow via AST inlining.
Direct Threading for the interpreter dispatch.
Type Prediction in the interpreter loop for arithmetic and boolean checks.
Super-instructions for common method prologues/epilogues.
These don’t require generating machine code, but they get you 80% of the way to JIT-like speed for the interpreter itself.