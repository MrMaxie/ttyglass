import { request } from 'node:http';

function sendDiagnostic(record: Record<string, unknown>): void {
  const endpoint = process.env.TTYGLASS_DIAGNOSTICS_URL;
  const token = process.env.TTYGLASS_DIAGNOSTICS_TOKEN;
  if (endpoint === undefined || token === undefined) return;
  const body = JSON.stringify(record);
  const outgoing = request(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Length': Buffer.byteLength(body),
      'Content-Type': 'application/json',
    },
  });
  outgoing.on('error', () => undefined);
  outgoing.end(body);
}

function finish(code = 0): never {
  process.stdout.write('\x1b[?1049l');
  process.exit(code);
}

process.stdin.setRawMode?.(true);
process.stdin.setEncoding('utf8');
process.stdin.resume();
process.stdout.write('\x1b[?1049h\x1b[2J\x1b[HTTYGLASS_FIXTURE_READY\r\n');
sendDiagnostic({
  source: 'fixture',
  level: 'info',
  event: 'fixture.ready',
  fields: { standardLibrary: true },
});

process.stdin.on('data', (data: string) => {
  for (const character of data) {
    if (character === '\x03' || character === 'q') {
      finish();
    } else if (character === 's') {
      process.stdout.write(`SIZE ${process.stdout.columns ?? 0}x${process.stdout.rows ?? 0}\r\n`);
    } else {
      process.stdout.write(`INPUT ${JSON.stringify(character)}\r\n`);
    }
  }
});

process.on('SIGTERM', () => finish());
