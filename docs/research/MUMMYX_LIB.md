# MummyX As An External Harding Library

## Verdict

MummyX can be broken out into an installable Harding library, but it is not a trivial lift today.

- The Harding-side `.hrd` portion is already close to external-library shape.
- The native/runtime wiring is still embedded in core interpreter and scheduler startup.
- The easiest path is to externalize it in phases.

My judgment:

- **Relatively easy** if we keep special MummyX build tasks for now.
- **Moderate to hard** if we want `harding lib install mummyx` to work cleanly with plain `nimble harding` and no special build path.

## What Already Looks Library-Ready

These files already resemble a normal Harding library:

- `lib/mummyx/Bootstrap.hrd`
- `lib/mummyx/HttpServer.hrd`
- `lib/mummyx/Router.hrd`
- `lib/mummyx/HttpRequest.hrd`

The Harding API surface is already packaged in a way that could move into an external repo with little change.

## What Is Still Coupled To Core

The main native integration still lives inside the Harding core codebase:

- `src/harding/web/mummyx_bridge.nim`
- `src/harding/interpreter/vm.nim:17`
- `src/harding/interpreter/vm.nim:5131`
- `src/harding/core/scheduler.nim:10`
- `src/harding/core/scheduler.nim:469`

Key couplings:

### 1. Build-time coupling

MummyX is enabled through dedicated build tasks, not the normal external library path:

- `harding.nimble:410`
- `harding.nimble:418`
- `harding.nimble:426`
- `harding.nimble:434`

Those tasks add:

- `-d:mummyx`
- `--threads:on`
- `--mm:orc`

That matters because the current external library system mainly contributes `-d:harding_<libname>` flags and dependency paths, but not library-specific runtime/build options.

Relevant files:

- `harding.nimble:24`
- `src/harding/external/generator.nim:25`
- `src/harding/external/discovery.nim:286`

### 2. Runtime initialization coupling

MummyX is initialized directly during stdlib load:

- `src/harding/interpreter/vm.nim:5131`
- `src/harding/interpreter/vm.nim:5136`

Today `loadStdlib` does this when built with `-d:mummyx`:

- calls `initMummyxBridge(interp)`
- calls `registerMcpPrimitives(interp)`

That means MummyX is not currently installed like other external libraries through the generated external-library installer path at:

- `src/harding/interpreter/vm.nim:5493`

### 3. Scheduler coupling

The scheduler contains explicit MummyX-specific integration:

- `src/harding/core/scheduler.nim:469`

It sets bridge callbacks directly on `mummyx_bridge`:

- `setupSchedulerAndWorkersProc`
- `runOneSliceProc`

It also hardcodes the global channel name:

- `MummyXRequestChannel`

And it embeds the worker loop source there.

This is the deepest architectural coupling in the current design.

### 4. Bootstrap ordering assumption

The current MummyX bootstrap assumes native classes already exist in globals:

- `lib/mummyx/Bootstrap.hrd:14`

It checks for `HttpServer` first, then loads the Harding-side method extensions.

That is different from the more normal external-package flow, where:

1. the package embeds its sources,
2. `installPackage` loads the bootstrap,
3. primitives are registered and rebound afterward.

Relevant package flow:

- `src/harding/packages/package_api.nim:77`

### 5. MCP is coupled to MummyX

MCP is currently tied into the same path:

- `src/harding/web/mcp_bridge.nim:15`
- `src/harding/interpreter/vm.nim:5136`

So moving MummyX cleanly probably means also deciding whether MCP moves with it or becomes a second external package layered on top.

## Why The Breakout Is Still Feasible

The repository already has a strong external-library model.

Relevant pieces:

- `external/README.md:111`
- `docs/MANUAL.md:1299`
- `src/harding/external/generator.nim:33`
- `src/harding/interpreter/vm.nim:5493`
- `src/harding/packages/package_api.nim:77`
- `src/harding/interpreter/vm.nim:5825`

This means Harding already supports:

- installable library repos under `external/`
- generated conditional imports
- runtime library installation through `installExternalLibraries`
- embedded `.hrd` sources via `HardingPackageSpec`
- `Harding load:` resolving package sources from memory

So MummyX is a good candidate for conversion; it just needs refactoring at the seams where it currently bypasses that system.

## What An Externalized MummyX Package Would Look Like

Likely repo structure:

```text
harding-mummyx/
├── mummyx.nimble
├── src/
│   └── mummyx/
│       ├── mummyx.nim
│       └── mummyx_bridge.nim
└── lib/
    └── mummyx/
        ├── Bootstrap.hrd
        ├── HttpServer.hrd
        ├── Router.hrd
        └── HttpRequest.hrd
```

The main entry file would export something like:

- `installMummyx(interp)`

That function would:

1. embed the `.hrd` files with `staticRead`
2. initialize native bridge classes/primitives
3. install the package via `installPackage(...)`

## Recommended Migration Strategy

### Phase 1: Externalize MummyX, keep special builds

This is the best short-term path.

Do this first:

- create a separate `harding-mummyx` repo
- move `lib/mummyx/*.hrd` there
- move `src/harding/web/mummyx_bridge.nim` there
- add `src/mummyx/mummyx.nim` with `installMummyx(interp)`
- stop initializing MummyX directly from `src/harding/interpreter/vm.nim`
- instead let the external library installer call it when `harding_mummyx` is compiled in

In this phase, keep:

- `nimble harding_mummyx`
- `nimble bona_mummyx`

Why this is attractive:

- minimal risk
- preserves current runtime assumptions
- gets MummyX out of core source ownership
- aligns with how MySQL, NimCP, and BitBarrel are distributed

### Phase 2: Remove MummyX-specific scheduler hooks

Refactor the scheduler so MummyX uses a generic extension seam rather than bespoke callbacks.

There is already a promising generic hook:

- `src/harding/packages/package_api.nim:17`
- `src/harding/core/scheduler.nim:444`

That likely becomes the seam for external packages needing thread-to-scheduler bridging.

The goal would be to replace:

- MummyX-specific callback vars in `mummyx_bridge.nim`
- hardcoded `MummyXRequestChannel`
- bridge-specific worker source in scheduler

with a more generic package-facing API.

### Phase 3: Decide what to do with MCP

Two reasonable options:

1. move MCP into the same `harding-mummyx` package
2. split MCP into `harding-mcp`, depending on MummyX

I would lean toward option 2 eventually, but option 1 is simpler for the first extraction.

### Phase 4: Teach external libraries about build requirements

This is only needed if we want MummyX to behave like a true first-class installable library with plain:

```bash
./harding lib install mummyx
nimble harding
```

without special MummyX build tasks.

Current blocker: external library metadata does not express things like:

- `--threads:on`
- `--mm:orc`
- extra compile symbols outside `-d:harding_<libname>`

So if we want full parity, the external library build metadata model must be extended.

## Main Blockers

### Blocker 1: external lib build metadata is too simple

Current discovery/generation is designed around:

- installed-library metadata
- compile flags like `-d:harding_<name>`
- dependency path discovery

It does not currently model special runtime/compiler requirements.

Relevant files:

- `harding.nimble:24`
- `src/harding/external/discovery.nim:286`
- `src/harding/external/generator.nim:92`

### Blocker 2: scheduler knows MummyX by name

The scheduler should not need direct knowledge of `mummyx_bridge`.

Relevant files:

- `src/harding/core/scheduler.nim:469`

### Blocker 3: bootstrap assumes native classes preexist

Current MummyX bootstrap is not shaped like a conventional external package bootstrap.

Relevant file:

- `lib/mummyx/Bootstrap.hrd:14`

### Blocker 4: MCP remains tied to the same path

If MummyX moves out but MCP stays in core, the dependency graph remains awkward.

Relevant files:

- `src/harding/web/mcp_bridge.nim:15`
- `src/harding/interpreter/vm.nim:5136`

## Practical Conclusion

Yes, MummyX can be turned into an installable Harding library.

The cleanest near-term answer is:

- make it an external package,
- keep dedicated `harding_mummyx` / `bona_mummyx` builds for now,
- move bridge initialization out of core startup,
- then refactor scheduler integration behind a generic API.

That would give most of the benefits of breakout without forcing a large build-system redesign immediately.

If the goal is a fully seamless library that installs and builds through the normal external-library path with no special MummyX tasks, that is possible too, but it requires additional work in the library/build metadata system.
