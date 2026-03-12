# Packaging Nim Primitives with Harding Code

This tutorial shows how to ship a Harding library as a Nim package that contains:

- Nim primitive implementations
- Embedded `.hrd` source files
- A bootstrap file that loads and imports the package library

The package API lives in `src/harding/packages/package_api.nim`.

## 1. Package layout

Use a standard Nimble structure:

```text
harding-echo/
├── harding-echo.nimble
├── src/
│   └── harding_echo/
│       ├── package.nim
│       └── primitives.nim
└── lib/
    └── harding/
        └── echo/
            ├── Bootstrap.hrd
            └── Echo.hrd
```

## 2. Define Harding-side API (`Echo.hrd`)

```smalltalk
Echo := Object derive: #().
Echo class>>value <primitive primitiveEchoValue>
```

## 3. Define package bootstrap (`Bootstrap.hrd`)

```smalltalk
EchoLib := Library new.
EchoLib load: "lib/echo/Echo.hrd".
Harding import: EchoLib.
```

`Library load:` and `Harding load:` now resolve embedded package sources as well as files.

## 4. Implement Nim primitives (`primitives.nim`)

```nim
import harding/core/types

proc primitiveEchoValueImpl*(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  discard self
  discard args
  return toValue("hello from Nim")
```

## 5. Register package and primitives (`package.nim`)

```nim
import harding/core/types
import harding/interpreter/objects
import harding/packages/package_api

import ./primitives

const BootstrapHrd = staticRead("../../lib/echo/Bootstrap.hrd")
const EchoHrd = staticRead("../../lib/echo/Echo.hrd")

proc registerEchoPrimitives(interp: var Interpreter) {.nimcall.} =
  if "Echo" notin interp.globals[]:
    return
  let echoClassVal = interp.globals[]["Echo"]
  if echoClassVal.kind != vkClass:
    return

  let m = createCoreMethod("primitiveEchoValue")
  m.setNativeImpl(primitiveEchoValueImpl)
  echoClassVal.classVal.classMethods["primitiveEchoValue"] = m
  echoClassVal.classVal.allClassMethods["primitiveEchoValue"] = m

proc installEchoPackage*(interp: var Interpreter): bool =
  let spec = HardingPackageSpec(
    name: "Echo",
    version: "0.1.0",
    bootstrapPath: "lib/echo/Bootstrap.hrd",
    sources: @[
      (path: "lib/echo/Bootstrap.hrd", source: BootstrapHrd),
      (path: "lib/echo/Echo.hrd", source: EchoHrd)
    ],
    registerPrimitives: registerEchoPrimitives
  )
  return installPackage(interp, spec)
```

## 6. Install from host application

After you create and initialize an interpreter:

```nim
var interp = newInterpreter()
initGlobals(interp)
loadStdlib(interp)

discard installEchoPackage(interp)
```

Now Harding code can call:

```smalltalk
Echo value
```

## External Library Distribution with `harding lib`

For distributing Harding libraries that can be installed by end users via `harding lib install`, use the external library workflow. This is separate from the embedded package flow above.

### 1. Create a Nimble package with external library metadata

```text
harding-mysql/
├── harding-mysql.nimble
├── src/
│   └── harding_mysql/
│       └── package.nim
└── lib/
    └── harding/
        └── mysql/
            ├── Bootstrap.hrd
            └── MySQL.hrd
```

### 2. Add library metadata to nimble file

```nimble
# harding-mysql.nimble
version       = "0.1.0"
author        = "Your Name"
description   = "Harding MySQL driver"
license       = "MIT"

requires      = "harding >= 0.8.0"

[extra]
hardingLibrary = "harding_mysql"
hardingSources = @["lib/harding/mysql/Bootstrap.hrd"]
```

### 3. Implement Bootstrap.hrd

```smalltalk
MySQLLib := Library new.
MySQLLib load: "lib/mysql/MySQL.hrd".
Harding import: MySQLLib.
```

### 4. Distribute via a registry

Users can install your library once it's published to a registry:

```bash
# List available libraries
harding lib list

# Install a library
harding lib install harding-mysql

# Use it in their code
MySQLConnection new host: "localhost" database: "test"
```

The `harding lib` command handles downloading, installing, and loading the library bootstrap automatically.

## Notes

- Keep primitive selectors in `.hrd` and Nim registration exactly matched.
- If you store Nim `ref object` values in `Instance.nimValue`, keep them alive with a registry (ARC safety).
- For package-relative source loading, use stable virtual paths in `sources` and in your bootstrap `load:` calls.
- Use `derive:`, `derivePublic:`, or `derive:read:write:` for class creation (not the deprecated `deriveWithAccessors:`).
