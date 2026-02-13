import * as net from 'net';
import * as child_process from 'child_process';
import * as path from 'path';

export interface StackFrameInfo {
    id: number;
    name: string;
    file: string;
    line: number;
    column: number;
    className: string;
    receiverClass: string;
}

export interface VariableInfo {
    name: string;
    value: string;
    type: string;
}

export interface EvaluateResult {
    value: string;
    type: string;
}

export class HardingDebugSession {
    private socket: net.Socket | undefined;
    private process: child_process.ChildProcess | undefined;
    private nextRequestId = 1;
    private pendingRequests = new Map<number, (response: any) => void>();

    // Event handlers
    public onBreakpointHit: ((file: string, line: number) => void) | undefined;
    public onPaused: ((reason: string) => void) | undefined;
    public onOutput: ((category: string, message: string) => void) | undefined;
    public onTerminated: (() => void) | undefined;

    constructor(
        private program: string,
        private args: string[],
        private cwd: string,
        private hardingHome: string,
        private port: number
    ) {}

    public async start(): Promise<void> {
        return new Promise((resolve, reject) => {
            // Start harding process with debugger
            const hardingPath = path.join(this.hardingHome, 'harding_debug');
            const spawnArgs = [
                '--debugger-port', this.port.toString(),
                this.program,
                ...this.args
            ];

            this.process = child_process.spawn(hardingPath, spawnArgs, {
                cwd: this.cwd,
                env: {
                    ...process.env,
                    HARDING_HOME: this.hardingHome
                }
            });

            // Handle process output
            this.process.stdout?.on('data', (data: Buffer) => {
                if (this.onOutput) {
                    this.onOutput('stdout', data.toString());
                }
            });

            this.process.stderr?.on('data', (data: Buffer) => {
                if (this.onOutput) {
                    this.onOutput('stderr', data.toString());
                }
            });

            this.process.on('exit', (code: number | null) => {
                if (this.onTerminated) {
                    this.onTerminated();
                }
            });

            // Wait a moment for the debugger server to start, then connect
            setTimeout(() => {
                this.connect().then(resolve).catch(reject);
            }, 500);
        });
    }

    public async connect(): Promise<void> {
        return new Promise((resolve, reject) => {
            this.socket = new net.Socket();

            this.socket.connect(this.port, '127.0.0.1', () => {
                // Send connect request
                this.sendRequest('connect', {}).then(() => {
                    resolve();
                }).catch(reject);
            });

            this.socket.on('data', (data: Buffer) => {
                this.handleData(data.toString());
            });

            this.socket.on('error', (err: Error) => {
                reject(err);
            });

            this.socket.on('close', () => {
                if (this.onTerminated) {
                    this.onTerminated();
                }
            });
        });
    }

    public async stop(): Promise<void> {
        // Send disconnect request
        try {
            await this.sendRequest('disconnect', {});
        } catch (e) {
            // Ignore errors during disconnect
        }

        // Close socket
        if (this.socket) {
            this.socket.destroy();
            this.socket = undefined;
        }

        // Kill process
        if (this.process) {
            this.process.kill();
            this.process = undefined;
        }
    }

    // Debug commands
    public async continue(): Promise<void> {
        await this.sendRequest('continue', {});
    }

    public async pause(): Promise<void> {
        await this.sendRequest('pause', {});
    }

    public async stepOver(): Promise<void> {
        await this.sendRequest('stepOver', {});
    }

    public async stepInto(): Promise<void> {
        await this.sendRequest('stepInto', {});
    }

    public async stepOut(): Promise<void> {
        await this.sendRequest('stepOut', {});
    }

    public async setBreakpoint(file: string, line: number): Promise<boolean> {
        const response = await this.sendRequest('setBreakpoint', {
            source: { path: file },
            line: line
        });
        return response.verified === true;
    }

    public async clearBreakpoints(file: string): Promise<void> {
        await this.sendRequest('clearBreakpoints', {
            source: { path: file }
        });
    }

    public async setExceptionBreakpoints(filters: string[]): Promise<void> {
        await this.sendRequest('setExceptionBreakpoints', {
            filters: filters
        });
    }

    public async getStackFrames(): Promise<StackFrameInfo[]> {
        const response = await this.sendRequest('getStackFrames', {});
        return response.stackFrames || [];
    }

    public async getVariables(frameId: number): Promise<VariableInfo[]> {
        const response = await this.sendRequest('getVariables', {
            frameId: frameId
        });
        return response.variables || [];
    }

    public async evaluate(expression: string, frameId: number): Promise<EvaluateResult> {
        const response = await this.sendRequest('evaluate', {
            expression: expression,
            frameId: frameId
        });
        return {
            value: response.result || '',
            type: response.type || 'Object'
        };
    }

    // Private methods
    private sendRequest(command: string, args: any): Promise<any> {
        return new Promise((resolve, reject) => {
            if (!this.socket) {
                reject(new Error('Not connected'));
                return;
            }

            const request = {
                seq: this.nextRequestId++,
                command: command,
                arguments: args
            };

            this.pendingRequests.set(request.seq, resolve);

            const json = JSON.stringify(request);
            this.socket.write(json + '\n');
        });
    }

    private handleData(data: string): void {
        // Handle multiple JSON messages separated by newlines
        const messages = data.split('\n').filter(m => m.trim().length > 0);

        for (const message of messages) {
            try {
                const json = JSON.parse(message);

                // Check if it's a response
                if (json.type === 'response') {
                    const requestSeq = json.request_seq;
                    const resolver = this.pendingRequests.get(requestSeq);
                    if (resolver) {
                        this.pendingRequests.delete(requestSeq);
                        if (json.success) {
                            resolver(json.body || {});
                        } else {
                            resolver(new Error(json.message || 'Request failed'));
                        }
                    }
                }

                // Check if it's an event
                if (json.type === 'event') {
                    this.handleEvent(json);
                }
            } catch (e) {
                // Ignore malformed JSON
            }
        }
    }

    private handleEvent(event: any): void {
        switch (event.event) {
            case 'breakpointHit':
                if (this.onBreakpointHit) {
                    this.onBreakpointHit(event.body.file, event.body.line);
                }
                break;
            case 'paused':
                if (this.onPaused) {
                    this.onPaused(event.body.reason);
                }
                break;
            case 'output':
                if (this.onOutput) {
                    this.onOutput(event.body.category, event.body.output);
                }
                break;
        }
    }
}
