# Diagnostics without a ttyglass library

ttyglass keeps application diagnostics separate from the terminal stream and from ttyglass's own process state. The Diagnostics panel contains only records submitted by the observed application. Every observed command receives two environment variables:

- `TTYGLASS_DIAGNOSTICS_URL`: a loopback-only HTTP endpoint for the current run.
- `TTYGLASS_DIAGNOSTICS_TOKEN`: the bearer token for that endpoint.

Send either one JSON object with `Content-Type: application/json` or newline-delimited JSON. Use this record shape:

```json
{
  "time": "2026-09-12T12:00:00.000Z",
  "source": "checkout",
  "level": "info",
  "event": "screen.loaded",
  "message": "Checkout screen is ready",
  "fields": {
    "items": 3
  }
}
```

All fields are optional. `level` accepts `trace`, `debug`, `info`, `warn`, `error`, or `fatal`. Unknown top-level fields are ignored. `fields` must contain JSON values, with at most 32 entries per object or array and at most three nested container levels. A request may contain up to 100 records and 64 KiB.

## Node.js standard library

```js
import { request } from 'node:http';

export function ttyglassDiagnostic(record) {
  const endpoint = process.env.TTYGLASS_DIAGNOSTICS_URL;
  const token = process.env.TTYGLASS_DIAGNOSTICS_TOKEN;
  if (!endpoint || !token) return;

  const body = JSON.stringify(record);
  const outgoing = request(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
    },
  });
  outgoing.on('error', () => {});
  outgoing.end(body);
}
```

## Python standard library

```python
import json
import os
import urllib.request


def ttyglass_diagnostic(record):
    endpoint = os.environ.get("TTYGLASS_DIAGNOSTICS_URL")
    token = os.environ.get("TTYGLASS_DIAGNOSTICS_TOKEN")
    if not endpoint or not token:
        return

    body = json.dumps(record).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        urllib.request.urlopen(request, timeout=1).close()
    except OSError:
        pass
```

Logging is optional and should never stop the observed application. Do not include secrets, credentials, personal data, or unrelated environment values. ttyglass keeps a bounded in-memory history for the current run and does not upload it.
