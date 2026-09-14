import assert from 'node:assert/strict';
import test from 'node:test';

import { sessionLabel } from '../frontend/src/lib/session-label.ts';

test('session labels prefer explicit names and abbreviate unnamed commands to 25 characters', () => {
  assert.equal(sessionLabel('  API logs  ', 'ignored command'), 'API logs');
  assert.equal(sessionLabel('', 'No command'), 'No command');
  assert.equal(sessionLabel('', '1234567890123456789012345'), '1234567890123456789012345');
  assert.equal(sessionLabel('', '12345678901234567890123456'), '1234567890123456789012345(...)');
  assert.equal(sessionLabel('', 'abcdefghijklmnopqrstuvwx🙂z'), 'abcdefghijklmnopqrstuvwx🙂(...)');
});
