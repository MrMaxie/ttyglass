import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { nativeExecutable } from './helpers.ts';

test('reports the native package version', () => {
  const result = spawnSync(nativeExecutable(), ['--version'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), '1.0.1');
});

test('documents the exact command separator and public options', () => {
  const result = spawnSync(nativeExecutable(), ['--help'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /ttyglass \[options\] -- <command> \[arguments\.\.\.\]/);
  assert.match(result.stdout, /--diagnostics-limit/);
  assert.match(result.stdout, /--no-open/);
});

test('rejects a missing command separator', () => {
  const result = spawnSync(nativeExecutable(), ['node'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Separate ttyglass options from the TUI command with --/);
});
