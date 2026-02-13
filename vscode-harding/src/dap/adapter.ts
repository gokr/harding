import * as vscode from 'vscode';
import {
    LoggingDebugSession,
    TerminatedEvent,
    StoppedEvent,
    Thread,
    StackFrame,
    Scope,
    Source,
    Handles,
    Breakpoint,
    InitializedEvent,
    OutputEvent
} from '@vscode/debugadapter';
import { DebugProtocol } from '@vscode/debugprotocol';
import { HardingDebugSession } from '../debugger/session';

export class HardingDebugConfigurationProvider implements vscode.DebugConfigurationProvider {
    resolveDebugConfiguration(
        folder: vscode.WorkspaceFolder | undefined,
        config: vscode.DebugConfiguration,
        token?: vscode.CancellationToken
    ): vscode.ProviderResult<vscode.DebugConfiguration> {
        // If launch.json is missing or empty, provide default configuration
        if (!config.type && !config.request && !config.name) {
            const editor = vscode.window.activeTextEditor;
            if (editor && editor.document.languageId === 'harding') {
                config.type = 'harding';
                config.name = 'Launch Harding Program';
                config.request = 'launch';
                config.program = editor.document.fileName;
                config.cwd = folder?.uri.fsPath || '${workspaceFolder}';
                config.debuggerPort = 9877;
            }
        }

        if (!config.program) {
            return vscode.window.showInformationMessage('Cannot find a Harding program to debug').then(_ => {
                return undefined;
            });
        }

        return config;
    }
}

interface LaunchRequestArguments extends DebugProtocol.LaunchRequestArguments {
    program: string;
    args?: string[];
    cwd?: string;
    hardingHome?: string;
    debuggerPort?: number;
    stopOnEntry?: boolean;
}

interface AttachRequestArguments extends DebugProtocol.AttachRequestArguments {
    port: number;
}

export class HardingDebugAdapter extends LoggingDebugSession {
    private session: HardingDebugSession | undefined;
    private variableHandles = new Handles<VariableScope>();

    public constructor() {
        super();
        this.setDebuggerLinesStartAt1(true);
        this.setDebuggerColumnsStartAt1(true);
    }

    protected initializeRequest(
        response: DebugProtocol.InitializeResponse,
        args: DebugProtocol.InitializeRequestArguments
    ): void {
        response.body = response.body || {};
        response.body.supportsConfigurationDoneRequest = true;
        response.body.supportsEvaluateForHovers = true;
        response.body.supportsStepBack = false;
        response.body.supportsDataBreakpoints = false;
        response.body.supportsCompletionsRequest = false;
        response.body.supportsBreakpointLocationsRequest = false;
        response.body.supportsDelayedStackTraceLoading = true;
        response.body.supportsLogPoints = false;
        response.body.supportsFunctionBreakpoints = false;
        response.body.supportsConditionalBreakpoints = true;
        response.body.exceptionBreakpointFilters = [];

        this.sendResponse(response);
        this.sendEvent(new InitializedEvent());
    }

    protected async launchRequest(
        response: DebugProtocol.LaunchResponse,
        args: LaunchRequestArguments
    ): Promise<void> {
        const config = vscode.workspace.getConfiguration('harding');
        const port = args.debuggerPort || config.get<number>('debugger.port', 9877);
        const hardingHome = args.hardingHome || config.get<string>('home', args.cwd || '${workspaceFolder}');

        this.session = new HardingDebugSession(
            args.program,
            args.args || [],
            args.cwd || '${workspaceFolder}',
            hardingHome,
            port
        );

        // Set up event handlers
        this.session.onBreakpointHit = (file, line) => {
            this.sendEvent(new StoppedEvent('breakpoint', 1));
        };

        this.session.onPaused = (reason) => {
            this.sendEvent(new StoppedEvent(reason, 1));
        };

        this.session.onOutput = (category, message) => {
            this.sendEvent(new OutputEvent(message + '\n', category));
        };

        this.session.onTerminated = () => {
            this.sendEvent(new TerminatedEvent());
        };

        // Start the debug session
        await this.session.start();

        // Set initial breakpoints
        await this.session.setExceptionBreakpoints([]);

        // Continue if not stopping on entry
        if (!args.stopOnEntry) {
            await this.session.continue();
        } else {
            this.sendEvent(new StoppedEvent('entry', 1));
        }

        this.sendResponse(response);
    }

    protected async attachRequest(
        response: DebugProtocol.AttachResponse,
        args: AttachRequestArguments
    ): Promise<void> {
        this.session = new HardingDebugSession('', [], '', '', args.port);

        this.session.onBreakpointHit = (file, line) => {
            this.sendEvent(new StoppedEvent('breakpoint', 1));
        };

        this.session.onPaused = (reason) => {
            this.sendEvent(new StoppedEvent(reason, 1));
        };

        this.session.onOutput = (category, message) => {
            this.sendEvent(new OutputEvent(message + '\n', category));
        };

        this.session.onTerminated = () => {
            this.sendEvent(new TerminatedEvent());
        };

        await this.session.connect();
        this.sendResponse(response);
    }

    protected async setBreakPointsRequest(
        response: DebugProtocol.SetBreakpointsResponse,
        args: DebugProtocol.SetBreakpointsArguments
    ): Promise<void> {
        if (!this.session) {
            this.sendResponse(response);
            return;
        }

        const path = args.source.path || '';
        const clientLines = args.lines || [];

        // Clear existing breakpoints for this file
        await this.session.clearBreakpoints(path);

        // Set new breakpoints
        const breakpoints: Breakpoint[] = [];
        for (const line of clientLines) {
            const verified = await this.session.setBreakpoint(path, line);
            breakpoints.push(new Breakpoint(verified, line));
        }

        response.body = { breakpoints };
        this.sendResponse(response);
    }

    protected async configurationDoneRequest(
        response: DebugProtocol.ConfigurationDoneResponse,
        args: DebugProtocol.ConfigurationDoneArguments
    ): Promise<void> {
        this.sendResponse(response);
    }

    protected async continueRequest(
        response: DebugProtocol.ContinueResponse,
        args: DebugProtocol.ContinueArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.continue();
        }
        this.sendResponse(response);
    }

    protected async nextRequest(
        response: DebugProtocol.NextResponse,
        args: DebugProtocol.NextArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.stepOver();
        }
        this.sendResponse(response);
    }

    protected async stepInRequest(
        response: DebugProtocol.StepInResponse,
        args: DebugProtocol.StepInArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.stepInto();
        }
        this.sendResponse(response);
    }

    protected async stepOutRequest(
        response: DebugProtocol.StepOutResponse,
        args: DebugProtocol.StepOutArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.stepOut();
        }
        this.sendResponse(response);
    }

    protected async pauseRequest(
        response: DebugProtocol.PauseResponse,
        args: DebugProtocol.PauseArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.pause();
        }
        this.sendResponse(response);
    }

    protected async threadsRequest(response: DebugProtocol.ThreadsResponse): Promise<void> {
        response.body = {
            threads: [new Thread(1, 'main')]
        };
        this.sendResponse(response);
    }

    protected async stackTraceRequest(
        response: DebugProtocol.StackTraceResponse,
        args: DebugProtocol.StackTraceArguments
    ): Promise<void> {
        if (!this.session) {
            this.sendResponse(response);
            return;
        }

        const frames = await this.session.getStackFrames();
        const stackFrames: StackFrame[] = frames.map((f, i) => {
            return new StackFrame(
                i,
                f.name,
                new Source(f.file.split('/').pop() || f.file, f.file),
                f.line,
                f.column
            );
        });

        response.body = {
            stackFrames,
            totalFrames: stackFrames.length
        };
        this.sendResponse(response);
    }

    protected async scopesRequest(
        response: DebugProtocol.ScopesResponse,
        args: DebugProtocol.ScopesArguments
    ): Promise<void> {
        const scopes: Scope[] = [
            new Scope('Locals', this.variableHandles.create(VariableScope.Locals), false),
            new Scope('Arguments', this.variableHandles.create(VariableScope.Arguments), false)
        ];

        response.body = { scopes };
        this.sendResponse(response);
    }

    protected async variablesRequest(
        response: DebugProtocol.VariablesResponse,
        args: DebugProtocol.VariablesArguments
    ): Promise<void> {
        if (!this.session) {
            this.sendResponse(response);
            return;
        }

        const scope = this.variableHandles.get(args.variablesReference);
        const frameId = 0; // TODO: Get actual frame ID

        const variables = await this.session.getVariables(frameId);
        response.body = {
            variables: variables.map(v => ({
                name: v.name,
                value: v.value,
                type: v.type,
                variablesReference: 0
            }))
        };
        this.sendResponse(response);
    }

    protected async evaluateRequest(
        response: DebugProtocol.EvaluateResponse,
        args: DebugProtocol.EvaluateArguments
    ): Promise<void> {
        if (!this.session) {
            this.sendResponse(response);
            return;
        }

        const frameId = args.frameId || 0;
        const result = await this.session.evaluate(args.expression, frameId);

        response.body = {
            result: result.value,
            type: result.type,
            variablesReference: 0
        };
        this.sendResponse(response);
    }

    protected async disconnectRequest(
        response: DebugProtocol.DisconnectResponse,
        args: DebugProtocol.DisconnectArguments
    ): Promise<void> {
        if (this.session) {
            await this.session.stop();
            this.session = undefined;
        }
        this.sendResponse(response);
    }
}

enum VariableScope {
    Locals = 1,
    Arguments = 2
}
