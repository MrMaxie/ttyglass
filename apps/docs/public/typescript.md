# Optional TypeScript diagnostics

The package exports a direct sender and a small writable sink. Both are no-ops by default when the application does not run under ttyglass.

## Direct events

```ts
import { sendTtyglassDiagnostic } from 'ttyglass';

await sendTtyglassDiagnostic({
  source: 'checkout',
  level: 'info',
  event: 'screen.loaded',
  fields: { items: 3 },
});
```

## Pino destination

ttyglass does not depend on Pino. Its sink implements the `write(string)` destination contract used by Pino and other JSON-line loggers.

```ts
import pino from 'pino';
import { createTtyglassSink } from 'ttyglass';

const ttyglass = createTtyglassSink({ source: 'checkout' });
const logger = pino(ttyglass);

logger.info({ items: 3 }, 'Checkout screen is ready');

// Flush only when the process already has an orderly shutdown path.
await ttyglass.flush();
```

The sink maps Pino numeric levels and moves `time`, `level`, `name`, `msg`, and `message` into ttyglass record fields. Remaining JSON properties become diagnostic `fields`.

If a logger cannot accept a writable destination, call `sendTtyglassDiagnostic` from a temporary adapter instead. Remove the adapter when visual debugging no longer needs those events.
