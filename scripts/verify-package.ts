import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

interface CommandResult {
  stderr: string;
  stdout: string;
}

interface Manifest {
  name: string;
  optionalDependencies: Record<string, string>;
  version: string;
}

interface PackFile {
  path: string;
}

interface PackMetadata {
  files: PackFile[];
  name: string;
  version: string;
}

type PackOutput = PackMetadata[] | Record<string, PackMetadata>;

interface WebSocketWithHeaders {
  new (url: string, options: { headers: Record<string, string> }): WebSocket;
}

const projectDirectory = resolve(import.meta.dirname, '..');
const privateDirectory = resolve(projectDirectory, '.local', 'package-check');
const nodeModulesDirectory = resolve(dirname(process.execPath), 'node_modules');
const npmRunner =
  process.platform === 'win32'
    ? { command: process.execPath, prefix: [resolve(nodeModulesDirectory, 'npm', 'bin', 'npm-cli.js')] }
    : { command: 'npm', prefix: [] };
const npxRunner =
  process.platform === 'win32'
    ? { command: process.execPath, prefix: [resolve(nodeModulesDirectory, 'npm', 'bin', 'npx-cli.js')] }
    : { command: 'npx', prefix: [] };
const platformTargets = new Map([
  ['win32:x64', { directory: 'win32-x64', executable: 'ttyglass.exe', packageName: '@maxiedev/ttyglass-win32-x64' }],
  [
    'linux:x64',
    { directory: 'linux-x64-gnu', executable: 'ttyglass', packageName: '@maxiedev/ttyglass-linux-x64-gnu' },
  ],
  ['darwin:x64', { directory: 'darwin-x64', executable: 'ttyglass', packageName: '@maxiedev/ttyglass-darwin-x64' }],
  [
    'darwin:arm64',
    { directory: 'darwin-arm64', executable: 'ttyglass', packageName: '@maxiedev/ttyglass-darwin-arm64' },
  ],
]);

const target = platformTargets.get(`${process.platform}:${process.arch}`);
assert.ok(target, `unsupported verification platform ${process.platform}/${process.arch}`);

async function run(
  command: string,
  argumentsValue: string[],
  options: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<CommandResult> {
  const child = spawn(command, argumentsValue, {
    cwd: options.cwd ?? projectDirectory,
    env: options.env ?? process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (data: string) => {
    stdout += data;
  });
  child.stderr.on('data', (data: string) => {
    stderr += data;
  });
  const exitCode = await new Promise<number | null>((resolveExit, rejectExit) => {
    child.once('error', rejectExit);
    child.once('exit', resolveExit);
  });
  if (exitCode !== 0) {
    throw new Error(`${command} ${argumentsValue.join(' ')} failed with exit code ${exitCode}\n${stdout}${stderr}`);
  }
  return { stdout, stderr };
}

function runTool(
  runner: { command: string; prefix: string[] },
  argumentsValue: string[],
  options: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<CommandResult> {
  return run(runner.command, [...runner.prefix, ...argumentsValue], {
    ...options,
    env: { ...process.env, npm_config_dry_run: 'false', ...options.env },
  });
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

async function terminateProcessTree(child: ReturnType<typeof spawn>): Promise<void> {
  if (child.exitCode !== null || child.pid === undefined) return;
  if (process.platform === 'win32') {
    const killer = spawn('taskkill.exe', ['/pid', String(child.pid), '/t', '/f'], {
      stdio: 'ignore',
      windowsHide: true,
    });
    await new Promise<void>((resolveExit) => killer.once('exit', () => resolveExit()));
    return;
  }
  child.kill('SIGTERM');
}

async function verifySession(executable: string): Promise<void> {
  const port = await reservePort();
  const fixture = resolve(projectDirectory, 'test', 'fixtures', 'tui-fixture.ts');
  const child = spawn(executable, ['--port', String(port), '--', process.execPath, fixture], {
    cwd: projectDirectory,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });
  let output = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (data: string) => {
    output += data;
  });
  child.stderr.on('data', (data: string) => {
    output += data;
  });
  let socket: WebSocket | undefined;
  try {
    const printedUrl = await waitUntil(
      () => output.match(/ttyglass: (http:\/\/127\.0\.0\.1:\d+\/#token=\S+)/)?.[1],
      'CLI startup',
    );
    const url = new URL(printedUrl);
    const token = new URLSearchParams(url.hash.slice(1)).get('token');
    assert.ok(token);
    const messages: Array<Record<string, unknown>> = [];
    const RuntimeWebSocket = WebSocket as unknown as WebSocketWithHeaders;
    socket = new RuntimeWebSocket(`${url.origin.replace('http', 'ws')}/terminal?token=${token}`, {
      headers: { Origin: url.origin },
    });
    socket.addEventListener('message', (event) => {
      messages.push(JSON.parse(String(event.data)) as Record<string, unknown>);
    });
    await new Promise<void>((resolveOpen, rejectOpen) => {
      socket?.addEventListener('open', () => resolveOpen(), { once: true });
      socket?.addEventListener('error', rejectOpen, { once: true });
    });
    await waitUntil(
      () => messages.find((message) => message.type === 'status' && message.state === 'running'),
      'native terminal startup',
    );
    socket.send(JSON.stringify({ type: 'resize', cols: 88, rows: 26 }));
    socket.send(JSON.stringify({ type: 'input', data: 's' }));
    await waitUntil(
      () => messages.find((message) => message.type === 'output' && String(message.data).includes('SIZE 88x26')),
      'native terminal resize',
    );
    await waitUntil(
      () =>
        messages.find(
          (message) => message.type === 'log' && (message.entry as { event?: string }).event === 'fixture.ready',
        ),
      'application diagnostic',
    );
    socket.send(JSON.stringify({ type: 'input', data: 'q' }));
    await waitUntil(
      () => messages.find((message) => message.type === 'status' && message.state === 'exited'),
      'native terminal exit',
    );
  } finally {
    socket?.close();
    await terminateProcessTree(child);
  }
}

async function pack(directory: string, destination: string): Promise<string> {
  const packed = await runTool(npmRunner, [
    'pack',
    directory,
    '--silent',
    '--ignore-scripts',
    '--pack-destination',
    destination,
  ]);
  const archiveName = packed.stdout.trim().split(/\r?\n/).at(-1);
  assert.ok(archiveName, `npm pack did not return an archive for ${directory}`);
  return resolve(destination, archiveName);
}

async function verifyNoMjs(): Promise<void> {
  const sourceFiles = await run('git', ['ls-files', '--cached', '--others', '--exclude-standard', '*.mjs']);
  const existingMjs: string[] = [];
  for (const path of sourceFiles.stdout.trim().split(/\r?\n/).filter(Boolean)) {
    try {
      await access(resolve(projectDirectory, path));
      existingMjs.push(path);
    } catch {
      // A tracked deletion is part of the migration away from .mjs.
    }
  }
  assert.deepEqual(existingMjs, [], 'repository source must not contain .mjs files');
}

await mkdir(privateDirectory, { recursive: true });
const workspace = await mkdtemp(join(privateDirectory, 'run-'));

try {
  await verifyNoMjs();
  const manifest = JSON.parse(await readFile(resolve(projectDirectory, 'package.json'), 'utf8')) as Manifest;
  assert.equal(manifest.optionalDependencies[target.packageName], manifest.version);
  const publishedMode = process.argv[2] === '--published';
  assert.equal(process.argv.length <= 3, true, 'usage: verify-package.ts [--published]');

  const consumer = resolve(workspace, 'consumer');
  await mkdir(consumer);
  await writeFile(resolve(consumer, 'package.json'), `${JSON.stringify({ private: true, type: 'module' }, null, 2)}\n`);

  if (publishedMode) {
    await runTool(
      npmRunner,
      [
        'install',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--no-package-lock',
        `${manifest.name}@${manifest.version}`,
      ],
      { cwd: consumer },
    );
  } else {
    const rootArchive = await pack(projectDirectory, workspace);
    const platformArchive = await pack(resolve(projectDirectory, 'packages', target.directory), workspace);

    const dryRun = await runTool(npmRunner, ['pack', '--dry-run', '--json', '--ignore-scripts']);
    const packOutput = JSON.parse(dryRun.stdout) as PackOutput;
    const metadata = Array.isArray(packOutput)
      ? packOutput.find((entry) => entry.name === 'ttyglass')
      : packOutput.ttyglass;
    assert.ok(metadata, 'npm pack did not describe ttyglass');
    const packagedPaths = new Set(metadata.files.map((file) => file.path));
    for (const requiredPath of [
      'CHANGELOG.md',
      'dist/cli.js',
      'dist/index.js',
      'dist/index.d.ts',
      'docs/diagnostics.md',
      'docs/typescript.md',
      'skills/codex/SKILL.md',
      'skills/claude/SKILL.md',
    ]) {
      assert.ok(packagedPaths.has(requiredPath), `package is missing ${requiredPath}`);
    }
    assert.equal(
      [...packagedPaths].some((path) => path.startsWith('frontend/')),
      false,
    );
    assert.equal(
      [...packagedPaths].some((path) => path.endsWith('.mjs')),
      false,
    );

    await runTool(
      npmRunner,
      ['install', '--ignore-scripts', '--no-audit', '--no-fund', '--no-package-lock', rootArchive, platformArchive],
      { cwd: consumer },
    );
  }

  const executable = resolve(consumer, 'node_modules', target.packageName, 'bin', target.executable);
  const version = await runTool(npxRunner, ['--yes', 'ttyglass', '--version'], { cwd: consumer });
  assert.equal(version.stdout.trim(), manifest.version);
  await run(
    process.execPath,
    [
      '--input-type=module',
      '--eval',
      "import { createTtyglassSink, sendTtyglassDiagnostic } from 'ttyglass'; if (typeof createTtyglassSink !== 'function' || typeof sendTtyglassDiagnostic !== 'function') process.exit(1);",
    ],
    { cwd: consumer },
  );
  await verifySession(executable);
  process.stdout.write(
    `verified ttyglass@${manifest.version} through npx, native PTY, diagnostics, and package import\n`,
  );
} finally {
  await rm(workspace, { force: true, recursive: true });
}
