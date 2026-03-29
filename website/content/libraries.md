---
title: External Libraries
---

## External Libraries

Harding can load installable external libraries through `harding lib`.

These packages can bundle:

- Harding source in `.hrd` files
- native Nim code and primitives
- metadata in `.harding-lib.json`

That means a single library can ship both the Harding-facing API and the native implementation behind it.

In practice, a Harding library is just a git repository with a small metadata file. When you install one with `harding lib install ...`, Harding clones that repository into the local `external/` directory. During the next build, Harding's external-library discovery step regenerates the import/install code so the library is compiled into the VM/runtime you build.

## Basic Commands

```bash
harding lib list
harding lib install sqlite
harding lib install bitbarrel

# then rebuild Harding so the library is compiled into the binary
nimble harding
```

## Current Libraries

### BitBarrel

- persistent storage integration
- hash table and sorted table abstractions
- useful for local-first data and API examples
- GitHub: [harding-bitbarrel](https://github.com/gokr/harding-bitbarrel)

```bash
harding lib install bitbarrel
```

### SQLite

- SQLite database connectivity for Harding
- simple local relational storage option
- useful for apps and examples that need embedded persistence
- GitHub: [harding-sqlite](https://github.com/gokr/harding-sqlite)

```bash
harding lib install sqlite
```

### MySQL

- MySQL database connectivity for Harding
- intended for external database-backed applications
- GitHub: [harding-mysql](https://github.com/gokr/harding-mysql)

```bash
harding lib install mysql
```

### NimCP

- Model Context Protocol server support through NimCP
- useful for building MCP tools/servers with Harding integration
- GitHub: [harding-nimcp](https://github.com/gokr/harding-nimcp)

```bash
harding lib install nimcp
```

### Curly

- HTTP client support
- useful for talking to external APIs and services
- GitHub: [harding-curly](https://github.com/gokr/harding-curly)

```bash
harding lib install curly
```

### OAuth2

- OAuth2 integration helpers
- useful for login, token exchange, and service authorization flows
- GitHub: [harding-oauth2](https://github.com/gokr/harding-oauth2)

```bash
harding lib install oauth2
```

### Google OAuth

- Google-specific OAuth integration on top of OAuth2 flows
- GitHub: [harding-googleoauth](https://github.com/gokr/harding-googleoauth)

```bash
harding lib install googleoauth
```

### JWT

- JSON Web Token support
- useful for auth tokens and API security flows
- GitHub: [harding-jwt](https://github.com/gokr/harding-jwt)

```bash
harding lib install jwt
```

## Package Layout

Typical layout:

```text
external/my-lib/
|- .harding-lib.json
|- lib/
|  `- my-lib/
|     `- Bootstrap.hrd
`- src/
   `- native_impl.nim
```

Installed libraries simply live under:

```text
external/
|- bitbarrel/
|- mysql/
|- nimcp/
`- sqlite/
```

So the package story stays straightforward:

- install = clone git repo into `external/`
- build = regenerate external-library wiring and compile it into Harding
- run = use the library through its normal Harding bootstrap/API

## Why This Matters

The external library model lets Harding stay small while still supporting:

- databases
- HTTP clients
- authentication
- MCP tooling
- custom native extensions

It also keeps the Harding and Nim sides versioned together as one installable unit.
