import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

export class HardingLanguageClient {
    private client: LanguageClient | undefined;

    constructor(context: vscode.ExtensionContext) {
        this.startClient(context);
    }

    private startClient(context: vscode.ExtensionContext) {
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

        // Create the client
        this.client = new LanguageClient(
            'harding',
            'Harding Language Server',
            serverOptions,
            clientOptions
        );

        // Start the client
        this.client.start();
        context.subscriptions.push(this.client);
    }

    public stop(): Thenable<void> | undefined {
        if (!this.client) {
            return undefined;
        }
        return this.client.stop();
    }
}
