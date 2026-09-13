#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';

interface NativeTarget {
  executable: string;
  packageName: string;
}

const targets = new Map<string, NativeTarget>([
  ['win32:x64', { executable: 'ttyglass.exe', packageName: 'ttyglass-win32-x64' }],
  ['linux:x64', { executable: 'ttyglass', packageName: 'ttyglass-linux-x64-gnu' }],
  ['darwin:x64', { executable: 'ttyglass', packageName: 'ttyglass-darwin-x64' }],
  ['darwin:arm64', { executable: 'ttyglass', packageName: 'ttyglass-darwin-arm64' }],
]);

const target = targets.get(`${process.platform}:${process.arch}`);
if (target === undefined) {
  process.stderr.write(`ttyglass: unsupported platform ${process.platform}/${process.arch}\n`);
  process.exitCode = 1;
} else {
  const require = createRequire(import.meta.url);
  let manifestPath: string;
  try {
    manifestPath = require.resolve(`${target.packageName}/package.json`);
  } catch {
    process.stderr.write(
      `ttyglass: the native package ${target.packageName} is missing. Reinstall ttyglass without --no-optional.\n`,
    );
    process.exit(1);
  }

  const executable = resolve(dirname(manifestPath), 'bin', target.executable);
  const child = spawn(executable, process.argv.slice(2), {
    stdio: 'inherit',
    windowsHide: true,
  });
  child.once('error', (error) => {
    process.stderr.write(`ttyglass: could not start the native executable: ${error.message}\n`);
    process.exitCode = 1;
  });
  child.once('exit', (code, signal) => {
    if (signal !== null) {
      process.kill(process.pid, signal);
      return;
    }
    process.exitCode = code ?? 1;
  });
}
