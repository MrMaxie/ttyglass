import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

import { WebSocket } from 'ws';

const fixtures = [
  {
    name: 'TypeScript',
    command: process.execPath,
    arguments: [resolve('tests', 'typescript', 'main.ts'), '--duration-ms', '10000'],
  },
  {
    name: 'Go',
    command: 'go',
    arguments: ['-C', resolve('tests', 'go'), 'run', '.', '--duration-ms', '10000'],
  },
  {
    name: 'Rust',
    command: 'cargo',
    arguments: [
      'run',
      '--quiet',
      '--manifest-path',
      resolve('tests', 'rust', 'Cargo.toml'),
      '--target-dir',
      resolve('.local', 'rust-target'),
      '--',
      '--duration-ms',
      '10000',
    ],
  },
  {
    name: 'Nim',
    command: resolve('.local', 'ttyglass-stress-nim.exe'),
    arguments: ['--duration-ms', '10000'],
  },
];

async function reservePort() {
  const server = createServer();
  await new Promise((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const address = server.address();
  await new Promise((resolveClose) => server.close(resolveClose));
  assert.equal(typeof address, 'object');
  return address.port;
}

async function waitUntil(predicate, description, timeout = 20_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value) return value;
    await delay(25);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function terminalOutput(messages) {
  return messages
    .filter((message) => message.type === 'output')
    .map((message) => message.data)
    .join('');
}

function diagnosticEntries(messages) {
  return messages.flatMap((message) => {
    if (message.type === 'log') return [message.entry];
    if (message.type === 'logs') return message.entries;
    return [];
  });
}

async function verifyFixture(fixture) {
  const port = await reservePort();
  const cli = spawn(
    process.execPath,
    ['dist/cli.js', '--port', String(port), '--', fixture.command, ...fixture.arguments],
    { cwd: process.cwd(), stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true },
  );
  let cliOutput = '';
  cli.stdout.setEncoding('utf8');
  cli.stderr.setEncoding('utf8');
  cli.stdout.on('data', (data) => {
    cliOutput += data;
  });
  cli.stderr.on('data', (data) => {
    cliOutput += data;
  });

  let socket;
  try {
    const printedUrl = await waitUntil(() => {
      const match = cliOutput.match(/ttyglass: (http:\/\/127\.0\.0\.1:\d+\/#token=\S+)/);
      return match?.[1];
    }, `${fixture.name} ttyglass startup`);
    const url = new URL(printedUrl);
    const token = new URLSearchParams(url.hash.slice(1)).get('token');
    assert.ok(token);

    const messages = [];
    socket = new WebSocket(`${url.origin}/terminal?token=${token}`, { origin: url.origin });
    socket.on('message', (raw) => messages.push(JSON.parse(raw.toString())));
    await new Promise((resolveOpen, rejectOpen) => {
      socket.once('open', resolveOpen);
      socket.once('error', rejectOpen);
    });

    await waitUntil(() => terminalOutput(messages).includes(`| ${fixture.name} |`), `${fixture.name} screen`);
    await waitUntil(
      () => diagnosticEntries(messages).some((entry) => entry.event === 'fixture.ready'),
      `${fixture.name} ready diagnostic`,
    );

    socket.send(JSON.stringify({ type: 'resize', cols: 72, rows: 22 }));
    await waitUntil(() => terminalOutput(messages).includes('viewport 72x22'), `${fixture.name} resize`);

    socket.send(JSON.stringify({ type: 'input', data: 'b\r' }));
    await waitUntil(
      () => diagnosticEntries(messages).some((entry) => entry.event === 'burst.item'),
      `${fixture.name} diagnostic burst`,
    );

    socket.send(JSON.stringify({ type: 'input', data: 'q\r' }));
    await waitUntil(
      () => messages.some((message) => message.type === 'status' && message.state === 'exited'),
      `${fixture.name} orderly exit`,
    );
    console.log(`verified ${fixture.name}`);
  } finally {
    socket?.close();
    if (cli.exitCode === null) cli.kill('SIGTERM');
    await Promise.race([
      new Promise((resolveExit) => cli.once('exit', resolveExit)),
      delay(2_000).then(() => {
        if (cli.exitCode === null) cli.kill('SIGKILL');
      }),
    ]);
  }
}

const requestedFixture = process.argv[2]?.toLowerCase();
const selectedFixtures = fixtures.filter(
  (fixture) => requestedFixture === undefined || fixture.name.toLowerCase() === requestedFixture,
);
assert.notEqual(selectedFixtures.length, 0, `Unknown fixture: ${process.argv[2]}`);

for (const fixture of selectedFixtures) {
  await verifyFixture(fixture);
}
