import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';

import { nativeExecutable } from './helpers.ts';

interface SessionInfo {
  argv: string[];
  displayCommand: string;
  mode: string;
  name: string;
  restartable: boolean;
  sessionId: string;
  token: string;
  url: string;
}

interface ServerMessage {
  argv?: string[];
  cols?: number;
  data?: string;
  displayCommand?: string;
  entries?: Array<{ event?: string }>;
  entry?: { event?: string };
  exitCode?: number;
  mode?: string;
  name?: string;
  pid?: number;
  restartable?: boolean;
  rows?: number;
  state?: string;
  type?: string;
}

interface NodeWebSocketConstructor {
  new (url: string, options: { headers: Record<string, string> }): WebSocket;
}

const environment = { ...process.env, TTYGLASS_RETENTION_MS: '3000' };

test.after(async () => {
  await delay(3_500);
});

function cli(argumentsValue: string[], input?: string): string {
  const result = spawnSync(nativeExecutable(), argumentsValue, {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: environment,
    input,
    maxBuffer: 4 * 1024 * 1024,
    windowsHide: true,
  });
  assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
  return result.stdout;
}

function startFixture(extraArguments: string[] = []): SessionInfo {
  const output = cli([
    'start',
    '--json',
    '--',
    process.execPath,
    resolve('test', 'fixtures', 'tui-fixture.ts'),
    ...extraArguments,
  ]);
  return JSON.parse(output) as SessionInfo;
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

async function connect(session: SessionInfo): Promise<{ messages: ServerMessage[]; socket: WebSocket }> {
  const messages: ServerMessage[] = [];
  const url = new URL(session.url);
  const RuntimeWebSocket = WebSocket as unknown as NodeWebSocketConstructor;
  const socket = new RuntimeWebSocket(
    `${url.origin.replace('http', 'ws')}/terminal?session=${session.sessionId}&token=${session.token}`,
    { headers: { Origin: url.origin } },
  );
  socket.addEventListener('message', (event) => {
    messages.push(JSON.parse(String(event.data)) as ServerMessage);
  });
  await new Promise<void>((resolveOpen, rejectOpen) => {
    socket.addEventListener('open', () => resolveOpen(), { once: true });
    socket.addEventListener('error', rejectOpen, { once: true });
  });
  return { messages, socket };
}

function output(messages: ServerMessage[]): string {
  return messages
    .filter((message) => message.type === 'output')
    .map((message) => message.data ?? '')
    .join('');
}

function processExists(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function servicePid(origin: string): number {
  for (const entry of readdirSync(tmpdir(), { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith('ttyglass-')) continue;
    try {
      const descriptor = JSON.parse(readFileSync(resolve(tmpdir(), entry.name, 'service.json'), 'utf8')) as {
        origin?: string;
        pid?: number;
      };
      if (descriptor.origin === origin && typeof descriptor.pid === 'number') return descriptor.pid;
    } catch {
      // A stale or concurrently removed descriptor is not the active service.
    }
  }
  throw new Error(`Could not find the service descriptor for ${origin}`);
}

test('one service runs parallel sessions and broadcasts one session to two browser clients', async () => {
  const firstSession = startFixture();
  const secondSession = startFixture();
  assert.notEqual(firstSession.sessionId, secondSession.sessionId);

  const first = await connect(firstSession);
  const secondClient = await connect(firstSession);
  const isolated = await connect(secondSession);
  try {
    const origin = new URL(firstSession.url).origin;
    const sessionUrlParameters = new URLSearchParams(new URL(firstSession.url).hash.slice(1));
    assert.equal(sessionUrlParameters.get('token'), firstSession.token);
    const managementToken = sessionUrlParameters.get('managementToken');
    assert.ok(managementToken, 'Session URLs must authorize the shared session picker');
    const authorizedList = await fetch(`${origin}/api/sessions`, {
      headers: { Authorization: `Bearer ${managementToken}` },
    });
    assert.equal(authorizedList.status, 200);
    assert.match(await authorizedList.text(), new RegExp(secondSession.sessionId));

    const unauthorizedList = await fetch(`${origin}/api/sessions`, {
      headers: { Authorization: `Bearer ${firstSession.token}` },
    });
    assert.equal(unauthorizedList.status, 401);
    const unauthorizedDiagnostics = await fetch(`${origin}/api/sessions/${firstSession.sessionId}/diagnostics`, {
      method: 'POST',
      headers: { Authorization: 'Bearer wrong', 'Content-Type': 'application/json' },
      body: '{"event":"must.not.appear"}',
    });
    assert.equal(unauthorizedDiagnostics.status, 401);

    const metadata = await waitUntil(
      () => first.messages.find((message) => message.type === 'metadata'),
      'session metadata',
    );
    assert.deepEqual(metadata.argv, [process.execPath, resolve('test', 'fixtures', 'tui-fixture.ts')]);
    assert.equal(metadata.displayCommand, firstSession.displayCommand);
    assert.equal(metadata.mode, 'command');
    assert.equal(metadata.restartable, true);

    first.socket.send(JSON.stringify({ type: 'resize', cols: 80, rows: 24 }));
    await waitUntil(
      () =>
        first.messages.some((message) => message.type === 'resize' && message.cols === 80 && message.rows === 24)
          ? true
          : undefined,
      'first resize receipt',
    );
    secondClient.socket.send(JSON.stringify({ type: 'resize', cols: 92, rows: 27 }));
    await waitUntil(
      () =>
        first.messages.some((message) => message.type === 'resize' && message.cols === 92 && message.rows === 27)
          ? true
          : undefined,
      'last resize receipt',
    );
    first.socket.send(JSON.stringify({ type: 'input', data: 's' }));
    await waitUntil(() => (output(secondClient.messages).includes('SIZE 92x27') ? true : undefined), 'last resize');

    first.socket.send(JSON.stringify({ type: 'input', data: 'x' }));
    await waitUntil(() => (output(first.messages).includes('INPUT "x"') ? true : undefined), 'first shared input');
    secondClient.socket.send(JSON.stringify({ type: 'input', data: 'y' }));
    await waitUntil(() => (output(first.messages).includes('INPUT "y"') ? true : undefined), 'shared input');
    const sharedOutput = output(first.messages);
    assert.ok(sharedOutput.indexOf('INPUT "x"') < sharedOutput.indexOf('INPUT "y"'));
    assert.equal(output(isolated.messages).includes('INPUT "x"'), false);

    const screen = JSON.parse(cli(['screen', firstSession.sessionId, '--json'])) as {
      cols: number;
      lines: string[];
      rows: number;
      status: string;
    };
    assert.equal(screen.cols, 92);
    assert.equal(screen.rows, 27);
    assert.ok(screen.lines.some((line) => line.includes('INPUT "y"')));

    const sessions = cli(['sessions', '--json']);
    assert.match(sessions, new RegExp(firstSession.sessionId));
    assert.match(sessions, new RegExp(secondSession.sessionId));
    assert.equal(sessions.includes(firstSession.token), false);
  } finally {
    first.socket.close();
    secondClient.socket.close();
    isolated.socket.close();
    cli(['stop', firstSession.sessionId]);
    cli(['stop', secondSession.sessionId]);
  }
});

test('stateless CLI and JSONL agent control the same retained session without a browser', async () => {
  const session = startFixture();
  try {
    cli(['resize', session.sessionId, '--cols', '84', '--rows', '25']);
    cli(['input', session.sessionId, '--text', 's']);
    await waitUntil(() => {
      const screen = JSON.parse(cli(['screen', session.sessionId, '--json'])) as { lines: string[] };
      return screen.lines.some((line) => line.includes('SIZE 84x25')) ? true : undefined;
    }, 'CLI-controlled screen');

    const requests = [
      { jsonrpc: '2.0', id: 1, method: 'attach_session', params: { sessionId: session.sessionId } },
      { jsonrpc: '2.0', id: 2, method: 'send_input', params: { sessionId: session.sessionId, text: 'z' } },
      { jsonrpc: '2.0', id: 3, method: 'read_screen', params: { sessionId: session.sessionId } },
      { jsonrpc: '2.0', id: 4, method: 'detach_session', params: { sessionId: session.sessionId } },
    ];
    const responses = cli(['agent'], `${requests.map((request) => JSON.stringify(request)).join('\n')}\n`)
      .trim()
      .split(/\r?\n/)
      .map((line) => JSON.parse(line) as { error?: unknown; id: number });
    assert.deepEqual(
      responses.map((response) => response.id),
      [1, 2, 3, 4],
    );
    assert.equal(
      responses.some((response) => response.error !== undefined),
      false,
    );

    await waitUntil(() => {
      const raw = JSON.parse(cli(['output', session.sessionId, '--json'])) as { data: string };
      return Buffer.from(raw.data, 'base64').toString().includes('INPUT "z"') ? true : undefined;
    }, 'agent input in raw output');
  } finally {
    cli(['stop', session.sessionId]);
  }
});

test('session tokens are isolated and reconnect restores retained output', async () => {
  const firstSession = startFixture();
  const secondSession = startFixture();
  const first = await connect(firstSession);
  first.socket.send(JSON.stringify({ type: 'input', data: 'r' }));
  await waitUntil(() => (output(first.messages).includes('INPUT "r"') ? true : undefined), 'initial output');
  first.socket.close();

  const wrong = { ...firstSession, token: secondSession.token };
  await assert.rejects(connect(wrong));

  const reconnected = await connect(firstSession);
  try {
    await waitUntil(() => (output(reconnected.messages).includes('INPUT "r"') ? true : undefined), 'replayed output');
  } finally {
    reconnected.socket.close();
    cli(['stop', firstSession.sessionId]);
    cli(['stop', secondSession.sessionId]);
  }
});

test('terminal mode resolves and starts a shell without restart support', async () => {
  const requestedShell = process.platform === 'win32' ? (process.env.ComSpec ?? 'cmd.exe') : '/bin/sh';
  const session = JSON.parse(cli(['start', '--json', '--shell', requestedShell])) as SessionInfo;
  const browser = await connect(session);
  try {
    assert.equal(session.mode, 'terminal');
    assert.equal(session.displayCommand, 'No command');
    assert.equal(session.restartable, false);
    assert.equal(session.argv.length, 1);
    assert.equal(session.argv[0], session.shell);
    assert.equal(session.shell.toLowerCase(), requestedShell.toLowerCase());
    const terminalState = await waitUntil(
      () => browser.messages.find((message) => message.type === 'status' && message.state !== 'starting')?.state,
      'resolved shell status',
    );
    const terminalStatus = JSON.parse(cli(['status', session.sessionId, '--json'])) as {
      message: string;
      state: string;
    };
    assert.equal(terminalState, 'running', JSON.stringify(terminalStatus));

    const restart = spawnSync(nativeExecutable(), ['restart', session.sessionId], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: environment,
      windowsHide: true,
    });
    assert.equal(restart.status, 2);
    assert.match(restart.stderr, /Terminal sessions cannot be restarted/);
  } finally {
    browser.socket.close();
    spawnSync(nativeExecutable(), ['stop', session.sessionId], {
      cwd: process.cwd(),
      env: environment,
      windowsHide: true,
    });
  }
});

test('CLI naming and metadata preserve complete argv values and a lossless display command', () => {
  const session = JSON.parse(
    cli([
      'start',
      '--name',
      'CLI session',
      '--json',
      '--',
      process.execPath,
      '-e',
      'process.exit(0)',
      '',
      'value with spaces',
      "quote'value",
    ]),
  ) as SessionInfo;
  try {
    assert.equal(session.name, 'CLI session');
    assert.deepEqual(session.argv, [process.execPath, '-e', 'process.exit(0)', '', 'value with spaces', "quote'value"]);
    assert.match(session.displayCommand, /''/);
    assert.match(session.displayCommand, /'value with spaces'/);
    assert.match(session.displayCommand, /quote'\\''value/);
  } finally {
    cli(['stop', session.sessionId]);
  }
});

test('raw ANSI output reports absolute offsets after bounded-buffer truncation', async () => {
  const session = JSON.parse(
    cli(['start', '--json', '--', process.execPath, '-e', "process.stdout.write('x'.repeat(1100000))"]),
  ) as SessionInfo;
  try {
    await waitUntil(() => {
      const status = JSON.parse(cli(['status', session.sessionId, '--json'])) as { state: string };
      return status.state === 'exited' ? true : undefined;
    }, 'large-output process exit');
    const result = JSON.parse(cli(['output', session.sessionId, '--from', '0', '--json'])) as {
      data: string;
      endOffset: number;
      startOffset: number;
      truncated: boolean;
    };
    assert.equal(result.truncated, true);
    assert.ok(result.startOffset > 0);
    assert.ok(result.endOffset > result.startOffset);
    assert.ok(Buffer.from(result.data, 'base64').byteLength <= 1024 * 1024);
  } finally {
    cli(['stop', session.sessionId]);
  }
});

test('an unattached running session expires after the configured grace period', async () => {
  const session = startFixture();
  await delay(3_400);
  const status = spawnSync(nativeExecutable(), ['status', session.sessionId, '--json'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    env: environment,
    windowsHide: true,
  });
  assert.equal(status.status, 2);
  assert.match(status.stderr, /Unknown ttyglass session/);
});

test('a dead singleton is replaced and its complete process tree is cleaned up', async () => {
  const session = JSON.parse(
    cli([
      'start',
      '--json',
      '--',
      process.execPath,
      '-e',
      "const{spawn}=require('node:child_process');const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)']);console.log('TREE:'+process.pid+':'+child.pid);setInterval(()=>{},1000)",
    ]),
  ) as SessionInfo;
  let rootPid = 0;
  let childPid = 0;
  let recovered: SessionInfo | undefined;
  const browser = await connect(session);
  try {
    await waitUntil(() => {
      const match = /TREE:(\d+):(\d+)/u.exec(output(browser.messages));
      if (match === null) return undefined;
      rootPid = Number(match[1]);
      childPid = Number(match[2]);
      return true;
    }, 'process tree PIDs');
    assert.equal(processExists(rootPid), true);
    assert.equal(processExists(childPid), true);

    const pid = servicePid(new URL(session.url).origin);
    process.kill(pid, 'SIGKILL');
    await waitUntil(
      () => (!processExists(rootPid) && !processExists(childPid) ? true : undefined),
      'service-owned process tree cleanup',
    );

    recovered = startFixture();
    assert.notEqual(recovered.sessionId, session.sessionId);
  } finally {
    browser.socket.close();
    if (recovered !== undefined) cli(['stop', recovered.sessionId]);
    if (rootPid > 0 && processExists(rootPid)) process.kill(rootPid, 'SIGKILL');
    if (childPid > 0 && processExists(childPid)) process.kill(childPid, 'SIGKILL');
  }
});
