## ADDED Requirements

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

#### Scenario: an empty separator is provided

- **WHEN** a user invokes `ttyglass --` without a command
- **THEN** ttyglass exits with a usage error that suggests removing the separator for terminal mode

### Requirement: session metadata preserves argument boundaries

Metadata MUST include `sessionId`, the optional user-provided `name`, `mode`, the complete `argv`, a lossless `displayCommand`, the resolved shell when applicable, and `restartable`. The display command MUST encode every argv value without reducing it to a filename. It does not need to reproduce quoting already removed by the invoking shell.

#### Scenario: command arguments contain spaces and empty values

- **WHEN** a command session receives arguments that include spaces, quotes, or empty strings
- **THEN** metadata returns the original argv values unchanged
- **AND** `displayCommand` distinguishes every value losslessly

#### Scenario: a session is given a name

- **WHEN** a CLI, JSONL, or MCP client starts a session with a non-empty name
- **THEN** metadata returns that name independently of the command or resolved shell

### Requirement: headless clients can inspect terminal state

Every session MUST expose a bounded raw ANSI byte stream and a terminal screen snapshot. Raw output MUST expose absolute byte offsets, truncation, and Base64 data. A snapshot MUST expose revision, dimensions, screen lines, cursor position and visibility, and status.

#### Scenario: a client reads output after buffer truncation

- **WHEN** a requested offset precedes the oldest byte retained by the configured buffer limit
- **THEN** the response begins at the oldest retained offset
- **AND** marks the response as truncated

#### Scenario: a full-screen application updates the alternate screen

- **WHEN** PTY output uses alternate-screen, Unicode, cursor movement, and resize control sequences
- **THEN** the snapshot reflects the visible terminal screen, cursor, dimensions, and a newer revision

### Requirement: disconnected sessions use bounded retention

A running session with no attached clients MUST remain available for five minutes. Reattachment MUST cancel that deadline. A completed session MUST remain readable for five minutes. Explicit stop and service shutdown MUST terminate the full owned process tree.

#### Scenario: a client reconnects during the grace period

- **WHEN** the last client detaches and another client attaches before five minutes pass
- **THEN** the same session remains running
- **AND** the attaching client receives its current metadata, snapshot, output, diagnostics, dimensions, and status

## MODIFIED Requirements

### Requirement: users can run an arbitrary TUI without adapting the target project

ttyglass MUST accept either a complete command after `--` or no command for terminal mode. The target command MUST run immediately in a real platform terminal with inherited environment, default working directory, and forwarded arguments. Starting and keeping the PTY alive MUST NOT depend on a browser connection.

#### Scenario: a user observes an existing TUI command

- **WHEN** the user runs `ttyglass -- <command> [arguments...]`
- **THEN** ttyglass creates a command session in the per-user service
- **AND** runs the complete command inside a real PTY or ConPTY without requiring changes to the target project

#### Scenario: a command session starts before a browser opens

- **WHEN** a command session is created by CLI, JSONL, or MCP
- **THEN** its PTY starts immediately
- **AND** a browser can attach later and observe the retained state
