## 1. Package and command surface

- [x] 1.1 Replace the placeholder runtime with an exact-versioned Node.js package and local `ttyglass` binary.
- [x] 1.2 Parse ttyglass options separately from the command after `--` and reject ambiguous input.

## 2. Real terminal observation

- [x] 2.1 Run the supplied command through PTY or ConPTY and propagate terminal output, input, binary input, and resize.
- [x] 2.2 Add loopback-only HTTP and authenticated WebSocket transport with bounded lifecycle cleanup.
- [x] 2.3 Build the xterm.js browser UI with process state, restart, and separate diagnostics.

## 3. Diagnostics and agent use

- [x] 3.1 Add authenticated, bounded diagnostics ingestion and document dependency-free logging.
- [x] 3.2 Export the optional TypeScript sender and writable JSON-line sink with a Pino example.
- [x] 3.3 Include separate Codex and Claude Code skills that explain purpose, safe use, and visual verification.

## 4. Verification and accepted behavior

- [x] 4.1 Add unit and real PTY integration coverage for parsing, transport, diagnostics, input, resize, restart, and cleanup.
- [x] 4.2 Run `just fmt`, `just check`, and `just build`.
- [x] 4.3 Verify the browser transport and packaged UI assets against a real local fixture without opening a browser, then archive the accepted OpenSpec change.
