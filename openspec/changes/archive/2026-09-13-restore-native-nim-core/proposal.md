## Why

ttyglass is intended to be a small native terminal observer delivered through npm, but its first implementation placed the server, PTY ownership, and process lifecycle in Node.js. That made JavaScript the runtime core and removed the native binary boundary that is central to the project.

## What Changes

- Move the CLI, HTTP and WebSocket server, PTY or ConPTY ownership, process lifecycle, diagnostics ingestion, and embedded browser asset delivery to Nim.
- Keep TypeScript only for the npm launcher, optional diagnostics helpers, tests, and build or verification scripts.
- Keep Svelte only for the browser UI and embed its production assets in each native executable.
- Distribute the native executables as exact-versioned, platform-specific optional npm packages selected by a thin root-package launcher.
- Build and verify Windows x64, Linux x64 glibc, macOS x64, and macOS arm64 on their native GitHub Actions runners before release-gated publication.

## Non-goals

- Publishing, tagging, committing, or pushing version 1.0.0 as part of this implementation.
- Replacing the Svelte browser UI with Nim-generated JavaScript.
- Adding a runtime dependency from an observed project to ttyglass.
- Supporting architectures outside the four explicitly packaged targets.

## Impact

- The executable runtime becomes a Nim binary using Mummy, cligen, jsony, and chronicles.
- The root npm package becomes a portable launcher and optional TypeScript library rather than the server implementation.
- npm installation selects one matching native optional package without compilation on the consumer machine.
