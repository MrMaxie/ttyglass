import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';

import { parseCliArguments, UsageError } from '../dist/options.js';

test('separates ttyglass options from the exact child command', () => {
  const initialCwd = process.cwd();
  const action = parseCliArguments([
    '--port',
    '0',
    '--diagnostics-limit',
    '42',
    '--cwd',
    'fixture',
    '--',
    'demo',
    '--flag',
    'value',
  ]);

  assert.equal(action.kind, 'run');
  assert.equal(action.options.command, 'demo');
  assert.deepEqual(action.options.commandArguments, ['--flag', 'value']);
  assert.equal(action.options.port, 0);
  assert.equal(action.options.diagnosticsLimit, 42);
  assert.equal(action.options.cwd, resolve(initialCwd, 'fixture'));
});

test('rejects a missing command separator', () => {
  assert.throws(() => parseCliArguments(['demo']), UsageError);
});

test('rejects an empty child command', () => {
  assert.throws(() => parseCliArguments(['--']), UsageError);
});

test('recognizes help and version without a child command', () => {
  assert.deepEqual(parseCliArguments(['--help']), { kind: 'help' });
  assert.deepEqual(parseCliArguments(['--version']), { kind: 'version' });
});
