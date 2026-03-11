# External Libraries

This directory contains external Harding libraries installed via the package manager.

## Overview

External libraries are Nim packages that extend Harding with additional functionality. They are:

- **Self-contained**: Each library is a complete Nimble package
- **Git-based**: Installed by cloning from Git repositories
- **Versioned**: Support specific versions via git tags
- **Optional**: Only compiled into Harding if installed

## Installation

### From the Registry

List available libraries:
```bash
harding lib list
```

Fetch cached metadata for all known libraries:
```bash
harding lib fetch
```

Fetch cached metadata for one library:
```bash
harding lib fetch mysql
```

Install a library:
```bash
harding lib install mysql
```

Install a specific version:
```bash
harding lib install mysql@1.0.0
```

### From Git (Advanced)

You can also manually clone libraries:
```bash
cd external
git clone https://github.com/user/harding-mylib.git mylib
```

Then regenerate imports:
```bash
nimble discover
```

If you install, remove, or update libraries via `harding lib ...`, this happens
automatically. `nimble discover` is mainly needed after manual changes under
`external/`.

## Managing Libraries

### List Installed Libraries
```bash
harding lib installed
```

### Show Library Information
```bash
harding lib info mysql
```

`harding lib list` is fast and primarily uses installed or cached metadata.
Use `harding lib fetch` to refresh metadata from remote repositories into
`$HARDING_HOME/registry-full.json`.

### Update Libraries

Update a specific library:
```bash
harding lib update mysql
```

Update all libraries:
```bash
harding lib update --all
```

### Remove Libraries
```bash
harding lib remove mysql
```

## Building with External Libraries

After installing, updating, or removing libraries, rebuild Harding:

```bash
nimble harding
```

This automatically:
1. Uses the current generated external library import file
2. Compiles with the appropriate flags

If you manually add, remove, or rename directories under `external/`, run:
```bash
nimble discover
```
before rebuilding.

## Library Structure

Each library in this directory follows this structure:

```
external/
├── mysql/                          # Library directory (git repo name)
│   ├── .harding-lib.json          # Metadata (auto-generated)
│   ├── mysql.nimble               # Nimble package file
│   ├── src/
│   │   └── mysql/                 # Nim source directory
│   │       ├── mysql.nim          # Main module
│   │       └── ...
│   └── lib/
│       └── mysql/                 # Harding source files
│           ├── Bootstrap.hrd
│           └── Mysql.hrd
└── redis/
    └── ...
```

## Creating a Library

To create your own Harding library:

1. **Repository**: Create a Git repository named `harding-<libname>`
2. **Nimble File**: Create `<libname>.nimble` with dependencies
3. **Nim Code**: Implement primitives in `src/harding_<libname>/`
4. **Harding Code**: Create classes in `lib/<libname>/`
5. **Bootstrap**: Create `lib/<libname>/Bootstrap.hrd`

### Example: Minimal Library

```
harding-echo/
├── echo.nimble
├── src/
│   └── echo/
│       ├── echo.nim
│       └── primitives.nim
└── lib/
    └── echo/
        ├── Bootstrap.hrd
        └── Echo.hrd
```

**echo.nimble**:
```nim
version = "1.0.0"
author = "Your Name"
description = "Echo library for Harding"
license = "MIT"
```

**src/echo/echo.nim**:
```nim
import harding/core/types
import harding/packages/package_api

const BootstrapHrd = staticRead("../../lib/echo/Bootstrap.hrd")
const EchoHrd = staticRead("../../lib/echo/Echo.hrd")

proc installEcho*(interp: var Interpreter) =
  let spec = HardingPackageSpec(
    name: "Echo",
    version: "1.0.0",
    bootstrapPath: "lib/echo/Bootstrap.hrd",
    sources: @[
      (path: "lib/echo/Bootstrap.hrd", source: BootstrapHrd),
      (path: "lib/echo/Echo.hrd", source: EchoHrd)
    ],
    registerPrimitives: registerEchoPrimitives
  )
  discard installPackage(interp, spec)
```

**lib/echo/Bootstrap.hrd**:
```smalltalk
Harding load: "lib/echo/Echo.hrd".
Transcript showCr: "Echo library loaded".
```

**lib/echo/Echo.hrd**:
```smalltalk
Echo := Object derive: #().
Echo class>>value <primitive primitiveEchoValue>
```

## Registry

The central registry is maintained in `registry.json` at the Harding repository root.

To add your library to the registry:
1. Ensure your library follows the structure above
2. Submit a PR to the Harding repository
3. Add an entry to `registry.json`

## Versioning

Libraries use semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

Versions are specified via git tags:
- `v1.0.0` or `1.0.0` (both formats supported)
- `HEAD` for the latest commit

## Troubleshooting

### Library not found after installation

Run `nimble discover` to regenerate imports:
```bash
nimble discover
nimble harding
```

### Compilation errors

Check that:
1. Git is installed and available in PATH
2. The library is properly cloned in `external/`
3. The library has a valid `.nimble` file
4. All dependencies are installed (`nimble install` in library directory)

### Rebuild after library changes

If you modify a library's Nim code, rebuild Harding:
```bash
nimble harding
```

## Git Submodules

For version-controlled projects, you can use git submodules:

```bash
git submodule add https://github.com/user/harding-mysql.git external/mysql
nimble discover
nimble harding
```

Add to your `.gitmodules`:
```
[submodule "external/mysql"]
    path = external/mysql
    url = https://github.com/user/harding-mysql.git
```

---

**Note**: This directory and its contents are managed by Harding's library system. Manual modifications may be overwritten by library management commands.
