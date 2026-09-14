import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { nativeExecutable } from './helpers.ts';

test('reports the native package version', () => {
  const result = spawnSync(nativeExecutable(), ['--version'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), '1.1.0');
});

test('documents terminal, session, agent, and MCP interfaces', () => {
  const result = spawnSync(nativeExecutable(), ['--help'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /ttyglass \[options\] \[-- <command> \[arguments\.\.\.\]\]/);
  assert.match(result.stdout, /--diagnostics-limit/);
  assert.match(result.stdout, /--name <name>/);
  assert.match(result.stdout, /ttyglass sessions \[--json\]/);
  assert.match(result.stdout, /ttyglass agent/);
  assert.match(result.stdout, /ttyglass mcp/);
  assert.match(result.stdout, /--no-open/);
});

test('rejects a command without the separator', () => {
  const result = spawnSync(nativeExecutable(), ['node'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Separate ttyglass options from the command with --/);
});

test('rejects an empty command separator with a terminal-mode hint', () => {
  const result = spawnSync(nativeExecutable(), ['--'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Remove the separator to start a terminal session/);
});
