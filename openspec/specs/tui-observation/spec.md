# tui-observation Specification

## Purpose

Define the generic, local, and authenticated observation boundary for running real terminal user interfaces through ttyglass.

## Requirements

### Requirement: Users can run an arbitrary TUI without adapting the target project

ttyglass MUST accept either a complete command after `--` or no command for terminal mode. The target command MUST run immediately in a real platform terminal with inherited environment, default working directory, and forwarded arguments. Starting and keeping the PTY alive MUST NOT depend on a browser connection.

#### Scenario: A user observes an unmodified project command

- **WHEN** the user runs `ttyglass -- <command> [arguments...]`
- **THEN** ttyglass creates a command session in the per-user service
- **AND** runs the complete command inside a real PTY or ConPTY without requiring changes to the target project

#### Scenario: A command session starts before a browser opens

- **WHEN** a command session is created by CLI, JSONL, or MCP
- **THEN** its PTY starts immediately
- **AND** a browser can attach later and observe the retained state

### Requirement: ttyglass manages multiple independent sessions

One per-user ttyglass service MUST own multiple simultaneous PTY or ConPTY sessions. Each session MUST have an opaque identifier, a distinct authorization token, independent process state, dimensions, diagnostics, snapshot, and raw ANSI output buffer.

#### Scenario: Two sessions run simultaneously

- **WHEN** two clients start different sessions through one ttyglass service
- **THEN** both PTY sessions run at the same time
- **AND** input, resize, output, status, and diagnostics remain isolated by session id

#### Scenario: Multiple clients share one session

- **WHEN** browser, CLI, JSONL, or MCP clients attach to one session
- **THEN** each client can observe current and subsequent state
- **AND** input is serialized in server receipt order
- **AND** the last valid resize becomes authoritative and is broadcast to every client

### Requirement: ttyglass supports command and terminal modes

Command sessions MUST execute the complete received argv and MUST be restartable. Terminal sessions MUST start the resolved user shell, display `No command`, and MUST NOT be restartable.

#### Scenario: ttyglass is invoked without a command

- **WHEN** a user invokes `ttyglass` without options or a separator
- **THEN** ttyglass creates a foreground terminal session using the user's resolved shell

#### Scenario: An empty separator is provided

- **WHEN** a user invokes `ttyglass --` without a command
- **THEN** ttyglass exits with a usage error that suggests removing the separator for terminal mode

### Requirement: Session metadata preserves argument boundaries

Metadata MUST include `sessionId`, the optional user-provided `name`, `mode`, the complete `argv`, a lossless `displayCommand`, the resolved shell when applicable, and `restartable`. The display command MUST encode every argv value without reducing it to a filename. It does not need to reproduce quoting already removed by the invoking shell.

#### Scenario: Command arguments contain spaces and empty values

- **WHEN** a command session receives arguments that include spaces, quotes, or empty strings
- **THEN** metadata returns the original argv values unchanged
- **AND** `displayCommand` distinguishes every value losslessly

#### Scenario: A session is given a name

- **WHEN** a CLI, JSONL, or MCP client starts a session with a non-empty name
- **THEN** metadata returns that name independently of the command or resolved shell

### Requirement: Headless clients can inspect terminal state

Every session MUST expose a bounded raw ANSI byte stream and a terminal screen snapshot. Raw output MUST expose absolute byte offsets, truncation, and Base64 data. A snapshot MUST expose revision, dimensions, screen lines, cursor position and visibility, and status.

#### Scenario: A client reads output after buffer truncation

- **WHEN** a requested offset precedes the oldest byte retained by the configured buffer limit
- **THEN** the response begins at the oldest retained offset
- **AND** marks the response as truncated

#### Scenario: A full-screen application updates the alternate screen

- **WHEN** PTY output uses alternate-screen, Unicode, cursor movement, and resize control sequences
- **THEN** the snapshot reflects the visible terminal screen, cursor, dimensions, and a newer revision

### Requirement: Disconnected sessions use bounded retention

A running session with no attached clients MUST remain available for five minutes. Reattachment MUST cancel that deadline. A completed session MUST remain readable for five minutes. Explicit stop and service shutdown MUST terminate the full owned process tree.

#### Scenario: A client reconnects during the grace period

- **WHEN** the last client detaches and another client attaches before five minutes pass
- **THEN** the same session remains running
- **AND** the attaching client receives its current metadata, snapshot, output, diagnostics, dimensions, and status

### Requirement: Browser renders the real terminal session

ttyglass MUST run the command through a real PTY on POSIX or ConPTY on Windows and MUST carry output, keyboard input, binary input, and terminal resize between the browser and that session.

#### Scenario: A TUI changes after input

- **WHEN** a connected browser sends a key to the terminal
- **THEN** the actual child process receives the key and its resulting terminal output is rendered in the browser

#### Scenario: The browser terminal changes size

- **WHEN** the rendered terminal reports valid new rows and columns
- **THEN** ttyglass resizes the underlying PTY or ConPTY session

#### Scenario: A user attempts to scroll through a full-screen TUI

- **WHEN** the observed application redraws its terminal screen and the user scrolls the terminal viewport
- **THEN** ttyglass keeps the current terminal screen visible instead of exposing stale redraw history

#### Scenario: The user opens browser diagnostics

- **WHEN** the user opens or closes Diagnostics
- **THEN** ttyglass docks the panel below the terminal and fits a dynamically sized TUI once to the remaining space without covering terminal content

#### Scenario: The user opens browser diagnostics with a fixed terminal size

- **WHEN** the user opens or closes Diagnostics while fixed terminal sizing is active
- **THEN** ttyglass keeps the configured terminal dimensions and keeps the terminal viewport scrollable without covering terminal content

### Requirement: Terminal display controls are session-local

ttyglass MUST let the user preview the observed TUI with its unmodified output or the built-in Catppuccin Mocha, Gruvbox Dark, Nord, Dracula, and Tokyo Night terminal color schemes. The preview MUST map ANSI colors, indexed colors, and application-supplied 24-bit RGB colors into the selected palette while leaving the ttyglass browser chrome unchanged. ttyglass MUST also let the user choose dynamic terminal fitting or a fixed valid column and row count. These controls MUST affect only the current browser session.

#### Scenario: The user selects a built-in color scheme

- **WHEN** the user selects a color scheme in Display
- **THEN** ttyglass recolors the terminal output with the corresponding palette without changing the ttyglass interface or restarting the observed process

#### Scenario: The user chooses a fixed terminal size

- **WHEN** the user enters valid columns and rows and applies the fixed size
- **THEN** ttyglass resizes the observed process to those exact dimensions and keeps them across browser layout changes

#### Scenario: The user chooses dynamic terminal sizing

- **WHEN** the user selects Dynamic or the available browser space changes while Dynamic is active
- **THEN** ttyglass fits the terminal to the available space and sends a resize only when the resulting columns or rows changed

#### Scenario: The user enters an invalid fixed size

- **WHEN** the fixed columns or rows are outside the documented input bounds
- **THEN** ttyglass keeps the existing terminal size and shows a validation message

### Requirement: Observation stays local and session-scoped

ttyglass MUST bind HTTP and WebSocket listeners only to `127.0.0.1`, MUST choose an available port by default, MUST use a management token for session listing, MUST use a distinct token for each session, and MUST reject unexpected browser origins.

#### Scenario: An unauthenticated terminal client connects

- **WHEN** a WebSocket upgrade omits or supplies the wrong session token
- **THEN** ttyglass rejects the connection without exposing or controlling the session

#### Scenario: ttyglass stops

- **WHEN** the service receives a shutdown signal or fails
- **THEN** ttyglass terminates every process tree owned by that service and closes its local transports

### Requirement: Diagnostics remain separate and bounded

ttyglass MUST accept authenticated JSON or newline-delimited JSON diagnostics through the child-specific endpoint, normalize only the documented record fields, retain a bounded in-memory history, and render that history outside the terminal surface. The history MUST contain only records submitted by the observed application, not ttyglass lifecycle, resize, transport, or other internal events.

#### Scenario: A child logs without a ttyglass library

- **WHEN** the child POSTs a documented record using `TTYGLASS_DIAGNOSTICS_URL` and `TTYGLASS_DIAGNOSTICS_TOKEN`
- **THEN** ttyglass displays the normalized record in Diagnostics without writing it into the PTY stream

#### Scenario: A diagnostic request exceeds its boundary

- **WHEN** a request is unauthenticated, oversized, malformed, or structurally too deep
- **THEN** ttyglass rejects it without adding the submitted data to history

#### Scenario: ttyglass changes its own process or terminal state

- **WHEN** ttyglass starts, stops, restarts, or resizes the observed process
- **THEN** Diagnostics remains unchanged unless the observed application submits a record

### Requirement: TypeScript applications may opt into diagnostics

The package MUST export a direct TypeScript diagnostic sender and a writable JSON-line sink that can be passed to loggers such as Pino without requiring that logger in ttyglass itself.

#### Scenario: A Pino-compatible logger writes JSON lines

- **WHEN** an application passes the ttyglass sink as its destination and runs under ttyglass
- **THEN** complete JSON lines are forwarded to the authenticated diagnostics endpoint

#### Scenario: An application runs outside ttyglass

- **WHEN** no diagnostics endpoint is present in the environment
- **THEN** the optional API remains a no-op by default and does not prevent the application from running

### Requirement: Agent guidance is included

The package MUST include guidance for Codex and Claude Code that explains ttyglass as a way to see, assess, interact with, and safely debug a real TUI through browser, stateless CLI, JSONL, or MCP clients, including cleanup and evidence boundaries.

#### Scenario: An agent needs to inspect a TUI

- **WHEN** an agent follows the included skill using an available ttyglass client
- **THEN** it runs the project command through ttyglass, verifies real terminal state through the selected client, and stops the owned session when finished

### Requirement: Package entrypoints support npm distribution

The npm package MUST define a `ttyglass` binary and TypeScript library exports that support global installation, `npx ttyglass`, and `nubx ttyglass` without changing the invocation contract.

#### Scenario: The package is installed from npm

- **WHEN** a user installs or executes a published version through an npm-compatible package manager
- **THEN** the `ttyglass` binary and documented library exports resolve from built package files

### Requirement: npm publication is verified and release-gated

The project MUST publish to npm only from a GitHub Release whose tag matches the root and native package versions. It MUST build and verify each native executable on its target architecture, publish the package set under a non-default candidate tag through npm Trusted Publishing, wait until every exact package is available from the registry, exercise the exact registry version from a fresh consumer and npm cache, and promote the complete verified set to `latest` only after verification succeeds. Immutable package publication MUST NOT require a long-lived npm token. Mutable dist-tag promotion MAY use a narrowly scoped automation token while npm Trusted Publishing does not support that operation.

#### Scenario: A matching GitHub Release is published

- **WHEN** a GitHub Release tag matches `v<package version>` and verification passes on Windows x64, Linux x64 glibc, macOS x64, and macOS arm64
- **THEN** the workflow publishes all native packages and the root package as candidates with provenance through trusted publishing
- **AND** waits until all five exact package versions and required native executable files are visible from the registry
- **AND** verifies the CLI, native terminal session, diagnostics, and TypeScript exports from a fresh registry consumer
- **AND** promotes the verified package set to `latest`

#### Scenario: Registry propagation is incomplete

- **WHEN** any exact package version or required native executable is not yet available from the registry
- **THEN** verification fails with the unavailable package identified
- **AND** the workflow retries from a fresh npm cache within its bounded propagation window
- **AND** does not promote any package to `latest`

#### Scenario: Release metadata or verification is invalid

- **WHEN** any package version differs, a target build fails, or exact-version registry verification fails after the bounded retry window
- **THEN** the workflow does not promote the package set to `latest`

### Requirement: The terminal observation runtime is native Nim

The distributed ttyglass executable MUST implement CLI parsing, HTTP and WebSocket handling, PTY or ConPTY ownership, process lifecycle, diagnostics ingestion, and embedded browser asset delivery in Nim. TypeScript MUST be limited to the npm launcher, optional diagnostics library, tests, and build or verification scripts. Svelte MUST be limited to the browser UI.

#### Scenario: A user starts ttyglass through npm

- **WHEN** a user invokes the root package through a global install, `npx`, or `nubx`
- **THEN** the TypeScript launcher selects and starts the matching native executable
- **AND** the native executable owns the complete observation session

#### Scenario: The browser UI is served

- **WHEN** a browser requests an application asset from a running ttyglass session
- **THEN** the native executable serves the Svelte production asset embedded at compile time

### Requirement: npm installation selects a prebuilt native package

The root npm package MUST declare exact-version optional dependencies for Windows x64, Linux x64 glibc, macOS x64, and macOS arm64. Installation MUST NOT compile Nim or native code on the consumer machine.

#### Scenario: A supported platform executes ttyglass

- **WHEN** the package runs on a supported operating system and CPU architecture
- **THEN** the launcher resolves the matching optional package and forwards all arguments to its executable

#### Scenario: The native package is unavailable

- **WHEN** the matching optional package was omitted or cannot be resolved
- **THEN** the launcher exits with a message that identifies the missing package and how to restore optional dependencies
