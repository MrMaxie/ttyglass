## ADDED Requirements

### Requirement: CLI launches an arbitrary TUI command

The package MUST expose a `ttyglass` executable that separates its own options from an arbitrary command at `--` and launches the command without a shell in the selected or current working directory.

#### Scenario: A user observes an unmodified project command

- **WHEN** the user runs `ttyglass -- <command> <arguments>` from a project directory
- **THEN** ttyglass launches that exact command and arguments without requiring project configuration or source changes

#### Scenario: Command separation is missing

- **WHEN** the user omits `--` or supplies no command after it
- **THEN** ttyglass exits with usage guidance and does not launch a process

### Requirement: Browser renders the real terminal session

ttyglass MUST run the command through a real PTY on POSIX or ConPTY on Windows and MUST carry output, keyboard input, binary input, and terminal resize between the browser and that session.

#### Scenario: A TUI changes after input

- **WHEN** a connected browser sends a key to the terminal
- **THEN** the actual child process receives the key and its resulting terminal output is rendered in the browser

#### Scenario: The browser terminal changes size

- **WHEN** the rendered terminal reports valid new rows and columns
- **THEN** ttyglass resizes the underlying PTY or ConPTY session

### Requirement: Observation stays local and session-scoped

ttyglass MUST bind only to `127.0.0.1`, MUST choose an available port by default, MUST authenticate terminal and diagnostics access with a per-run token, and MUST reject unexpected browser origins.

#### Scenario: An unauthenticated terminal client connects

- **WHEN** a WebSocket upgrade omits or supplies the wrong session token
- **THEN** ttyglass rejects the connection without launching the command

#### Scenario: ttyglass stops

- **WHEN** the server receives a shutdown signal or its browser client disconnects
- **THEN** ttyglass terminates only the terminal process tree owned by that session and closes its local transports

### Requirement: Diagnostics remain separate and bounded

ttyglass MUST accept authenticated JSON or newline-delimited JSON diagnostics through the child-specific endpoint, normalize only the documented record fields, retain a bounded in-memory history, and render that history outside the terminal surface.

#### Scenario: A child logs without a ttyglass library

- **WHEN** the child POSTs a documented record using `TTYGLASS_DIAGNOSTICS_URL` and `TTYGLASS_DIAGNOSTICS_TOKEN`
- **THEN** ttyglass displays the normalized record in Diagnostics without writing it into the PTY stream

#### Scenario: A diagnostic request exceeds its boundary

- **WHEN** a request is unauthenticated, oversized, malformed, or structurally too deep
- **THEN** ttyglass rejects it without adding the submitted data to history

### Requirement: TypeScript applications may opt into diagnostics

The package MUST export a direct TypeScript diagnostic sender and a writable JSON-line sink that can be passed to loggers such as Pino without requiring that logger in ttyglass itself.

#### Scenario: A Pino-compatible logger writes JSON lines

- **WHEN** an application passes the ttyglass sink as its destination and runs under ttyglass
- **THEN** complete JSON lines are forwarded to the authenticated diagnostics endpoint

#### Scenario: An application runs outside ttyglass

- **WHEN** no diagnostics endpoint is present in the environment
- **THEN** the optional API remains a no-op by default and does not prevent the application from running

### Requirement: Agent guidance is included

The package MUST include guidance for Codex and Claude Code that explains ttyglass as a way to see, assess, interact with, and safely debug a real TUI, including cleanup and evidence boundaries.

#### Scenario: An agent needs to inspect a TUI

- **WHEN** an agent follows the included skill for an available browser workflow
- **THEN** it runs the project command through ttyglass, opens the printed authenticated URL, verifies the real rendered states, and stops the ttyglass process when finished

### Requirement: Package entrypoints support future npm use

The local package MUST define a `ttyglass` binary and TypeScript library exports so the same package structure can later support global installation, `npx ttyglass`, and `nubx ttyglass` without changing its invocation contract.

#### Scenario: The package is installed from a local directory

- **WHEN** a user installs or executes the local package through an npm-compatible package manager
- **THEN** the `ttyglass` binary and documented library exports resolve from built package files
