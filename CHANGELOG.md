# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-14

### Added

- Run multiple named or automatically labeled command and shell sessions through one per-user ttyglass service and switch between them from the browser toolbar.
- Inspect and control retained terminal sessions without a browser through stateless CLI commands, persistent JSONL, or MCP stdio tools.
- Read terminal screen snapshots, cursor state, dimensions, status, diagnostics, and bounded raw ANSI output with absolute offsets.
- Exercise the complete runtime with TypeScript, Go, Rust, Nim, and Ruby TUI fixtures.

### Changed

- Start PTY or ConPTY sessions immediately instead of waiting for a browser connection, and retain disconnected or completed sessions for five minutes.
- Allow several clients to share input and resize control for one session while keeping parallel sessions isolated.
- Display the complete received argument vector in command-session metadata and use `No command` for non-restartable shell sessions.
- Replace native session and theme selects with consistent custom menus, including an explicit empty state when no sessions exist.

### Security

- Authenticate the per-user Named Pipe or Unix Domain Socket control plane with a private management token and scope browser and diagnostics tokens to one session.
- Keep HTTP and WebSocket listeners on loopback and clean up complete process trees when sessions stop or the owning service exits.

## [1.0.1] - 2026-09-13

### Fixed

- Verify the published package through a fresh `npx` cache so a local source checkout cannot be mistaken for a successful registry installation.
- Document how to force registry resolution when manually testing ttyglass from its own source checkout.

## [1.0.0] - 2026-09-13

### Added

- Run an arbitrary TUI command through a real PTY or Windows ConPTY session and interact with it from a local browser.
- Preview terminal output with built-in color schemes and dynamic or exact fixed terminal dimensions.
- Collect bounded, structured application diagnostics separately from terminal output using a dependency-free HTTP contract.
- Send diagnostics from TypeScript directly or through a JSON-line sink compatible with loggers such as Pino.
- Guide Codex and Claude Code through safe visual TUI inspection with packaged agent skills.

### Security

- Restrict the observer and diagnostics service to loopback, authenticate each session with a fresh token, validate browser origins, and terminate the owned terminal process tree when the session ends.

[Unreleased]: https://github.com/MrMaxie/ttyglass/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/MrMaxie/ttyglass/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/MrMaxie/ttyglass/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MrMaxie/ttyglass/releases/tag/v1.0.0
