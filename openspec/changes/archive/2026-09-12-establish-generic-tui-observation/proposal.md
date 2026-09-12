## Why

Terminal user interfaces are difficult for coding agents to inspect and operate because their visual state exists inside a real terminal session. Project-specific preview harnesses solve this only after each tested project is adapted, which makes visual review slow and inconsistent.

## What Changes

- Replace the placeholder greeting service with a command-line tool that runs any supplied command in a real PTY or ConPTY session.
- Expose that terminal session through a loopback-only browser UI with keyboard input, resize propagation, restart controls, and separate diagnostics.
- Make the package usable locally through its `ttyglass` binary and structurally ready for later global, `npx`, and `nubx` installation without publishing it now.
- Provide an optional TypeScript diagnostics API, including a writable sink compatible with JSON-line loggers such as Pino.
- Document a dependency-free diagnostics protocol and include agent skills for Codex and Claude Code.

## Non-goals

- Publishing an npm package, creating a release, or installing ttyglass globally.
- Emulating terminal output without a real PTY or ConPTY.
- Modifying the project being observed or requiring it to depend on ttyglass.
- Exposing the observer on a non-loopback interface or uploading diagnostics.

## Impact

- The runtime changes from the initial Nim HTTP placeholder to a Node.js package because the required invocation contract is npm-native and the real cross-platform terminal bridge is provided by `node-pty`.
- The browser frontend remains TypeScript and xterm.js based.
- `node-pty` and `ws` become required runtime dependencies. Development tooling remains exact-versioned.
