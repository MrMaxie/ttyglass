## 1. Multi-session runtime

- [x] 1.1 Add the per-user service descriptor and local control transport with dead-service recovery.
- [x] 1.2 Add `SessionManager`, immediate command and shell session startup, shared input and resize, retention, restart, stop, and process-tree cleanup.
- [x] 1.3 Add bounded raw ANSI output and terminal screen snapshots.

## 2. Public clients

- [x] 2.1 Add the compatible foreground command and terminal forms plus `serve`, `start`, and stateless session commands.
- [x] 2.2 Add the persistent JSON-RPC 2.0 JSONL agent protocol.
- [x] 2.3 Add the MCP 2025-11-25 stdio server and exact MCP client test dependency.

## 3. Browser and diagnostics

- [x] 3.1 Add default and empty session states, a custom named-session selector, direct session routes, multi-client WebSockets, reconnect bootstrap, and session-scoped diagnostics.
- [x] 3.2 Show the complete lossless display command and hide Restart for terminal sessions.

## 4. Documentation and fixtures

- [x] 4.1 Finish the Astro site and generated docs with terminal, session CLI, and MCP examples.
- [x] 4.2 Update Codex and Claude skills for multi-session and headless usage.
- [x] 4.3 Include the Ruby diagnostic fixture in `check-tuis` and `verify-tuis` alongside TypeScript, Go, Rust, and Nim.

## 5. Verification and release preparation

- [x] 5.1 Cover parallel sessions and clients, all client surfaces, ordering, resize, reconnect, retention, shell mode, full argv, snapshots, truncation, authorization, dead service recovery, and cleanup.
- [x] 5.2 Run `just fmt`, `just check`, `just build`, `just test`, `just check-tuis`, `just verify-tuis`, `just docs-check`, `just docs-build`, and `just package-check`.
- [x] 5.3 Complete browser QA for default selection and switching between two sessions at wide and narrow viewports.
- [x] 5.4 Set every distributable version to 1.1.0 and add Added, Changed, and Security changelog outcomes.
- [x] 5.5 Archive this change into the accepted specifications after all tasks pass.
