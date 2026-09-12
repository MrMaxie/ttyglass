## Context

The existing service is a placeholder. The requested product is a reusable local observation boundary around arbitrary TUI commands. It must preserve actual terminal behavior, require no changes in the observed project, and be distributable later as one npm package.

## Decisions

### Use one Node.js package for the CLI, server, terminal bridge, and optional library

The public command and library contracts are npm contracts. A single package avoids a separately installed compiler or platform binary selection layer. `node-pty` provides POSIX PTY and Windows ConPTY behavior, while the Node.js standard library owns HTTP, lifecycle, tokens, and diagnostics ingestion.

### Start one terminal session per browser connection

The observed command starts only after an authenticated browser client connects. A second simultaneous terminal client is rejected so one command cannot be driven concurrently by multiple actors. Closing the client stops its process tree. Restart replaces only that terminal process.

### Keep access loopback-only and session-scoped

The server binds to `127.0.0.1`, chooses an available port by default, and generates an unguessable token. WebSocket upgrades require the exact origin and token. Diagnostic submissions require a bearer token. Static responses use restrictive browser headers and no-store caching.

### Keep diagnostics out of terminal output

The child receives `TTYGLASS_DIAGNOSTICS_URL` and `TTYGLASS_DIAGNOSTICS_TOKEN`. It may POST one JSON record or newline-delimited JSON using only its language standard library. ttyglass retains a bounded in-memory history and never uploads it.

### Offer a generic writable TypeScript sink

The package exports a direct diagnostic sender and a writable JSON-line sink. The sink follows the small `write(string)` contract used by Pino and similar loggers without depending on any logging framework.

## Safety boundaries

- ttyglass launches only the command supplied after `--`, without a shell.
- It inherits the requested working directory and environment but does not inspect or modify the observed project.
- Diagnostics accept an allowlisted record shape, bounded field depth, bounded request size, and bounded history.
- Shutdown attempts a graceful interrupt and then terminates only the recorded child process tree.
