# Nimony migration assessment

Research snapshot: Nimony source `6d9bafc02c8c18418c30cb34819a3efd65977459`, cloned to `~/git/nimony`; website reviewed alongside that checkout. This is an investigation, not a successful Harding port. Nimony is in active development, so pin the compiler and repeat experiments before relying on these findings.

## Recommendation

Keep Nim 2.2.12 as Harding's production toolchain. Explore Nimony in parallel, starting with small isolated modules and the C backend, then the interpreter and Granite runtime. Do not replace Harding's stackless scheduler, language exception semantics or Granite backend just because Nimony has passive procedures, native code generation or NIF. These are distinct architectural choices requiring separate evidence.

## Potential advantages

- **Safer host implementation:** nullable types, borrow checks against aliasing and iterator invalidation, checked generics and optional static contracts could expose bugs in VM state, collections and scheduler code. This does not make raw pointer casts, FFI, callbacks or cross-thread registries safe automatically.
- **Build feedback:** NIF-based incremental, parallel compilation could shorten rebuilds. Measure clean and incremental Harding builds; no improvement has been measured here.
- **Native backend:** `nimony n` generates machine code and executable images without a C compiler in its freestanding configuration. It could simplify distribution of suitable standalone Harding executables. Linux FFI and foreign object linkage require the libc-linked mode and a system linker; GTK, VTE and external libraries remain dependencies. Validate each target and foreign-call path.
- **Assembler procedures:** `doc/assembler.md` describes typed instruction-oriented procedures, register and ABI assertions, and checks on flag usage. Potential candidates include carefully profiled tagged-value or dispatch kernels, not the whole VM. Architecture-specific and native-backend-only: the C backend rejects them, so keep a portable implementation and test both. They are not a JIT or a runtime assembler interface. Compare release code and real workloads before expecting a speedup.
- **NIF and plugins:** inspectable intermediate representations and native plugins might enable Harding-specific diagnostics or an alternative Granite integration. Granite currently generates Nim modules using `compiled_support`; emitting checked NIF directly would require understanding and maintaining the relevant compiler-stage contracts, runtime ABI, ownership, diagnostics and source mapping. It is a research option, not a demonstrated shortcut.
- **Passive procedures:** continuation-based host concurrency is interesting for I/O integrations. Harding's green threads, blocking/yield protocol, error handling and GTK thread affinity have their own semantics; passive procedures are not a drop-in replacement.

## Migration risks specific to Harding

1. **Language compatibility:** the upstream FAQ explicitly says Nimony is not a Nim 2 drop-in. Nullable references are explicit, generics and borrows are checked differently, names are case sensitive by default, closures need explicit annotations unless a compatibility feature is enabled, and integer overflow wraps by default. Audit any Harding behavior relying on Nim overflow checks. Compatibility switches mitigate individual issues, not the whole migration.
2. **Exceptions:** upstream `doc/differences.md` says its exception system is not Nim-compatible. Harding catches Nim errors in parsing, host I/O and primitive paths, including division-by-zero conversion. Preserve Harding `on:do:`, cleanup, uncaught signals and nonfatal host callbacks; do not silently change language behavior to accommodate a host port.
3. **Ownership and FFI:** `types.nim`, VM and compiled runtime use recursive refs, nullable pointers, raw-pointer keep-alive registries, callbacks and GTK C strings. Nimony documents changed string termination and ref/nil rules. Audit string lifetimes, C ABI, object layout, pointer tagging and ARC/ORC cycle handling with focused tests, including callbacks and shutdown under both supported memory managers. Borrow checks cannot validate raw pointer lifetimes.
4. **Dependencies:** Harding pins Nim 2.2.12 and checksums, uses libffi, GTK4/VTE and optionally MummyX, NimCP and external libraries. Pnak reads `.nimble` requirements and pins commits, but dependency resolution is not proof that those packages compile or behave correctly under Nimony. Nimble tasks, generated external registrations and build flags also need an explicit replacement or adapter.
5. **Two compilation layers:** both the Harding executable/Granite compiler and Granite-generated Nim plus `compiled_support` need porting. Generated code's type declarations, imports, closures and error paths must match the selected compiler. Existing Granite parity and mixed-engine boundary tests remain mandatory.
6. **Native packaging:** a freestanding native executable cannot simply use arbitrary foreign symbols. Test Linux `-d:useLibc` linking, dynamic libraries, GTK callbacks and actual deployment separately. No claim of a GTK single executable without its system libraries follows from native code generation.

Upstream's `src/v2/readme.md` describes a Nim 2 import plugin but says it currently requires Nim devel; its suitability for Harding or dependencies has not been tested. Upstream also documents macros for compatibility, so it would be inaccurate to claim that every Nim macro must already be rewritten as a plugin.

## Proposed staged investigation

1. Pin a Nimony revision and matching native backend, record OS, compiler flags and reproducible build commands. Establish clean Nim 2 baselines and store logs in `build/`. Test Nimony's C and native hello-world and a C-ABI callback, including nullable pointers, C strings and repeated allocation.
2. Port a small isolated tagged-integer kernel without changing semantics. Differential-test boundaries, negative values, overflow, division and invalid tags under Nim 2 and Nimony. Compare ordinary native output and a separately guarded assembler version only after profiling. The existing tagged module also uses heap refs and Nim exceptions, so a standalone arithmetic slice is not equivalent to porting it whole.
3. Compile progressively larger parser and core slices. Catalog first failures and dependency gaps, rather than immediately applying global `unchecked` or weakening safety. Exercise errors and source locations, compare AST results and run existing focused tests.
4. Prototype VM and scheduler ownership/callback boundaries; run interpreter core, exception, sync and scheduler regressions under ARC and ORC. Preserve language semantics and use the project discussion gate for any proposed language changes.
5. Port Granite's runtime and generated-code subset, then run existing parity and mixed-engine tests. Measure cold/warm build time, executable size and steady-state benchmarks against matched release Nim builds.
6. Separately validate Bona, GTK/VTE callback lifetimes and shutdown, then each optional external service and library. Keep Nim 2 CI and releases until supported targets and regressions are green.

## Sources

- [Nimony FAQ](https://nimony.org/faq.html), [home](https://nimony.org/), [tools](https://nimony.org/tools.html), [installation and FFI linking](https://nimony.org/install.html).
- [Nimony source](https://github.com/nim-lang/nimony), particularly `doc/differences.md`, `doc/assembler.md`, `doc/lenientnils.md`, `doc/language.md`, and `src/v2/readme.md` at the revision above.
- Harding: `harding.nimble`, `src/harding/core/tagged.nim`, `src/harding/core/types.nim`, `src/harding/interpreter/vm.nim`, `src/harding/compiler/granite.nim`, `src/harding/codegen/module.nim`, and `docs/GRANITE_STATUS.md`.
