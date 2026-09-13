import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { request } from 'node:http';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';

import { nativeExecutable } from './helpers.ts';

interface NodeWebSocketConstructor {
  new (url: string, options: { headers: Record<string, string> }): WebSocket;
}

interface ServerMessage {
  data?: string;
  entries?: DiagnosticEntry[];
  entry?: DiagnosticEntry;
  exitCode?: number;
  pid?: number;
  state?: string;
  type?: string;
}

interface DiagnosticEntry {
  event?: string;
  source?: string;
}

async function reservePort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const address = server.address();
  await new Promise<void>((resolveClose) => server.close(() => resolveClose()));
  assert.equal(typeof address, 'object');
  assert.ok(address);
  return address.port;
}

async function waitUntil<T>(predicate: () => T | undefined, description: string, timeout = 15_000): Promise<T> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value !== undefined && value !== false) return value;
    await delay(25);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function processExists(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function connect(origin: string, token: string): Promise<{ messages: ServerMessage[]; socket: WebSocket }> {
  const messages: ServerMessage[] = [];
  const RuntimeWebSocket = WebSocket as unknown as NodeWebSocketConstructor;
  const socket = new RuntimeWebSocket(`${origin.replace('http', 'ws')}/terminal?token=${token}`, {
    headers: { Origin: origin },
  });
  socket.addEventListener('message', (event) => {
    messages.push(JSON.parse(String(event.data)) as ServerMessage);
  });
  await new Promise<void>((resolveOpen, rejectOpen) => {
    socket.addEventListener('open', () => resolveOpen(), { once: true });
    socket.addEventListener('error', rejectOpen, { once: true });
  });
  return { messages, socket };
}

async function websocketStatus(origin: string): Promise<number> {
  return new Promise<number>((resolveStatus, rejectStatus) => {
    const upgrade = request(`${origin}/terminal?token=wrong`, {
      headers: {
        Connection: 'Upgrade',
        Origin: origin,
        'Sec-WebSocket-Key': Buffer.alloc(16).toString('base64'),
        'Sec-WebSocket-Version': '13',
        Upgrade: 'websocket',
      },
    });
    upgrade.once('response', (response) => {
      response.resume();
      resolveStatus(response.statusCode ?? 0);
    });
    upgrade.once('upgrade', () => rejectStatus(new Error('Unauthenticated WebSocket unexpectedly opened.')));
    upgrade.once('error', rejectStatus);
    upgrade.end();
  });
}

test('runs real ConPTY or PTY input, resize, diagnostics, restart, and cleanup', async (context) => {
  const port = await reservePort();
  const fixture = resolve('test', 'fixtures', 'tui-fixture.ts');
  const child = spawn(nativeExecutable(), ['--port', String(port), '--', process.execPath, fixture], {
    cwd: process.cwd(),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let cliOutput = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (data: string) => {
    cliOutput += data;
  });
  child.stderr.on('data', (data: string) => {
    cliOutput += data;
  });
  context.after(() => {
    if (child.exitCode === null) child.kill('SIGTERM');
  });

  const printedUrl = await waitUntil(
    () => cliOutput.match(/ttyglass: (http:\/\/127\.0\.0\.1:\d+\/#token=\S+)/)?.[1],
    'CLI startup',
  );
  const url = new URL(printedUrl);
  const token = new URLSearchParams(url.hash.slice(1)).get('token');
  assert.ok(token);

  const unauthorizedDiagnostic = await fetch(`${url.origin}/api/diagnostics`, {
    method: 'POST',
    headers: { Authorization: 'Bearer wrong', 'Content-Type': 'application/json' },
    body: '{"event":"must.not.appear"}',
  });
  assert.equal(unauthorizedDiagnostic.status, 401);
  assert.equal(await websocketStatus(url.origin), 403);

  const excessiveDiagnostic = await fetch(`${url.origin}/api/diagnostics`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{"event":"too.deep","fields":{"a":{"b":{"c":{"d":1}}}}}',
  });
  assert.equal(excessiveDiagnostic.status, 400);

  const first = await connect(url.origin, token);
  const started = await waitUntil(
    () => first.messages.find((message) => message.type === 'status' && message.state === 'running'),
    'first terminal startup',
  );
  assert.equal(processExists(started.pid ?? 0), true);
  first.socket.send(JSON.stringify({ type: 'resize', cols: 88, rows: 26 }));
  first.socket.send(JSON.stringify({ type: 'input', data: 's' }));
  await waitUntil(
    () => first.messages.find((message) => message.type === 'output' && message.data?.includes('SIZE 88x26')),
    'resized child terminal',
  );
  await waitUntil(
    () => first.messages.find((message) => message.type === 'log' && message.entry?.event === 'fixture.ready'),
    'fixture diagnostic',
  );
  const diagnostics = first.messages.flatMap((message) =>
    message.type === 'log' ? [message.entry] : message.type === 'logs' ? message.entries : [],
  );
  assert.equal(
    diagnostics.some((entry) => entry?.source === 'ttyglass'),
    false,
  );

  first.socket.send(JSON.stringify({ type: 'binary', data: Buffer.from('x').toString('base64') }));
  await waitUntil(
    () => first.messages.find((message) => message.type === 'output' && message.data?.includes('INPUT "x"')),
    'binary terminal input',
  );

  first.socket.send(JSON.stringify({ type: 'restart', cols: 90, rows: 28 }));
  const restarted = await waitUntil(
    () =>
      first.messages.find(
        (message) => message.type === 'status' && message.state === 'running' && message.pid !== started.pid,
      ),
    'restarted terminal',
  );
  assert.equal(processExists(restarted.pid ?? 0), true);

  first.socket.close();
  await waitUntil(() => (processExists(restarted.pid ?? 0) ? undefined : true), 'browser disconnect cleanup');
});
