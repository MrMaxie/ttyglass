## Why

ttyglass currently couples one process, one browser connection, and one PTY. That prevents CLI and MCP agents from sharing a terminal session, prevents more than one observed session from running at once, and makes browser presence control process lifetime.

## What Changes

- Introduce one per-user ttyglass service that owns multiple independent PTY or ConPTY sessions.
- Keep `ttyglass -- <command>` compatible and add a no-command terminal mode using the user's shell.
- Add stateless session commands, a persistent JSONL agent protocol, and an MCP stdio server.
- Allow browser, CLI, agent, and MCP clients to attach to the same session with shared output, input, resize, status, and diagnostics.
- Add bounded raw ANSI output and terminal screen snapshots for headless observation.
- Replace filename-only browser metadata with a lossless display of the received argument vector.
- Retain disconnected and completed sessions for a five-minute grace period and clean up complete process trees.
- Include the Astro documentation site and Ruby fixture in the 1.1.0 release scope.

## Non-goals

- Installing an operating-system service or retaining sessions across a computer restart.
- Remote access, non-loopback HTTP, Streamable HTTP MCP, or MCP resources.
- Changing the public TypeScript diagnostics API.
- Publishing, tagging, committing, pushing, or deploying version 1.1.0.

## Impact

- The native Nim executable becomes a per-user multi-session service and remains the owner of all runtime, transport, PTY, snapshot, and MCP behavior.
- The browser changes from a single implicit session to direct session pages with a persistent custom session selector, optional session names, concise command fallbacks, and an explicit no-session state.
- Agents can observe and control sessions without a browser.
- Package and native executable versions advance to 1.1.0 after verification.

---

## Archive Information

**Archived:** 2026-09-14
**Outcome:** Successfully implemented and verified

### Specs Updated

- `tui-observation`: multi-session PTY ownership, command and terminal modes, snapshots, output retention, reconnect behavior, and full argv metadata.
- `http-service`: default session selection, direct session routes, custom session and theme menus, an empty state, and session-scoped browser access.
- `agent-control`: shared local control plane, stateless CLI, JSONL agent, and MCP stdio interfaces.
