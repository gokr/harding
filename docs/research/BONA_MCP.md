# Bona MCP Integration Notes

This note captures a likely direction for adding MCP support to Bona so that an LLM can interoperate directly with a live Bona environment.

## Goal

The goal is not just to expose Harding over HTTP. The goal is to let an external MCP client operate against the same live environment that Bona is using:

- the same interpreter
- the same globals and loaded libraries
- the same Browser, Workspace, Builder, and Inspector models
- potentially the same open windows and current editing state

That implies the core integration constraint:

- all Harding and GTK-facing work must stay on the Bona/main thread

## Relevant shape from `nemo-mummyx-channels`

The `nemo-mummyx-channels` worktree explores a useful architecture pattern:

- a background MummyX server thread accepts requests
- worker threads package requests into plain Nim data
- requests are sent through a thread-safe channel
- the main Harding thread turns those requests into Harding objects and runs handlers
- responses are sent back through a response channel to the server thread

The key pieces are:

- `src/harding/web/mummyx_bridge.nim`
  - background-thread server
  - request/response packaging
  - main-thread dispatch through polling
- `src/harding/core/scheduler.nim`
  - `NimChannel`
  - scheduler polling of native-thread inputs
  - worker green threads that receive jobs and invoke Harding blocks

This is a reasonable direction for Bona MCP support.

## Why this fits Bona

This architecture respects the two main constraints:

1. GTK must remain on the main thread.
2. The live Harding/Bona environment should remain the authority for tool execution.

With a background server thread and a main-thread dispatch bridge:

- NimCP can run independently of the GUI event loop
- Bona stays responsive
- MCP requests can operate on live BrowserModel, BuilderModel, InspectorModel, Workspace, and Catalog state
- Harding code does not need to become thread-safe in a broad sense

## Recommended architectural direction

The important pattern is not specifically MummyX. The important pattern is:

- transport thread
- thread-safe request queue
- main-thread Harding/Bona dispatcher
- thread-safe response path back to the transport

For Bona, the preferred layering is:

1. `BonaBridge` or `ToolBridge`
- transport-agnostic
- owns request queue, response queue, dispatch state, lifecycle
- runs on behalf of one live interpreter/Bona instance

2. `NimCP` transport adapter
- HTTP/MCP server concerns only
- parses MCP requests
- sends tool invocations into the bridge
- waits for results and serializes responses

3. Bona/main-thread dispatcher
- resolves tools against live Bona objects and models
- calls `Catalog`, `BrowserModel`, `BuilderModel`, `InspectorModel`, `Workspace`, and related Harding APIs
- returns plain structured results

In other words:

- NimCP should not talk to GTK directly
- NimCP should not mutate Harding state from its own thread
- NimCP should hand requests into a main-thread bridge

## What to reuse from the channel prototype

The following ideas from `nemo-mummyx-channels` are worth keeping:

- background server thread
- request/response envelopes as plain Nim data
- a `NimChannel`-like abstraction for main-thread delivery
- green-thread worker processes on the Harding side if helpful
- a hook to process pending requests from the main thread

These pieces already line up well with the stackless scheduler design.

## What should change before adopting it directly

### 1. Avoid process-global singleton state

The current MummyX bridge shape uses global state for:

- request channel
- active routes
- active server/thread references

That is acceptable for a prototype, but for Bona embedding it is better to have a per-instance controller object.

Preferred shape:

- one live Bona/interpreter instance
- one bridge/controller instance
- one request queue owned by that controller
- one transport adapter attached to that controller

This will make start/stop/restart behavior much safer.

### 2. Make the bridge transport-agnostic

The reusable abstraction should not be named around MummyX.

Better:

- `BonaBridge`
- `ToolBridge`
- `MainThreadBridge`

Then MummyX, NimCP, or something else can sit on top of it.

### 3. Tighten ownership of per-request response channels

The prototype creates a per-request response channel and passes a pointer around. That may be workable, but for long-lived IDE embedding it is a fragile ownership pattern.

Safer shape:

- heap-owned request context object
- request payload
- response channel or completion slot owned by that context
- keep-alive registry if any pointer-backed proxy is stored in `nimValue`

### 4. Add explicit lifecycle and shutdown rules

For Bona embedding, shutdown and restart need to be predictable.

The bridge should define:

- start server
- stop accepting new requests
- drain or cancel pending requests
- stop worker thread(s)
- join thread(s)
- release channels and proxies in the correct order

### 5. Do not use `serveForever` in the GUI path

For a GUI-hosted Bona, the main thread must continue serving GTK.

So the correct shape is not:

- start server
- enter a blocking Harding scheduler loop forever

Instead:

- start NimCP in a background thread
- periodically pump pending bridge requests on the Bona/main thread

That pumping can likely happen via:

- a GLib idle callback, or
- a GLib timeout, or
- an existing scheduler slice hook if Bona already has a suitable place for it

## Suggested Bona-side flow

1. Bona starts normally.
2. Bona creates a `MainThreadBridge` bound to its interpreter.
3. NimCP starts on a background thread and receives MCP calls.
4. Each MCP tool call is converted into a plain request record.
5. The request is pushed into the bridge queue.
6. Bona's main thread pumps pending requests.
7. The dispatcher resolves the request against live Harding/Bona objects.
8. The result is written back to the request context.
9. NimCP serializes the result and returns it to the client.

## How this aligns with the current Bona refactor

The recent Bona refactor makes this approach more practical.

We now have:

- `Catalog` for shared code discovery and source-oriented operations
- `BrowserModel` for browser selection/editing state
- `BuilderModel` for application builder state
- `InspectorModel` for inspection state

That means the MCP layer does not need to drive GTK widgets.

It can operate against:

- `Catalog`
- model objects
- Workspace evaluation hooks
- live Harding globals

This is much better than trying to automate the GTK surface itself.

## Proposed rule of thumb

If an MCP operation should work without clicking a widget, it should be implemented against:

- `Catalog`
- a model object
- a headless Bona/Harding API

GTK classes should remain presentation shells.

## Conclusion

The `nemo-mummyx-channels` architecture is a reasonable prototype for Bona MCP support.

The right long-term move is to keep the same basic pattern:

- server on a background thread
- channel/queue bridge to the main thread
- Harding/Bona execution on the main thread
- response returned to the server thread

But before adopting it directly, it should be reshaped into a per-instance, transport-agnostic bridge with stricter lifecycle and ownership rules.

That would provide a solid basis for integrating NimCP into Bona so an LLM can interoperate with a live Bona environment safely and predictably.
