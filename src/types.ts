export type DiagnosticLevel = 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'fatal';

export interface DiagnosticRecord {
  time?: string | number | Date;
  source?: string;
  level?: DiagnosticLevel | number;
  event?: string;
  message?: string;
  fields?: Record<string, unknown>;
}

export interface NormalizedDiagnosticRecord {
  time: string;
  source: string;
  level: DiagnosticLevel;
  event: string;
  message?: string;
  fields: Record<string, unknown>;
}

export interface TtyglassStartOptions {
  command: string;
  commandArguments?: string[];
  cwd?: string;
  port?: number;
  diagnosticsLimit?: number;
}

export interface TtyglassController {
  readonly url: string;
  readonly origin: string;
  readonly diagnosticsUrl: string;
  readonly token: string;
  readonly closed: Promise<void>;
  stop(reason?: string): Promise<void>;
}
