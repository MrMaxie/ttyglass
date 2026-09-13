# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/MrMaxie/ttyglass/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/MrMaxie/ttyglass/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MrMaxie/ttyglass/releases/tag/v1.0.0
