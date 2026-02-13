# Harding VS Code Extension

VS Code extension for the Harding programming language - a modern Smalltalk dialect that compiles to Nim.

## Features

### Language Support
- **Syntax Highlighting** - Full support for `.hrd` files
- **Code Completion** - Context-aware completions for Harding selectors and keywords
- **Hover Information** - Shows documentation and type information
- **Go to Definition** - Navigate to method and class definitions
- **Document Symbols** - Outline view of classes and methods
- **Workspace Symbols** - Global symbol search

### Debugger Support
- **Breakpoints** - Set breakpoints in `.hrd` files
- **Stepping** - Step over, into, and out of methods
- **Call Stack** - View the current call stack
- **Variables** - Inspect local variables, arguments, and slots
- **Watch Expressions** - Evaluate expressions in the current context
- **Debug Console** - Interactive console for expression evaluation

## Requirements

- Harding compiler and REPL must be installed and available in PATH
- For debugging: `harding_debug` binary (built with `-d:debugger`)
- For LSP features: `harding-lsp` binary

## Installation

1. Build the Harding Language Server:
   ```bash
   nimble harding_lsp
   ```

2. Build Harding with debugger support:
   ```bash
   nimble harding_debug
   ```

3. Install the VS Code extension:
   ```bash
   cd vscode-harding
   npm install
   npm run compile
   ```

4. Copy or symlink the extension to VS Code extensions directory:
   ```bash
   ln -s $(pwd) ~/.vscode/extensions/harding-lang.harding
   ```

## Configuration

The extension provides the following settings:

- `harding.languageServer.path`: Path to the Harding language server (default: `harding-lsp`)
- `harding.debugger.port`: Port for the debug protocol server (default: `9877`)
- `harding.home`: HARDING_HOME directory (defaults to workspace root)

## Usage

### Running a Harding File

Open a `.hrd` file and press F5 to debug or use the Run menu.

### Creating a Launch Configuration

Create a `.vscode/launch.json` in your workspace:

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

The extension adds commands to the command palette:

- `Harding: Run Harding File` - Run the current file without debugging
- `Harding: Debug Harding File` - Start debugging the current file

## Architecture

The extension consists of three parts:

1. **Language Client** (`src/lsp/client.ts`) - Communicates with the Harding Language Server via LSP
2. **Debug Adapter** (`src/dap/adapter.ts`) - Implements the Debug Adapter Protocol
3. **Debugger Session** (`src/debugger/session.ts`) - Communicates with the Harding VM via HDP (Harding Debug Protocol)

## Development

### Building from Source

```bash
cd vscode-harding
npm install
npm run watch    # Watch mode for development
```

### Testing

1. Open VS Code with the extension:
   ```bash
   code --extensionDevelopmentPath=$(pwd)
   ```

2. Open a Harding file and test the features

## License

MIT License - See LICENSE file for details.
