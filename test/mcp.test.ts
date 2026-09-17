import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';

import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

import { isolatedEnvironment, nativeExecutable } from './helpers.ts';

interface ToolTextResult {
  content: Array<{ text: string; type: string }>;
  isError?: boolean;
}

function parsed(result: unknown): Record<string, unknown> {
  const value = result as ToolTextResult;
  assert.equal(value.isError, undefined);
  assert.equal(value.content[0]?.type, 'text');
  return JSON.parse(value.content[0]?.text ?? '{}') as Record<string, unknown>;
}

test('the exact MCP client can drive a ttyglass session over stdio', async () => {
  const transport = new StdioClientTransport({
    command: nativeExecutable(),
    args: ['mcp'],
    cwd: process.cwd(),
    env: { ...isolatedEnvironment, TTYGLASS_RETENTION_MS: '800' } as Record<string, string>,
    stderr: 'pipe',
  });
  const client = new Client({ name: 'ttyglass-test', version: '1.0.0' }, { capabilities: {} });
  await client.connect(transport);

  let sessionId = '';
  try {
    const tools = await client.listTools();
    assert.deepEqual(
      tools.tools.map((tool) => tool.name),
      [
        'list_sessions',
        'start_session',
        'attach_session',
        'detach_session',
        'get_status',
        'read_screen',
        'read_output',
        'send_input',
        'resize_terminal',
        'read_diagnostics',
        'restart_session',
        'stop_session',
      ],
    );

    const started = parsed(
      await client.callTool({
        name: 'start_session',
        arguments: {
          mode: 'command',
          name: 'MCP session',
          command: process.execPath,
          arguments: [resolve('test', 'fixtures', 'tui-fixture.ts')],
        },
      }),
    );
    sessionId = String(started.sessionId);
    assert.ok(sessionId);
    assert.equal(started.name, 'MCP session');

    parsed(await client.callTool({ name: 'attach_session', arguments: { sessionId } }));
    parsed(await client.callTool({ name: 'resize_terminal', arguments: { sessionId, cols: 86, rows: 26 } }));
    parsed(await client.callTool({ name: 'send_input', arguments: { sessionId, text: 's' } }));

    let snapshot: Record<string, unknown> = {};
    for (let attempt = 0; attempt < 100; attempt += 1) {
      snapshot = parsed(await client.callTool({ name: 'read_screen', arguments: { sessionId } }));
      if ((snapshot.lines as string[] | undefined)?.some((line) => line.includes('SIZE 86x26'))) break;
      await delay(25);
    }
    assert.ok((snapshot.lines as string[]).some((line) => line.includes('SIZE 86x26')));

    parsed(await client.callTool({ name: 'detach_session', arguments: { sessionId } }));
    parsed(await client.callTool({ name: 'stop_session', arguments: { sessionId } }));
    sessionId = '';
  } finally {
    if (sessionId) {
      await client.callTool({ name: 'stop_session', arguments: { sessionId } }).catch(() => undefined);
    }
    await client.close();
    await delay(1_000);
  }
});
