import assert from 'node:assert/strict';
import test from 'node:test';

import { createTtyglassSink, sendTtyglassDiagnostic } from '../dist/index.js';

test('direct diagnostics are a no-op outside ttyglass', async () => {
  assert.equal(await sendTtyglassDiagnostic({ event: 'outside' }, { endpoint: '', token: '' }), false);
});

test('direct diagnostics use the authenticated loopback endpoint', async () => {
  let request: { init?: RequestInit; input?: string } = {};
  const sent = await sendTtyglassDiagnostic(
    { level: 'info', event: 'ready', fields: { count: 2 } },
    {
      endpoint: 'http://127.0.0.1:43210/api/diagnostics',
      token: 'test-token',
      fetchImplementation: async (input, init) => {
        request = { input: String(input), init };
        return new Response(null, { status: 202 });
      },
    },
  );

  assert.equal(sent, true);
  assert.equal(request.input, 'http://127.0.0.1:43210/api/diagnostics');
  assert.ok(request.init);
  assert.equal((request.init.headers as Record<string, string>).Authorization, 'Bearer test-token');
  assert.deepEqual(JSON.parse(String(request.init?.body)), {
    level: 'info',
    event: 'ready',
    fields: { count: 2 },
  });
});

test('the writable sink adapts Pino-style JSON lines', async () => {
  const records: unknown[] = [];
  const sink = createTtyglassSink({
    endpoint: 'http://127.0.0.1:43210/api/diagnostics',
    token: 'test-token',
    fetchImplementation: async (_input, init) => {
      records.push(JSON.parse(String(init?.body)));
      return new Response(null, { status: 202 });
    },
  });

  sink.write('{"level":40,"time":1700000000000,"name":"demo","msg":"slow","elapsed":125}\n');
  await sink.flush();

  assert.deepEqual(records, [
    {
      time: 1700000000000,
      source: 'demo',
      level: 'warn',
      event: 'log',
      message: 'slow',
      fields: { elapsed: 125 },
    },
  ]);
});
