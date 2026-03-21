# JSON API Server and OpenAPI Plan

## Goal

Add a clear path for building plain JSON API servers in Harding, backed by BitBarrel persistence, with enough endpoint metadata to generate useful OpenAPI documents automatically.

This plan has two linked outcomes:

1. a user-facing tutorial and runnable example for a regular JSON API server
2. a metadata-driven OpenAPI system that can describe most Harding HTTP endpoints without parsing arbitrary handler code

## Current Starting Point

Harding already has the main primitives needed for this work:

- MummyX HTTP server integration documented in `docs/MUMMYX.md`
- a small API example in `examples/mummyx_hello.hrd`
- larger real-world API-style handlers in `badminton-buddy/BadmintonApp.hrd`
- BitBarrel persistence documented in `docs/MANUAL.md`
- fast JSON serialization for Harding values and ordinary objects via `Json stringify:`

What is missing is a coherent API-server story:

- no dedicated tutorial for plain JSON APIs
- no canonical example showing MummyX + BitBarrel + `Json stringify:` together
- no standard way to attach endpoint metadata for OpenAPI generation
- no schema-generation layer for Harding classes used as request/response DTOs

## Proposed Deliverables

### 1. Tutorial Document

Add a new user-facing guide, likely:

- `docs/API_SERVER_TUTORIAL.md`

The tutorial should show how to build a small CRUD JSON API server, not an htmx or HTML app.

### 2. Runnable Example

Add a complete example, likely:

- `examples/api_todos.hrd`

This should be the code used by the tutorial.

### 3. Optional OpenAPI Example Endpoint

The example should expose:

- `GET /openapi.json`

so users can fetch the generated API description directly.

### 4. API Metadata Layer

Add a thin declarative layer over `Router` for endpoint metadata, rather than trying to reverse-engineer route blocks.

### 5. OpenAPI Builder

Add a component that walks registered endpoint metadata and emits an OpenAPI 3.1-ish JSON document.

## Tutorial Scope

The tutorial should target a simple Todo API with BitBarrel-backed persistence.

Recommended endpoints:

- `GET /health`
- `GET /todos`
- `GET /todos/@id`
- `POST /todos`
- `PATCH /todos/@id`
- `DELETE /todos/@id`
- `GET /openapi.json`

Recommended data model:

- `Todo` class for API output
- `CreateTodoRequest` class for input
- `UpdateTodoRequest` class for patch input
- `ErrorResponse` class for structured errors

Recommended persistence layout:

- `BarrelTable` keyed by todo id
- values stored as Tables or normalized DTO objects

The tutorial should emphasize:

- plain JSON responses with `respondJson:`
- request parsing with `req body`, `Json parse:`, `pathParam:`, and `queryParam:`
- structured JSON responses via `toJson`
- simple validation and error responses
- BitBarrel usage for durable storage

## Tutorial Outline

### Part 1: Build and Run

- build Harding with MummyX enabled
- install BitBarrel if needed
- run the example server
- verify endpoints with `curl`

### Part 2: Define DTO Classes

- create `Todo`, `CreateTodoRequest`, `UpdateTodoRequest`, and `ErrorResponse`
- configure JSON serialization where useful
- show how `toJson` gives compact JSON output

### Part 3: Wire MummyX Routes

- create `HttpServer` and `Router`
- register JSON-only routes
- keep handlers focused on request -> domain -> JSON response

### Part 4: Parse Requests

- parse request bodies with `Json parse:`
- validate required fields
- normalize malformed input into `400` error responses

### Part 5: Persist to BitBarrel

- open a `BarrelTable`
- insert, update, fetch, and delete todos
- describe practical key strategy and record layout

### Part 6: Return Consistent Responses

- `200` with JSON body for reads
- `201` for creation
- `404` for missing records
- `400` for invalid input
- `204` or `200` for delete, depending on final style choice

### Part 7: Serve OpenAPI

- expose `GET /openapi.json`
- return the generated document through `respondJson:`
- optionally mention Swagger UI/ReDoc as a later step

## Example Architecture

Recommended structure for the example app:

```text
examples/api_todos.hrd
lib/api/ApiRouter.hrd            # later, if this becomes reusable
lib/api/OpenApiBuilder.hrd       # later, if this becomes reusable
```

Example internal objects:

- `TodoApiApp`
- `TodoRepository`
- `Todo`
- `CreateTodoRequest`
- `UpdateTodoRequest`
- `ErrorResponse`

The example should remain self-contained first. If the API helpers prove good, they can move into a reusable library later.

## OpenAPI Strategy

Do not try to infer full OpenAPI data from arbitrary route blocks.

That would require analyzing user code, handler control flow, request parsing, validation, and response branching. It would be fragile and difficult to make predictable.

Instead, make OpenAPI metadata explicit and close to the route declaration.

## Recommended API Metadata Shape

The metadata layer should be declarative and ergonomic.

Example shape:

```harding
Api get: "/todos/@id"
    summary: "Fetch one todo"
    operationId: "getTodo"
    tag: "Todos"
    pathParams: #(
      #{#name -> "id", #schema -> #{#type -> "string"}, #required -> true}
    )
    responses: #{
      200 -> #{#description -> "Todo", #json -> Todo}
      404 -> #{#description -> "Todo not found", #json -> ErrorResponse}
    }
    do: [:req |
      ...
    ].
```

That metadata should be stored in a registry on the API router, not lost after route registration.

## Recommended Minimal Metadata API

First version should support:

- HTTP method
- path template
- summary
- description
- operation id
- tags
- path parameters
- query parameters
- request body schema
- response schemas by status code

Good first-class messages might be:

- `get:summary:operationId:responses:do:`
- `post:summary:operationId:requestBody:responses:do:`
- `patch:...`
- `delete:...`

Or, if chaining is preferred, an intermediate endpoint-builder object could be used.

## Schema Generation Strategy

OpenAPI component schemas should be generated primarily from Harding classes, reusing the JSON serialization work where possible.

### Reuse from JSON serialization

Use these signals when generating schema properties:

- class slot names
- `jsonRename:`
- `jsonOnly:`
- `jsonExclude:`
- `jsonOmitNil:`
- primitive-safe formatters like `#string` and `#className` where they map cleanly

### Add API-specific schema metadata

JSON serialization metadata is not enough to describe a full API schema. Add API-only metadata such as:

- `apiSchemaName`
- `apiRequired:`
- `apiDescribe:`
- `apiExamples:`
- `apiEnum:`
- `apiFormat:`
- `apiNullable:`

Example:

```harding
Todo class>>apiSchemaName [ ^ "Todo" ]

Todo apiRequired: #(id title completed).
Todo apiDescribe: #{
  #id -> "Stable todo identifier"
  #title -> "Short task title"
  #completed -> "Whether the task is finished"
}.
Todo apiFormat: #{
  #createdAt -> "date-time"
}.
```

This avoids overloading the JSON serializer with concerns that belong specifically to API documentation.

## OpenAPI Builder Responsibilities

An `OpenApiBuilder` should:

1. collect endpoint metadata from the API router
2. resolve referenced Harding classes into component schemas
3. produce a JSON-compatible Table/Array structure
4. emit the final spec via `Json stringify:`

The emitted spec should include:

- `openapi`
- `info`
- `servers`
- `paths`
- `components.schemas`

## Mapping Rules for v1

Recommended v1 mapping rules:

- `String` -> `{type: "string"}`
- `Integer` -> `{type: "integer"}`
- `Float` -> `{type: "number"}`
- `Boolean` -> `{type: "boolean"}`
- `Array` -> `{type: "array", items: ...}` only when item schema is explicitly known
- ordinary Harding class -> `{type: "object", properties: ...}`
- `jsonOmitNil:` should not automatically mark a field as not required; requiredness should be explicit in API metadata

When type information is not known precisely, prefer explicit schema metadata over guessing.

## What Should Be Automatic vs Explicit

### Automatic

- path/method registration
- path parameter extraction from route templates like `/todos/@id`
- base property names from class slots
- renamed property names from JSON metadata
- component schema emission for referenced classes

### Explicit

- request body schema class
- response schemas
- status codes
- required fields
- examples
- textual descriptions
- authentication/security metadata

This keeps the system predictable.

## Suggested Implementation Phases

### Phase 1: Tutorial and Example

1. Write `examples/api_todos.hrd`
2. Write `docs/API_SERVER_TUTORIAL.md`
3. Keep OpenAPI static or hand-built for the first draft if needed

### Phase 2: Endpoint Metadata Registry

1. Add an API router wrapper or endpoint registration helper
2. Store metadata alongside route handlers
3. Keep route execution behavior compatible with existing MummyX router usage

### Phase 3: Schema Metadata on Classes

1. Add API schema metadata helpers to classes
2. Reuse JSON serialization metadata where it already fits
3. Keep API schema metadata separate from runtime serializer internals

### Phase 4: OpenAPI Builder

1. Build OpenAPI Tables/Arrays from the endpoint registry
2. Resolve component schemas from Harding classes
3. Expose `GET /openapi.json`

### Phase 5: Optional Tooling

1. Add Swagger UI or ReDoc endpoint support
2. Add validation helpers for request bodies against declared schema
3. Add tests for generated OpenAPI correctness

## Proposed Tests

Add tests for:

- route metadata registration
- path parameter extraction from templates
- schema generation from ordinary classes
- schema generation with `jsonRename:` and `jsonExclude:`
- `openapi.json` emission shape
- OpenAPI output stability for the example API

## Non-Goals for v1

Do not block on:

- full request/response validation from OpenAPI schema
- automatic schema inference from handler bodies
- polymorphic OpenAPI features like `oneOf` or `allOf`
- automatic auth scheme inference
- code generation from OpenAPI

## Recommended First Concrete Step

Start with the tutorial and example server.

That gives Harding users immediate value even before full OpenAPI automation lands, and it will also reveal what the metadata API needs to look like in practice.

The best initial sequence is:

1. build `examples/api_todos.hrd`
2. write `docs/API_SERVER_TUTORIAL.md`
3. hand-write or partially generate `GET /openapi.json`
4. extract the repeated pieces into a reusable API/OpenAPI layer afterward
