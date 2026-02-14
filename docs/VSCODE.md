# VSCode Extension for Harding

## Overview

The Harding repository includes a full-featured VSCode extension that provides:

- **Syntax Highlighting** for `.hrd` files
- **Language Server Protocol (LSP)** support for completions, hover info, and symbol navigation
- **Debug Adapter Protocol (DAP)** support for breakpoints, stepping, and variable inspection

## Installation

### Prerequisites

1. Build the Harding Language Server:
   ```bash
   nimble harding_lsp
   ```

2. Build Harding with debugger support:
   ```bash
   nimble harding_debug
   ```

3. Install `vsce` (VSCode Extension Manager):
   ```bash
   npm install -g @vscode/vsce
   ```

### Building the Extension

```bash
nimble vsix
```

This will:
1. Build the Harding Language Server (`harding-lsp`)
2. Install npm dependencies
3. Compile TypeScript
4. Create `vscode-harding/vscode-harding-0.4.0.vsix`

### Installing the Extension

**Command line:**
```bash
code --install-extension vscode-harding/vscode-harding-0.4.0.vsix
```

**From VSCode:**
1. Press `Ctrl+Shift+P` (Cmd+Shift+P on Mac)
2. Type "Extensions: Install from VSIX..."
3. Select `vscode-harding/vscode-harding-0.4.0.vsix`
4. Reload VSCode when prompted

## Features

### Syntax Highlighting

The grammar provides scopes for the following constructs:

| Construct | Scope | Example |
|-----------|-------|---------|
| Comments | `comment.line.harding` | `# This is a comment` |
| Strings | `string.quoted.double.harding` | `"hello"` |
| Symbols | `entity.name.tag.symbol.harding` | `#foo`, `#bar:baz:` |
| Symbols (quoted) | `entity.name.tag.symbol.quoted.harding` | `"symbol with spaces"` |
| Numbers | `constant.numeric.harding` | `42`, `3.14`, `-10` |
| Booleans | `constant.language.harding` | `true`, `false` |
| Nil | `constant.language.harding` | `nil` |
| Self/Super | `constant.language.harding` | `self`, `super` |
| Globals (classes) | `constant.other.class.harding` | `Object`, `Point` |
| Variables | `variable.other.harding` | `x`, `message` |
| Block parameters | `variable.parameter.harding` | `:param`, `:x :y` |
| Block temps | `variable.other.temporary.harding` | `\| temp1 temp2` |
| Keywords | `keyword.control.harding` | `ifTrue:`, `at:put:` |
| Assignment | `keyword.operator.assignment.harding` | `:=` |
| Return | `keyword.operator.return.harding` | `^` |
| Method def | `keyword.operator.method-definition.harding` | `>>` |
| Arrow | `keyword.operator.arrow.harding` | `->` |
| Operators | `keyword.operator.harding` | `+`, `-`, `*`, `/`, `&`, `\|` |
| Arrays | `meta.array.literal.harding` | `#(1 2 3)` |
| Tables | `meta.table.literal.harding` | `#{"key" -> "value"}` |
| Objects | `meta.object.literal.harding` | `{\| x: 1 \|}` |
| Primitives | `support.function.primitive.harding` | `<primitive>...</primitive>` |

### Language Server Features (LSP)

The Language Server provides IDE features via `harding-lsp`:

- **Completions** - Context-aware suggestions for selectors and keywords
- **Hover Information** - Shows documentation and type information
- **Go to Definition** - Navigate to method and class definitions
- **Document Symbols** - Outline view of classes and methods
- **Workspace Symbols** - Global symbol search

### Debugger Features (DAP)

The Debug Adapter provides debugging via `harding_debug`:

- **Breakpoints** - Set breakpoints in `.hrd` files
- **Stepping** - Step over, into, and out of methods
- **Call Stack** - View the current call stack
- **Variables** - Inspect local variables, arguments, and slots
- **Watch Expressions** - Evaluate expressions in the current context
- **Debug Console** - Interactive console for expression evaluation

## Configuration

The extension provides the following settings (in `.vscode/settings.json`):

```json
{
  "harding.languageServer.path": "harding-lsp",
  "harding.debugger.port": 9877,
  "harding.home": "/path/to/harding"
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `harding.languageServer.path` | `harding-lsp` | Path to the Harding language server |
| `harding.debugger.port` | `9877` | Port for the Harding debug protocol server |
| `harding.home` | workspace root | HARDING_HOME directory |

## Debugging

### Creating a Launch Configuration

Create `.vscode/launch.json` in your workspace:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "harding",
      "request": "launch",
      "name": "Debug Harding Program",
      "program": "${workspaceFolder}/main.hrd",
      "cwd": "${workspaceFolder}",
      "debuggerPort": 9877,
      "stopOnEntry": false
    }
  ]
}
```

### Debugging Commands

| Key | Action |
|-----|--------|
| `F5` | Start debugging |
| `F10` | Step over |
| `F11` | Step into |
| `Shift+F11` | Step out |
| `Ctrl+Shift+P` → "Harding: Run Harding File" | Run without debugging |
| `Ctrl+Shift+P` → "Harding: Debug Harding File" | Start debugging current file |

## Extension Structure

```
vscode-harding/
├── package.json              # Extension manifest
├── tsconfig.json             # TypeScript configuration
├── language-configuration.json # Language configuration
├── README.md                 # Extension documentation
├── src/
│   ├── extension.ts          # Main entry point
│   ├── lsp/
│   │   └── client.ts         # LSP client setup
│   ├── dap/
│   │   └── adapter.ts        # Debug Adapter (DAP)
│   └── debugger/
│       └── session.ts        # HDP connection manager
└── syntaxes/
    └── harding.tmLanguage.json # Syntax highlighting
```

## Architecture

The extension follows a three-layer architecture:

```
VSCode Extension (TypeScript)
    ├─ LSP Client ──→ Harding Language Server (Nim)
    │                    └─ Provides completions, hover, symbols
    └─ DAP Client ──→ Harding Debug Adapter (TypeScript)
                         └─ HDP (TCP) ──→ VM
```

**Why this architecture?**
- LSP handles static analysis (doesn't need running VM)
- DAP requires running VM with debug hooks
- Clean separation matches standard language tooling
- Each component can be tested independently

## Verifying Syntax Highlighting

To check that syntax highlighting is working correctly:

1. Open any `.hrd` file in VSCode
2. Press `Ctrl+Shift+P` (Cmd+Shift+P on Mac)
3. Type "Developer: Inspect Editor Tokens and Scopes"
4. Move your cursor over different code elements
5. A popup will show the scopes applied (e.g., `source.harding keyword.control.harding`)

## Customizing Colors

To customize the colors in your VSCode settings (`settings.json`):

```json
{
  "editor.tokenColorCustomizations": {
    "textMateRules": [
      {
        "scope": "entity.name.tag.symbol.harding",
        "settings": {
          "foreground": "#ff5555"
        }
      },
      {
        "scope": "constant.other.class.harding",
        "settings": {
          "foreground": "#8be9fd",
          "fontStyle": "bold"
        }
      }
    ]
  }
}
```

## Grammar Notes

### Comment vs Symbol Disambiguation

The grammar distinguishes between comments (`# comment`) and symbols (`#foo`):
- Comments require a space after the `#` or special characters
- Symbols require a letter/underscore immediately after `#`

This prevents cases like `#primitiveIsKindOf:` from being incorrectly highlighted as comments.

### Identifiers vs Globals

- Identifiers starting with lowercase: `variable.other.harding`
- Identifiers starting with uppercase: `constant.other.class.harding`

This convention makes class references stand out from local variables.

## Troubleshooting

**Extension not loading:**
- Ensure VSCode is reloaded after installation
- Check that `harding-lsp` and `harding_debug` are in your PATH

**LSP not working:**
- Verify `harding-lsp` was built: `./harding-lsp --help`
- Check VSCode output panel: View → Output → "Harding Language Server"

**Debugger not connecting:**
- Verify `harding_debug` was built: `./harding_debug --help`
- Check that the debug port (default 9877) is not blocked
- Look at VSCode debug console for connection errors

**Incorrect highlighting:**
- Use "Developer: Inspect Editor Tokens and Scopes" to verify which scopes are applied
- If needed, rebuild and reinstall the extension after modifying the grammar

**Extension file too large:**
- Check `.vscodeignore` to ensure source files are excluded
- Run `vsce package` again after updating `.vscodeignore`

## Rebuilding the Extension

If you modify the extension:

```bash
# After modifying TypeScript files
cd vscode-harding
npm run compile

# After modifying LSP or debugger Nim files
nimble vsix
```

## See Also

- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Harding debugger documentation
- [README.md](../README.md) - Project overview
- `CLAUDE.md` - Development guidelines
