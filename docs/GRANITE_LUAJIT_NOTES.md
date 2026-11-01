# LuaJIT lessons applicable to Granite

Sources consulted:

- https://luajit.org/faq.html
- https://luajit.org/luajit.html
- https://luajit.org/ext_ffi.html
- https://luajit.org/ext_profiler.html

The FAQ points to trace compilation, SSA, dynamic-language optimization and
linear-scan allocation; it is not a detailed compiler design document. The
following are Granite design proposals informed by those topics, not claims
that LuaJIT's implementation can be transplanted unchanged.

## Transferable ideas

1. **Avoid generic work before proving it necessary.** Generated native numeric
   operations previously constructed argument sequences for host routing even
   when the operand's immediate kind made interpreted dispatch impossible.
   Granite now defers only buffer construction until the host is selected;
   operands still run once, in language order, before that selection. This is
   a small AOT change, not JIT infrastructure.
2. **Keep primitive values native across a region.** A typed expression that is
   boxed immediately before the next operation loses much of its benefit. A
   future typed dataflow/SSA pass should propagate values through locals, calls
   and control flow, materializing NodeValue only at actual dynamic boundaries.
   Nim's compiler can optimize the resulting native IR, but it cannot generally
   infer through our opaque runtime dispatch and allocation helpers.
3. **Use profiles to choose specialized code, not to redefine the language.**
   Collected receiver/type evidence can justify a guarded native call clone.
   Class/layout/method-version checks and a correct fallback remain mandatory.
   A test run does not prove all future inputs have the same type.
4. **Make layout an explicit performance tool.** LuaJIT's FFI example illustrates
   how contiguous C-shaped storage replaces nested tables and reduces overhead.
   Harding's specialized numeric arrays/native typed fields can pursue the same
   goal without introducing implicit pointer access. Identity, aliasing, lifetime
   and Integer precision contracts still apply.
5. **Measure the dynamic/native boundary.** LuaJIT exposes a low-overhead profiler
   that distinguishes execution contexts. Granite's current gprof counts and
   timings should likewise separate generated methods, argument/value copying,
   host routing, dispatch and allocation instead of attributing all allocator
   calls to one mechanism. Instrumented wall times are not production scores.

## What is not a direct fit

- Trace recording, side traces, machine-code register allocation and online
  deoptimization are JIT mechanisms. Granite is currently AOT via Nim; adding a
  tracing JIT would be a different project, not a cache optimization.
- AOT guarded clones can fall back at a send/expression boundary. Speculating
  across effects would need explicit state reconstruction or another agreed
  continuation design; do not restart effectful expressions on guard failure.
- Do not copy Lua numeric semantics into Harding. Integer and Float remain
  distinct; Float64 cannot preserve every 64-bit Integer. Profiles report mixed
  numeric evidence as a decision for the author, not silent storage widening.
- A compact tagged value representation may help, but replacing the current
  32-byte managed NodeValue variant is a broad ownership/ABI change. It requires
  separate design, ARC/ORC and FFI validation, not unsafe casts of existing refs.

## Current priority

The fresh profile in `BENCHMARK_PRACTICAL_BASELINES.md` supports starting with
avoidable argument-sequence construction, then profiling again. More inference
is useful when it eliminates a measured hot boundary (e.g. a repeated receiver
send), not merely when it increases a candidate count. No LuaJIT speedup or
architectural parity is claimed by this note.
