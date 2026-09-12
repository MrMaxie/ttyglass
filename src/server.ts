import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { createServer as createHttpServer } from 'node:http';
import { basename, dirname, extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { IPty } from 'node-pty';
import * as pty from 'node-pty';
import { WebSocket, WebSocketServer } from 'ws';

import type { DiagnosticLevel, NormalizedDiagnosticRecord, TtyglassController, TtyglassStartOptions } from './types.js';

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const packageDirectory = resolve(moduleDirectory, '..');
const frontendDirectory = resolve(packageDirectory, 'frontend', 'dist');
const logoPath = resolve(packageDirectory, 'assets', 'ttyglass-logo.svg');
const host = '127.0.0.1';
const maximumDiagnosticBodyBytes = 64 * 1024;
const allowedLevels = new Set<DiagnosticLevel>(['trace', 'debug', 'info', 'warn', 'error', 'fatal']);

const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
  ['.svg', 'image/svg+xml; charset=utf-8'],
  ['.woff2', 'font/woff2'],
]);

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function tokenMatches(header: string | undefined, token: string): boolean {
  if (header === undefined || !header.startsWith('Bearer ')) {
    return false;
  }
  const candidate = Buffer.from(header.slice('Bearer '.length));
  const expected = Buffer.from(token);
  return candidate.length === expected.length && timingSafeEqual(candidate, expected);
}

function safeText(value: unknown, maximumLength: number): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed.slice(0, maximumLength);
}

function normalizeLevel(value: unknown): DiagnosticLevel {
  if (typeof value === 'string' && allowedLevels.has(value as DiagnosticLevel)) {
    return value as DiagnosticLevel;
  }
  if (typeof value === 'number') {
    if (value >= 60) return 'fatal';
    if (value >= 50) return 'error';
    if (value >= 40) return 'warn';
    if (value >= 30) return 'info';
    if (value >= 20) return 'debug';
    return 'trace';
  }
  return 'info';
}

function normalizeTime(value: unknown): string {
  const date =
    typeof value === 'number' || typeof value === 'string'
      ? new Date(value)
      : value instanceof Date
        ? value
        : new Date();
  return Number.isNaN(date.valueOf()) ? new Date().toISOString() : date.toISOString();
}

function normalizeValue(value: unknown, depth: number): unknown {
  if (value === null || typeof value === 'boolean' || typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    return value.slice(0, 2_048);
  }
  if (depth >= 3) {
    throw new HttpError(400, 'Diagnostic fields exceed the maximum depth.');
  }
  if (Array.isArray(value)) {
    if (value.length > 32) {
      throw new HttpError(400, 'Diagnostic arrays may contain at most 32 items.');
    }
    return value.map((item) => normalizeValue(item, depth + 1));
  }
  if (typeof value === 'object' && value !== null) {
    const entries = Object.entries(value);
    if (entries.length > 32) {
      throw new HttpError(400, 'Diagnostic objects may contain at most 32 fields.');
    }
    return Object.fromEntries(entries.map(([key, item]) => [key.slice(0, 128), normalizeValue(item, depth + 1)]));
  }
  throw new HttpError(400, 'Diagnostic fields must contain JSON values.');
}

function normalizeDiagnostic(value: unknown, defaultSource: string): NormalizedDiagnosticRecord {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new HttpError(400, 'Each diagnostic record must be a JSON object.');
  }
  const input = value as Record<string, unknown>;
  const fields = input.fields === undefined ? {} : normalizeValue(input.fields, 0);
  if (typeof fields !== 'object' || fields === null || Array.isArray(fields)) {
    throw new HttpError(400, 'Diagnostic fields must be a JSON object.');
  }
  const source = safeText(input.source, 64) ?? defaultSource;
  const event = safeText(input.event, 128) ?? 'message';
  const message = safeText(input.message, 2_048);
  return {
    time: normalizeTime(input.time),
    source,
    level: normalizeLevel(input.level),
    event,
    ...(message === undefined ? {} : { message }),
    fields: fields as Record<string, unknown>,
  };
}

async function readRequestBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > maximumDiagnosticBodyBytes) {
      throw new HttpError(413, 'Diagnostic request is too large.');
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function parseDiagnosticBody(body: string, contentType: string | undefined): unknown[] {
  if (body.trim().length === 0) {
    throw new HttpError(400, 'Diagnostic request body is empty.');
  }
  if (contentType?.toLowerCase().startsWith('application/json')) {
    return [JSON.parse(body) as unknown];
  }
  const lines = body.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length > 100) {
    throw new HttpError(400, 'A diagnostic request may contain at most 100 records.');
  }
  return lines.map((line) => JSON.parse(line) as unknown);
}

function writeText(response: ServerResponse, status: number, message: string): void {
  response.writeHead(status, {
    'Cache-Control': 'no-store',
    'Content-Type': 'text/plain; charset=utf-8',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(`${message}\n`);
}

function send(socket: WebSocket, message: object): void {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

function environmentValue(environment: NodeJS.ProcessEnv | Record<string, string>, name: string): string | undefined {
  const normalizedName = name.toLowerCase();
  return Object.entries(environment).find(([key]) => key.toLowerCase() === normalizedName)?.[1];
}

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

export function resolvePtyCommand(
  command: string,
  environment: NodeJS.ProcessEnv | Record<string, string>,
  platform = process.platform,
  cwd = process.cwd(),
): string {
  if (platform !== 'win32' || extname(command) !== '') {
    return command;
  }

  const extensions = (environmentValue(environment, 'PATHEXT') ?? '.COM;.EXE;.BAT;.CMD')
    .split(';')
    .filter((extension) => extension.length > 0);
  const hasPathSeparator = /[\\/]/.test(command);
  const searchDirectories = hasPathSeparator
    ? ['']
    : (environmentValue(environment, 'PATH') ?? '')
        .split(';')
        .map((directory) => directory.replace(/^"|"$/g, ''))
        .filter((directory) => directory.length > 0);

  for (const directory of searchDirectories) {
    const basePath = hasPathSeparator ? resolve(cwd, command) : join(directory, command);
    for (const extension of extensions) {
      const candidate = `${basePath}${extension}`;
      if (isFile(candidate)) {
        return candidate;
      }
    }
  }

  return command;
}

async function terminateProcessTree(pid: number): Promise<void> {
  if (process.platform === 'win32') {
    await new Promise<void>((resolveTermination) => {
      const killer = spawn('taskkill.exe', ['/PID', String(pid), '/T', '/F'], {
        windowsHide: true,
        stdio: 'ignore',
      });
      killer.once('error', () => resolveTermination());
      killer.once('exit', () => resolveTermination());
    });
    return;
  }
  try {
    process.kill(-pid, 'SIGTERM');
  } catch {
    try {
      process.kill(pid, 'SIGTERM');
    } catch {
      // The process already exited.
    }
  }
}

class TerminalSession {
  private process: IPty | undefined;
  private running = false;
  private exitPromise = Promise.resolve();
  private resolveExit: (() => void) | undefined;
  private stopPromise: Promise<void> | undefined;

  constructor(
    private readonly socket: WebSocket,
    private readonly options: Required<Pick<TtyglassStartOptions, 'command' | 'commandArguments' | 'cwd'>>,
    private readonly environment: Record<string, string>,
  ) {}

  start(cols = 100, rows = 30): void {
    if (this.running) {
      return;
    }
    const safeColumns = Number.isInteger(cols) && cols >= 2 && cols <= 1_000 ? cols : 100;
    const safeRows = Number.isInteger(rows) && rows >= 1 && rows <= 500 ? rows : 30;
    try {
      const terminalProcess = pty.spawn(
        resolvePtyCommand(this.options.command, this.environment, process.platform, this.options.cwd),
        this.options.commandArguments,
        {
          name: 'xterm-256color',
          cols: safeColumns,
          rows: safeRows,
          cwd: this.options.cwd,
          env: this.environment,
          useConpty: process.platform === 'win32',
        },
      );
      this.process = terminalProcess;
      this.running = true;
      this.stopPromise = undefined;
      this.exitPromise = new Promise((resolveExit) => {
        this.resolveExit = resolveExit;
      });
      send(this.socket, { type: 'status', state: 'running', pid: terminalProcess.pid });
      terminalProcess.onData((data) => send(this.socket, { type: 'output', data }));
      terminalProcess.onExit(({ exitCode, signal }) => {
        this.running = false;
        send(this.socket, {
          type: 'status',
          state: 'exited',
          pid: terminalProcess.pid,
          exitCode,
          signal,
        });
        this.resolveExit?.();
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      send(this.socket, { type: 'status', state: 'failed', message });
    }
  }

  write(data: string): void {
    if (this.running) {
      this.process?.write(data);
    }
  }

  resize(cols: unknown, rows: unknown): void {
    if (
      !this.running ||
      !Number.isInteger(cols) ||
      !Number.isInteger(rows) ||
      (cols as number) < 2 ||
      (rows as number) < 1 ||
      (cols as number) > 1_000 ||
      (rows as number) > 500
    ) {
      return;
    }
    this.process?.resize(cols as number, rows as number);
  }

  stop(_reason: string): Promise<void> {
    if (!this.running || this.process === undefined) {
      return Promise.resolve();
    }
    this.stopPromise ??= this.stopProcess().finally(() => {
      this.stopPromise = undefined;
    });
    return this.stopPromise;
  }

  private async stopProcess(): Promise<void> {
    const terminalProcess = this.process;
    if (terminalProcess === undefined) {
      return;
    }
    terminalProcess.write('\x03');
    await Promise.race([this.exitPromise, delay(600)]);
    if (this.running) {
      await terminateProcessTree(terminalProcess.pid);
      await Promise.race([this.exitPromise, delay(1_500)]);
    }
    if (this.running) {
      try {
        terminalProcess.kill();
      } catch {
        // The PTY closed between the state check and fallback.
      }
    }
  }
}

function resolveStaticPath(pathname: string): string | undefined {
  if (pathname === '/') {
    return resolve(frontendDirectory, 'index.html');
  }
  if (pathname === '/ttyglass-logo.svg') {
    return logoPath;
  }
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return undefined;
  }
  const candidate = resolve(frontendDirectory, `.${decoded}`);
  const boundary = `${frontendDirectory}${sep}`;
  return candidate.startsWith(boundary) ? candidate : undefined;
}

export async function startTtyglass(options: TtyglassStartOptions): Promise<TtyglassController> {
  if (options.command.trim().length === 0) {
    throw new Error('A command is required.');
  }
  const port = options.port ?? 0;
  if (!Number.isInteger(port) || port < 0 || port > 65_535) {
    throw new Error('Port must be an integer from 0 to 65535.');
  }
  const diagnosticsLimit = options.diagnosticsLimit ?? 500;
  if (!Number.isInteger(diagnosticsLimit) || diagnosticsLimit < 1 || diagnosticsLimit > 5_000) {
    throw new Error('Diagnostics limit must be an integer from 1 to 5000.');
  }

  const commandArguments = [...(options.commandArguments ?? [])];
  const cwd = resolve(options.cwd ?? process.cwd());
  const token = randomBytes(32).toString('base64url');
  const diagnostics: NormalizedDiagnosticRecord[] = [];
  const sockets = new Set<WebSocket>();
  let origin = '';
  let activeSession: TerminalSession | undefined;
  let activeSocket: WebSocket | undefined;
  let stopping = false;
  let resolveClosed: (() => void) | undefined;
  const closed = new Promise<void>((resolveClose) => {
    resolveClosed = resolveClose;
  });

  function appendDiagnostic(entry: NormalizedDiagnosticRecord): void {
    diagnostics.push(entry);
    if (diagnostics.length > diagnosticsLimit) {
      diagnostics.splice(0, diagnostics.length - diagnosticsLimit);
    }
    for (const socket of sockets) {
      send(socket, { type: 'log', entry });
    }
  }

  const httpServer = createHttpServer(async (request, response) => {
    try {
      const requestUrl = new URL(request.url ?? '/', origin);
      if (request.method === 'POST' && requestUrl.pathname === '/api/diagnostics') {
        if (!tokenMatches(request.headers.authorization, token)) {
          writeText(response, 401, 'Unauthorized');
          return;
        }
        const body = await readRequestBody(request);
        let values: unknown[];
        try {
          values = parseDiagnosticBody(body, request.headers['content-type']);
        } catch (error) {
          if (error instanceof SyntaxError) {
            throw new HttpError(400, 'Diagnostic request contains invalid JSON.');
          }
          throw error;
        }
        const normalized = values.map((value) => normalizeDiagnostic(value, basename(options.command)));
        for (const entry of normalized) {
          appendDiagnostic(entry);
        }
        response.writeHead(202, {
          'Cache-Control': 'no-store',
          'Content-Type': 'application/json; charset=utf-8',
          'X-Content-Type-Options': 'nosniff',
        });
        response.end(JSON.stringify({ accepted: normalized.length }));
        return;
      }
      if (request.method !== 'GET') {
        writeText(response, 404, 'Not found');
        return;
      }
      const staticPath = resolveStaticPath(requestUrl.pathname);
      if (staticPath === undefined) {
        writeText(response, 404, 'Not found');
        return;
      }
      try {
        const content = await readFile(staticPath);
        response.writeHead(200, {
          'Cache-Control': 'no-store',
          'Content-Security-Policy':
            "default-src 'self'; connect-src 'self' ws://127.0.0.1:*; style-src 'self' 'unsafe-inline'; img-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
          'Content-Type': contentTypes.get(extname(staticPath)) ?? 'application/octet-stream',
          'Referrer-Policy': 'no-referrer',
          'X-Content-Type-Options': 'nosniff',
        });
        response.end(content);
      } catch {
        writeText(response, 404, 'Not found');
      }
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : 'Internal server error';
      writeText(response, status, message);
    }
  });

  const webSocketServer = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });
  httpServer.on('upgrade', (request, socket, head) => {
    const requestUrl = new URL(request.url ?? '/', origin);
    if (
      requestUrl.pathname !== '/terminal' ||
      requestUrl.searchParams.get('token') !== token ||
      request.headers.origin !== origin
    ) {
      socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    webSocketServer.handleUpgrade(request, socket, head, (webSocket) => {
      webSocketServer.emit('connection', webSocket, request);
    });
  });

  webSocketServer.on('connection', (socket) => {
    if (activeSocket !== undefined && activeSocket.readyState !== WebSocket.CLOSED) {
      socket.close(1013, 'The terminal is already open in another client.');
      return;
    }
    activeSocket = socket;
    sockets.add(socket);
    send(socket, { type: 'metadata', command: basename(options.command) });
    send(socket, { type: 'logs', entries: diagnostics });
    const environment = Object.fromEntries(
      Object.entries(process.env).filter((entry): entry is [string, string] => entry[1] !== undefined),
    );
    environment.TERM = 'xterm-256color';
    environment.COLORTERM = 'truecolor';
    environment.TTYGLASS_DIAGNOSTICS_URL = `${origin}/api/diagnostics`;
    environment.TTYGLASS_DIAGNOSTICS_TOKEN = token;
    delete environment.NO_COLOR;
    const session = new TerminalSession(socket, { command: options.command, commandArguments, cwd }, environment);
    activeSession = session;
    session.start();
    let lifecycle = Promise.resolve();

    socket.on('message', (raw) => {
      let message: Record<string, unknown>;
      try {
        const parsed = JSON.parse(raw.toString()) as unknown;
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
          return;
        }
        message = parsed as Record<string, unknown>;
      } catch {
        return;
      }
      if (message.type === 'input' && typeof message.data === 'string') {
        session.write(message.data);
      } else if (message.type === 'binary' && typeof message.data === 'string') {
        session.write(Buffer.from(message.data, 'base64').toString('binary'));
      } else if (message.type === 'resize') {
        session.resize(message.cols, message.rows);
      } else if (message.type === 'restart') {
        lifecycle = lifecycle.then(async () => {
          await session.stop('restart');
          session.start(
            typeof message.cols === 'number' ? message.cols : undefined,
            typeof message.rows === 'number' ? message.rows : undefined,
          );
        });
      } else if (message.type === 'clearLogs') {
        diagnostics.length = 0;
        for (const client of sockets) {
          send(client, { type: 'logsCleared' });
        }
      }
    });

    socket.once('close', () => {
      sockets.delete(socket);
      lifecycle = lifecycle
        .then(() => session.stop('browser disconnected'))
        .finally(() => {
          if (activeSocket === socket) {
            activeSocket = undefined;
            activeSession = undefined;
          }
        });
    });
  });

  await new Promise<void>((resolveListen, rejectListen) => {
    httpServer.once('error', rejectListen);
    httpServer.listen(port, host, resolveListen);
  });
  const address = httpServer.address();
  if (address === null || typeof address === 'string') {
    throw new Error('ttyglass could not determine its loopback address.');
  }
  origin = `http://${host}:${address.port}`;
  const url = `${origin}/#token=${token}`;

  async function stop(_reason = 'requested'): Promise<void> {
    if (stopping) {
      return closed;
    }
    stopping = true;
    for (const socket of sockets) {
      socket.close(1001, 'ttyglass is stopping');
    }
    await activeSession?.stop('server shutdown');
    await Promise.all([
      new Promise<void>((resolveClose) => webSocketServer.close(() => resolveClose())),
      new Promise<void>((resolveClose) => httpServer.close(() => resolveClose())),
    ]);
    resolveClosed?.();
  }

  return {
    url,
    origin,
    diagnosticsUrl: `${origin}/api/diagnostics`,
    token,
    closed,
    stop,
  };
}
