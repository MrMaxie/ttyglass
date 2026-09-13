## Context

The public npm contract must remain `ttyglass`, `npx ttyglass`, or `nubx ttyglass`, while the runtime implementation must be native Nim. The browser still needs an xterm.js and Svelte application, and TypeScript applications still need optional importable diagnostics helpers.

## Decisions

### Keep the runtime in one native executable

The public executable owns cligen option parsing, Mummy HTTP and WebSocket handling, diagnostics normalization with jsony, chronicles logging, authentication, and lifecycle coordination. The same executable has a hidden PTY-host mode so terminal ownership can be isolated behind a small framed IPC protocol without shipping another binary.

### Use native PTY implementations

Windows uses the ConPTY API and a Job Object that kills only the process tree owned by the session. POSIX uses `forkpty`, terminal resize through `TIOCSWINSZ`, and a dedicated process group. Terminal output remains raw bytes inside the native IPC frame and is never parsed as JSON.

### Embed the Svelte build

Vite produces stable `app.js` and `app.css` names. Nim embeds the generated HTML, JavaScript, CSS, and logo at compile time. A published native package therefore contains one executable and no separate browser asset tree.

### Use an esbuild-style npm package boundary

The root package declares four exact-version optional dependencies. Its TypeScript launcher maps `process.platform` and `process.arch` to one package and spawns that executable with inherited standard streams. Consumer installation never invokes Nim or a native compiler.

### Publish as a verified package set

CI builds and tests each executable on its target architecture. A release job downloads those exact artifacts, publishes the four native packages and root package under a temporary `candidate` dist-tag, verifies an exact registry install, and promotes the complete set to `latest` only after that smoke test passes.

## Safety boundaries

- HTTP remains bound to `127.0.0.1` and session access requires a fresh token and exact origin.
- The observed command receives raw arguments and is not evaluated through a shell, except that Windows batch files use the operating system command processor required to execute them.
- Native IPC frames are length-delimited and bounded.
- Application diagnostics remain authenticated, shape-limited, depth-limited, and bounded in memory.
- Browser disconnect and server shutdown terminate only the owned PTY process tree.
