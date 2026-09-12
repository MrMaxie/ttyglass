import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';

import { WebSocket } from 'ws';

import { resolvePtyCommand } from '../dist/server.js';

async function reservePort() {
  const server = createServer();
  await new Promise((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const address = server.address();
  await new Promise((resolveClose) => server.close(resolveClose));
  return address.port;
}

async function waitUntil(predicate, description, timeout = 15_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value) {
      return value;
    }
    await delay(25);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function processExists(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

test('resolves a bare Windows command through PATH and PATHEXT', () => {
  const command = process.platform === 'win32' ? 'node' : 'node';
  const resolvedCommand = resolvePtyCommand(command, process.env, process.platform);

  if (process.platform === 'win32') {
    assert.match(resolvedCommand, /node\.exe$/i);
    assert.notEqual(resolvedCommand, command);
  } else {
    assert.equal(resolvedCommand, command);
  }
});

async function connect(origin, token) {
  const messages = [];
  const socket = new WebSocket(`${origin}/terminal?token=${token}`, { origin });
  socket.on('message', (raw) => messages.push(JSON.parse(raw.toString())));
  await new Promise((resolveOpen, rejectOpen) => {
    socket.once('open', resolveOpen);
    socket.once('error', rejectOpen);
  });
  return { socket, messages };
}

test('runs the CLI with real ConPTY or PTY input, resize, diagnostics, restart, and cleanup', async (t) => {
  const port = await reservePort();
  const fixture = resolve('test', 'fixtures', 'tui-fixture.mjs');
  const child = spawn(process.execPath, ['dist/cli.js', '--port', String(port), '--', process.execPath, fixture], {
    cwd: process.cwd(),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let cliOutput = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (data) => {
    cliOutput += data;
  });
  child.stderr.on('data', (data) => {
    cliOutput += data;
  });
  t.after(() => {
    if (child.exitCode === null) {
      child.kill('SIGTERM');
    }
  });

  const printedUrl = await waitUntil(() => {
    const match = cliOutput.match(/ttyglass: (http:\/\/127\.0\.0\.1:\d+\/#token=\S+)/);
    return match?.[1];
  }, 'CLI startup');
  const url = new URL(printedUrl);
  const origin = url.origin;
  const token = new URLSearchParams(url.hash.slice(1)).get('token');
  assert.ok(token);

  const unauthorizedDiagnostic = await fetch(`${origin}/api/diagnostics`, {
    method: 'POST',
    headers: { Authorization: 'Bearer wrong', 'Content-Type': 'application/json' },
    body: '{"event":"must.not.appear"}',
  });
  assert.equal(unauthorizedDiagnostic.status, 401);

  const excessiveDiagnostic = await fetch(`${origin}/api/diagnostics`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{"event":"too.deep","fields":{"a":{"b":{"c":{"d":1}}}}}',
  });
  assert.equal(excessiveDiagnostic.status, 400);

  const unauthorizedSocket = new WebSocket(`${origin}/terminal?token=wrong`, { origin });
  const unauthorizedStatus = await new Promise((resolveStatus, rejectStatus) => {
    unauthorizedSocket.once('unexpected-response', (_request, response) => {
      const statusCode = response.statusCode;
      response.resume();
      resolveStatus(statusCode);
    });
    unauthorizedSocket.once('open', () => rejectStatus(new Error('Unauthenticated socket unexpectedly opened.')));
    unauthorizedSocket.once('error', () => {});
  });
  assert.equal(unauthorizedStatus, 403);

  const first = await connect(origin, token);
  const started = await waitUntil(
    () => first.messages.find((message) => message.type === 'status' && message.state === 'running'),
    'first terminal startup',
  );
  assert.equal(processExists(started.pid), true);
  let output = '';
  await waitUntil(() => {
    output = first.messages
      .filter((message) => message.type === 'output')
      .map((message) => message.data)
      .join('');
    return output.includes('TTYGLASS_FIXTURE_READY');
  }, 'fixture output');
  await waitUntil(
    () => first.messages.find((message) => message.type === 'log' && message.entry.event === 'fixture.ready'),
    'dependency-free fixture diagnostic',
  );
  const diagnosticEntries = first.messages.flatMap((message) => {
    if (message.type === 'log') return [message.entry];
    if (message.type === 'logs') return message.entries;
    return [];
  });
  assert.equal(
    diagnosticEntries.some((entry) => entry.source === 'ttyglass'),
    false,
    'Diagnostics must contain only records emitted by the observed application.',
  );

  first.socket.send(JSON.stringify({ type: 'resize', cols: 88, rows: 26 }));
  first.socket.send(JSON.stringify({ type: 'input', data: 's' }));
  await waitUntil(() => {
    output = first.messages
      .filter((message) => message.type === 'output')
      .map((message) => message.data)
      .join('');
    return output.includes('SIZE 88x26');
  }, 'resized child terminal');
  first.socket.send(JSON.stringify({ type: 'binary', data: Buffer.from('x').toString('base64') }));
  await waitUntil(() => {
    output = first.messages
      .filter((message) => message.type === 'output')
      .map((message) => message.data)
      .join('');
    return output.includes('INPUT "x"');
  }, 'binary terminal input');

  first.socket.send(JSON.stringify({ type: 'restart', cols: 90, rows: 28 }));
  const restarted = await waitUntil(
    () =>
      first.messages.find(
        (message) => message.type === 'status' && message.state === 'running' && message.pid !== started.pid,
      ),
    'restarted terminal',
  );
  assert.equal(processExists(restarted.pid), true);

  first.socket.close();
  await waitUntil(() => !processExists(restarted.pid), 'browser disconnect cleanup');
  child.kill('SIGTERM');
  const exit = await new Promise((resolveExit, rejectExit) => {
    child.once('exit', (code, signal) => resolveExit({ code, signal }));
    child.once('error', rejectExit);
  });
  assert.ok(exit.code === 0 || exit.signal === 'SIGTERM', cliOutput);
});
