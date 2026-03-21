# JSON API Server Tutorial

This tutorial walks through a plain JSON API server in Harding using:

- MummyX for HTTP routing
- BitBarrel for persistence
- `Json parse:` and `Json stringify:` for request/response handling
- an OpenAPI endpoint at `/openapi.json`

The full example lives in `examples/api_todos.hrd`.

## What You Will Build

A small Todo API with these endpoints:

- `GET /health`
- `GET /todos`
- `GET /todos/@id`
- `POST /todos`
- `PATCH /todos/@id`
- `DELETE /todos/@id`
- `GET /openapi.json`

The example is intentionally plain JSON. It does not render HTML pages or use htmx.

## Requirements

### 1. Build Harding with MummyX support

```bash
nimble harding_mummyx
```

### 2. Install BitBarrel and rebuild

```bash
./harding lib install bitbarrel
nimble harding_mummyx
```

BitBarrel is an external Harding library, so the rebuild is required after installation.

Once Harding is rebuilt with BitBarrel enabled, the library is installed into the runtime automatically. You do not need a separate `Harding load: "lib/bitbarrel/Bootstrap.hrd"` in this example.

## Running the Example

```bash
./harding examples/api_todos.hrd
```

You should then have a server on `http://127.0.0.1:8080`.

## Quick Verification

### Health Check

```bash
curl http://127.0.0.1:8080/health
```

Expected shape:

```json
{"ok":true,"service":"todo-api"}
```

### Create a Todo

```bash
curl -X POST http://127.0.0.1:8080/todos \
  -H 'Content-Type: application/json' \
  -d '{"title":"Write tutorial"}'
```

### List Todos

```bash
curl http://127.0.0.1:8080/todos
```

### Fetch One Todo

```bash
curl http://127.0.0.1:8080/todos/1
```

### Update a Todo

```bash
curl -X PATCH http://127.0.0.1:8080/todos/1 \
  -H 'Content-Type: application/json' \
  -d '{"completed":true}'
```

### Delete a Todo

```bash
curl -X DELETE http://127.0.0.1:8080/todos/1
```

### Fetch the OpenAPI Document

```bash
curl http://127.0.0.1:8080/openapi.json
```

## Structure of the Example

The example is organized around a few simple classes:

- `Todo` - response DTO
- `ErrorResponse` - structured JSON error payload
- `CreateTodoRequest` / `UpdateTodoRequest` - request DTOs for schema documentation
- `TodoRepository` - persistence layer using BitBarrel
- `TodoApiApp` - MummyX server and route handlers

## Step 1: Define JSON DTOs

The example uses ordinary Harding objects as JSON DTOs.

```smalltalk
Todo := Object derivePublic: #(id title completed createdAt)
    ; jsonFieldOrder: #(id title completed createdAt).

ErrorResponse := Object derivePublic: #(error message status)
    ; jsonFieldOrder: #(error message status).
```

Because Harding now supports ordinary object serialization through `Json stringify:`, these DTOs can be returned directly as JSON.

That means code like this works:

```smalltalk
todo := Todo new.
todo::id := "1".
todo::title := "Write tutorial".
todo::completed := false.
todo::createdAt := 1.

todo toJson
```

## Step 2: Open BitBarrel Tables

The example uses two persistent tables:

- one for todo records
- one for counters and metadata

```smalltalk
TodoRepository>>openDefault [
    todos := BarrelTable create: "api_todos.todos".
    meta := BarrelTable create: "api_todos.meta".
    (meta includesKey: "nextId") ifFalse: [
        meta at: "nextId" put: 1
    ].
    ^ self
].
```

The stored values are plain Harding Tables. The repository turns them into `Todo` objects when responding to API requests.

That split is useful because:

- persistence stays simple
- API output stays explicit
- JSON serialization uses ordinary objects instead of hand-built strings

## Step 3: Install MummyX Routes

The example uses a normal `Router` and `HttpServer`:

```smalltalk
TodoApiApp>>installRoutes [
    router get: "/health" do: [:req | self handleHealth: req ].
    router get: "/todos" do: [:req | self handleListTodos: req ].
    router get: "/todos/@id" do: [:req | self handleGetTodo: req ].
    router post: "/todos" do: [:req | self handleCreateTodo: req ].
    router patch: "/todos/@id" do: [:req | self handleUpdateTodo: req ].
    router delete: "/todos/@id" do: [:req | self handleDeleteTodo: req ].
    router get: "/openapi.json" do: [:req | self handleOpenApi: req ].
    ^ self
].
```

Path parameters like `@id` are available with:

```smalltalk
req pathParam: "id"
```

When you need to send a message to a slot value, prefer normal accessor sends such as `(app server) serveForever: 8080` rather than chaining from `::` access.

## Step 4: Parse JSON Requests

Request bodies are parsed with `Json parse:`:

```smalltalk
TodoApiApp>>parseJsonBody: req [
    | body |
    req body isNil ifTrue: [ ^ nil ].
    req body isEmpty ifTrue: [ ^ nil ].
    body := Json parse: req body.
    ^ body
].
```

That gives back Harding values, typically a `Table` for JSON objects.

The example then validates required fields manually:

```smalltalk
TodoApiApp>>validatedCreateBody: body [
    | title |
    body isNil ifTrue: [ ^ nil ].
    title := body at: "title" ifAbsent: [ nil ].
    ((title isNil) or: [ title isEmpty ]) ifTrue: [ ^ nil ].
    ^ body
].
```

This keeps the first version straightforward. Full schema validation can come later.

## Step 5: Return JSON Responses

The example centralizes JSON responses in one helper:

```smalltalk
TodoApiApp>>respondJson: req status: status value: value [
    req respond: status
        headers: #{"Content-Type" -> "application/json"}
        body: (Json stringify: value)
].
```

That helper works for:

- Arrays of DTOs
- single DTOs
- error DTOs
- raw Tables used for simple one-off responses

Structured errors are returned through `ErrorResponse`:

```smalltalk
TodoApiApp>>respondError: req status: status error: code message: message [
    | err |
    err := ErrorResponse new.
    err::error := code.
    err::message := message.
    err::status := status.
    ^ self respondJson: req status: status value: err
].
```

## Step 6: CRUD Flow

### Create

`POST /todos`:

- parse body
- validate `title`
- allocate a new id from BitBarrel metadata
- persist the record
- return a `Todo` object with status `201`

### Read

`GET /todos` and `GET /todos/@id`:

- load records from BitBarrel
- convert them to `Todo` DTOs
- serialize with `Json stringify:`

### Update

`PATCH /todos/@id`:

- parse body
- allow `title` and/or `completed`
- reject invalid or empty patch payloads
- update stored record and return the DTO

### Delete

`DELETE /todos/@id`:

- remove the record from BitBarrel
- return a small JSON confirmation payload

## Step 7: Serve OpenAPI

The example also exposes a machine-readable spec at `/openapi.json`.

Right now the example builds that spec explicitly in Harding code:

```smalltalk
TodoApiApp>>handleOpenApi: req [
    ^ self respondJson: req status: 200 value: self openApiDocument
].
```

This is useful for two reasons:

1. the API already has a standards-shaped description
2. it gives a concrete bridge toward future automatic OpenAPI generation

The component schemas are defined on the DTO classes themselves:

```smalltalk
Todo class>>openApiSchema [
    ^ #{
        "type" -> "object",
        "properties" -> #{ ... },
        "required" -> #("id" "title" "completed" "createdAt")
    }
]
```

That is not fully automatic yet, but it is a good intermediate pattern.

## Why This Example Uses Explicit OpenAPI Tables

Harding does not yet have a built-in OpenAPI generator for MummyX routes.

The example therefore uses explicit schema and endpoint metadata rather than trying to infer documentation from handler blocks.

That keeps the example:

- understandable
- predictable
- OpenAPI-compliant
- close to the future metadata-driven direction described in `docs/plans/OPENAPI_AND_API_SERVER_PLAN.md`

## Suggested Next Improvements

If you want to turn this into a reusable API framework, the next steps are:

1. add a route metadata registry on top of `Router`
2. generate OpenAPI `paths` from declarative endpoint metadata
3. generate component schemas from Harding classes plus explicit API metadata
4. optionally add Swagger UI or ReDoc over the emitted `/openapi.json`

## Related Files

- `examples/api_todos.hrd`
- `docs/MUMMYX.md`
- `docs/MANUAL.md`
- `docs/plans/OPENAPI_AND_API_SERVER_PLAN.md`
