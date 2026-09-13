import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const targets = new Map([
  ['win32:x64', { directory: 'win32-x64', executable: 'ttyglass.exe' }],
  ['linux:x64', { directory: 'linux-x64-gnu', executable: 'ttyglass' }],
  ['darwin:x64', { directory: 'darwin-x64', executable: 'ttyglass' }],
  ['darwin:arm64', { directory: 'darwin-arm64', executable: 'ttyglass' }],
]);

const target = targets.get(`${process.platform}:${process.arch}`);
if (target === undefined) {
  throw new Error(`ttyglass does not support native builds for ${process.platform}/${process.arch}`);
}

const output = resolve('packages', target.directory, 'bin', target.executable);
mkdirSync(dirname(output), { recursive: true });

const result = spawnSync(
  'nimble',
  ['c', '-d:release', `--out:${output}`, '--nimcache:.local/nimcache/release', 'src/ttyglass.nim'],
  { shell: false, stdio: 'inherit' },
);
if (result.error !== undefined) {
  throw result.error;
}
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
