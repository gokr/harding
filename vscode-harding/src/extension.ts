import * as vscode from 'vscode';
import { LanguageClient, LanguageClientOptions, ServerOptions, TransportKind } from 'vscode-languageclient/node';
import { HardingDebugConfigurationProvider } from './dap/adapter';

let client: LanguageClient | undefined;

export function activate(context: vscode.ExtensionContext) {
    // Register debug configuration provider
    const provider = new HardingDebugConfigurationProvider();
    context.subscriptions.push(
        vscode.debug.registerDebugConfigurationProvider('harding', provider)
    );

    // Start Language Server
    startLanguageServer(context);

    // Register commands
    registerCommands(context);
}

function startLanguageServer(context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration('harding');
    const lspPath = config.get<string>('languageServer.path', 'harding-lsp');

    // Server options
    const serverOptions: ServerOptions = {
        command: lspPath,
        args: ['--stdio'],
        transport: TransportKind.stdio
    };

    // Client options
    const clientOptions: LanguageClientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'harding' }
        ],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.hrd')
        }
    };

    // Create and start the client
    client = new LanguageClient(
        'harding',
        'Harding Language Server',
        serverOptions,
        clientOptions
    );

    // Start the client and add to subscriptions
    client.start();
    context.subscriptions.push(client);
}

function registerCommands(context: vscode.ExtensionContext) {
    // Run Harding file command
    const runCommand = vscode.commands.registerCommand('harding.runFile', () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor || editor.document.languageId !== 'harding') {
            vscode.window.showErrorMessage('No Harding file is currently open');
            return;
        }

        const filePath = editor.document.fileName;
        const terminal = vscode.window.createTerminal('Harding');
        terminal.sendText(`harding "${filePath}"`);
        terminal.show();
    });

    // Debug Harding file command
    const debugCommand = vscode.commands.registerCommand('harding.debugFile', () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor || editor.document.languageId !== 'harding') {
            vscode.window.showErrorMessage('No Harding file is currently open');
            return;
        }

        const filePath = editor.document.fileName;
        vscode.debug.startDebugging(undefined, {
            type: 'harding',
            request: 'launch',
            name: 'Debug Harding File',
            program: filePath,
            stopOnEntry: false
        });
    });

    context.subscriptions.push(runCommand, debugCommand);
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
