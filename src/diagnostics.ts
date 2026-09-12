import type { DiagnosticLevel, DiagnosticRecord } from './types.js';

export interface SendDiagnosticOptions {
  endpoint?: string;
  token?: string;
  timeoutMilliseconds?: number;
  throwOnError?: boolean;
  fetchImplementation?: typeof fetch;
}

export interface TtyglassSinkOptions extends SendDiagnosticOptions {
  source?: string;
  onError?: (error: unknown) => void;
}

export interface TtyglassSink {
  write(chunk: string | Uint8Array): boolean;
  flush(): Promise<void>;
}

const pinoLevels = new Map<number, DiagnosticLevel>([
  [10, 'trace'],
  [20, 'debug'],
  [30, 'info'],
  [40, 'warn'],
  [50, 'error'],
  [60, 'fatal'],
]);

function isLoopbackEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    return (
      url.protocol === 'http:' &&
      (url.hostname === '127.0.0.1' || url.hostname === 'localhost' || url.hostname === '[::1]')
    );
  } catch {
    return false;
  }
}

function resolveConnection(options: SendDiagnosticOptions): { endpoint: string; token: string } | undefined {
  const endpoint = options.endpoint ?? process.env.TTYGLASS_DIAGNOSTICS_URL;
  const token = options.token ?? process.env.TTYGLASS_DIAGNOSTICS_TOKEN;
  if (endpoint === undefined || token === undefined || !isLoopbackEndpoint(endpoint)) {
    return undefined;
  }
  return { endpoint, token };
}

export async function sendTtyglassDiagnostic(
  record: DiagnosticRecord,
  options: SendDiagnosticOptions = {},
): Promise<boolean> {
  const connection = resolveConnection(options);
  if (connection === undefined) {
    return false;
  }

  try {
    const fetchImplementation = options.fetchImplementation ?? fetch;
    const response = await fetchImplementation(connection.endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${connection.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(record),
      signal: AbortSignal.timeout(options.timeoutMilliseconds ?? 1_000),
    });
    if (!response.ok) {
      throw new Error(`ttyglass diagnostics returned HTTP ${response.status}`);
    }
    return true;
  } catch (error) {
    if (options.throwOnError === true) {
      throw error;
    }
    return false;
  }
}

function fromJsonLine(line: string, source?: string): DiagnosticRecord {
  try {
    const parsed = JSON.parse(line) as unknown;
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { ...(source === undefined ? {} : { source }), event: 'log', message: line };
    }
    const input = parsed as Record<string, unknown>;
    const fields = { ...input };
    delete fields.time;
    delete fields.level;
    delete fields.name;
    delete fields.source;
    delete fields.event;
    delete fields.msg;
    delete fields.message;
    const time = input.time;
    const recordSource =
      typeof input.source === 'string' ? input.source : typeof input.name === 'string' ? input.name : source;
    const message =
      typeof input.message === 'string' ? input.message : typeof input.msg === 'string' ? input.msg : undefined;
    return {
      ...(typeof time === 'string' || typeof time === 'number' ? { time } : {}),
      ...(recordSource === undefined ? {} : { source: recordSource }),
      level:
        typeof input.level === 'number'
          ? (pinoLevels.get(input.level) ?? 'info')
          : typeof input.level === 'string'
            ? (input.level as DiagnosticLevel)
            : 'info',
      event: typeof input.event === 'string' ? input.event : 'log',
      ...(message === undefined ? {} : { message }),
      fields,
    };
  } catch {
    return { ...(source === undefined ? {} : { source }), event: 'log', message: line };
  }
}

export function createTtyglassSink(options: TtyglassSinkOptions = {}): TtyglassSink {
  let buffered = '';
  let pending = Promise.resolve();

  function enqueue(line: string): void {
    if (line.length === 0) {
      return;
    }
    const record = fromJsonLine(line, options.source);
    pending = pending
      .then(async () => {
        await sendTtyglassDiagnostic(record, { ...options, throwOnError: true });
      })
      .catch((error: unknown) => {
        options.onError?.(error);
      });
  }

  return {
    write(chunk): boolean {
      buffered += typeof chunk === 'string' ? chunk : new TextDecoder().decode(chunk);
      for (;;) {
        const newline = buffered.indexOf('\n');
        if (newline < 0) {
          break;
        }
        enqueue(buffered.slice(0, newline).trimEnd());
        buffered = buffered.slice(newline + 1);
      }
      return true;
    },
    async flush(): Promise<void> {
      enqueue(buffered.trimEnd());
      buffered = '';
      await pending;
    },
  };
}
