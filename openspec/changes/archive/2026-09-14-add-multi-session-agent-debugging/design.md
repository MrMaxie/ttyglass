## Context

The existing native runtime owns one command and starts its PTY only after one browser WebSocket connects. Version 1.1.0 needs one local service to own many sessions while several browser and headless clients can independently attach.

## Goals

- Support `n clients : 1 ttyglass service : n PTY sessions`.
- Preserve exact argument boundaries received by ttyglass.
- Make browser, stateless CLI, JSONL agent, and MCP equal session clients.
- Keep all network listeners on `127.0.0.1` and all management access local and authenticated.
- Keep output and snapshots bounded while allowing incremental reads.

## Decisions

### Per-user service and control plane

The first client starts a background service when no live descriptor exists. `ttyglass serve` runs the same service in the foreground. A private runtime directory contains a descriptor with the service process id, loopback origin, control endpoint, and a management token. Windows uses a Named Pipe and POSIX uses a Unix Domain Socket. Dead descriptors are removed before starting a replacement.

### Session ownership

A central `SessionManager` owns a map of sessions. Each session contains its id, private token, mode, complete argv, display command, resolved shell, dimensions, status, diagnostics, ANSI buffer, terminal screen, PTY host, and attached client count. A session starts its PTY immediately and independently of the browser.

Command sessions execute the received argv and can restart. Terminal sessions execute the resolved user shell and cannot restart. Shell resolution is `--shell`, `SHELL`, Windows `pwsh`, `powershell.exe`, `ComSpec`, then POSIX `/bin/sh`.

### Shared client behavior

Every attached client receives current metadata, snapshot/output bootstrap, diagnostics, status, and subsequent broadcasts. Input writes are serialized by the session lock in receipt order. A valid resize updates the session dimensions, resizes the PTY, increments the snapshot revision, and broadcasts the new size; the last accepted resize wins.

### Output model

PTY output is broadcast live, applied to the terminal screen, and appended to a byte-oriented ANSI ring buffer with a default 1 MiB capacity. Incremental output responses expose start and end offsets, truncation, and Base64 bytes. Screen responses expose revision, dimensions, lines, cursor position and visibility, and session status.

### Authentication

The management token authorizes session listing and creation. Each session has a distinct token that authorizes only that session's browser and diagnostics endpoints. Tokens are carried in the private descriptor, control-plane messages, standard input, or URL fragments. They are not printed by `ttyglass sessions` and are not placed in process arguments.

### Retention and shutdown

When the last client detaches, a running session receives a five-minute grace deadline. Reattachment clears it. Completed sessions remain readable for five minutes. Explicit stop terminates the entire owned process tree. The service closes all PTY hosts during shutdown and exits when no clients or retained sessions remain.

### Browser routing

The root route opens the previously selected retained session or the first session when no selection exists, and renders an instructional empty state when none exist. A direct session route renders one terminal with a custom toolbar menu for switching sessions. The toolbar shows the TTYGLASS identity and packaged version before the selector. CLI, JSONL, and MCP starts may assign a session name independently of the command. The selector prefers that name and otherwise uses the first 25 characters of the display command with `(...)` when truncated. The complete display command remains available as the option title and through Copy. The Display theme selector uses the same custom menu component. Its option list is positioned on a viewport layer so opening it does not expand or scroll the Display panel. Terminal mode displays `No command` and does not render Restart.

### Agent and MCP protocols

`ttyglass agent` is JSON-RPC 2.0 over JSONL and maps requests to the same local control operations used by stateless commands. `ttyglass mcp` is an MCP 2025-11-25 stdio server. Stdout contains protocol messages only and operational logs go to stderr. Both protocols can attach to more than one session in one process.

## Compatibility

`ttyglass -- <command> [arguments...]` continues to create and attach to a command session. The TypeScript diagnostics helpers remain source compatible. `ttyglass --` is still invalid and now suggests removing the separator to start a terminal session.

## Risks and mitigations

- Shared mutable session state is protected by manager and per-session locks; socket broadcasts copy client lists before I/O.
- Service crashes could orphan processes; each native PTY host owns its child in a process group or kill-on-close Job Object and the service closes every host on shutdown.
- Terminal emulation drift is covered by focused alternate-screen, Unicode, cursor, and resize tests.
- Authentication regressions are covered by invalid-token and session-isolation tests.
